import Darwin
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
        let services: [ServiceProxyBackup]
        let timestamp: Date
        let rockxyPort: Int?
    }

    // MARK: - Public API

    /// Save current proxy settings for all specified services before overriding them.
    static func saveOriginalSettings(services: [String], rockxyPort: Int) throws {
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
            rockxyPort: rockxyPort
        )

        do {
            try ensureBackupDirectoryExists()
            let data = try PropertyListEncoder().encode(backup)
            for url in backupURLs {
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: url.path
                )
            }
            logger
                .info(
                    "Proxy backup saved to \(backupURLs.first?.path ?? "<unknown>") (\(backup.services.count) service(s))"
                )
        } catch {
            logger.error("Failed to save proxy backup: \(error.localizedDescription)")
            throw error
        }
    }

    /// Check for stale backup on daemon launch and restore if found.
    /// A backup existing at launch time means Rockxy crashed without restoring proxy settings.
    static func restoreIfNeeded() {
        guard hasBackup() else {
            logger.info("No stale proxy backup found — clean startup")
            return
        }

        guard let backup = loadBackup() else {
            logger.warning("Backup file exists but could not be read — clearing")
            clearBackup()
            return
        }

        let status = ProxyConfigurator.getCurrentStatus()
        switch ProxyBackupRecoveryPolicy.action(
            proxyStillPointsAtRockxy: status.isOverridden &&
                (backup.rockxyPort == nil || backup.rockxyPort == status.port),
            listenerIsReachable: listenerIsReachable(port: status.port)
        ) {
        case .restore:
            logger.warning("Owned proxy backup has no live listener — restoring proxy settings")
            ProxyConfigurator.restoreProxy()
        case .preserve:
            logger.info("Owned proxy backup belongs to a live listener — preserving the active session")
        case .clear:
            logger.info("Proxy no longer points at the backed-up Rockxy session — clearing stale backup")
            clearBackup()
        }
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

    private static func listenerIsReachable(port: Int) -> Bool {
        guard let port = UInt16(exactly: port), port > 0 else {
            return false
        }

        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }
        defer { Darwin.close(descriptor) }

        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            return false
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 {
            return true
        }
        guard errno == EINPROGRESS else {
            return false
        }

        var state = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard Darwin.poll(&state, 1, 250) > 0 else {
            return false
        }

        var socketError: Int32 = 0
        var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorLength) == 0 else {
            return false
        }
        return socketError == 0
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
