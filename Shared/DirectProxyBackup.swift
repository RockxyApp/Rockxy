import Foundation

// The direct-mode proxy backup, shared by the app that writes it and the helper binary that is
// launched as its watchdog. One definition rather than two: the two processes read and write
// the same file, so a field either of them decoded differently would be a silent divergence in
// exactly the record recovery depends on.

// MARK: - ProxyBackupExtension

/// What a backup carries forward when an override attempt extends it.
///
/// An attempt that adds a newly enabled service, or takes the same services on a different port,
/// rewrites the backup. Neither is a reason to forget what any service was already in the middle
/// of. A journal record dropped here is the only thing that could have told a later attempt which
/// live states it may still write, so losing it turns an override this backup already covers into
/// one nothing can prove is Rockxy's — abandoned rather than undone, and left on the user's
/// machine. The mid-recovery flag travels with it for the same reason: a rewrite that forgot it
/// would hand every later launch a backup claiming no recovery had ever begun.
enum ProxyBackupExtension {
    static func carriedForward(
        journal: [ProxyServiceRecoveryJournalEntry]?,
        recoveryPending: Bool?
    )
        -> (journal: [ProxyServiceRecoveryJournalEntry], recoveryPending: Bool)
    {
        (journal ?? [], recoveryPending ?? false)
    }
}

// MARK: - DirectProxyBackup

/// Persistent on-disk backup of the pre-Rockxy proxy state for all services.
/// Written before any direct-mode mutation; cleared after successful restore.
struct DirectProxyBackup: Codable {
    init(
        services: [DirectServiceBackup],
        timestamp: Date,
        rockxyPort: Int,
        ownerPID: Int32? = nil,
        ownerStartSignature: String? = nil,
        recoveryPending: Bool = false,
        journal: [ProxyServiceRecoveryJournalEntry] = []
    ) {
        self.services = services
        self.timestamp = timestamp
        self.rockxyPort = rockxyPort
        self.ownerPID = ownerPID
        self.ownerStartSignature = ownerStartSignature
        self.recoveryPending = recoveryPending
        self.journal = journal
    }

    /// A backup written before the recovery journal existed decodes with an empty journal, which
    /// recovery reads as "no step has been recorded for these services yet". A record this build
    /// cannot read degrades the same way rather than costing the backup its restore point — and
    /// only that record: the ones beside it are read on their own, so one unusable entry never
    /// erases the evidence that authorizes an unrelated service's restore.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        services = try container.decode([DirectServiceBackup].self, forKey: .services)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        rockxyPort = try container.decode(Int.self, forKey: .rockxyPort)
        ownerPID = try container.decodeIfPresent(Int32.self, forKey: .ownerPID)
        ownerStartSignature = try container.decodeIfPresent(String.self, forKey: .ownerStartSignature)
        recoveryPending = try container.decodeIfPresent(Bool.self, forKey: .recoveryPending) ?? false
        journal = ProxyRecoveryJournalCoding.decodeEntries(from: container, forKey: .journal)
    }

    let services: [DirectServiceBackup]
    let timestamp: Date
    let rockxyPort: Int
    /// Exact app process that owns this override. Legacy backups decode without an owner and are
    /// therefore recoverable, never assumed to belong to whichever process happens to launch.
    let ownerPID: Int32?
    let ownerStartSignature: String?
    /// Kept so a build that predates the journal still reads this backup the way it always has.
    let recoveryPending: Bool
    /// Per-service recovery intent: the state each step expected to find and the state it leaves
    /// behind, which is what lets a retry tell an interrupted restore apart from a service the
    /// user has since changed.
    let journal: [ProxyServiceRecoveryJournalEntry]

    private enum CodingKeys: String, CodingKey {
        case services
        case timestamp
        case rockxyPort
        case ownerPID
        case ownerStartSignature
        case recoveryPending
        case journal
    }

    /// The same backup with individual parts replaced. `recoveryPending` defaults to the flag
    /// this backup already carries: narrowing a backup is not the same act as starting to write
    /// one, and only the write may claim recovery has begun.
    func with(
        services: [DirectServiceBackup]? = nil,
        journal: [ProxyServiceRecoveryJournalEntry]? = nil,
        recoveryPending: Bool? = nil
    )
        -> DirectProxyBackup
    {
        DirectProxyBackup(
            services: services ?? self.services,
            timestamp: timestamp,
            rockxyPort: rockxyPort,
            ownerPID: ownerPID,
            ownerStartSignature: ownerStartSignature,
            recoveryPending: recoveryPending ?? self.recoveryPending,
            journal: journal ?? self.journal
        )
    }
}

// MARK: - DirectProxyBackup + Extension

extension DirectProxyBackup {
    /// The backup covering everything `existing` already held plus the services just captured.
    ///
    /// Everything the previous attempt recorded travels with it. See `ProxyBackupExtension` for
    /// why adding a service or changing the port must never be the moment a record is dropped.
    static func extending(
        _ existing: DirectProxyBackup?,
        with additions: [DirectServiceBackup],
        rockxyPort: Int,
        now: Date,
        ownerPID: Int32? = nil,
        ownerStartSignature: String? = nil
    )
        -> DirectProxyBackup
    {
        let carried = ProxyBackupExtension.carriedForward(
            journal: existing?.journal,
            recoveryPending: existing?.recoveryPending
        )
        return DirectProxyBackup(
            services: (existing?.services ?? []) + additions,
            timestamp: existing?.timestamp ?? now,
            rockxyPort: rockxyPort,
            ownerPID: existing?.ownerPID ?? ownerPID,
            ownerStartSignature: existing?.ownerStartSignature ?? ownerStartSignature,
            recoveryPending: carried.recoveryPending,
            journal: carried.journal
        )
    }
}

