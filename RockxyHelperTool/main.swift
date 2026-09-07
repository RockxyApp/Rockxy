import Darwin
import Foundation
import os

// Boots the privileged helper, restores stale proxy state, and starts the XPC listener.

private let identity = RockxyIdentity.current
private let logger = Logger(subsystem: identity.logSubsystem, category: "Main")

// MARK: - DirectProxyBackup

private struct DirectProxyBackup: Codable {
    init(
        services: [DirectServiceBackup],
        timestamp: Date,
        rockxyPort: Int,
        recoveryPending: Bool = false
    ) {
        self.services = services
        self.timestamp = timestamp
        self.rockxyPort = rockxyPort
        self.recoveryPending = recoveryPending
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        services = try container.decode([DirectServiceBackup].self, forKey: .services)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        rockxyPort = try container.decode(Int.self, forKey: .rockxyPort)
        recoveryPending = try container.decodeIfPresent(Bool.self, forKey: .recoveryPending) ?? false
    }

    let services: [DirectServiceBackup]
    let timestamp: Date
    let rockxyPort: Int
    let recoveryPending: Bool

    private enum CodingKeys: String, CodingKey {
        case services
        case timestamp
        case rockxyPort
        case recoveryPending
    }
}

// MARK: - DirectServiceBackup

private struct DirectServiceBackup: Codable {
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

// MARK: - DirectProxySnapshot

private struct DirectProxySnapshot {
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
}

// MARK: - DirectProxyWatchdog

private enum DirectProxyWatchdog {
    // MARK: Internal

    static func run(arguments: [String]) -> Bool {
        guard arguments.count >= 4,
              arguments[1] == "--rockxy-direct-proxy-watchdog",
              let parentPID = Int32(arguments[2]) else
        {
            return false
        }

        let backupPath = arguments[3]
        let backupURL = URL(fileURLWithPath: backupPath)
        logger.info("RockxyHelperTool running direct proxy watchdog for parent pid \(parentPID)")

        while true {
            let parentAlive = isProcessAlive(parentPID)
            let backupExists = FileManager.default.fileExists(atPath: backupPath)

            if !backupExists {
                return true
            }

            if parentAlive {
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }

            restoreIfNeeded(from: backupURL)
            return true
        }
    }

    // MARK: Private

    private static let networkSetupPath = "/usr/sbin/networksetup"

    /// Restores only the backed-up services that still carry Rockxy's override. A service the
    /// user re-pointed after the crash is left alone, and its absence never justifies deleting
    /// the restore point the remaining owned services still depend on.
    private static func restoreIfNeeded(from backupURL: URL) {
        guard let backup = loadBackup(from: backupURL) else {
            return
        }

        let ownedServices = backup.recoveryPending
            ? backup.services.map(\.service)
            : residualOwnedServices(in: backup)
        guard !ownedServices.isEmpty else {
            logger.info("Direct proxy watchdog clearing stale backup because no service still points at Rockxy")
            try? FileManager.default.removeItem(at: backupURL)
            return
        }

        // Narrow the backup before mutating anything: if this write fails, the original backup
        // and the current settings both stay exactly as they are.
        let ownedBackup = DirectProxyBackup(
            services: ProxyBackupSubset.select(
                backup.services,
                services: Set(ownedServices),
                serviceName: \.service
            ),
            timestamp: backup.timestamp,
            rockxyPort: backup.rockxyPort,
            recoveryPending: true
        )
        do {
            try write(ownedBackup, to: backupURL)
        } catch {
            logger
                .error(
                    "Direct proxy watchdog could not narrow the backup — leaving settings untouched: \(error.localizedDescription)"
                )
            return
        }

        logger
            .warning(
                "Direct proxy watchdog restoring \(ownedBackup.services.count) owned service(s) after parent exit"
            )
        var failedServices: Set<String> = []

        for entry in ownedBackup.services {
            let snapshot = DirectProxySnapshot(
                httpEnabled: entry.httpEnabled,
                httpHost: entry.httpHost,
                httpPort: entry.httpPort,
                httpsEnabled: entry.httpsEnabled,
                httpsHost: entry.httpsHost,
                httpsPort: entry.httpsPort,
                socksEnabled: entry.socksEnabled,
                socksHost: entry.socksHost,
                socksPort: entry.socksPort,
                pacEnabled: entry.pacEnabled,
                pacURL: entry.pacURL,
                autoDiscoveryEnabled: entry.autoDiscoveryEnabled
            )

            do {
                try restoreProxyState(for: entry.service, snapshot: snapshot)
            } catch {
                failedServices.insert(entry.service)
                logger
                    .error(
                        "Direct proxy watchdog failed to restore proxy state for '\(entry.service)': \(error.localizedDescription)"
                    )
            }

            do {
                try restoreBypassDomains(for: entry.service, domains: entry.bypassDomains)
            } catch {
                failedServices.insert(entry.service)
                logger
                    .error(
                        "Direct proxy watchdog failed to restore bypass domains for '\(entry.service)': \(error.localizedDescription)"
                    )
            }
        }

        let unresolvedEntries = ProxyBackupSubset.unresolvedEntries(
            ownedBackup.services,
            failedServices: failedServices,
            stillOwnedServices: Set(residualOwnedServices(in: ownedBackup)),
            serviceName: \.service
        )

        guard !unresolvedEntries.isEmpty else {
            try? FileManager.default.removeItem(at: backupURL)
            return
        }

        let retainedBackup = DirectProxyBackup(
            services: unresolvedEntries,
            timestamp: ownedBackup.timestamp,
            rockxyPort: ownedBackup.rockxyPort,
            recoveryPending: true
        )
        do {
            try write(retainedBackup, to: backupURL)
        } catch {
            logger.error("Direct proxy watchdog could not narrow the retained backup: \(error.localizedDescription)")
        }
        logger
            .warning(
                "Direct proxy watchdog left \(unresolvedEntries.count) service(s) in the backup for later recovery"
            )
    }

