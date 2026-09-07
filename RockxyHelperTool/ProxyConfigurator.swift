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

    struct PACInfo {
        var enabled: Bool = false
        var url: String = ""
    }

    // MARK: - Public API

    /// Override system HTTP and HTTPS proxy to 127.0.0.1 on the given port.
    /// Saves current settings via CrashRecovery before making changes.
    static func overrideProxy(port: Int, ownerPID: Int32) throws {
        let services = try detectAllEnabledServices()
        guard !services.isEmpty else {
            throw ProxyConfiguratorError.noActiveService
        }

        // Existing service snapshots are preserved, while newly enabled services are added
        // before they are mutated so every touched route has an exact restore point.
        try CrashRecovery.saveOriginalSettings(services: services, rockxyPort: port, ownerPID: ownerPID)

        logger.info("Setting system proxy to 127.0.0.1:\(port) for \(services.count) service(s)")

        var configuredCount = 0
        for service in services {
            do {
                try runNetworkSetup(["-setwebproxy", service, "127.0.0.1", String(port)])
                try runNetworkSetup(["-setwebproxystate", service, "on"])
                try runNetworkSetup(["-setsecurewebproxy", service, "127.0.0.1", String(port)])
                try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
                try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
                try runNetworkSetup(["-setautoproxystate", service, "off"])
                try runNetworkSetup(["-setproxyautodiscovery", service, "off"])
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
        guard let sourceBackup = CrashRecovery.loadBackup() else {
            logger.info("No proxy backup exists, so there is no owned proxy state to restore")
            return
        }
        let backedUpServices = sourceBackup.services.map(\.service)
        let inferredPort = ProxyOverrideOwnership.inferredOwnedPort(
            in: currentOverrideStates(for: backedUpServices)
        )
        let backup = try CrashRecovery.reduceBackup(
            sourceBackup,
            to: backedUpServices,
            rockxyPort: inferredPort
        )

        var failedServices: Set<String> = []
        for service in backup.services.map(\.service) {
            do {
                try disableProxyStates(for: service)
                logger.debug("Disabled proxy on '\(service)'")
            } catch {
                failedServices.insert(service)
                logger.debug("Failed to disable proxy for '\(service)': \(error.localizedDescription)")
            }
        }

        logger.info("Restoring original proxy settings for \(backup.services.count) service(s)")

        for serviceBackup in backup.services {
            logger.info("Restoring proxy settings for '\(serviceBackup.service)'")

            do {
                try applyServiceBackup(serviceBackup)
            } catch {
                failedServices.insert(serviceBackup.service)
                logger
                    .error(
                        "Failed to restore proxy for '\(serviceBackup.service)': \(error.localizedDescription)"
                    )
            }
        }

        let stillOwnedServices = Set(backup.rockxyPort.map { port in
            ProxyOverrideOwnership.residualOwnedServices(
                in: currentOverrideStates(for: backup.services.map(\.service)),
                port: port
            )
        } ?? [])
        let unresolvedEntries = ProxyBackupSubset.unresolvedEntries(
            backup.services,
            failedServices: failedServices,
            stillOwnedServices: stillOwnedServices,
            serviceName: \.service
        )

        guard unresolvedEntries.isEmpty else {
            do {
                _ = try CrashRecovery.reduceBackup(backup, to: unresolvedEntries.map(\.service))
            } catch {
                logger.error("Could not narrow the retained proxy backup: \(error.localizedDescription)")
            }
            throw ProxyConfiguratorError.executionFailed(
                command: "restore proxy",
                reason: "\(unresolvedEntries.count) network service(s) could not be restored; the recovery backup was preserved"
            )
        }

        CrashRecovery.clearBackup()
        logger.info("Proxy settings restored successfully")
    }

    /// Restores only the backed-up services that still carry Rockxy's override, leaving any
    /// service the user (or another tool) has since re-pointed exactly as it is.
    ///
    /// The backup is narrowed to those services *before* the first setting is written, so a
    /// retry after a partial failure can never replay stale settings onto a service that is no
    /// longer Rockxy's. If that reduced backup cannot be persisted, the original backup stays
    /// on disk and nothing is mutated — losing the restore point is worse than a stranded
    /// override that can still be recovered later.
    static func restoreOwnedServicesOrThrow(ownedServices: [String], port: Int?) throws {
        guard let backup = CrashRecovery.loadBackup() else {
            logger.info("No proxy backup exists, so there is no owned proxy state to restore")
            return
        }

        let ownedEntries = ProxyBackupSubset.select(
            backup.services,
            services: Set(ownedServices),
            serviceName: \.service
        )
        guard !ownedEntries.isEmpty else {
            logger.info("No backed-up service is still Rockxy-owned — clearing the stale backup")
            CrashRecovery.clearBackup()
            return
        }

        let reducedBackup: CrashRecovery.ProxyBackup
        do {
            reducedBackup = try CrashRecovery.reduceBackup(
                backup,
                to: ownedEntries.map(\.service),
                rockxyPort: port
            )
        } catch {
            logger
                .error(
                    "Could not persist the reduced proxy backup — leaving settings untouched: \(error.localizedDescription)"
                )
            throw error
        }

        logger.info("Restoring original proxy settings for \(reducedBackup.services.count) owned service(s)")

        var failedServices: Set<String> = []
        for serviceBackup in reducedBackup.services {
            do {
                try disableProxyStates(for: serviceBackup.service)
                try applyServiceBackup(serviceBackup)
            } catch {
                failedServices.insert(serviceBackup.service)
                logger
                    .error(
                        "Failed to restore proxy for '\(serviceBackup.service)': \(error.localizedDescription)"
                    )
            }
        }

        let stillOwnedServices = Set(port.map { ownedPort in
            ProxyOverrideOwnership.residualOwnedServices(
                in: currentOverrideStates(for: reducedBackup.services.map(\.service)),
                port: ownedPort
            )
        } ?? [])
        let unresolvedEntries = ProxyBackupSubset.unresolvedEntries(
            reducedBackup.services,
            failedServices: failedServices,
            stillOwnedServices: stillOwnedServices,
            serviceName: \.service
        )

        guard unresolvedEntries.isEmpty else {
            // Keep exactly the services that still need recovery so a retry has a restore point
            // for them and only them.
            do {
                _ = try CrashRecovery.reduceBackup(reducedBackup, to: unresolvedEntries.map(\.service))
            } catch {
                logger
                    .error(
                        "Could not narrow the retained proxy backup: \(error.localizedDescription)"
                    )
            }
            throw ProxyConfiguratorError.executionFailed(
                command: "restore owned proxy services",
                reason: "\(unresolvedEntries.count) network service(s) could not be restored; the recovery backup was preserved"
            )
        }

        CrashRecovery.clearBackup()
        logger.info("Owned proxy settings restored successfully")
    }

    /// Reads the ownership-relevant proxy fields for each service. Services that cannot be read
    /// report as not overridden, which keeps recovery from claiming ownership it cannot prove.
    static func currentOverrideStates(for services: [String]) -> [ProxyServiceOverrideState] {
        services.map { service in
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
    }

    /// Set bypass domains on all enabled network services.
    /// Pass an empty array to clear the bypass list (uses "Empty" per macOS convention).
    static func setBypassDomains(_ domains: [String]) throws {
        let services = try detectAllEnabledServices()
        guard !services.isEmpty else {
            throw ProxyConfiguratorError.noActiveService
        }

        let indomains = domains.filter { domain in
            !ProxyBypassDomainValidator.isValid(domain)
        }
        if !indomains.isEmpty {
            logger.warning("SECURITY: Rejected \(indomains.count) invalid bypass domain(s): \(indomains)")
            throw ProxyConfiguratorError.executionFailed(
                command: "-setproxybypassdomains",
                reason: "Invalid bypass domains: \(indomains.joined(separator: ", "))"
            )
        }

        var failedServices: [String] = []
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
                failedServices.append(service)
                logger.debug("Failed to set bypass domains for '\(service)': \(error.localizedDescription)")
            }
        }

        guard failedServices.isEmpty else {
            throw ProxyConfiguratorError.executionFailed(
                command: "-setproxybypassdomains",
                reason: "Failed to update bypass domains on: \(failedServices.joined(separator: ", "))"
            )
        }

        logger.info("Bypass domains updated on \(services.count) service(s)")
    }

    /// Restore original bypass domains for a specific service.
    static func restoreBypassDomains(service: String, domains: [String]) throws {
        if domains.isEmpty {
            try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
        } else {
            let args = ["-setproxybypassdomains", service] + domains
            try runNetworkSetup(args)
        }
        logger.info("Restored original bypass domains for '\(service)'")
    }

    /// Returns whether the proxy is currently overridden by Rockxy and the active port.
    static func getCurrentStatus() -> (isOverridden: Bool, port: Int) {
        guard let services = try? detectAllEnabledServices(), !services.isEmpty else {
            return (false, 0)
        }
        guard let backup = CrashRecovery.loadBackup() else {
            return (false, 0)
        }

        let servicesToCheck = detectPrimaryService(from: services).map { [$0] } ?? services
        var matchedPort: Int?
        for service in servicesToCheck {
            guard let httpOutput = try? runNetworkSetup(["-getwebproxy", service]),
                  let httpsOutput = try? runNetworkSetup(["-getsecurewebproxy", service]),
                  let socksOutput = try? runNetworkSetup(["-getsocksfirewallproxy", service]),
                  let pacOutput = try? runNetworkSetup(["-getautoproxyurl", service]),
                  let autoDiscoveryOutput = try? runNetworkSetup(["-getproxyautodiscovery", service]),
                  let bypassOutput = try? runNetworkSetup(["-getproxybypassdomains", service])
            else {
                return (false, 0)
            }

            let http = parseProxyOutput(httpOutput)
            let https = parseProxyOutput(httpsOutput)
            let socks = parseProxyOutput(socksOutput)
            let pac = parsePACOutput(pacOutput)
            let hasGlobalBypass = bypassOutput.components(separatedBy: "\n").contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == "*"
            }
            guard http.enabled,
                  http.host == "127.0.0.1",
                  https.enabled,
                  https.host == "127.0.0.1",
                  http.port == https.port,
                  !socks.enabled,
                  !pac.enabled,
                  !parseAutoDiscoveryOutput(autoDiscoveryOutput),
                  !hasGlobalBypass
            else {
                return (false, 0)
            }
            if let matchedPort, matchedPort != http.port {
                return (false, 0)
            }
            if let rockxyPort = backup.rockxyPort, rockxyPort != http.port {
                return (false, 0)
            }
            matchedPort = http.port
        }

        return matchedPort.map { (true, $0) } ?? (false, 0)
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

    static func parsePACOutput(_ output: String) -> PACInfo {
        var info = PACInfo()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                let value = trimmed.replacingOccurrences(of: "Enabled:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                info.enabled = value.lowercased() == "yes"
            } else if trimmed.hasPrefix("URL:") {
                let value = trimmed.replacingOccurrences(of: "URL:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if value != "(null)" {
                    info.url = value
                }
            }
        }
        return info
    }

    static func parseAutoDiscoveryOutput(_ output: String) -> Bool {
        output.components(separatedBy: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Auto Proxy Discovery:") else {
                return false
            }
            let value = trimmed.replacingOccurrences(of: "Auto Proxy Discovery:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return value.lowercased() == "on"
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProxyConfigurator")
    private static let networkSetupPath = "/usr/sbin/networksetup"
    private static let routePath = "/sbin/route"

    /// Turns every proxy mode off for one service before its snapshot is written back, so a
    /// mode the snapshot does not mention cannot survive the restore.
    private static func disableProxyStates(for service: String) throws {
        try runNetworkSetup(["-setwebproxystate", service, "off"])
        try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        try runNetworkSetup(["-setautoproxystate", service, "off"])
        try runNetworkSetup(["-setproxyautodiscovery", service, "off"])
    }

    /// Writes one service's captured pre-Rockxy proxy configuration back verbatim.
    private static func applyServiceBackup(_ serviceBackup: CrashRecovery.ServiceProxyBackup) throws {
        let service = serviceBackup.service

        if !serviceBackup.httpHost.isEmpty, serviceBackup.httpPort > 0 {
            try runNetworkSetup([
                "-setwebproxy", service, serviceBackup.httpHost,
                String(serviceBackup.httpPort),
            ])
            try runNetworkSetup([
                "-setwebproxystate", service, serviceBackup.httpEnabled ? "on" : "off",
            ])
        }

        if !serviceBackup.httpsHost.isEmpty, serviceBackup.httpsPort > 0 {
            try runNetworkSetup([
                "-setsecurewebproxy", service, serviceBackup.httpsHost,
                String(serviceBackup.httpsPort),
            ])
            try runNetworkSetup([
                "-setsecurewebproxystate", service, serviceBackup.httpsEnabled ? "on" : "off",
            ])
        }

        if !serviceBackup.socksHost.isEmpty, serviceBackup.socksPort > 0 {
            try runNetworkSetup([
                "-setsocksfirewallproxy", service, serviceBackup.socksHost,
                String(serviceBackup.socksPort),
            ])
            try runNetworkSetup([
                "-setsocksfirewallproxystate", service, serviceBackup.socksEnabled ? "on" : "off",
            ])
        }

        if serviceBackup.pacEnabled {
            if !serviceBackup.pacURL.isEmpty {
                try runNetworkSetup(["-setautoproxyurl", service, serviceBackup.pacURL])
            }
            try runNetworkSetup(["-setautoproxystate", service, "on"])
        }

        if serviceBackup.autoDiscoveryEnabled {
            try runNetworkSetup(["-setproxyautodiscovery", service, "on"])
        }

        try restoreBypassDomains(service: service, domains: serviceBackup.bypassDomains)
    }

    private static func validateBinary(_ path: String) throws {
        guard BinaryValidator.validateAppleSignedBinary(at: path) else {
            throw ProxyConfiguratorError.executionFailed(
                command: path,
                reason: "Binary failed Apple code signature validation"
            )
        }
    }

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
        guard BinaryValidator.validateAppleSignedBinary(at: routePath) else {
            logger.error("SECURITY: /sbin/route failed Apple code signature validation")
            return nil
        }

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
        try validateBinary(networkSetupPath)

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
