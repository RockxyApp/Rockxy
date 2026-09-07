import Foundation

// Durable per-service state machine that makes a proxy recovery retry safe to resume.

// MARK: - ProxyBypassDomainOutput

/// Normalizes the bypass list `networksetup` prints, so the value recovery compares is the same
/// one no matter which process read it. macOS answers with a sentence rather than an empty list
/// when a service has no bypass domains, and that sentence is not a domain.
enum ProxyBypassDomainOutput {
    static let emptyListPrefix = "There aren't any bypass domains"

    static func parse(_ output: String) -> [String] {
        output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(emptyListPrefix) }
    }
}

// MARK: - ProxyEndpointState

/// One proxy protocol's configuration on a network service.
///
/// `networksetup` writes the endpoint and its on/off state with two separate commands, so a
/// restore that stops between them leaves the host and port of one step beside the enabled flag
/// of another. Keeping the three values together lets recovery reason about that gap.
struct ProxyEndpointState: Codable, Equatable {
    // MARK: Lifecycle

    init(enabled: Bool, host: String, port: Int) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }

    // MARK: Internal

    let enabled: Bool
    let host: String
    let port: Int

    /// True when a captured endpoint names somewhere to point at. Anything else is never written
    /// back: the restore only switches that mode off.
    var isWritable: Bool {
        !host.isEmpty && port > 0
    }

    /// The same endpoint with only its on/off state cleared. Every restore switches all proxy
    /// modes off before it writes anything back, and the stored host and port survive that step.
    var disabled: ProxyEndpointState {
        ProxyEndpointState(enabled: false, host: host, port: port)
    }

    /// The same endpoint with only its on/off state set.
    func settingEnabled(_ isEnabled: Bool) -> ProxyEndpointState {
        ProxyEndpointState(enabled: isEnabled, host: host, port: port)
    }
}

// MARK: - ProxyServiceRestorationState

/// Every proxy field a restore reads or writes for one network service.
///
/// Ownership asks the narrower question of whether a service still carries Rockxy's override.
/// A retry has to answer something stricter — whether the live settings are still explained by
/// what recovery itself wrote — and that needs the SOCKS endpoint, the PAC URL, and the bypass
/// list too, none of which ownership looks at.
struct ProxyServiceRestorationState: Codable, Equatable {
    // MARK: Lifecycle

    init(
        service: String,
        http: ProxyEndpointState,
        https: ProxyEndpointState,
        socks: ProxyEndpointState,
        pacEnabled: Bool,
        pacURL: String,
        autoDiscoveryEnabled: Bool,
        bypassDomains: [String]
    ) {
        self.service = service
        self.http = http
        self.https = https
        self.socks = socks
        self.pacEnabled = pacEnabled
        self.pacURL = pacURL
        self.autoDiscoveryEnabled = autoDiscoveryEnabled
        self.bypassDomains = bypassDomains
    }

    // MARK: Internal

    let service: String
    let http: ProxyEndpointState
    let https: ProxyEndpointState
    let socks: ProxyEndpointState
    let pacEnabled: Bool
    let pacURL: String
    let autoDiscoveryEnabled: Bool
    let bypassDomains: [String]

    /// The ownership-relevant projection of this state, so a single read serves both the
    /// ownership question and the journal comparison.
    var overrideState: ProxyServiceOverrideState {
        ProxyServiceOverrideState(
            service: service,
            httpEnabled: http.enabled,
            httpHost: http.host,
            httpPort: http.port,
            httpsEnabled: https.enabled,
            httpsHost: https.host,
            httpsPort: https.port,
            socksEnabled: socks.enabled,
            pacEnabled: pacEnabled,
            autoDiscoveryEnabled: autoDiscoveryEnabled,
            hasGlobalBypass: bypassDomains.contains("*")
        )
    }

    /// The shape a service passes through in the middle of a restore: every proxy mode is
    /// switched off before the captured settings are written back, so the hosts, ports, PAC URL,
    /// and bypass list still read as they did before the step started.
    var withProxyModesDisabled: ProxyServiceRestorationState {
        replacing(
            http: http.disabled,
            https: https.disabled,
            socks: socks.disabled,
            pacEnabled: false,
            autoDiscoveryEnabled: false
        )
    }

    /// The settings a completed restore actually leaves behind.
    ///
    /// This is not the captured snapshot verbatim: a snapshot with no host or no port for a
    /// protocol only causes that mode to be switched off, so the host and port stay whatever the
    /// override left there. Comparing against the snapshot instead would report a finished
    /// restore as unfinished forever.
    static func expectedRestorationResult(
        target: ProxyServiceRestorationState,
        from current: ProxyServiceRestorationState
    )
        -> ProxyServiceRestorationState
    {
        ProxyServiceRestorationState(
            service: target.service,
            http: restoredEndpoint(target: target.http, current: current.http),
            https: restoredEndpoint(target: target.https, current: current.https),
            socks: restoredEndpoint(target: target.socks, current: current.socks),
            pacEnabled: target.pacEnabled,
            pacURL: target.pacEnabled && !target.pacURL.isEmpty ? target.pacURL : current.pacURL,
            autoDiscoveryEnabled: target.autoDiscoveryEnabled,
            bypassDomains: target.bypassDomains
        )
    }

    /// The same state with individual fields replaced, used to walk one `networksetup` command
    /// at a time.
    func replacing(
        http: ProxyEndpointState? = nil,
        https: ProxyEndpointState? = nil,
        socks: ProxyEndpointState? = nil,
        pacEnabled: Bool? = nil,
        pacURL: String? = nil,
        autoDiscoveryEnabled: Bool? = nil,
        bypassDomains: [String]? = nil
    )
        -> ProxyServiceRestorationState
    {
        ProxyServiceRestorationState(
            service: service,
            http: http ?? self.http,
            https: https ?? self.https,
            socks: socks ?? self.socks,
            pacEnabled: pacEnabled ?? self.pacEnabled,
            pacURL: pacURL ?? self.pacURL,
            autoDiscoveryEnabled: autoDiscoveryEnabled ?? self.autoDiscoveryEnabled,
            bypassDomains: bypassDomains ?? self.bypassDomains
        )
    }

