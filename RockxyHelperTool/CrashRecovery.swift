import Foundation
import os

// MARK: - CrashRecoveryError

enum CrashRecoveryError: LocalizedError {
    case backupOwnedByAnotherSession
    case backupUnreadable

    var errorDescription: String? {
        switch self {
        case .backupOwnedByAnotherSession:
            "Another app process owns the existing proxy recovery backup"
        case .backupUnreadable:
            "The proxy recovery backup exists but could not be read safely"
        }
    }
}

/// Manages proxy settings backup and crash recovery.
/// Stores original proxy configuration to a plist file before Rockxy overrides it.
/// On daemon launch, checks for stale backups indicating a previous crash and restores settings.
enum CrashRecovery {
    // MARK: Internal

    // MARK: - Backup Data

    struct ServiceProxyBackup: Codable {
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

    struct ProxyBackup: Codable {
        // MARK: Lifecycle

        init(
            services: [ServiceProxyBackup],
            timestamp: Date,
            rockxyPort: Int?,
            ownerPID: Int32?,
            ownerStartSignature: String?,
            ownerUID: uid_t? = nil,
            recoveryPending: Bool = false,
            journal: [ProxyServiceRecoveryJournalEntry] = [],
            copyRole: ProxyBackupCopyRole? = nil
        ) {
            self.services = services
            self.timestamp = timestamp
            self.rockxyPort = rockxyPort
            self.ownerPID = ownerPID
            self.ownerStartSignature = ownerStartSignature
            self.ownerUID = ownerUID
            self.recoveryPending = recoveryPending
            self.journal = journal
            self.copyRole = copyRole
        }

        /// Backups written before owner identity existed decode with no owner, which recovery
        /// reads as "the session that took this override is gone". A backup written before the
        /// recovery journal existed decodes with an empty journal, which recovery reads as "no
        /// step has been recorded for these services yet". One written before the copy marker
        /// existed decodes with no role, which is what keeps its compatibility location readable
        /// by this build.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            services = try container.decode([ServiceProxyBackup].self, forKey: .services)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            rockxyPort = try container.decodeIfPresent(Int.self, forKey: .rockxyPort)
            ownerPID = try container.decodeIfPresent(Int32.self, forKey: .ownerPID)
            ownerStartSignature = try container.decodeIfPresent(String.self, forKey: .ownerStartSignature)
            ownerUID = try container.decodeIfPresent(uid_t.self, forKey: .ownerUID)
            recoveryPending = try container.decodeIfPresent(Bool.self, forKey: .recoveryPending) ?? false
            // A journal record this build cannot read must not cost the backup its restore point,
            // and must not cost the records beside it either: each one is read on its own, and a
            // service left without a usable record is deferred rather than rebaselined from
            // settings that may now belong to the user.
            journal = ProxyRecoveryJournalCoding.decodeEntries(from: container, forKey: .journal)
            copyRole = try? container.decodeIfPresent(ProxyBackupCopyRole.self, forKey: .copyRole)
        }

        // MARK: Internal

        let services: [ServiceProxyBackup]
        let timestamp: Date
        let rockxyPort: Int?
        /// The Rockxy app process that asked for the override, and the kernel start time that
        /// tells it apart from a later process which inherited the same PID.
        let ownerPID: Int32?
        let ownerStartSignature: String?
        let ownerUID: uid_t?
        /// True after recovery has narrowed the backup and before every retained entry has been
        /// fully restored. Kept so a build that predates the journal still reads this backup the
        /// way it always has.
        let recoveryPending: Bool
        /// Per-service recovery intent. Each entry records the state its step expected to find
        /// and the state that step leaves behind, which is what lets a retry tell an interrupted
        /// restore apart from a service the user has since changed.
        let journal: [ProxyServiceRecoveryJournalEntry]
        /// Which on-disk copy this is. Absent only on a backup written before the marker existed.
        let copyRole: ProxyBackupCopyRole?

