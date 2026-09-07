import Foundation

// Decides what happens to a proxy backup that outlived the session that wrote it.

// MARK: - ProxyBackupRecoveryAction

enum ProxyBackupRecoveryAction: Equatable {
    case restore
    case preserve
    case clear
}

// MARK: - ProxyServiceOverrideState

/// The proxy fields recovery reads to decide whether one backed-up network service still
/// carries Rockxy's override. Readiness reporting inspects more fields and answers for the
/// routed service; ownership only asks whether this service still points at Rockxy.
struct ProxyServiceOverrideState: Equatable {
    init(
        service: String,
        httpEnabled: Bool,
        httpHost: String,
        httpPort: Int,
        httpsEnabled: Bool,
        httpsHost: String,
        httpsPort: Int,
        socksEnabled: Bool = false,
        pacEnabled: Bool = false,
        autoDiscoveryEnabled: Bool = false,
        hasGlobalBypass: Bool = false
    ) {
        self.service = service
        self.httpEnabled = httpEnabled
        self.httpHost = httpHost
        self.httpPort = httpPort
        self.httpsEnabled = httpsEnabled
        self.httpsHost = httpsHost
        self.httpsPort = httpsPort
        self.socksEnabled = socksEnabled
        self.pacEnabled = pacEnabled
        self.autoDiscoveryEnabled = autoDiscoveryEnabled
        self.hasGlobalBypass = hasGlobalBypass
    }

    let service: String
    let httpEnabled: Bool
    let httpHost: String
    let httpPort: Int
    let httpsEnabled: Bool
    let httpsHost: String
    let httpsPort: Int
    let socksEnabled: Bool
    let pacEnabled: Bool
    let autoDiscoveryEnabled: Bool
    let hasGlobalBypass: Bool

    /// The answer for a service whose settings could not be read: not overridden, by anybody.
    /// Reporting an unreadable service as owned is how recovery would claim something it cannot
    /// prove, and every caller that reads ownership needs the same answer for it.
    static func unreadable(service: String) -> ProxyServiceOverrideState {
        ProxyServiceOverrideState(
            service: service,
            httpEnabled: false,
            httpHost: "",
            httpPort: 0,
            httpsEnabled: false,
            httpsHost: "",
            httpsPort: 0
        )
    }
}

// MARK: - ProxyOverrideOwnership

/// Per-service ownership for recovery. This is deliberately an *any* predicate: a backup covers
/// several network services, and one service the user has since re-pointed must not make the
/// remaining Rockxy-owned services look unowned — that is how a stranded override survives with
/// its only restore point deleted.
enum ProxyOverrideOwnership {
    // MARK: Internal

    static let loopbackHost = "127.0.0.1"

    /// True when this service still carries Rockxy's strict HTTP+HTTPS loopback override on the
    /// persisted port. Both protocols must match: a half-configured service belongs to whoever
    /// changed it, not to Rockxy.
    static func isOwnedByRockxy(_ state: ProxyServiceOverrideState, port: Int) -> Bool {
        guard port > 0 else {
            return false
        }
        return state.httpEnabled
            && state.httpHost == loopbackHost
            && state.httpPort == port
            && state.httpsEnabled
            && state.httpsHost == loopbackHost
            && state.httpsPort == port
            && !state.socksEnabled
            && !state.pacEnabled
            && !state.autoDiscoveryEnabled
            && !state.hasGlobalBypass
    }

    /// The backed-up services Rockxy still owns right now, in the order they were supplied.
    /// Restoring these and only these leaves a user-changed or foreign service untouched.
    static func residualOwnedServices(in states: [ProxyServiceOverrideState], port: Int) -> [String] {
        states.filter { isOwnedByRockxy($0, port: port) }.map(\.service)
    }

    static func hasResidualOwnedService(in states: [ProxyServiceOverrideState], port: Int) -> Bool {
        states.contains { isOwnedByRockxy($0, port: port) }
    }

    /// The loopback port a backup without a persisted port is still overriding, taken from the
    /// first backed-up service that carries a complete HTTP+HTTPS loopback override. Backups
    /// written before the port was recorded have nothing to compare against otherwise, and an
    /// unidentifiable port means the restore point gets thrown away.
    static func inferredOwnedPort(in states: [ProxyServiceOverrideState]) -> Int? {
        for state in states where state.httpEnabled
            && state.httpsEnabled
            && state.httpHost == loopbackHost
            && state.httpsHost == loopbackHost
            && state.httpPort == state.httpsPort
            && state.httpPort > 0
            && !state.socksEnabled
            && !state.pacEnabled
            && !state.autoDiscoveryEnabled
            && !state.hasGlobalBypass
        {
            return state.httpPort
        }
        return nil
    }
}