    // MARK: Private

    /// A captured endpoint is written back only when it names both a host and a port. Anything
    /// else leaves the live endpoint where it is and just turns the mode off.
    private static func restoredEndpoint(
        target: ProxyEndpointState,
        current: ProxyEndpointState
    )
        -> ProxyEndpointState
    {
        guard target.isWritable else {
            return current.disabled
        }
        return target
    }
}

// MARK: - ProxyRestoreTransition

/// The exact sequence of states one service passes through while its captured settings are
/// written back.
///
/// A restore is a fixed, ordered list of `networksetup` commands: every proxy mode is switched
/// off, each captured endpoint is written and then switched to its captured state, the PAC URL
/// and PAC state follow, then auto discovery, and the bypass list is written last. Walking that
/// order produces the complete set of shapes an interrupted restore can leave behind — and,
/// just as importantly, excludes everything else. A field combination that no prefix of the
/// sequence produces (a restored bypass list beside an untouched HTTP endpoint, say) belongs to
/// whoever else wrote it.
enum ProxyRestoreTransition {
    /// Every state observable while the restore of `target` runs against a service that starts
    /// in `pre`, in command order and beginning with `pre` itself.
    ///
    /// `networksetup` does not define what writing an endpoint or a PAC URL does to that mode's
    /// on/off flag, so both answers are treated as reachable — but only at the single command
    /// that writes it, and only for that one field. The very next command sets the flag
    /// outright, which is why the uncertainty never spreads into a free choice across fields.
    static func reachableStates(
        from pre: ProxyServiceRestorationState,
        target: ProxyServiceRestorationState
    )
        -> [ProxyServiceRestorationState]
    {
        var states: [ProxyServiceRestorationState] = [pre]
        var current = pre

        func commit(_ next: ProxyServiceRestorationState) {
            current = next
            states.append(next)
        }

        // Phase 1 — every proxy mode is switched off, in the order the commands run.
        commit(current.replacing(http: current.http.disabled))
        commit(current.replacing(https: current.https.disabled))
        commit(current.replacing(socks: current.socks.disabled))
        commit(current.replacing(pacEnabled: false))
        commit(current.replacing(autoDiscoveryEnabled: false))

        // Phase 2 — each captured endpoint is written, then switched to its captured state.
        if target.http.isWritable {
            states.append(current.replacing(http: target.http.disabled))
            states.append(current.replacing(http: target.http.settingEnabled(true)))
            commit(current.replacing(http: target.http))
        }
        if target.https.isWritable {
            states.append(current.replacing(https: target.https.disabled))
            states.append(current.replacing(https: target.https.settingEnabled(true)))
            commit(current.replacing(https: target.https))
        }
        if target.socks.isWritable {
            states.append(current.replacing(socks: target.socks.disabled))
            states.append(current.replacing(socks: target.socks.settingEnabled(true)))
            commit(current.replacing(socks: target.socks))
        }

        // Phase 3 — the PAC URL, then the PAC state. Neither runs unless the capture had PAC on.
        if target.pacEnabled {
            if !target.pacURL.isEmpty {
                states.append(current.replacing(pacEnabled: false, pacURL: target.pacURL))
                states.append(current.replacing(pacEnabled: true, pacURL: target.pacURL))
                current = current.replacing(pacURL: target.pacURL)
            }
            commit(current.replacing(pacEnabled: true))
        }

        // Phase 4 — auto discovery, and only when the capture had it on.
        if target.autoDiscoveryEnabled {
            commit(current.replacing(autoDiscoveryEnabled: true))
        }

        // Phase 5 — the bypass list is always written, and always last.
        commit(current.replacing(bypassDomains: target.bypassDomains))

        return states
    }
}

// MARK: - ProxyOverrideTransition

/// The exact sequence of states one service passes through while Rockxy's loopback override is
/// written onto it.
///
/// Applying the override is a fixed, ordered list of seven `networksetup` commands: the HTTP
/// endpoint and its state, the HTTPS endpoint and its state, then SOCKS, PAC, and auto discovery
/// switched off. Walking that order produces every shape an interrupted override can leave
/// behind — and excludes everything else, which is what turns "this process wrote that service"
/// from an assertion into proof. A recorded bypass write is the final step of that sequence.
enum ProxyOverrideTransition {
    // MARK: Internal

    static let loopbackHost = "127.0.0.1"

    /// Every state observable while the override is applied to a service that starts in
    /// `captured`, in command order and beginning with `captured` itself.
    ///
    /// `networksetup` does not define what writing an endpoint does to that mode's on/off flag,
    /// so both answers are treated as reachable — but only at the single command that writes the
    /// endpoint, and only for that one field. The very next command sets the flag outright.
    ///
    /// `appliedBypassDomains` is the bounded bypass list Rockxy writes once the override is on,
    /// taken from the record that says so. It is a separate command, issued after the seven and
    /// recorded before it runs, so it adds exactly one more state to the end of the sequence —
    /// and only when a record names the list. Without one the bypass list is not part of what
    /// this sequence can produce, and a service whose bypass list differs is nobody's to undo.
    static func reachableStates(
        from captured: ProxyServiceRestorationState,
        port: Int,
        previousAppliedBypassDomains: [String]? = nil,
        appliedBypassDomains: [String]? = nil
    )
        -> [ProxyServiceRestorationState]
    {
        guard port > 0 else {
            return [captured]
        }

        let endpoint = ProxyEndpointState(enabled: true, host: loopbackHost, port: port)
        var states: [ProxyServiceRestorationState] = [captured]
        var current = captured

        func commit(_ next: ProxyServiceRestorationState) {
            current = next
            states.append(next)
        }

        // Commands 1–2 — the HTTP endpoint is written, then switched on. The endpoint write may
        // or may not have switched the mode on by itself; the switched-on answer is the same
        // state command 2 produces, so it is only recorded once.
        states.append(current.replacing(http: endpoint.disabled))
        commit(current.replacing(http: endpoint))

        // Commands 3–4 — the HTTPS endpoint, in the same two steps.
        states.append(current.replacing(https: endpoint.disabled))
        commit(current.replacing(https: endpoint))

        // Commands 5–7 — SOCKS, PAC, and auto discovery are switched off, in that order.
        commit(current.replacing(socks: current.socks.disabled))
        commit(current.replacing(pacEnabled: false))
        commit(current.replacing(autoDiscoveryEnabled: false))

        // A later bypass update records both the state it starts from and the one it intends to
        // write. Either can be live across a crash between durable publication and the command.
        if let previousAppliedBypassDomains, previousAppliedBypassDomains != current.bypassDomains {
            commit(current.replacing(bypassDomains: previousAppliedBypassDomains))
        }

        // Command 8 — the bounded bypass list, written after the override and only when a record
        // says which list it is.
        if let appliedBypassDomains, appliedBypassDomains != current.bypassDomains {
            commit(current.replacing(bypassDomains: appliedBypassDomains))
        }

        return states
    }

