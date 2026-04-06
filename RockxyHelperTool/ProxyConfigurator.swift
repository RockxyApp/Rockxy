import Foundation
import os

// Applies and restores macOS network proxy settings on behalf of the helper tool.

// MARK: - ProxyConfigurator

/// Configures macOS system proxy settings by running `/usr/sbin/networksetup` as root.
/// The helper tool runs as a launch daemon with root privileges, so no password prompts are needed.
enum ProxyConfigurator {
    // MARK: Internal

    // MARK: - Proxy Output Parsing

    struct ProxyInfo {
        var enabled: Bool = false
        var host: String = ""
        var port: Int = 0
    }

    // MARK: - Public API

    /// Override system HTTP and HTTPS proxy to 127.0.0.1 on the given port.
    /// Saves current settings via CrashRecovery before making changes.
    static func overrideProxy(port: Int) throws {
        let services = try detectAllEnabledServices()
        guard !services.isEmpty else {
            throw ProxyConfiguratorError.noActiveService
        }

        logger.info("Saving original proxy settings for \(services.count) service(s)")
        CrashRecovery.saveOriginalSettings(services: services)

        logger.info("Setting system proxy to 127.0.0.1:\(port) for \(services.count) service(s)")

        var configuredCount = 0
        for service in services {
            do {
                try runNetworkSetup(["-setwebproxy", service, "127.0.0.1", String(port)])
                try runNetworkSetup(["-setwebproxystate", service, "on"])
                try runNetworkSetup(["-setsecurewebproxy", service, "127.0.0.1", String(port)])
                try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
                try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
                configuredCount += 1
                logger.info("Proxy set on '\(service)' → 127.0.0.1:\(port)")
            } catch {
                logger.debug("Skipping proxy for '\(service)': \(error.localizedDescription)")
            }
        }

        guard configuredCount > 0 else {
            throw ProxyConfiguratorError.executionFailed(
                command: "setwebproxy (all services)",
                reason: "Failed to configure proxy on any network service"
            )
        }

        logger.info("System proxy override complete on \(configuredCount) service(s)")
    }

    /// Restore proxy settings from backup. Logs errors but does not throw.
    static func restoreProxy() {
        do {
            try restoreProxyOrThrow()
        } catch {
            logger.error("Failed to restore proxy: \(error.localizedDescription)")
        }
    }

    /// Restore proxy settings from CrashRecovery backup. Throws on failure.
    static func restoreProxyOrThrow() throws {
        let backup = CrashRecovery.loadBackup()

        let allServices = (try? detectAllEnabledServices()) ?? []
        for service in allServices {
            do {
                try runNetworkSetup(["-setwebproxystate", service, "off"])
                try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
                try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
                logger.debug("Disabled proxy on '\(service)'")
            } catch {
                logger.debug("Failed to disable proxy for '\(service)': \(error.localizedDescription)")
            }
        }

        if let backup {
            logger.info("Restoring original proxy settings for \(backup.services.count) service(s)")

            for serviceBackup in backup.services {
                let service = serviceBackup.service
                logger.info("Restoring proxy settings for '\(service)'")

                do {
                    if serviceBackup.httpEnabled {
                        try runNetworkSetup([
                            "-setwebproxy", service, serviceBackup.httpHost,
                            String(serviceBackup.httpPort),
                        ])
                        try runNetworkSetup(["-setwebproxystate", service, "on"])
                    }

                    if serviceBackup.httpsEnabled {
                        try runNetworkSetup([
                            "-setsecurewebproxy", service, serviceBackup.httpsHost,
                            String(serviceBackup.httpsPort),
                        ])
                        try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
                    }

                    try runNetworkSetup([
                        "-setsocksfirewallproxy", service, serviceBackup.socksHost,
                        String(serviceBackup.socksPort),
                    ])
                    try runNetworkSetup([
                        "-setsocksfirewallproxystate", service, serviceBackup.socksEnabled ? "on" : "off",
                    ])

                    restoreBypassDomains(service: service, domains: serviceBackup.bypassDomains)
                } catch {
                    logger.error("Failed to restore proxy for '\(service)': \(error.localizedDescription)")
                }
            }
        }

        CrashRecovery.clearBackup()
        logger.info("Proxy settings restored successfully")
    }