        /// The same backup labelled as one of its copies, which is what distinguishes the record
        /// a commit publishes from the one kept only so an older build can still find something.
        func markedAs(_ role: ProxyBackupCopyRole) -> ProxyBackup {
            ProxyBackup(
                services: services,
                timestamp: timestamp,
                rockxyPort: rockxyPort,
                ownerPID: ownerPID,
                ownerStartSignature: ownerStartSignature,
                ownerUID: ownerUID,
                recoveryPending: recoveryPending,
                journal: journal,
                copyRole: role
            )
        }

        // MARK: Private

        private enum CodingKeys: String, CodingKey {
            case services
            case timestamp
            case rockxyPort
            case ownerPID
            case ownerStartSignature
            case ownerUID
            case recoveryPending
            case journal
            case copyRole
        }
    }

    /// The still-live owner a preserved backup belongs to. The start signature travels with the
    /// identifier so the re-armed watchdog watches the same process, not whatever later inherits
    /// its PID. It is not optional: a preserved owner has just been authenticated against that
    /// exact signature, so there is always one to hand on.
    struct PreservedOwner: Equatable {
        // MARK: Lifecycle

        init(processIdentifier: Int32, startSignature: String, userID: uid_t?) {
            self.processIdentifier = processIdentifier
            self.startSignature = startSignature
            self.userID = userID
        }

        // MARK: Internal

        let processIdentifier: Int32
        let startSignature: String
        let userID: uid_t?
    }

    /// What launch-time recovery did with the backup it found.
    enum StartupRecoveryOutcome: Equatable {
        case noBackup
        case cleared
        case restored
        case restoreIncomplete
        /// The recorded owner is still alive and still passes caller validation, so its override
        /// stays in place. The owner identity is handed back so the helper can re-arm its
        /// watchdog against the same process.
        case preserved(owner: PreservedOwner?)
    }

    // MARK: - Public API