    /// The settings a finished override leaves behind: every one of its commands applied, and the
    /// bypass list a record says followed them.
    static func completedState(
        from captured: ProxyServiceRestorationState,
        port: Int,
        previousAppliedBypassDomains: [String]? = nil,
        appliedBypassDomains: [String]? = nil
    )
        -> ProxyServiceRestorationState?
    {
        guard port > 0 else {
            return nil
        }
        return reachableStates(
            from: captured,
            port: port,
            previousAppliedBypassDomains: previousAppliedBypassDomains,
            appliedBypassDomains: appliedBypassDomains
        ).last
    }

    /// True when the live settings are exactly one of the states applying the override to
    /// `captured` passes through.
    ///
    /// This is the only thing that makes a service Rockxy just wrote safe to undo. A service is
    /// recorded as touched before its first command runs, so "we touched it" on its own cannot
    /// tell a command that never mutated anything from a change somebody else made in the
    /// meantime — and both of those must stay out of an automatic rollback.
    static func isReachedByApplying(
        _ live: ProxyServiceRestorationState,
        from captured: ProxyServiceRestorationState,
        port: Int,
        previousAppliedBypassDomains: [String]? = nil,
        appliedBypassDomains: [String]? = nil
    )
        -> Bool
    {
        guard live.service == captured.service else {
            return false
        }
        return reachableStates(
            from: captured,
            port: port,
            previousAppliedBypassDomains: previousAppliedBypassDomains,
            appliedBypassDomains: appliedBypassDomains
        ).contains(live)
    }
}

// MARK: - ProxyBackupFilePublication

/// Publishes a proxy backup so that "the call reported failure" and "the new contents are on
/// disk" can never both be true.
///
/// Writing atomically and then adjusting the file afterwards leaves exactly that gap: the
/// permission change can fail after the new contents are already visible, and a caller that
/// reads the thrown error as "nothing was written" would then skip a command a resumed attempt
/// believes may already have run. Permissions are therefore prepared on the temporary file, and
/// the rename that publishes it is the single act whose success or failure is the answer.
enum ProxyBackupFilePublication {
    // MARK: Internal

    static let ownerOnlyFilePermissions = 0o600
    static let ownerOnlyDirectoryPermissions = 0o700

    /// Writes `data` to a sibling temporary file with owner-only permissions and renames it over
    /// `url`. Nothing is observable at `url` unless this returns.
    static func publish(_ data: Data, to url: URL) throws {
        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).partial")

        do {
            try data.write(to: temporaryURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: ownerOnlyFilePermissions],
                ofItemAtPath: temporaryURL.path
            )
            // `rename` carries the prepared mode with the contents, so there is nothing left to
            // do to the published file — and nothing left that can fail after it exists.
            guard rename(temporaryURL.path, url.path) == 0 else {
                throw publicationError(url: url, code: errno)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    // MARK: Private

    private static func publicationError(url: URL, code: Int32) -> any Error {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not publish \(url.lastPathComponent): \(String(cString: strerror(code)))",
            ]
        )
    }
}

// MARK: - ProxyServiceRestoreStep

/// The two halves of one service's restore, in the order the commands run.
enum ProxyServiceRestoreStep: String, Equatable {
    /// Every proxy mode is switched off and the captured endpoints, PAC, and auto discovery are
    /// written back.
    case proxyState
    /// The captured bypass list, which is always the last thing a restore writes.
    case bypassDomains
}

// MARK: - ProxyServiceRestoreOutcome

enum ProxyServiceRestoreOutcome {
    case restored
    case failed(step: ProxyServiceRestoreStep, error: any Error)

    /// The step that stopped the restore, or nil when every command returned.
    var failedStep: ProxyServiceRestoreStep? {
        switch self {
        case .restored:
            nil
        case let .failed(step, _):
            step
        }
    }

    var error: (any Error)? {
        switch self {
        case .restored:
            nil
        case let .failed(_, error):
            error
        }
    }
}

enum ProxyRecoveryRevalidationError: LocalizedError {
    case stateChangedAfterCommit(service: String)

    var errorDescription: String? {
        switch self {
        case let .stateChangedAfterCommit(service):
            "The live proxy settings for \(service) changed while its recovery record was being committed"
        }
    }
}

// MARK: - ProxyServiceRestoreExecution

/// Runs one service's restore in exactly the order `ProxyRestoreTransition` models: the proxy
/// state first, the bypass list last.
///
/// The bypass list is not written when a proxy-state command fails. That ordering is the whole
/// basis on which a later attempt recognises its own unfinished work, and a service whose bypass
/// list has been restored beside a half-written proxy state is a shape no prefix of the sequence
/// produces — which is precisely the shape recovery has to read as somebody else's.
enum ProxyServiceRestoreExecution {
    static func run(
        proxyState: () throws -> Void,
        bypassDomains: () throws -> Void
    )
        -> ProxyServiceRestoreOutcome
    {
        do {
            try proxyState()
        } catch {
            return .failed(step: .proxyState, error: error)
        }

        do {
            try bypassDomains()
        } catch {
            return .failed(step: .bypassDomains, error: error)
        }

        return .restored
    }
}

// MARK: - ProxyJournaledServiceRestore

