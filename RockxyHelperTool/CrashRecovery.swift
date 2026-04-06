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
            case bypassDomains
        }
    }

    struct ProxyBackup: Codable {
        let services: [ServiceProxyBackup]
        let timestamp: Date
    }

    // MARK: - Public API

    /// Save current proxy settings for all specified services before overriding them.
    static func saveOriginalSettings(services: [String]) {
        logger.info("Saving original proxy settings for \(services.count) service(s)")

        var serviceBackups: [ServiceProxyBackup] = []
        for service in services {
            let httpOutput = (try? readProxySettings(type: "webproxy", service: service)) ?? ""
            let httpsOutput = (try? readProxySettings(type: "securewebproxy", service: service)) ?? ""
            let socksOutput = (try? readProxySettings(type: "socksfirewallproxy", service: service)) ?? ""
            let bypassDomains = (try? readBypassDomains(service: service)) ?? []

            let httpInfo = ProxyConfigurator.parseProxyOutput(httpOutput)
            let httpsInfo = ProxyConfigurator.parseProxyOutput(httpsOutput)
            let socksInfo = ProxyConfigurator.parseProxyOutput(socksOutput)

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
                bypassDomains: bypassDomains
            )
            serviceBackups.append(serviceBackup)
            logger.debug("Captured proxy state for '\(service)'")
        }

        let backup = ProxyBackup(
            services: serviceBackups,
            timestamp: Date()
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
            logger.info("Proxy backup saved to \(backupURLs.first?.path ?? "<unknown>") (\(serviceBackups.count) service(s))")
        } catch {
            logger.error("Failed to save proxy backup: \(error.localizedDescription)")
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

        let maxAge: TimeInterval = 24 * 60 * 60
        if Date().timeIntervalSince(backup.timestamp) > maxAge {
            logger.warning("Backup is stale (> 24h old) — discarding rather than restoring")
            clearBackup()
            return
        }

        logger.warning("Recent proxy backup found — previous session may have crashed. Restoring proxy settings.")
        ProxyConfigurator.restoreProxy()
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
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
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
        let allowedTypes: Set = ["webproxy", "securewebproxy", "socksfirewallproxy", "proxybypassdomains"]
        guard allowedTypes.contains(type) else {
            throw ProxyConfiguratorError.executionFailed(command: "-get\(type)", reason: "Invalid proxy type: \(type)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
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