    /// Save current proxy settings for all specified services before overriding them.
    /// The owning app process is recorded with the backup so a later helper launch can tell a
    /// still-running session from a stranded override. The caller supplies the start signature it
    /// already acquired, so the identity written here is the same one the watchdog watches.
    @discardableResult
    static func saveOriginalSettings(
        services: [String],
        rockxyPort: Int,
        ownerPID: Int32,
        ownerStartSignature: String,
        ownerUID: uid_t
    ) throws -> ProxyBackup {
        let existingBackup = try loadBackup()
        if let existingBackup,
           !HelperBoundProcessIdentityPolicy.recordedSessionBelongsToCaller(
               recordedOwnerPID: existingBackup.ownerPID,
               recordedOwnerStartSignature: existingBackup.ownerStartSignature,
               callerPID: ownerPID,
               callerStartSignature: ownerStartSignature
           )
        {
            throw CrashRecoveryError.backupOwnedByAnotherSession
        }
        let existingServices = Set(existingBackup?.services.map(\.service) ?? [])
        let servicesToCapture = services.filter { !existingServices.contains($0) }

        if servicesToCapture.isEmpty {
            logger.info("Preserving the existing proxy backup for \(existingServices.count) service(s)")
        } else {
            logger.info("Saving original proxy settings for \(servicesToCapture.count) new service(s)")
        }

        var serviceBackups: [ServiceProxyBackup] = []
        for service in servicesToCapture {
            do {
                let httpOutput = try readProxySettings(type: "webproxy", service: service)
                let httpsOutput = try readProxySettings(type: "securewebproxy", service: service)
                let socksOutput = try readProxySettings(type: "socksfirewallproxy", service: service)
                let pacOutput = try readProxySettings(type: "autoproxyurl", service: service)
                let autoDiscoveryOutput = try readProxySettings(type: "proxyautodiscovery", service: service)
                let bypassDomains = try readBypassDomains(service: service)

                let httpInfo = ProxyConfigurator.parseProxyOutput(httpOutput)
                let httpsInfo = ProxyConfigurator.parseProxyOutput(httpsOutput)
                let socksInfo = ProxyConfigurator.parseProxyOutput(socksOutput)
                let pacInfo = ProxyConfigurator.parsePACOutput(pacOutput)

                let serviceBackup = ServiceProxyBackup(
                    service: service,
                    httpEnabled: httpInfo.enabled,
                    httpHost: httpInfo.host,
                    httpPort: httpInfo.port,
                    httpsEnabled: httpsInfo.enabled,
                    httpsHost: httpsInfo.host,
                    httpsPort: httpsInfo.port,
                    socksEnabled: socksInfo.enabled,
                    socksHost: socksInfo.host,
                    socksPort: socksInfo.port,
                    pacEnabled: pacInfo.enabled,
                    pacURL: pacInfo.url,
                    autoDiscoveryEnabled: ProxyConfigurator.parseAutoDiscoveryOutput(autoDiscoveryOutput),
                    bypassDomains: bypassDomains
                )
                serviceBackups.append(serviceBackup)
                logger.debug("Captured proxy state for '\(service)'")
            } catch {
                logger
                    .error(
                        "Failed to read proxy settings for '\(service)': \(error.localizedDescription) — aborting backup"
                    )
                throw error
            }
        }

        // Whatever the previous attempt recorded travels with the extended backup. See
        // `ProxyBackupExtension` for why adding a service or changing the port must never be the
        // moment a record is dropped.
        let carried = ProxyBackupExtension.carriedForward(
            journal: existingBackup?.journal,
            recoveryPending: existingBackup?.recoveryPending
        )
        let backup = ProxyBackup(
            services: (existingBackup?.services ?? []) + serviceBackups,
            timestamp: existingBackup?.timestamp ?? Date(),
            rockxyPort: rockxyPort,
            ownerPID: ownerPID,
            ownerStartSignature: ownerStartSignature,
            ownerUID: ownerUID,
            recoveryPending: carried.recoveryPending,
            journal: carried.journal
        )

        do {
            try persist(backup)
            logger
                .info(
                    "Proxy backup saved to \(backupURLs.first?.path ?? "<unknown>") (\(backup.services.count) service(s))"
                )
        } catch {
            logger.error("Failed to save proxy backup: \(error.localizedDescription)")
            throw error
        }

        return backup
    }

    /// Writes a backup to every backup location with owner-only permissions.
    /// Used both for the initial capture and for the reduced backup a subset restore persists
    /// before it touches any setting.
    ///
    /// One location is authoritative and its publication is the commit: it either happened or it
    /// did not, with nothing left to fail afterwards. The second location exists so a build that
    /// predates the current support directory can still find a backup.
    ///
    /// The compatibility copies are dealt with *before* the commit, and a copy that can be neither
    /// marked nor removed stops this call before the commit is attempted. That order is the whole
    /// guarantee. A build older than the marker wrote unmarked bytes to both locations, and this
    /// build reads an unmarked compatibility copy as truth — correctly, because for that build it
    /// was the only backup there was. Committing first and mirroring afterwards would leave those
    /// stale unmarked bytes sitting beside a record that had already moved on, and the moment the
    /// authoritative file was lost they would be read back and written onto the user's services.
    /// Marking the copy first means an unmarked one can only survive where no commit in the
    /// current format ever succeeded, which is exactly when it is the honest answer.
    ///
    /// A throw therefore means nothing was committed, which is what the callers that treat a
    /// successful write as their permission to issue a command depend on.
    static func persist(_ backup: ProxyBackup) throws {
        guard let authoritativeURL = backupURLs.first else {
            return
        }
        try ensureBackupDirectoryExists(for: authoritativeURL)

        let encoder = PropertyListEncoder()
        let authoritativeData = try encoder.encode(backup.markedAs(.authoritative))
        let mirrorData = try encoder.encode(backup.markedAs(.mirror))

        try ProxyBackupCommit.run(
            prepareCompatibilityCopies: {
                for url in backupURLs.dropFirst() {
                    try prepareCompatibilityCopy(mirrorData, at: url)
                }
            },
            publishAuthoritative: {
                try ProxyBackupFilePublication.publish(authoritativeData, to: authoritativeURL)
            }
        )
    }