// MARK: - DirectProxyBackupOwnerPolicy

/// Binds one direct-mode restore point to the exact app process that created it.
enum DirectProxyBackupOwnerPolicy {
    static func belongsToSession(
        _ backup: DirectProxyBackup,
        processIdentifier: Int32,
        processStartSignature: String?
    )
        -> Bool
    {
        backup.ownerPID == processIdentifier
            && ProcessStartIdentity.identifiesSameProcess(
                recordedPID: backup.ownerPID,
                recordedStartSignature: backup.ownerStartSignature,
                liveStartSignature: processStartSignature
            )
    }

    static func ownerIsLive(
        _ backup: DirectProxyBackup,
        processIsAlive: (Int32) -> Bool,
        liveStartSignature: (Int32) -> String?
    )
        -> Bool
    {
        guard let ownerPID = backup.ownerPID, processIsAlive(ownerPID) else {
            return false
        }
        return ProcessStartIdentity.identifiesSameProcess(
            recordedPID: ownerPID,
            recordedStartSignature: backup.ownerStartSignature,
            liveStartSignature: liveStartSignature(ownerPID)
        )
    }
}

// MARK: - DirectServiceBackup

/// Per-service proxy configuration captured before Rockxy overrides it.
struct DirectServiceBackup: Codable {
    // MARK: Lifecycle

    init(
        service: String,
        httpEnabled: Bool,
        httpHost: String,
        httpPort: Int,
        httpsEnabled: Bool,
        httpsHost: String,
        httpsPort: Int,
        socksEnabled: Bool,
        socksHost: String,
        socksPort: Int,
        pacEnabled: Bool,
        pacURL: String,
        autoDiscoveryEnabled: Bool,
        bypassDomains: [String]
    ) {
        self.service = service
        self.httpEnabled = httpEnabled
        self.httpHost = httpHost
        self.httpPort = httpPort
        self.httpsEnabled = httpsEnabled
        self.httpsHost = httpsHost
        self.httpsPort = httpsPort
        self.socksEnabled = socksEnabled
        self.socksHost = socksHost
        self.socksPort = socksPort
        self.pacEnabled = pacEnabled
        self.pacURL = pacURL
        self.autoDiscoveryEnabled = autoDiscoveryEnabled
        self.bypassDomains = bypassDomains
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        service = try container.decode(String.self, forKey: .service)
        httpEnabled = try container.decode(Bool.self, forKey: .httpEnabled)
        httpHost = try container.decode(String.self, forKey: .httpHost)
        httpPort = try container.decode(Int.self, forKey: .httpPort)
        httpsEnabled = try container.decode(Bool.self, forKey: .httpsEnabled)
        httpsHost = try container.decode(String.self, forKey: .httpsHost)
        httpsPort = try container.decode(Int.self, forKey: .httpsPort)
        socksEnabled = try container.decodeIfPresent(Bool.self, forKey: .socksEnabled) ?? false
        socksHost = try container.decodeIfPresent(String.self, forKey: .socksHost) ?? ""
        socksPort = try container.decodeIfPresent(Int.self, forKey: .socksPort) ?? 0
        pacEnabled = try container.decodeIfPresent(Bool.self, forKey: .pacEnabled) ?? false
        pacURL = try container.decodeIfPresent(String.self, forKey: .pacURL) ?? ""
        autoDiscoveryEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoDiscoveryEnabled) ?? false
        bypassDomains = try container.decode([String].self, forKey: .bypassDomains)
    }

    // MARK: Internal

    let service: String
    let httpEnabled: Bool
    let httpHost: String
    let httpPort: Int
    let httpsEnabled: Bool
    let httpsHost: String
    let httpsPort: Int
    let socksEnabled: Bool
    let socksHost: String
    let socksPort: Int
    let pacEnabled: Bool
    let pacURL: String
    let autoDiscoveryEnabled: Bool
    let bypassDomains: [String]

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case service
        case httpEnabled
        case httpHost
        case httpPort
        case httpsEnabled
        case httpsHost
        case httpsPort
        case socksEnabled
        case socksHost
        case socksPort
        case pacEnabled
        case pacURL
        case autoDiscoveryEnabled
        case bypassDomains
    }
}

// MARK: - DirectServiceBackup + Restoration

extension DirectServiceBackup {
    /// The captured pre-Rockxy settings for this service, in the shape recovery compares against.
    var restorationTarget: ProxyServiceRestorationState {
        ProxyServiceRestorationState(
            service: service,
            http: ProxyEndpointState(enabled: httpEnabled, host: httpHost, port: httpPort),
            https: ProxyEndpointState(enabled: httpsEnabled, host: httpsHost, port: httpsPort),
            socks: ProxyEndpointState(enabled: socksEnabled, host: socksHost, port: socksPort),
            pacEnabled: pacEnabled,
            pacURL: pacURL,
            autoDiscoveryEnabled: autoDiscoveryEnabled,
            bypassDomains: bypassDomains
        )
    }
}