// MARK: - ProxyBackupRecoveryPolicy

/// Decides backup lifetime from live ownership instead of elapsed wall-clock time or a loopback
/// probe. Any process can answer on a loopback port, so reachability never proved that the
/// capture session which took the override was still the one running.
enum ProxyBackupRecoveryPolicy {
    static func action(
        residualOwnedServicesExist: Bool,
        ownerSessionIsLive: Bool
    )
        -> ProxyBackupRecoveryAction
    {
        guard residualOwnedServicesExist else {
            return .clear
        }
        return ownerSessionIsLive ? .preserve : .restore
    }
}

// MARK: - ProxyBackupOwnerIdentityPolicy

/// Decides whether the process recorded in a backup is still the live, trusted Rockxy session
/// that took the override. Every clause has to hold: a recycled PID, a legacy record with no
/// identity, or a process that no longer satisfies caller validation all mean the session is
/// gone and its residual services must be restored.
enum ProxyBackupOwnerIdentityPolicy {
    static func ownerSessionIsLive(
        recordedOwnerPID: Int32?,
        recordedStartSignature: String?,
        ownerProcessIsAlive: Bool,
        liveStartSignature: String?,
        ownerPassesCallerValidation: Bool
    )
        -> Bool
    {
        guard ownerProcessIsAlive, ownerPassesCallerValidation else {
            return false
        }
        return ProcessStartIdentity.identifiesSameProcess(
            recordedPID: recordedOwnerPID,
            recordedStartSignature: recordedStartSignature,
            liveStartSignature: liveStartSignature
        )
    }
}

// MARK: - ProxyBackupSubset

/// Pure selection helpers that make subset restore deterministic and testable without touching
/// system state.
enum ProxyBackupSubset {
    /// Keeps the backup entries naming one of `services`, preserving the backup's order.
    static func select<Entry>(
        _ entries: [Entry],
        services: Set<String>,
        serviceName: (Entry) -> String
    )
        -> [Entry]
    {
        entries.filter { services.contains(serviceName($0)) }
    }

    /// The entries a restore attempt did not resolve: the services whose commands failed, plus
    /// the services still pointing at Rockxy afterwards. While this is non-empty the backup has
    /// to survive, because those services have no other restore point.
    static func unresolvedEntries<Entry>(
        _ entries: [Entry],
        failedServices: Set<String>,
        stillOwnedServices: Set<String>,
        serviceName: (Entry) -> String
    )
        -> [Entry]
    {
        entries.filter { entry in
            let service = serviceName(entry)
            return failedServices.contains(service) || stillOwnedServices.contains(service)
        }
    }
}

// MARK: - ProxyBackupRetention

/// The services a restore attempt keeps a restore point for while it runs.
///
/// An attempt may be authorized to write only part of a backup — the services one failed override
/// touched, say. The rest is not merely left unwritten: its entries have to stay in the
/// authoritative backup for the whole run, because a crash or a failed write in between would
/// otherwise be the moment a service nobody touched lost the only restore point it has. Removing
/// them and adding them back at the end is the same bug with a smaller window.
struct ProxyBackupRetention: Equatable {
    // MARK: Lifecycle

    /// - Parameters:
    ///   - authorized: entries this attempt may write.
    ///   - preserved: entries this attempt may not write but must keep for its whole run.
    ///   - preAttemptServices: the services the backup already held before this attempt captured
    ///     anything, or nil when the attempt captured nothing and every entry therefore predates
    ///     it. Only these preserved entries may outlive the attempt.
    init(authorized: [String], preserved: [String], preAttemptServices: Set<String>? = nil) {
        authorizedServices = authorized
        preservedServices = preserved
        self.preAttemptServices = preAttemptServices
    }

    // MARK: Internal

    /// Entries this attempt may write, and may stop keeping once it has finished with them.
    private(set) var authorizedServices: [String]
    /// Entries this attempt was never authorized to write.
    let preservedServices: [String]
    /// The services proven to have had a restore point before this attempt started.
    let preAttemptServices: Set<String>?