    private static func write(_ backup: DirectProxyBackup, to backupURL: URL) throws {
        let data = try PropertyListEncoder().encode(backup)
        try data.write(to: backupURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: backupURL.path
        )
    }

    private static func loadBackup(from backupURL: URL) -> DirectProxyBackup? {
        do {
            let data = try Data(contentsOf: backupURL)
            return try PropertyListDecoder().decode(DirectProxyBackup.self, from: data)
        } catch {
            logger.error("Direct proxy watchdog could not load backup: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: backupURL)
            return nil
        }
    }

    /// The backed-up services that still carry Rockxy's override on the persisted port.
    private static func residualOwnedServices(in backup: DirectProxyBackup) -> [String] {
        ProxyOverrideOwnership.residualOwnedServices(
            in: backup.services.map { currentOverrideState(for: $0.service) },
            port: backup.rockxyPort
        )
    }

    private static func currentOverrideState(for service: String) -> ProxyServiceOverrideState {
        let http = parseProxyOutput((try? runNetworkSetup(["-getwebproxy", service])) ?? "")
        let https = parseProxyOutput((try? runNetworkSetup(["-getsecurewebproxy", service])) ?? "")
        let socks = parseProxyOutput((try? runNetworkSetup(["-getsocksfirewallproxy", service])) ?? "")
        let pac = parsePACOutput((try? runNetworkSetup(["-getautoproxyurl", service])) ?? "")
        let autoDiscovery = parseAutoDiscoveryOutput(
            (try? runNetworkSetup(["-getproxyautodiscovery", service])) ?? ""
        )
        let bypassOutput = (try? runNetworkSetup(["-getproxybypassdomains", service])) ?? ""
        let hasGlobalBypass = bypassOutput.components(separatedBy: "\n").contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "*"
        }

        return ProxyServiceOverrideState(
            service: service,
            httpEnabled: http.enabled,
            httpHost: http.host,
            httpPort: http.port,
            httpsEnabled: https.enabled,
            httpsHost: https.host,
            httpsPort: https.port,
            socksEnabled: socks.enabled,
            pacEnabled: pac.enabled,
            autoDiscoveryEnabled: autoDiscovery,
            hasGlobalBypass: hasGlobalBypass
        )
    }