    /// Set bypass domains on all enabled network services.
    /// Pass an empty array to clear the bypass list (uses "Empty" per macOS convention).
    static func setBypassDomains(_ domains: [String]) throws {
        let services = try detectAllEnabledServices()
        guard !services.isEmpty else {
            throw ProxyConfiguratorError.noActiveService
        }

        let asciiAllowed =
            CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_*")
        let indomains = domains.filter { domain in
            domain.isEmpty || domain.count > 253
                || !domain.unicodeScalars.allSatisfy { $0.isASCII && asciiAllowed.contains($0) }
        }
        if !indomains.isEmpty {
            logger.warning("SECURITY: Rejected \(indomains.count) invalid bypass domain(s): \(indomains)")
            throw ProxyConfiguratorError.executionFailed(
                command: "-setproxybypassdomains",
                reason: "Invalid bypass domains: \(indomains.joined(separator: ", "))"
            )
        }

        for service in services {
            do {
                if domains.isEmpty {
                    try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
                } else {
                    let args = ["-setproxybypassdomains", service] + domains
                    try runNetworkSetup(args)
                }
                logger.debug("Set bypass domains on '\(service)': \(domains)")
            } catch {
                logger.debug("Failed to set bypass domains for '\(service)': \(error.localizedDescription)")
            }
        }

        logger.info("Bypass domains updated on \(services.count) service(s)")
    }

    /// Restore original bypass domains for a specific service.
    static func restoreBypassDomains(service: String, domains: [String]) {
        do {
            if domains.isEmpty {
                try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
            } else {
                let args = ["-setproxybypassdomains", service] + domains
                try runNetworkSetup(args)
            }
            logger.info("Restored original bypass domains for '\(service)'")
        } catch {
            logger.error("Failed to restore bypass domains for '\(service)': \(error.localizedDescription)")
        }
    }

    /// Returns whether the proxy is currently overridden by Rockxy and the active port.
    static func getCurrentStatus() -> (isOverridden: Bool, port: Int) {
        guard let services = try? detectAllEnabledServices(), !services.isEmpty else {
            return (false, 0)
        }

        for service in services {
            guard let output = try? runNetworkSetup(["-getwebproxy", service]) else {
                continue
            }

            let parsed = parseProxyOutput(output)
            if parsed.enabled, parsed.host == "127.0.0.1", CrashRecovery.hasBackup() {
                return (true, parsed.port)
            }
        }

        return (false, 0)
    }