    /// Every service the backup on disk must still hold an entry for while the attempt runs, in
    /// backup order.
    var services: [String] {
        authorizedServices + preservedServices
    }

    /// The preserved entries that were already on disk when this attempt started.
    ///
    /// An entry this very attempt captured for a service it then never touched describes settings
    /// nobody overrode. Keeping it past the attempt would hand the next enable a snapshot older
    /// than whatever the user has set in the meantime, and the enable after that would write it
    /// back over their change.
    var preservedServicesPredatingAttempt: [String] {
        guard let preAttemptServices else {
            return preservedServices
        }
        return preservedServices.filter { preAttemptServices.contains($0) }
    }

    /// Every service the backup must still hold an entry for once the attempt has finished: the
    /// ones it could not resolve, plus the untouched ones that had a restore point before it
    /// began.
    func retainedAfterAttempt(unresolvedServices: [String]) -> [String] {
        unresolvedServices + preservedServicesPredatingAttempt
    }

    /// Drops a service this attempt has finished with.
    ///
    /// A preserved entry is never dropped here. This attempt was not allowed to write that
    /// service, so it is not this attempt's to delete mid-run either — whatever it decided about
    /// its own work.
    mutating func drop(_ service: String) {
        authorizedServices.removeAll { $0 == service }
    }
}

// MARK: - ProxyBackupCopyRole

/// Which of a backup's on-disk copies a file is.
///
/// The marker exists so a current build can tell the record it commits to from the copy it keeps
/// only for older builds. Without it the two are indistinguishable, and a mirror left behind by a
/// failed mirror write reads exactly like the truth.
enum ProxyBackupCopyRole: String, Codable, Equatable {
    /// The copy whose publication is the commit. Recovery reads this one.
    case authoritative
    /// A compatibility copy, prepared before the authoritative commit so an older build can still
    /// find a backup. It is never recovery's answer in a build that understands this marker.
    case mirror
}

// MARK: - ProxyBackupCopyPolicy

/// Decides whether a decoded backup copy may be used as recovery truth.
///
/// The authoritative location always may unless it is explicitly marked as a mirror. A secondary
/// location may be an unmarked legacy backup or a marked compatibility copy. Current writers
/// prepare that copy before the authoritative publication, so a surviving marked copy is either
/// the exact committed record or a safe record whose later commit failed and authorized no command.
enum ProxyBackupCopyPolicy {
    static func isRecoveryTruth(role: ProxyBackupCopyRole?, isAuthoritativeLocation: Bool) -> Bool {
        if isAuthoritativeLocation {
            return role != .mirror
        }
        return role == nil || role == .mirror
    }
}

// MARK: - ProxyBackupCompatibilityCopy

/// Brings one compatibility copy of a backup into a state a later loader can never misread, or
/// says plainly that it could not.
///
/// A build older than the copy marker wrote unmarked bytes to both locations, and a current build
/// reads an unmarked compatibility copy as truth — correctly, because for that build it was the
/// only backup there was. Once a current build commits, those bytes are stale, and leaving them
/// where they are is what lets them be read back and written onto the user's services the moment
/// the authoritative record is lost.
///
/// Rewriting the copy with the marker is the ordinary answer. Removing it is just as good a one:
/// a copy that is not there is never read. Only a file that can be neither rewritten nor removed
/// is a genuine blocker.
enum ProxyBackupCompatibilityCopy {
    // MARK: Internal

    enum Outcome: Equatable {
        /// The marked copy is on disk.
        case published
        /// The copy could not be written, but nothing is left at the location either.
        case invalidated
    }

    @discardableResult
    static func prepare(
        publish: () throws -> Void,
        remove: () -> Void,
        copyExists: () -> Bool
    )
        throws -> Outcome
    {
        do {
            try publish()
            return .published
        } catch {
            remove()
            guard copyExists() else {
                return .invalidated
            }
            throw error
        }
    }
}

// MARK: - ProxyBackupCommit

/// Publishes a backup's copies in the one order that cannot leave stale bytes a later loader would
/// accept.
///
/// The compatibility copies are dealt with first and the authoritative record second, because the
/// authoritative publication *is* the commit. Committing first and mirroring afterwards leaves a
/// window — the whole rest of the session, if the mirror write failed — in which an unmarked copy
/// from an older build sits beside a record that has already moved on. Doing the copies first
/// means an unmarked one can only survive where no commit in the current format ever succeeded,
/// which is exactly the case where it is the honest answer.
///
/// A throw therefore means nothing was committed, which is what every caller that treats a
/// successful write as its permission to issue a command depends on.
enum ProxyBackupCommit {
    static func run(
        prepareCompatibilityCopies: () throws -> Void,
        publishAuthoritative: () throws -> Void
    )
        throws
    {
        try prepareCompatibilityCopies()
        try publishAuthoritative()
    }
}

