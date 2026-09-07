import Foundation
import os

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
            recoveryPending: Bool = false
        ) {
            self.services = services
            self.timestamp = timestamp
            self.rockxyPort = rockxyPort
            self.ownerPID = ownerPID
            self.ownerStartSignature = ownerStartSignature
            self.recoveryPending = recoveryPending
        }

        /// Backups written before owner identity existed decode with no owner, which recovery
        /// reads as "the session that took this override is gone".
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            services = try container.decode([ServiceProxyBackup].self, forKey: .services)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            rockxyPort = try container.decodeIfPresent(Int.self, forKey: .rockxyPort)
            ownerPID = try container.decodeIfPresent(Int32.self, forKey: .ownerPID)
            ownerStartSignature = try container.decodeIfPresent(String.self, forKey: .ownerStartSignature)
            recoveryPending = try container.decodeIfPresent(Bool.self, forKey: .recoveryPending) ?? false
        }

        // MARK: Internal

        let services: [ServiceProxyBackup]
        let timestamp: Date
        let rockxyPort: Int?
        /// The Rockxy app process that asked for the override, and the kernel start time that
        /// tells it apart from a later process which inherited the same PID.
        let ownerPID: Int32?
        let ownerStartSignature: String?
        /// True after recovery has narrowed the backup and before every retained entry has been
        /// fully restored. Retained entries remain authoritative even after partial commands
        /// change their live shape enough that strict ownership no longer matches.
        let recoveryPending: Bool

        // MARK: Private

        private enum CodingKeys: String, CodingKey {
            case services
            case timestamp
            case rockxyPort
            case ownerPID
            case ownerStartSignature
            case recoveryPending
        }
    }

    /// What launch-time recovery did with the backup it found.
    enum StartupRecoveryOutcome: Equatable {
        case noBackup
        case cleared
        case restored
        case restoreIncomplete
        /// The recorded owner is still alive and still passes caller validation, so its override
        /// stays in place. The PID is handed back so the helper can re-arm its owner watchdog.
        case preserved(ownerPID: Int32?)
    }

    // MARK: - Public API

    /// Save current proxy settings for all specified services before overriding them.
    /// The owning app process is recorded with the backup so a later helper launch can tell a
    /// still-running session from a stranded override.
    static func saveOriginalSettings(services: [String], rockxyPort: Int, ownerPID: Int32) throws {
        let existingBackup = loadBackup()
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

        let backup = ProxyBackup(
            services: (existingBackup?.services ?? []) + serviceBackups,
            timestamp: existingBackup?.timestamp ?? Date(),
            rockxyPort: rockxyPort,
            ownerPID: ownerPID,
            ownerStartSignature: ProcessStartIdentity.startSignature(for: ownerPID),
            recoveryPending: false
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
    }

    /// Writes a backup to every backup location with owner-only permissions.
    /// Used both for the initial capture and for the reduced backup a subset restore persists
    /// before it touches any setting.
    static func persist(_ backup: ProxyBackup) throws {
        try ensureBackupDirectoryExists()
        let data = try PropertyListEncoder().encode(backup)
        for url in backupURLs {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }

    /// Narrows the backup on disk to `services` before a subset restore mutates anything.
    /// Dropping the entries recovery no longer owns is what stops a later retry from writing
    /// stale settings over a service the user has since changed.
    static func reduceBackup(
        _ backup: ProxyBackup,
        to services: [String],
        rockxyPort: Int? = nil
    )
        throws -> ProxyBackup
    {
        let reduced = ProxyBackup(
            services: ProxyBackupSubset.select(
                backup.services,
                services: Set(services),
                serviceName: \.service
            ),
            timestamp: backup.timestamp,
            rockxyPort: backup.rockxyPort ?? rockxyPort,
            ownerPID: nil,
            ownerStartSignature: nil,
            recoveryPending: true
        )
        try persist(reduced)
        return reduced
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

        guard let backup = loadBackup() else {
            logger.warning("Backup file exists but could not be read — clearing")
            clearBackup()
            return .cleared
        }

        // Legacy backups predate the persisted port, so fall back to the port the backed-up
        // services are still overriding, then to the port the live status reports. With none of
        // those, nothing can be identified as Rockxy-owned.
        let overrideStates = ProxyConfigurator.currentOverrideStates(for: backup.services.map(\.service))
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

        let residualOwnedServices = if backup.recoveryPending {
            backup.services.map(\.service)
        } else {
            ProxyOverrideOwnership.residualOwnedServices(in: overrideStates, port: ownedPort ?? 0)
        }
        let liveOwnerPID = backup.recoveryPending ? nil : liveOwnerPID(for: backup)

        switch ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: !residualOwnedServices.isEmpty,
            ownerSessionIsLive: liveOwnerPID != nil
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
            return .preserved(ownerPID: liveOwnerPID)
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
    static func liveOwnerPID(for backup: ProxyBackup) -> Int32? {
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

        return ownerPID
    }

    /// Load the backup data from disk.
    /// Returns nil if file doesn't exist, is corrupt, or uses an old format.
    /// Invalid backup files are cleared automatically.
    static func loadBackup() -> ProxyBackup? {
        for url in backupURLs {
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                return try PropertyListDecoder().decode(ProxyBackup.self, from: data)
            } catch {
                logger.error("Failed to decode proxy backup at \(url.path): \(error.localizedDescription)")
            }
        }
        clearBackup()
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

    private static func ensureBackupDirectoryExists() throws {
        for url in backupURLs {
            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        }
    }

    private static func readBypassDomains(service: String) throws -> [String] {
        let output = try readProxySettings(type: "proxybypassdomains", service: service)
        return output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("There aren't any bypass domains") }
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