    /// Narrows the backup on disk to `services` before a subset restore mutates anything, and
    /// records the recovery intent for exactly those services.
    ///
    /// Dropping the entries recovery no longer owns is what stops a later retry from writing
    /// stale settings over a service the user has since changed; writing the journal in the same
    /// step is what lets that retry tell an interrupted restore apart from such a change.
    ///
    /// `recoveryPending` says whether this narrowing is about to be followed by a write. An
    /// attempt that decided to write nothing leaves the flag alone, because marking recovery as
    /// started would cost every service in the backup the one chance it has to record the state
    /// its restore begins from.
    @discardableResult
    static func reduceBackup(
        _ backup: ProxyBackup,
        to services: [String],
        rockxyPort: Int? = nil,
        journal: [ProxyServiceRecoveryJournalEntry]? = nil,
        recoveryPending: Bool = true
    )
        throws -> ProxyBackup
    {
        let retainedServices = Set(services)
        let retainedJournal = ProxyBackupSubset.select(
            journal ?? backup.journal,
            services: retainedServices,
            serviceName: \.service
        )
        let reduced = ProxyBackup(
            services: ProxyBackupSubset.select(
                backup.services,
                services: retainedServices,
                serviceName: \.service
            ),
            timestamp: backup.timestamp,
            rockxyPort: backup.rockxyPort ?? rockxyPort,
            ownerPID: backup.ownerPID,
            ownerStartSignature: backup.ownerStartSignature,
            ownerUID: backup.ownerUID,
            recoveryPending: recoveryPending,
            journal: retainedJournal
        )
        try persist(reduced)
        return reduced
    }

    /// Records what an override is about to do, without narrowing the backup or disturbing the
    /// session that owns it.
    ///
    /// This is not `reduceBackup`. That one is recovery's own bookkeeping: it drops the services
    /// recovery no longer owns and says a recovery has started. None of that is true here — the
    /// override has not begun, every captured service
    /// still needs its entry, and the owner is precisely the session being recorded. Only the
    /// journal changes.
    @discardableResult
    static func recordOverrideApplication(
        _ backup: ProxyBackup,
        journal: [ProxyServiceRecoveryJournalEntry]
    )
        throws -> ProxyBackup
    {
        let recorded = ProxyBackup(
            services: backup.services,
            timestamp: backup.timestamp,
            rockxyPort: backup.rockxyPort,
            ownerPID: backup.ownerPID,
            ownerStartSignature: backup.ownerStartSignature,
            ownerUID: backup.ownerUID,
            recoveryPending: backup.recoveryPending,
            journal: journal
        )
        try persist(recorded)
        return recorded
    }

    /// Drops the entries an override attempt captured for services it then never touched, leaving
    /// the owner identity and everything else exactly as it is.
    ///
    /// This is not `reduceBackup`. That one is recovery's own bookkeeping: it drops the services
    /// recovery no longer owns and says a recovery has started. None of that is true here — the
    /// session is running and still owns everything that
    /// is left. What goes is only what describes settings nobody overrode, because keeping it
    /// would hand the next override a snapshot older than whatever the user has set since.
    @discardableResult
    static func dropUntouchedCapturedServices(
        _ backup: ProxyBackup,
        services: [String]
    )
        throws -> ProxyBackup
    {
        let dropped = Set(services)
        guard backup.services.contains(where: { dropped.contains($0.service) }) else {
            return backup
        }
        let narrowed = ProxyBackup(
            services: backup.services.filter { !dropped.contains($0.service) },
            timestamp: backup.timestamp,
            rockxyPort: backup.rockxyPort,
            ownerPID: backup.ownerPID,
            ownerStartSignature: backup.ownerStartSignature,
            ownerUID: backup.ownerUID,
            recoveryPending: backup.recoveryPending,
            journal: backup.journal.filter { !dropped.contains($0.service) }
        )
        try persist(narrowed)
        return narrowed
    }