    private static func restoreProxyState(for service: String, snapshot: DirectProxySnapshot) throws {
        try runNetworkSetup(["-setwebproxystate", service, "off"])
        try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        try runNetworkSetup(["-setautoproxystate", service, "off"])
        try runNetworkSetup(["-setproxyautodiscovery", service, "off"])

        if !snapshot.httpHost.isEmpty, snapshot.httpPort > 0 {
            try runNetworkSetup(["-setwebproxy", service, snapshot.httpHost, String(snapshot.httpPort)])
            try runNetworkSetup(["-setwebproxystate", service, snapshot.httpEnabled ? "on" : "off"])
        }

        if !snapshot.httpsHost.isEmpty, snapshot.httpsPort > 0 {
            try runNetworkSetup(["-setsecurewebproxy", service, snapshot.httpsHost, String(snapshot.httpsPort)])
            try runNetworkSetup(["-setsecurewebproxystate", service, snapshot.httpsEnabled ? "on" : "off"])
        }

        if !snapshot.socksHost.isEmpty, snapshot.socksPort > 0 {
            try runNetworkSetup(["-setsocksfirewallproxy", service, snapshot.socksHost, String(snapshot.socksPort)])
            try runNetworkSetup(["-setsocksfirewallproxystate", service, snapshot.socksEnabled ? "on" : "off"])
        }

        if snapshot.pacEnabled {
            if !snapshot.pacURL.isEmpty {
                try runNetworkSetup(["-setautoproxyurl", service, snapshot.pacURL])
            }
            try runNetworkSetup(["-setautoproxystate", service, "on"])
        }

        if snapshot.autoDiscoveryEnabled {
            try runNetworkSetup(["-setproxyautodiscovery", service, "on"])
        }
    }

    private static func restoreBypassDomains(for service: String, domains: [String]) throws {
        if domains.isEmpty {
            try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
        } else {
            try runNetworkSetup(["-setproxybypassdomains", service] + domains)
        }
    }

    private static func parseProxyOutput(_ output: String) -> (enabled: Bool, host: String, port: Int) {
        var enabled = false
        var host = ""
        var port = 0

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                let value = trimmed.replacingOccurrences(of: "Enabled:", with: "").trimmingCharacters(in: .whitespaces)
                enabled = value.lowercased() == "yes"
            } else if trimmed.hasPrefix("Server:") {
                host = trimmed.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Port:") {
                let value = trimmed.replacingOccurrences(of: "Port:", with: "").trimmingCharacters(in: .whitespaces)
                port = Int(value) ?? 0
            }
        }

        return (enabled, host, port)
    }

    private static func parsePACOutput(_ output: String) -> (enabled: Bool, url: String) {
        var enabled = false
        var url = ""
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                enabled = trimmed.replacingOccurrences(of: "Enabled:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased() == "yes"
            } else if trimmed.hasPrefix("URL:") {
                let value = trimmed.replacingOccurrences(of: "URL:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value != "(null)" {
                    url = value
                }
            }
        }
        return (enabled, url)
    }

    private static func parseAutoDiscoveryOutput(_ output: String) -> Bool {
        output.components(separatedBy: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Auto Proxy Discovery:") else {
                return false
            }
            return trimmed.replacingOccurrences(of: "Auto Proxy Discovery:", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased() == "on"
        }
    }

    @discardableResult
    private static func runNetworkSetup(_ arguments: [String]) throws -> String {
        guard BinaryValidator.validateAppleSignedBinary(at: networkSetupPath) else {
            throw NSError(domain: "DirectProxyWatchdog", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "networksetup binary failed Apple code signature validation",
            ])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: networkSetupPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let output = stderr.isEmpty ? stdout : stderr
            throw NSError(domain: "DirectProxyWatchdog", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "networksetup \(arguments.joined(separator: " ")) failed: \(output)",
            ])
        }

        return stdout
    }

    private static func isProcessAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}

if DirectProxyWatchdog.run(arguments: ProcessInfo.processInfo.arguments) {
    Foundation.exit(0)
}

logger.info("RockxyHelperTool starting up")

// Check for stale proxy settings from a previous crash. A session whose owner is still alive
// and still validates keeps its override, and its watchdog is re-armed before this helper takes
// any new work, so a later owner death still restores the user's settings.
if case let .preserved(ownerPID) = CrashRecovery.restoreIfNeeded(), let ownerPID {
    HelperService.shared.resumeOwnerWatchdog(for: ownerPID)
}

let delegate = HelperDelegate()
let machServiceName = identity.helperMachServiceName
let listener = NSXPCListener(machServiceName: machServiceName)
listener.delegate = delegate
listener.resume()

logger.info("RockxyHelperTool listening on Mach service \(machServiceName)")

IdleExitMonitor.start()

RunLoop.current.run()