/// Runs one service's restore only after its `inFlight` record has been committed.
///
/// The commit is the permission to issue a command, not a note about one that already ran. If it
/// fails, not a single command may be sent for that service: an unrecorded write is exactly the
/// case a resumed attempt has no way to reason about, and it is what turns a half-restored
/// service into one nobody can prove anything about. Keeping the two in one place is what stops
/// the order drifting apart in the paths that use it.
enum ProxyJournaledServiceRestore {
    // MARK: Internal

    enum Attempt {
        /// The record could not be committed, so not one command was issued for this service.
        case notIssued(commitError: any Error)
        /// The record was committed and the commands ran.
        case issued(ProxyServiceRestoreOutcome)
    }

    static func run(
        commitInFlight: () throws -> Void,
        restore: () -> ProxyServiceRestoreOutcome
    )
        -> Attempt
    {
        do {
            try commitInFlight()
        } catch {
            return .notIssued(commitError: error)
        }
        return .issued(restore())
    }
}

// MARK: - ProxyRecoveryStage

/// How far recovery has got with one network service.
///
/// The stage is written to disk before and after the commands it describes, which is what lets a
/// later attempt tell "the command never ran" apart from "the command completed and the process
/// died before it could say so".
enum ProxyRecoveryStage: String, Codable, Equatable {
    /// Recorded before any command for this service has been issued.
    case pending
    /// A command sequence was issued for this service and has not been confirmed complete.
    case inFlight
    /// Every command for this service returned without an error.
    case restored
    /// Legacy pre-command application record. Current writers commit `.applying` immediately
    /// before each service's first mutation; this case remains decodable so older backups can be
    /// handled without treating an unissued command as proof of a changed state.
    case applicationPending
    /// Rockxy's override commands were issued for this service and have not been confirmed.
    /// Recorded immediately before that service's first command.
    case applying

    /// True for the stages that describe an override being written rather than a restore.
    ///
    /// The two kinds of record authorize completely different writes, so they are never read by
    /// the same policy: an application record says "Rockxy was putting its override on this
    /// service", which is what lets a relaunch undo a sequence that stopped half-way.
    var isOverrideApplication: Bool {
        switch self {
        case .applicationPending, .applying:
            true
        case .pending, .inFlight, .restored:
            false
        }
    }
}

// MARK: - ProxyServiceRecoveryJournalEntry

/// One service's durable recovery intent: the stage, the state the step expects to find, and the
/// captured settings that step writes back.
///
/// The captured settings are recorded rather than derived so a later attempt can check that the
/// record still describes the restore the backup on disk asks for. A record that describes some
/// other restore is stale, and a stale record is never a licence to write.
struct ProxyServiceRecoveryJournalEntry: Codable, Equatable {
    // MARK: Lifecycle

    init(
        service: String,
        stage: ProxyRecoveryStage,
        expectedPreStepState: ProxyServiceRestorationState,
        target: ProxyServiceRestorationState,
        appliedOverridePort: Int? = nil,
        previousAppliedBypassDomains: [String]? = nil,
        appliedBypassDomains: [String]? = nil
    ) {
        self.service = service
        self.stage = stage
        self.expectedPreStepState = expectedPreStepState
        self.target = target
        self.appliedOverridePort = appliedOverridePort
        self.previousAppliedBypassDomains = previousAppliedBypassDomains
        self.appliedBypassDomains = appliedBypassDomains
    }

    /// A record written before an override touches one service.
    ///
    /// The captured settings are what a rollback writes back. `baseline` is what the service
    /// actually reads when the sequence is about to start, and on a fresh service the two are the
    /// same snapshot. They are not the same on a session reclaiming an override it already holds:
    /// there the sequence begins at the override already on the machine, while the settings to
    /// put back are still the ones captured before Rockxy ever touched it. Recording the live
    /// baseline is what lets a later attempt recognise the sequence this one issued; recording the
    /// capture as the target is what keeps the rollback aimed at the user's own configuration.
    ///
    /// The port travels with them because it is what turns a half-applied service into a shape
    /// recovery can recognise as Rockxy's own work.
    init(
        overrideApplicationFor captured: ProxyServiceRestorationState,
        baseline: ProxyServiceRestorationState? = nil,
        stage: ProxyRecoveryStage,
        port: Int,
        appliedBypassDomains: [String]? = nil
    ) {
        self.init(
            service: captured.service,
            stage: stage,
            expectedPreStepState: baseline ?? captured,
            target: captured,
            appliedOverridePort: port,
            appliedBypassDomains: appliedBypassDomains
        )
    }