    /// Check for stale backup on daemon launch and restore if found.
    /// A backup existing at launch time means the previous session ended without restoring proxy
    /// settings — unless its owner is still running, which the recorded process identity proves.
    @discardableResult
    static func restoreIfNeeded() -> StartupRecoveryOutcome {
        guard hasBackup() else {
            logger.info("No stale proxy backup found — clean startup")
            return .noBackup
        }

        let backup: ProxyBackup
        do {
            guard let loadedBackup = try loadBackup() else {
                logger.info("No readable proxy backup remains — clean startup")
                return .noBackup
            }
            backup = loadedBackup
        } catch {
            logger.error("Backup file exists but could not be read — preserving it for retry")
            return .restoreIncomplete
        }

        // Legacy backups predate the persisted port, so fall back to the port the backed-up
        // services are still overriding, then to the port the live status reports. With none of
        // those, nothing can be identified as Rockxy-owned.
        let backedUpServices = backup.services.map(\.service)
        // One read serves every question below: which services still carry the override, which
        // port they carry it on, and whether the recorded session ever finished applying it.
        let liveStates = ProxyConfigurator.currentRestorationStates(for: backedUpServices)
        let overrideStates = backedUpServices.map {
            liveStates[$0]?.overrideState ?? ProxyServiceOverrideState.unreadable(service: $0)
        }
        if liveStates.count != backedUpServices.count {
            // A failed read is not evidence that an override disappeared. This is especially
            // important for backups created before journaling, where strict ownership would
            // otherwise see no residual service and discard the only restore point.
            logger.error("At least one backed-up service is unreadable — preserving backup for retry")
            return .restoreIncomplete
        }
        let fallbackPort: () -> Int? = {
            if let inferredPort = ProxyOverrideOwnership.inferredOwnedPort(in: overrideStates) {
                return inferredPort
            }
            let status = ProxyConfigurator.getCurrentStatus()
            return status.isOverridden ? status.port : nil
        }
        let ownedPort = backup.rockxyPort ?? fallbackPort()
        guard backup.recoveryPending || ownedPort != nil else {
            logger.info("No Rockxy-owned port could be identified — clearing stale backup")
            clearBackup()
            return .cleared
        }

        // A recovery already under way keeps every retained service in play: a partial command
        // can leave a shape strict ownership no longer recognises. Which of those services may
        // still be written is then decided per service against the recovery journal, so a
        // service the user changed between attempts is dropped rather than overwritten.
        let residualOwnedServices = if backup.recoveryPending || !backup.journal.isEmpty {
            backedUpServices
        } else {
            ProxyOverrideOwnership.residualOwnedServices(in: overrideStates, port: ownedPort ?? 0)
        }

        // A live owner only keeps its session when that session is provably finished: every
        // backed-up service carrying the exact state its own record says the override ends at. An
        // application that stopped part-way left a service that is neither Rockxy's nor the user's,
        // and the sequence that would have completed it has already failed — so the owner still
        // being alive is not a reason to leave that shape on the machine. It is recovered now,
        // while the record that explains it is still readable.
        let sessionIsComplete = !backup.recoveryPending
            && ProxyOverrideSessionCompletionPolicy.sessionIsFullyApplied(
                services: backedUpServices,
                journal: backup.journal,
                liveStates: liveStates,
                ownedPort: ownedPort
            )
        let liveOwner = sessionIsComplete ? liveOwner(for: backup) : nil
        if !sessionIsComplete, !backup.recoveryPending, !backup.journal.isEmpty {
            logger
                .warning(
                    "The recorded proxy session did not finish applying its override — recovering it rather than preserving it"
                )
        }

        switch ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: !residualOwnedServices.isEmpty,
            ownerSessionIsLive: liveOwner != nil
        ) {
        case .restore:
            logger
                .warning(
                    "Owned proxy backup has no live owner — restoring \(residualOwnedServices.count) residual service(s)"
                )
            do {
                try ProxyConfigurator.restoreOwnedServicesOrThrow(
                    ownedServices: residualOwnedServices,
                    port: ownedPort
                )
                return .restored
            } catch {
                logger.error("Stale proxy restore incomplete: \(error.localizedDescription)")
                return .restoreIncomplete
            }
        case .preserve:
            logger.info("Owned proxy backup belongs to a live authenticated owner — preserving the active session")
            return .preserved(owner: liveOwner)
        case .clear:
            logger.info("No backed-up service still points at the Rockxy session — clearing stale backup")
            clearBackup()
            return .cleared
        }
    }

    /// The recorded owner, but only when it is still the same live process *and* still passes
    /// caller validation as the Rockxy app. A recycled PID, a legacy backup with no recorded
    /// identity, or a process that no longer validates all resolve to nil, which makes recovery
    /// treat the override as stranded.
    ///
    /// The recorded start signature is returned with the identifier: this call has just proved it
    /// names the live process, so the watchdog that gets re-armed can keep checking against it
    /// instead of trusting the PID on its own.
    static func liveOwner(for backup: ProxyBackup) -> PreservedOwner? {
        guard let ownerPID = backup.ownerPID, ownerPID > 0 else {
            return nil
        }

        let ownerIsAlive = ProcessStartIdentity.isAlive(ownerPID)
        let liveStartSignature = ownerIsAlive ? ProcessStartIdentity.startSignature(for: ownerPID) : nil
        let passesCallerValidation = ownerIsAlive && CallerValidation.validateCaller(
            pid: ownerPID,
            allowedIdentifiers: RockxyIdentity.current.allowedCallerIdentifiers
        )

        guard ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
            recordedOwnerPID: ownerPID,
            recordedStartSignature: backup.ownerStartSignature,
            ownerProcessIsAlive: ownerIsAlive,
            liveStartSignature: liveStartSignature,
            ownerPassesCallerValidation: passesCallerValidation
        ) else {
            return nil
        }

        guard let ownerStartSignature = backup.ownerStartSignature, !ownerStartSignature.isEmpty else {
            // Unreachable in practice: the identity check above only passes when a signature was
            // recorded. Refusing here keeps that guarantee local rather than assumed.
            return nil
        }

        return PreservedOwner(
            processIdentifier: ownerPID,
            startSignature: ownerStartSignature,
            userID: backup.ownerUID
        )
    }

    /// Load the backup data from disk.
    /// Returns nil only when no copy exists. An unreadable or unrecognized copy is preserved and
    /// reported as an error so a transient filesystem failure can never be mistaken for a clean
    /// restore and delete the only recovery point.
    ///
    /// A compatibility copy can be a legacy unmarked backup or a current marked mirror. Current
    /// writers prepare mirrors before the authoritative publication, so a surviving marked copy is
    /// either the committed record or a safe record whose later commit failed and authorized no
    /// command. Either preserves the exact restore point when the authoritative file is unavailable.
    static func loadBackup() throws -> ProxyBackup? {
        var foundUnusableCopy = false
        for (index, url) in backupURLs.enumerated() {
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                let backup = try PropertyListDecoder().decode(ProxyBackup.self, from: data)
                guard ProxyBackupCopyPolicy.isRecoveryTruth(
                    role: backup.copyRole,
                    isAuthoritativeLocation: index == 0
                ) else {
                    logger.warning("Ignoring a proxy backup whose copy role does not match its location at \(url.path)")
                    foundUnusableCopy = true
                    continue
                }
                return backup
            } catch {
                logger.error("Failed to decode proxy backup at \(url.path): \(error.localizedDescription)")
                foundUnusableCopy = true
            }
        }
        if foundUnusableCopy {
            throw CrashRecoveryError.backupUnreadable
        }
        return nil
    }

    /// Returns whether a backup file exists on disk.
    static func hasBackup() -> Bool {
        backupURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Remove the backup file after successful restore.
    static func clearBackup() {
        for url in backupURLs {
            do {
                try FileManager.default.removeItem(at: url)
                logger.info("Proxy backup cleared at \(url.path)")
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
            {
                // Already gone — nothing to do
            } catch {
                logger.error("Failed to remove proxy backup at \(url.path): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "CrashRecovery"
    )

    private static let legacyBackupDirectory = "/Library/Application Support/com.amunx.Rockxy"
    private static let backupFileName = "proxy-backup.plist"

    private static var backupURLs: [URL] {
        [
            RockxyIdentity.current.sharedSupportDirectory().appendingPathComponent(backupFileName),
            URL(fileURLWithPath: legacyBackupDirectory).appendingPathComponent(backupFileName),
        ]
    }

    // MARK: - Private Helpers

    /// Creates the directory one backup location lives in, with owner-only permissions.
    ///
    /// The authoritative location and every compatibility location must be ready before the
    /// authoritative record is committed. A compatibility path that can be neither prepared nor
    /// cleared blocks the commit so stale unmarked bytes cannot survive beside newer truth.
    private static func ensureBackupDirectoryExists(for url: URL) throws {
        let dir = url.deletingLastPathComponent()
        guard !FileManager.default.fileExists(atPath: dir.path) else {
            return
        }
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: ProxyBackupFilePublication.ownerOnlyDirectoryPermissions]
        )
    }

    /// Brings one compatibility copy up to date before the authoritative commit is attempted, or
    /// leaves nothing there a later loader could mistake for truth.
    ///
    /// Writing the marked copy is the ordinary path. When that cannot be done, removing whatever
    /// is at the location is just as good an answer: an absent compatibility copy is never read,
    /// so nothing stale can survive the commit that follows. Only a file that can be neither
    /// rewritten nor removed is a genuine blocker, and that throws — before anything is committed
    /// and therefore before any command is authorized.
    private static func prepareCompatibilityCopy(_ data: Data, at url: URL) throws {
        let outcome = try ProxyBackupCompatibilityCopy.prepare(
            publish: {
                try ensureBackupDirectoryExists(for: url)
                try ProxyBackupFilePublication.publish(data, to: url)
            },
            remove: { try? FileManager.default.removeItem(at: url) },
            copyExists: { FileManager.default.fileExists(atPath: url.path) }
        )
        if outcome == .invalidated {
            logger
                .warning(
                    "Could not write the compatibility proxy backup at \(url.path) — removed the stale copy instead"
                )
        }
    }

    private static func readBypassDomains(service: String) throws -> [String] {
        ProxyBypassDomainOutput.parse(try readProxySettings(type: "proxybypassdomains", service: service))
    }

    private static func readProxySettings(type: String, service: String) throws -> String {
        let allowedTypes: Set = [
            "webproxy",
            "securewebproxy",
            "socksfirewallproxy",
            "autoproxyurl",
            "proxyautodiscovery",
            "proxybypassdomains",
        ]
        guard allowedTypes.contains(type) else {
            throw ProxyConfiguratorError.executionFailed(command: "-get\(type)", reason: "Invalid proxy type: \(type)")
        }

        let networkSetupPath = "/usr/sbin/networksetup"
        guard BinaryValidator.validateAppleSignedBinary(at: networkSetupPath) else {
            throw ProxyConfiguratorError.executionFailed(
                command: "-get\(type)",
                reason: "networksetup binary failed Apple code signature validation"
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: networkSetupPath)
        process.arguments = ["-get\(type)", service]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