// MARK: - HelperOwnerBindingPolicy

/// Resolves the app process a privileged proxy request is allowed to act for.
///
/// The owner identifier arrives in the message, so on its own it is a claim rather than a fact: a
/// client could name any process and have the helper arm a watchdog on it — or record it as the
/// session that owns the user's proxy settings. The connection the request came in on has already
/// been authenticated, and its peer identifier cannot be chosen by the sender, so that is the only
/// identity the helper acts on. The parameter is kept, and required to agree, so the wire protocol
/// is unchanged and a disagreement is refused rather than quietly reinterpreted.
enum HelperOwnerBindingPolicy {
    static func authorizedOwnerPID(boundConnectionPID: Int32?, requestedOwnerPID: Int32) -> Int32? {
        guard let boundConnectionPID, boundConnectionPID > 0, requestedOwnerPID > 0 else {
            return nil
        }
        return boundConnectionPID == requestedOwnerPID ? boundConnectionPID : nil
    }
}

// MARK: - ProxyOwnerWatchdogPolicy

/// Decides whether the process a watchdog is watching is still the one it was armed for.
///
/// Liveness alone is not identity: the kernel recycles process identifiers, so a bare `kill(pid, 0)`
/// keeps reporting an owner that exited minutes ago as present. Pairing the identifier with the
/// recorded kernel start time makes a reused identifier read as what it is — the owner is gone and
/// the override it left behind has to be restored.
///
/// A watchdog is never armed without a start signature: an override that cannot name the process
/// it belongs to is refused before anything is written. A record with no signature therefore
/// cannot describe a session worth protecting, and reporting it as live would be exactly the
/// bare-identifier check this type exists to remove.
enum ProxyOwnerWatchdogPolicy {
    static func watchedOwnerIsLive(
        recordedPID: Int32,
        recordedStartSignature: String?,
        processIsAlive: Bool,
        liveStartSignature: String?
    )
        -> Bool
    {
        guard processIsAlive else {
            return false
        }
        return ProcessStartIdentity.identifiesSameProcess(
            recordedPID: recordedPID,
            recordedStartSignature: recordedStartSignature,
            liveStartSignature: liveStartSignature
        )
    }
}

// MARK: - ProxyOverrideApplicationPolicy

/// Decides what an override attempt may report once every service it touched has been answered.
///
/// Applying an override is a multi-service write with no transaction behind it. A service whose
/// command sequence stopped part-way is neither Rockxy's nor the user's: strict ownership does
/// not recognise it, so recovery cannot adopt it, and reporting the attempt as a success would
/// leave that shape on the machine with nothing watching it. The attempt therefore has to put
/// back everything it touched and say plainly when it could not.
enum ProxyOverrideApplicationPolicy {
    // MARK: Internal

    enum Outcome: Equatable {
        /// Every service the attempt configured carries the override, and none was left part-way.
        case applied
        /// The attempt failed and every service it touched is back on its captured settings.
        case rolledBack
        /// The attempt failed and at least one touched service is still changed, so the backup
        /// has to survive and the failure has to be reported.
        case rollbackIncomplete
    }

    /// True when a service whose override sequence failed still reads exactly as it was captured,
    /// which is the only evidence that nothing was written to it.
    ///
    /// A service that could not be read answers false. An unreadable state cannot be shown to be
    /// unchanged, and treating it as untouched is how a mutated service ends up with no rollback
    /// and no restore point.
    static func serviceIsUntouched(
        live: ProxyServiceRestorationState?,
        captured: ProxyServiceRestorationState
    )
        -> Bool
    {
        live == captured
    }

    static func outcome(
        configuredServices: [String],
        partiallyAppliedServices: [String],
        unresolvedServices: [String]
    )
        -> Outcome
    {
        guard unresolvedServices.isEmpty else {
            return .rollbackIncomplete
        }
        guard partiallyAppliedServices.isEmpty, !configuredServices.isEmpty else {
            return .rolledBack
        }
        return .applied
    }
}