    /// A record whose port is optional, so a build that predates it still reads every field
    /// beside it rather than losing the whole entry.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        service = try container.decode(String.self, forKey: .service)
        stage = try container.decode(ProxyRecoveryStage.self, forKey: .stage)
        expectedPreStepState = try container.decode(
            ProxyServiceRestorationState.self,
            forKey: .expectedPreStepState
        )
        target = try container.decode(ProxyServiceRestorationState.self, forKey: .target)
        appliedOverridePort = try container.decodeIfPresent(Int.self, forKey: .appliedOverridePort)
        previousAppliedBypassDomains = try container.decodeIfPresent(
            [String].self,
            forKey: .previousAppliedBypassDomains
        )
        appliedBypassDomains = try container.decodeIfPresent([String].self, forKey: .appliedBypassDomains)
    }

    // MARK: Internal

    let service: String
    let stage: ProxyRecoveryStage
    /// The settings recorded when this service entered recovery.
    let expectedPreStepState: ProxyServiceRestorationState
    /// The captured pre-Rockxy settings this step writes back.
    let target: ProxyServiceRestorationState
    /// The loopback port an override record was written for. Only an override application
    /// carries one; a restore record has no port of its own.
    let appliedOverridePort: Int?
    /// The bypass list live immediately before the recorded update. Present only while that
    /// per-service command may be in flight, so recovery accepts both sides of the transition.
    let previousAppliedBypassDomains: [String]?
    /// The bounded bypass list Rockxy wrote onto this service after its override, recorded before
    /// that command ran. Absent until it does, and absent on a restore record.
    ///
    /// Without it the finished override is only recognisable through a projection that reads
    /// neither the bypass list, nor a switched-off SOCKS endpoint, nor the PAC URL — and a
    /// configuration that merely points at the loopback port would then authorize writing a whole
    /// captured snapshot over fields nothing proved were Rockxy's.
    let appliedBypassDomains: [String]?

    /// The settings a completed step leaves behind.
    var expectedPostStepState: ProxyServiceRestorationState {
        ProxyServiceRestorationState.expectedRestorationResult(
            target: target,
            from: expectedPreStepState
        )
    }

    /// True when this record still describes the restore the backup on disk asks for. Everything
    /// has to line up: the service it names, the service its states name, and the captured
    /// settings themselves.
    func describesRestore(of target: ProxyServiceRestorationState) -> Bool {
        service == target.service
            && expectedPreStepState.service == service
            && self.target == target
    }

    func advanced(to stage: ProxyRecoveryStage) -> ProxyServiceRecoveryJournalEntry {
        ProxyServiceRecoveryJournalEntry(
            service: service,
            stage: stage,
            expectedPreStepState: expectedPreStepState,
            target: target,
            appliedOverridePort: appliedOverridePort,
            previousAppliedBypassDomains: previousAppliedBypassDomains,
            appliedBypassDomains: appliedBypassDomains
        )
    }

    /// The same record naming the bypass list about to be written onto this service.
    ///
    /// The record has to be committed before that command runs. Recording it afterwards would
    /// leave the one window where the bypass list on the machine is Rockxy's while nothing on disk
    /// says so — which is exactly the state a relaunch has to read as somebody else's.
    func recordingAppliedBypassDomains(
        _ domains: [String],
        from previousDomains: [String]
    )
        -> ProxyServiceRecoveryJournalEntry
    {
        ProxyServiceRecoveryJournalEntry(
            service: service,
            stage: stage,
            expectedPreStepState: expectedPreStepState,
            target: target,
            appliedOverridePort: appliedOverridePort,
            previousAppliedBypassDomains: previousDomains,
            appliedBypassDomains: domains
        )
    }

    /// Clears the in-flight side of a bypass transition at the exact side observed or written.
    func completingAppliedBypassUpdate(at domains: [String]) -> ProxyServiceRecoveryJournalEntry {
        ProxyServiceRecoveryJournalEntry(
            service: service,
            stage: stage,
            expectedPreStepState: expectedPreStepState,
            target: target,
            appliedOverridePort: appliedOverridePort,
            appliedBypassDomains: domains
        )
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case service
        case stage
        case expectedPreStepState
        case target
        case appliedOverridePort
        case previousAppliedBypassDomains
        case appliedBypassDomains
    }
}

// MARK: - ProxyRecoveryContinuation

/// What a retry is allowed to do with one service.
enum ProxyRecoveryContinuation: Equatable {
    /// The live settings are still explained by this service's recovery, so writing the captured
    /// settings back is safe.
    case restore
    /// The live settings already are the restored settings. Nothing is written and the service
    /// leaves recovery.
    case complete
    /// The live settings are not something recovery could have produced, so someone else owns
    /// this service now. It leaves recovery untouched.
    case abandon
    /// The live settings could not be read. Nothing is written and the service keeps its restore
    /// point for a later attempt.
    case retryLater
}

// MARK: - ProxyServiceRecoveryPolicy

/// Decides, for one journaled service, whether a retry may still write.
///
/// The rule is that recovery only ever overwrites its own work. A service whose live settings
/// cannot be produced by the recorded step — not before it, not part-way through it, not after it
/// — has been changed by the user or another tool, and the correct response is to walk away from
/// it rather than replay a snapshot over the change.
enum ProxyServiceRecoveryPolicy {
    // MARK: Internal

    static func continuation(
        for entry: ProxyServiceRecoveryJournalEntry,
        live: ProxyServiceRestorationState?
    )
        -> ProxyRecoveryContinuation
    {
        guard let live else {
            return .retryLater
        }
        guard live.service == entry.service else {
            return .abandon
        }
        if live == entry.expectedPostStepState {
            return .complete
        }

        switch entry.stage {
        case .pending:
            // No command has been issued, so the only state that authorizes a write is exactly
            // the one recorded when the service entered recovery.
            return live == entry.expectedPreStepState ? .restore : .abandon
        case .inFlight, .restored:
            // A sequence that was interrupted — or one that completed without the settings
            // landing — can only have stopped at one of the points its commands pass through.
            return isExplainedByStep(live, entry: entry) ? .restore : .abandon
        case .applicationPending, .applying:
            // An application record does not describe a restore at all: it says the override was
            // being written, and the states that authorizes are the ones applying it passes
            // through, on the port that record carries. Recovery turns such a record into a
            // restore baseline before planning a write, so one reaching here is not the record
            // this step planned from — and nothing may be written from it.
            return .abandon
        }
    }

    /// True when the live settings are exactly one of the states the recorded step passes
    /// through, in the order its commands run.
    static func isExplainedByStep(
        _ live: ProxyServiceRestorationState,
        entry: ProxyServiceRecoveryJournalEntry
    )
        -> Bool
    {
        guard live.service == entry.service else {
            return false
        }
        return ProxyRestoreTransition.reachableStates(
            from: entry.expectedPreStepState,
            target: entry.target
        )
        .contains(live)
    }
}

// MARK: - ProxyOverrideApplicationContinuation

/// What recovery may do with a service an override record names.
enum ProxyOverrideApplicationContinuation: Equatable {
    /// The live settings are provably Rockxy's own half-written or finished override, so the
    /// captured settings may be written back. The baseline is the state the rollback starts
    /// from, which is what the restore records as its own `expectedPreStepState`.
    case rollBack(baseline: ProxyServiceRestorationState)
    /// The live settings are exactly what was captured, so no command of the override landed on
    /// this service. There is nothing to undo and the record is spent.
    case untouched
    /// The live settings are not something applying the override could have produced. Somebody
    /// else owns this service now and it is left exactly as it is.
    case abandon
    /// The live settings could not be read, so nothing is decided and the restore point stays.
    case retryLater
}

// MARK: - ProxyOverrideApplicationRecoveryPolicy

