import Darwin
import Foundation
import os

// Boots the privileged helper, restores stale proxy state, and starts the XPC listener.

private let identity = RockxyIdentity.current
private let logger = Logger(subsystem: identity.logSubsystem, category: "Main")

private struct DirectProxyBackup: Decodable {
    let services: [DirectServiceBackup]
    let timestamp: Date
    let rockxyPort: Int
}

private struct DirectServiceBackup: Decodable {
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
}

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
}

private enum DirectProxyWatchdog {
    private static let networkSetupPath = "/usr/sbin/networksetup"

    static func run(arguments: [String]) -> Bool {
        guard arguments.count >= 4,
              arguments[1] == "--rockxy-direct-proxy-watchdog",
              let parentPID = Int32(arguments[2])
        else {
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

    private static func restoreIfNeeded(from backupURL: URL) {
        guard let backup = loadBackup(from: backupURL) else {
            return
        }

        let backedUpServices = backup.services.map(\.service)
        guard currentProxyMatchesRockxy(port: backup.rockxyPort, services: backedUpServices) else {
            logger.info("Direct proxy watchdog clearing stale backup because proxy no longer points at Rockxy")
            try? FileManager.default.removeItem(at: backupURL)
            return
        }

        logger.warning("Direct proxy watchdog restoring proxy settings after parent exit")
        var allSucceeded = true

        for entry in backup.services {
            let snapshot = DirectProxySnapshot(
                httpEnabled: entry.httpEnabled,
                httpHost: entry.httpHost,
                httpPort: entry.httpPort,
                httpsEnabled: entry.httpsEnabled,
                httpsHost: entry.httpsHost,
                httpsPort: entry.httpsPort,
                socksEnabled: entry.socksEnabled,
                socksHost: entry.socksHost,
                socksPort: entry.socksPort
            )

            do {
                try restoreProxyState(for: entry.service, snapshot: snapshot)
            } catch {
                allSucceeded = false
                logger.error("Direct proxy watchdog failed to restore proxy state for '\(entry.service)': \(error.localizedDescription)")
            }

            do {
                try restoreBypassDomains(for: entry.service, domains: entry.bypassDomains)
            } catch {
                allSucceeded = false
                logger.error("Direct proxy watchdog failed to restore bypass domains for '\(entry.service)': \(error.localizedDescription)")
            }
        }

        if allSucceeded {
            try? FileManager.default.removeItem(at: backupURL)
        } else {
            logger.warning("Direct proxy watchdog left backup on disk for later recovery")
        }
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

    private static func currentProxyMatchesRockxy(port: Int, services: [String]) -> Bool {
        for service in services {
            let snapshot = captureProxySnapshot(for: service)
            let httpMatch = snapshot.httpEnabled
                && snapshot.httpHost == "127.0.0.1"
                && snapshot.httpPort == port
            let httpsMatch = snapshot.httpsEnabled
                && snapshot.httpsHost == "127.0.0.1"
                && snapshot.httpsPort == port
            if httpMatch, httpsMatch {
                return true
            }
        }

        return false
    }

    private static func captureProxySnapshot(for service: String) -> DirectProxySnapshot {
        let http = parseProxyOutput((try? runNetworkSetup(["-getwebproxy", service])) ?? "")
        let https = parseProxyOutput((try? runNetworkSetup(["-getsecurewebproxy", service])) ?? "")
        let socks = parseProxyOutput((try? runNetworkSetup(["-getsocksfirewallproxy", service])) ?? "")

        return DirectProxySnapshot(
            httpEnabled: http.enabled,
            httpHost: http.host,
            httpPort: http.port,
            httpsEnabled: https.enabled,
            httpsHost: https.host,
            httpsPort: https.port,
            socksEnabled: socks.enabled,
            socksHost: socks.host,
            socksPort: socks.port
        )
    }

    private static func restoreProxyState(for service: String, snapshot: DirectProxySnapshot) throws {
        try runNetworkSetup(["-setwebproxystate", service, "off"])
        try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])

        if snapshot.httpEnabled {
            try runNetworkSetup(["-setwebproxy", service, snapshot.httpHost, String(snapshot.httpPort)])
            try runNetworkSetup(["-setwebproxystate", service, "on"])
        }

        if snapshot.httpsEnabled {
            try runNetworkSetup(["-setsecurewebproxy", service, snapshot.httpsHost, String(snapshot.httpsPort)])
            try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
        }

        if snapshot.socksEnabled {
            try runNetworkSetup(["-setsocksfirewallproxy", service, snapshot.socksHost, String(snapshot.socksPort)])
            try runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
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

    @discardableResult
    private static func runNetworkSetup(_ arguments: [String]) throws -> String {
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

// Check for stale proxy settings from a previous crash
CrashRecovery.restoreIfNeeded()

let delegate = HelperDelegate()
let machServiceName = identity.helperMachServiceName
let listener = NSXPCListener(machServiceName: machServiceName)
listener.delegate = delegate
listener.resume()

logger.info("RockxyHelperTool listening on Mach service \(machServiceName)")

RunLoop.current.run()