    static func parseProxyOutput(_ output: String) -> ProxyInfo {
        var info = ProxyInfo()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                let value = trimmed.replacingOccurrences(of: "Enabled:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                info.enabled = value.lowercased() == "yes"
            } else if trimmed.hasPrefix("Server:") {
                info.host = trimmed.replacingOccurrences(of: "Server:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Port:") {
                let portStr = trimmed.replacingOccurrences(of: "Port:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                info.port = Int(portStr) ?? 0
            }
        }
        return info
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProxyConfigurator")
    private static let networkSetupPath = "/usr/sbin/networksetup"
    private static let routePath = "/sbin/route"

    // MARK: - Network Service Detection

    /// Determines which enabled service is the actual primary by mapping the default
    /// route interface (from `route -n get 0.0.0.0`) to a service name via
    /// `networksetup -listnetworkserviceorder`. Falls back to nil if detection fails.
    private static func detectPrimaryService(from services: [String]) -> String? {
        guard let iface = detectPrimaryInterface() else {
            return nil
        }
        guard let orderOutput = try? runNetworkSetup(["-listnetworkserviceorder"]) else {
            return nil
        }

        var lastService: String?
        for line in orderOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let openParen = trimmed.firstIndex(of: "("),
               let closeParen = trimmed.firstIndex(of: ")"),
               openParen == trimmed.startIndex
            {
                let afterParen = trimmed.index(after: closeParen)
                let name = String(trimmed[afterParen...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    lastService = name
                }
            } else if trimmed.hasPrefix("(Hardware Port:"), let service = lastService {
                if let deviceRange = trimmed.range(of: "Device: ") {
                    let device = String(trimmed[deviceRange.upperBound...].prefix(while: { $0 != ")" }))
                    if device == iface, services.contains(service) {
                        logger.info("Primary service detected: '\(service)' (interface: \(iface))")
                        return service
                    }
                }
            }
        }

        return nil
    }

    private static func detectPrimaryInterface() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: routePath)
        process.arguments = ["-n", "get", "0.0.0.0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("interface:") {
                    let iface = trimmed
                        .replacingOccurrences(of: "interface:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !iface.isEmpty {
                        return iface
                    }
                }
            }
        } catch {
            logger.warning("Failed to detect primary interface: \(error.localizedDescription)")
        }

        return nil
    }

    private static func detectAllEnabledServices() throws -> [String] {
        let output = try runNetworkSetup(["-listallnetworkservices"])
        var services: [String] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty,
               !trimmed.hasPrefix("An asterisk"),
               !trimmed.hasPrefix("*")
            {
                services.append(trimmed)
            }
        }
        services = services
            .filter { !$0.isEmpty && !$0.contains("\0") && !$0.contains("\n") && !$0.contains("\r") && $0.count <= 128 }
        logger.info("Enabled network services: \(services)")
        return services
    }

    private static func detectActiveNetworkService() throws -> String {
        let output = try runNetworkSetup(["-listnetworkserviceorder"])
        let services = parseNetworkServices(from: output)

        for service in services {
            if let status = try? runNetworkSetup(["-getwebproxy", service]),
               !status.contains("** Error")
            {
                logger.debug("Detected active network service: '\(service)'")
                return service
            }
        }

        let allOutput = try runNetworkSetup(["-listallnetworkservices"])
        for line in allOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("An asterisk"), !trimmed.hasPrefix("*") {
                logger.debug("Falling back to network service: '\(trimmed)'")
                return trimmed
            }
        }

        logger.warning("No active network service found, defaulting to Wi-Fi")
        return "Wi-Fi"
    }

    private static func parseNetworkServices(from output: String) -> [String] {
        var services: [String] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let openParen = trimmed.firstIndex(of: "("),
               let closeParen = trimmed.firstIndex(of: ")"),
               openParen == trimmed.startIndex
            {
                let afterParen = trimmed.index(after: closeParen)
                let name = String(trimmed[afterParen...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    services.append(name)
                }
            }
        }
        return services
    }

    // MARK: - Process Execution

    @discardableResult
    private static func runNetworkSetup(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: networkSetupPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch networksetup: \(error.localizedDescription)")
            throw ProxyConfiguratorError.executionFailed(
                command: arguments.joined(separator: " "),
                reason: error.localizedDescription
            )
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let combined = stderr.isEmpty ? stdout : stderr
            logger.error("networksetup failed (\(process.terminationStatus)): \(combined)")
            throw ProxyConfiguratorError.executionFailed(
                command: arguments.joined(separator: " "),
                reason: combined
            )
        }

        return stdout
    }
}

// MARK: - ProxyConfiguratorError

enum ProxyConfiguratorError: LocalizedError {
    case executionFailed(command: String, reason: String)
    case noActiveService

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .executionFailed(command, reason):
            "networksetup \(command) failed: \(reason)"
        case .noActiveService:
            "No active network service detected"
        }
    }
}