/// Decides whether a relaunch, watchdog, or in-process rollback may undo an override this
/// machine started applying.
///
/// A crash in the middle of the seven-command override leaves a service that is neither Rockxy's
/// nor the user's: the strict ownership test does not recognise it, so without a durable record
/// of the attempt nothing would ever put it back. The record supplies the missing half — the
/// settings the override started from and the port it was writing — and authorization is then
/// exactly the set of shapes that sequence passes through. Nothing wider: a configuration no
/// prefix produces belongs to whoever wrote it.
enum ProxyOverrideApplicationRecoveryPolicy {
    static func continuation(
        for entry: ProxyServiceRecoveryJournalEntry,
        live: ProxyServiceRestorationState?,
        ownedPort: Int?
    )
        -> ProxyOverrideApplicationContinuation
    {
        guard entry.stage.isOverrideApplication else {
            return .abandon
        }
        guard let live else {
            return .retryLater
        }
        guard live.service == entry.service, entry.expectedPreStepState.service == entry.service else {
            return .abandon
        }
        if live == entry.expectedPreStepState {
            // A fresh application begins at the captured user state, so equality means no command
            // landed. A reclaim begins at a prior owned override while its target remains the
            // original user state; consuming that record as untouched would lose the only restore
            // point for the override already on the machine.
            if entry.expectedPreStepState == entry.target {
                return .untouched
            }
            let reclaimPort = entry.appliedOverridePort ?? ownedPort
            guard entry.stage == .applying, let reclaimPort, reclaimPort > 0 else {
                return .abandon
            }
            return .rollBack(baseline: live)
        }

        let recordedPort = entry.appliedOverridePort ?? ownedPort
        guard let recordedPort, recordedPort > 0 else {
            return .abandon
        }

        // A record whose commands were never issued authorizes no changed state at all, whatever
        // the settings happen to look like.
        guard entry.stage == .applying else {
            return .abandon
        }

        // The bounded bypass list Rockxy writes after the override is part of the sequence only
        // when this record names it, which it does before that command runs. Everything else is
        // decided by exact equality with a state the sequence passes through.
        //
        // An ownership projection would answer here too, and used to. It reads neither the bypass
        // list, nor the endpoint of a switched-off SOCKS mode, nor the PAC URL — so a service that
        // merely happens to point at the loopback port authorized writing a whole captured
        // snapshot over three fields nothing had shown were Rockxy's to touch.
        guard ProxyOverrideTransition.isReachedByApplying(
            live,
            from: entry.expectedPreStepState,
            port: recordedPort,
            previousAppliedBypassDomains: entry.previousAppliedBypassDomains,
            appliedBypassDomains: entry.appliedBypassDomains
        ) else {
            return .abandon
        }
        return .rollBack(baseline: live)
    }
}

// MARK: - ProxyOverrideApplicationDecision

/// What an override attempt may do with one service, decided immediately before its first command.
enum ProxyOverrideApplicationDecision: Equatable {
    /// The service may be written. `baseline` is the state the sequence actually starts from, and
    /// it is what the record committed before the first command has to say.
    case apply(baseline: ProxyServiceRestorationState)
    /// The live settings are neither the capture this attempt holds nor anything this machine can
    /// prove Rockxy produced. Not one command may be issued for the service.
    case abort
}

// MARK: - ProxyOverrideApplicationPreflight

/// Decides, for one service and against the settings read right now, whether an override may be
/// written to it.
///
/// The capture a backup holds was taken at some earlier point — moments earlier for a service this
/// attempt just captured, an entire session earlier for one it is reclaiming. Either way the state
/// the override is about to start from is a fact about the machine now, not about when the backup
/// was written, and the two disagree exactly when somebody else has changed the service in
/// between. Writing then would put Rockxy's override over a configuration nothing recorded, and
/// leave a rollback aiming at a snapshot that no longer describes anything.
///
/// So a fresh service is writable only while it still reads exactly as captured, and a reclaim
/// only while the record of the earlier session still explains the live settings. Anything else
/// leaves the service exactly as it is.
enum ProxyOverrideApplicationPreflight {
    static func decision(
        captured: ProxyServiceRestorationState,
        live: ProxyServiceRestorationState?,
        priorEntry: ProxyServiceRecoveryJournalEntry?,
        port: Int
    )
        -> ProxyOverrideApplicationDecision
    {
        // A service whose settings could not be read cannot be shown to be either, and an
        // unreadable service is never written to.
        guard port > 0, let live, live.service == captured.service else {
            return .abort
        }
        if live == captured {
            return .apply(baseline: live)
        }

        // The settings moved on from the capture, so the only thing that can still authorize a
        // write is the durable record of what this machine did to the service itself.
        guard let priorEntry, priorEntry.describesRestore(of: captured) else {
            return .abort
        }
        switch ProxyOverrideApplicationRecoveryPolicy.continuation(
            for: priorEntry,
            live: live,
            ownedPort: port
        ) {
        case let .rollBack(baseline):
            return .apply(baseline: baseline)
        case .untouched:
            // The service is still exactly where the earlier record says its sequence began, and
            // that baseline was itself proven before anything was written to it.
            return .apply(baseline: live)
        case .abandon, .retryLater:
            return .abort
        }
    }
}

// MARK: - ProxyBypassUpdatePreflight

/// What a per-service bypass update may do after comparing the complete live state with its
/// durable override record.
enum ProxyBypassUpdateDecision: Equatable {
    case apply(baseline: ProxyServiceRestorationState)
    case unchanged
    case abort
}

/// Authorizes a bypass command only for a service whose complete override state is still exactly
/// one of the two sides of its last recorded bypass transition.
enum ProxyBypassUpdatePreflight {
    static func decision(
        entry: ProxyServiceRecoveryJournalEntry,
        live: ProxyServiceRestorationState?,
        ownedPort: Int?,
        requestedDomains: [String]
    )
        -> ProxyBypassUpdateDecision
    {
        guard entry.stage == .applying,
              let live,
              live.service == entry.service,
              let port = entry.appliedOverridePort ?? ownedPort,
              port > 0
        else {
            return .abort
        }

        var expectedStates = [ProxyOverrideTransition.completedState(
                from: entry.expectedPreStepState,
                port: port,
                appliedBypassDomains: entry.appliedBypassDomains
            )].compactMap { $0 }
        if let previousDomains = entry.previousAppliedBypassDomains,
           let previous = ProxyOverrideTransition.completedState(
               from: entry.expectedPreStepState,
               port: port,
               appliedBypassDomains: previousDomains
           )
        {
            expectedStates.append(previous)
        }

        guard expectedStates.contains(live) else {
            return .abort
        }
        return live.bypassDomains == requestedDomains ? .unchanged : .apply(baseline: live)
    }
}

// MARK: - ProxyOverrideSessionCompletionPolicy

/// Whether a backup whose recorded owner is still alive describes a session safe to leave exactly
/// where it is.
///
/// Preserving a session means the helper writes nothing, re-arms the watchdog, and lets its idle
/// timer run again. That is only defensible when every service the backup covers carries the
/// finished override — the exact state the record says the sequence ends at. A journal that
/// stopped part-way describes a service that is neither Rockxy's nor the user's, and a live owner
/// does not make that shape safe: the sequence that would have finished it has already failed, and
/// nothing is coming back to finish it. Such a session is recovered immediately instead.
enum ProxyOverrideSessionCompletionPolicy {
    // MARK: Internal

    static func sessionIsFullyApplied(
        services: [String],
        journal: [ProxyServiceRecoveryJournalEntry],
        liveStates: [String: ProxyServiceRestorationState],
        ownedPort: Int?
    )
        -> Bool
    {
        guard !services.isEmpty else {
            return false
        }
        guard !journal.isEmpty else {
            // A backup with no record at all predates the journal, so there is no partial
            // application to read out of it. The older question is the only one available, and it
            // stays the answer for those backups rather than tearing down a live session this
            // build simply cannot describe. It decides nothing but whether to write nothing.
            return legacySessionIsFullyApplied(
                services: services,
                liveStates: liveStates,
                ownedPort: ownedPort
            )
        }
        guard Set(journal.map(\.service)) == Set(services) else {
            // A service the journal says nothing about is a service nothing proves was finished.
            return false
        }
        return services.allSatisfy { service in
            guard let entry = journal.first(where: { $0.service == service }),
                  entry.stage == .applying,
                  let live = liveStates[service],
                  let port = entry.appliedOverridePort ?? ownedPort,
                  let completed = ProxyOverrideTransition.completedState(
                      from: entry.expectedPreStepState,
                      port: port,
                      previousAppliedBypassDomains: entry.previousAppliedBypassDomains,
                      appliedBypassDomains: entry.appliedBypassDomains
                  )
            else {
                return false
            }
            return live == completed
        }
    }

    // MARK: Private

    private static func legacySessionIsFullyApplied(
        services: [String],
        liveStates: [String: ProxyServiceRestorationState],
        ownedPort: Int?
    )
        -> Bool
    {
        guard let ownedPort, ownedPort > 0 else {
            return false
        }
        return services.allSatisfy { service in
            guard let live = liveStates[service] else {
                return false
            }
            return ProxyOverrideOwnership.isOwnedByRockxy(live.overrideState, port: ownedPort)
        }
    }
}

// MARK: - ProxyRecoveryPlan

/// The verdict for every service a recovery attempt considered.
struct ProxyRecoveryPlan: Equatable {
    // MARK: Lifecycle

    init(
        entriesToRestore: [ProxyServiceRecoveryJournalEntry],
        completedServices: [String],
        abandonedServices: [String],
        deferredServices: [String]
    ) {
        self.entriesToRestore = entriesToRestore
        self.completedServices = completedServices
        self.abandonedServices = abandonedServices
        self.deferredServices = deferredServices
    }

    // MARK: Internal

    /// The services this attempt may write, each at the stage it was recorded at. Re-checking a
    /// service immediately before its first command uses these, because the recorded stage is
    /// what says which live states still authorize a write.
    let entriesToRestore: [ProxyServiceRecoveryJournalEntry]
    let completedServices: [String]
    let abandonedServices: [String]
    let deferredServices: [String]

    /// The services that still need a restore point after this attempt is planned. A deferred
    /// service has to keep its entry, a completed or abandoned one must not.
    var servicesKeepingBackup: [String] {
        entriesToRestore.map(\.service) + deferredServices
    }
}

// MARK: - ProxyRecoveryPlanner

/// Turns a backup, its journal, and the live settings into the per-service decisions a recovery
/// attempt acts on.
enum ProxyRecoveryPlanner {
    /// - Parameters:
    ///   - targets: the captured pre-Rockxy settings, one per service the caller still owns.
    ///   - journal: whatever a previous attempt recorded; empty on the first attempt.
    ///   - liveStates: the settings read right now, keyed by service. A service missing from the
    ///     map could not be read and is deferred rather than guessed at.
    ///   - ownedPort: the loopback port this backup records as Rockxy's, when one is known. A
    ///     service with no usable record may only enter recovery when its complete live state
    ///     still proves Rockxy owns it on exactly that port. Nothing weaker will do: a restore
    ///     switches every proxy mode off before it writes anything, so a service that still
    ///     carries the strict override cannot be part-way through one — while a merely readable
    ///     service may be the user's own configuration, and recording that as "where the restore
    ///     begins" is how a user's settings end up written over.
    ///   - locallyMutatedServices: the services this very process has just issued override
    ///     commands for and has not confirmed. These are not authorized by name — a service is
    ///     recorded as touched before its first command runs, so the name alone cannot tell an
    ///     override that never mutated anything from a change somebody else made. What it buys
    ///     them is the second proof: live settings that are exactly one of the states applying
    ///     the override passes through, which is the evidence a half-applied service needs to be
    ///     undone at all.
    static func plan(
        targets: [ProxyServiceRestorationState],
        journal: [ProxyServiceRecoveryJournalEntry],
        liveStates: [String: ProxyServiceRestorationState],
        ownedPort: Int?,
        locallyMutatedServices: Set<String> = []
    )
        -> ProxyRecoveryPlan
    {
        var entriesToRestore: [ProxyServiceRecoveryJournalEntry] = []
        var completedServices: [String] = []
        var abandonedServices: [String] = []
        var deferredServices: [String] = []

        for target in targets {
            let live = liveStates[target.service]

            // An override record is answered first and on its own terms. It says the override was
            // being written to this service, not that a restore was, so the states that authorize
            // a write are the ones applying it passes through — which is the only evidence a
            // service left half-overridden by a crash ever has.
            if let application = overrideApplicationRecord(for: target, journal: journal) {
                switch ProxyOverrideApplicationRecoveryPolicy.continuation(
                    for: application,
                    live: live,
                    ownedPort: ownedPort
                ) {
                case let .rollBack(baseline):
                    // The rollback starts from what is live now, not from what was captured, so
                    // the record it writes describes the restore it is actually about to run.
                    entriesToRestore.append(ProxyServiceRecoveryJournalEntry(
                        service: target.service,
                        stage: .pending,
                        expectedPreStepState: baseline,
                        target: target
                    ))
                case .untouched:
                    completedServices.append(target.service)
                case .abandon:
                    abandonedServices.append(target.service)
                case .retryLater:
                    deferredServices.append(target.service)
                }
                continue
            }

            let entry = resolvedEntry(
                target: target,
                journal: journal,
                live: live,
                ownedPort: ownedPort,
                isLocallyMutated: locallyMutatedServices.contains(target.service)
            )

            guard let entry else {
                // There is no record this attempt may reason from, and nothing it may safely
                // invent. The restore point survives untouched for a later attempt.
                deferredServices.append(target.service)
                continue
            }

            switch ProxyServiceRecoveryPolicy.continuation(for: entry, live: live) {
            case .restore:
                entriesToRestore.append(entry)
            case .complete:
                completedServices.append(target.service)
            case .abandon:
                abandonedServices.append(target.service)
            case .retryLater:
                deferredServices.append(target.service)
            }
        }

        return ProxyRecoveryPlan(
            entriesToRestore: entriesToRestore,
            completedServices: completedServices,
            abandonedServices: abandonedServices,
            deferredServices: deferredServices
        )
    }

    /// The override record for this service, when the journal holds one that still describes the
    /// backup on disk. A record naming some other capture belongs to a different attempt, and a
    /// stale record is never a licence to write.
    private static func overrideApplicationRecord(
        for target: ProxyServiceRestorationState,
        journal: [ProxyServiceRecoveryJournalEntry]
    )
        -> ProxyServiceRecoveryJournalEntry?
    {
        journal.first {
            $0.service == target.service
                && $0.stage.isOverrideApplication
                && $0.describesRestore(of: target)
        }
    }

    /// The journal record this attempt reasons from, or nil when there is none it may use.
    ///
    /// A recorded entry that no longer describes the backup on disk is stale — it belongs to a
    /// different restore — so it is never trusted. It is not a licence to record whatever is live
    /// now as "the state recovery started from" either; only the same proof a service with no
    /// record at all has to give can do that.
    private static func resolvedEntry(
        target: ProxyServiceRestorationState,
        journal: [ProxyServiceRecoveryJournalEntry],
        live: ProxyServiceRestorationState?,
        ownedPort: Int?,
        isLocallyMutated: Bool
    )
        -> ProxyServiceRecoveryJournalEntry?
    {
        if let recorded = journal.first(where: {
            $0.service == target.service && !$0.stage.isOverrideApplication
        }), recorded.describesRestore(of: target) {
            return recorded
        }

        guard let live, baselineIsProven(
            live: live,
            target: target,
            ownedPort: ownedPort,
            isLocallyMutated: isLocallyMutated
        ) else {
            return nil
        }

        return ProxyServiceRecoveryJournalEntry(
            service: target.service,
            stage: .pending,
            expectedPreStepState: live,
            target: target
        )
    }

    /// Whether the live settings themselves prove this service is still Rockxy's, which is the
    /// only evidence a new baseline may be built on.
    ///
    /// There are exactly two proofs. A legacy completed override is one, but only when its entire
    /// restoration-relevant state equals the end of the known command sequence. A strict ownership
    /// projection is not enough because it omits the bypass list, the endpoint of disabled SOCKS,
    /// and the PAC URL. A state earlier in that exact sequence is the other proof, and it is
    /// available only to the process that just issued those commands — which is what lets an
    /// override that stopped after its second command be undone while a configuration nobody can
    /// account for is left exactly where it is.
    ///
    /// A backup that cannot name the port it overrode proves nothing about any service, so it
    /// baselines none of them: the services keep their restore points for an attempt that can.
    private static func baselineIsProven(
        live: ProxyServiceRestorationState,
        target: ProxyServiceRestorationState,
        ownedPort: Int?,
        isLocallyMutated: Bool
    )
        -> Bool
    {
        guard let ownedPort else {
            return false
        }
        guard ownedPort > 0 else {
            return false
        }
        let reachable = ProxyOverrideTransition.reachableStates(
            from: target,
            port: ownedPort
        )
        if live == reachable.last {
            return true
        }
        guard isLocallyMutated else {
            return false
        }
        return reachable.contains(live)
    }
}

// MARK: - ProxyRecoveryJournalCoding

/// Reads a persisted journal without letting one unreadable record cost the others.
///
/// A backup's journal is the only thing that tells a retry which services it may still write.
/// Decoding the array as a whole means a single record this build cannot parse erases the
/// records beside it, and services with perfectly good entries would silently lose the evidence
/// that authorizes their restore.
enum ProxyRecoveryJournalCoding {
    // MARK: Internal

    static func decodeEntries<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    )
        -> [ProxyServiceRecoveryJournalEntry]
    {
        guard container.contains(key) else {
            return []
        }
        if let entries = try? container.decode([ProxyServiceRecoveryJournalEntry].self, forKey: key) {
            return entries
        }
        guard let salvaged = try? container.decode([SalvagedEntry].self, forKey: key) else {
            return []
        }
        return salvaged.compactMap(\.entry)
    }

    // MARK: Private

    /// One journal record that decodes to nothing rather than failing, so the records after it
    /// are still reached.
    private struct SalvagedEntry: Decodable {
        // MARK: Lifecycle

        init(from decoder: any Decoder) throws {
            entry = try? ProxyServiceRecoveryJournalEntry(from: decoder)
        }

        // MARK: Internal

        let entry: ProxyServiceRecoveryJournalEntry?
    }
}
