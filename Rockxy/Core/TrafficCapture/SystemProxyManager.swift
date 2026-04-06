import Darwin
import Foundation
import os

// Defines `SystemProxyManager`, which coordinates system proxy behavior in traffic capture
// and system proxy coordination.

// MARK: - SystemProxyError

/// Errors raised when configuring macOS system proxy settings via `networksetup`.
enum SystemProxyError: LocalizedError {
    case networkSetupFailed(command: String, output: String, exitCode: Int32)
    case noActiveNetworkService
    case unexpectedOutput(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .networkSetupFailed(command, output, exitCode):
            "networksetup \(command) failed (exit \(exitCode)): \(output)"
        case .noActiveNetworkService:
            "Could not detect an active network service"
        case let .unexpectedOutput(output):
            "Unexpected networksetup output: \(output)"
        }
    }
}

// MARK: - DirectProxyBackup

/// Persistent on-disk backup of the pre-Rockxy proxy state for all services.
/// Written before any direct-mode mutation; cleared after successful restore.
struct DirectProxyBackup: Codable {
    let services: [DirectServiceBackup]
    let timestamp: Date
    let rockxyPort: Int
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

// MARK: - ProxyOverrideOwner

/// Describes who currently owns the system proxy override.
enum ProxyOverrideOwner {
    case none
    case direct(backup: DirectProxyBackup)
    case helper(port: Int)
}

// MARK: - DirectProxyWatchdogAction

enum DirectProxyWatchdogAction {
    case wait
    case restore
    case exit
}

// MARK: - ServiceProxySnapshot

/// Snapshot of a network service's proxy configuration before Rockxy modifies it.
/// Used to restore the exact pre-Rockxy state on disable/quit.
struct ServiceProxySnapshot {
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

// MARK: - SystemProxyManager

/// Manages the macOS system HTTP/HTTPS proxy by shelling out to `/usr/sbin/networksetup`.
/// Configures both HTTP and HTTPS proxy settings on ALL enabled network services
/// (Wi-Fi, Ethernet, USB LAN, etc.) to ensure traffic is captured regardless of which
/// interface the browser uses. This matches the behavior of Proxyman, Charles, and Fiddler.
final class SystemProxyManager: @unchecked Sendable {
    // MARK: Internal

    static let shared = SystemProxyManager()

    var systemProxyEnabled: Bool {
        lock.lock()
        let enabled = isEnabled
        lock.unlock()
        return enabled
    }

    var usingHelperProxyOverride: Bool {
        lock.lock()
        let helper = usingHelper
        lock.unlock()
        return helper
    }

    nonisolated static func shouldAttemptHelperEmergencyRestore(
        wasUsingHelper: Bool,
        helperBackupExists: Bool,
        loopbackProxyDetected: Bool
    )
        -> Bool
    {
        if wasUsingHelper {
            return true
        }

        return helperBackupExists && loopbackProxyDetected
    }

    nonisolated static func directProxyWatchdogAction(
        parentAlive: Bool,
        backupExists: Bool
    ) -> DirectProxyWatchdogAction {
        if !backupExists {
            return .exit
        }

        if parentAlive {
            return .wait
        }

        return .restore
    }

    nonisolated static func shouldClearDirectBackupAfterRestoreAttempt(
        commandsSucceeded: Bool,
        proxyStillPointsAtRockxy: Bool
    ) -> Bool {
        commandsSucceeded && !proxyStillPointsAtRockxy
    }

    @discardableResult
    nonisolated static func runDirectProxyWatchdogIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        guard arguments.count >= 3,
              arguments[1] == "--rockxy-direct-proxy-watchdog",
              let parentPID = Int32(arguments[2])
        else {
            return false
        }

        let pollInterval: TimeInterval = 0.5
        while true {
            let parentAlive = kill(parentPID, 0) == 0 || errno == EPERM
            let backupExists = FileManager.default.fileExists(atPath: directBackupURL.path)

            switch directProxyWatchdogAction(parentAlive: parentAlive, backupExists: backupExists) {
            case .wait:
                Thread.sleep(forTimeInterval: pollInterval)
            case .restore:
                shared.performEmergencyTerminationCleanup(
                    reason: "direct proxy watchdog observed parent exit"
                )
                return true
            case .exit:
                return true
            }
        }
    }

    // MARK: - Public API

    func enableSystemProxy(port: Int) async throws {
        Self.logger.info("enableSystemProxy called for port \(port)")

        // Snapshot per-service state BEFORE any mutation
        saveOriginalState()

        // Detect VPN/tunnel BEFORE choosing helper vs networksetup — applies to both paths
        if let primaryIface = detectPrimaryInterface() {
            if primaryIface.hasPrefix("utun") || primaryIface.hasPrefix("ppp") || primaryIface.hasPrefix("tun") {
                Self.logger.warning(
                    "Primary interface '\(primaryIface)' is a VPN/tunnel — system proxy may not capture traffic"
                )
                NotificationCenter.default.post(
                    name: .systemProxyVPNWarning,
                    object: nil,
                    userInfo: ["interface": primaryIface]
                )
            }
        }

        var helperStatus = await HelperManager.shared.status
        Self.logger.info("Helper tool status: \(String(describing: helperStatus))")

        // Lazy status check — handles race where startProxy() runs before
        // AppDelegate's checkStatus() Task completes
        if helperStatus == .notInstalled {
            Self.logger.info("Helper status is .notInstalled — running lazy checkStatus()")
            await HelperManager.shared.checkStatus()
            helperStatus = await HelperManager.shared.status
            Self.logger.info("Helper status after lazy check: \(String(describing: helperStatus))")
        }

        if helperStatus == .installedCompatible || helperStatus == .installedOutdated {
            if await HelperConnection.shared.isHelperAvailable() {
                Self.logger.info("Enabling system proxy via helper tool on port \(port)")
                try await HelperConnection.shared.overrideSystemProxy(port: port)

                lock.lock()
                isEnabled = true
                usingHelper = true
                lock.unlock()
            } else {
                Self.logger.warning("Helper registered but not responding, falling back to networksetup")
                try enableSystemProxyViaNetworkSetup(port: port)
            }
        } else if helperStatus == .requiresApproval {
            Self.logger.warning(
                "Helper requires approval in System Settings — falling back to networksetup"
            )
            try enableSystemProxyViaNetworkSetup(port: port)
        } else {
            Self.logger
                .info("Helper not installed (status: \(String(describing: helperStatus))), using networksetup directly")
            try enableSystemProxyViaNetworkSetup(port: port)
        }

        await applyBypassDomains()
        startBypassListObserver()

        Self.logger.info("System proxy enabled on port \(port)")
        NotificationCenter.default.post(name: .systemProxyDidChange, object: nil, userInfo: ["enabled": true])
    }

    func disableSystemProxy() async throws {
        // Same-session shortcut: if we know we own a direct override, skip ownership detection
        lock.lock()
        let pending = directRestorePending
        lock.unlock()

        if pending, let backup = loadDirectBackup() {
            Self.logger.info("Direct restore pending — restoring \(backup.services.count) service(s)")
            restoreDirectMode(using: backup)
        } else {
            let owner = await effectiveOverrideOwner()

            switch owner {
            case .none:
                Self.logger.info("No proxy override detected, nothing to restore")
                return

            case .helper:
                Self.logger.info("Disabling system proxy via helper tool")
                try await HelperConnection.shared.restoreSystemProxy()

            case let .direct(backup):
                Self.logger.info("Disabling direct-mode system proxy, restoring \(backup.services.count) service(s)")
                restoreDirectMode(using: backup)
            }
        }

        stopBypassListObserver()

        lock.lock()
        isEnabled = false
        usingHelper = false
        activeServices = []
        originalBypassDomains = [:]
        originalProxyState = [:]
        lock.unlock()

        Self.logger.info("System proxy disabled")
        NotificationCenter.default.post(name: .systemProxyDidChange, object: nil, userInfo: ["enabled": false])
    }

    func isSystemProxyEnabled() -> Bool {
        guard let service = try? detectPrimaryNetworkService() else {
            return false
        }

        guard let output = try? runNetworkSetup(["-getwebproxy", service]) else {
            return false
        }

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                let value = trimmed.replacingOccurrences(of: "Enabled:", with: "").trimmingCharacters(in: .whitespaces)
                return value.lowercased() == "yes"
            }
        }

        return false
    }

    // MARK: - Bypass Domain Management

    /// Apply bypass domains from BypassProxyManager to the system proxy.
    /// Uses helper tool if available, otherwise runs networksetup directly.
    func applyBypassDomains() async {
        let domains = await BypassProxyManager.shared.enabledDomainStrings()

        lock.lock()
        let currentlyUsingHelper = usingHelper
        lock.unlock()

        if currentlyUsingHelper {
            do {
                try await HelperConnection.shared.setBypassDomains(domains)
                Self.logger.info("Applied \(domains.count) bypass domain(s) via helper")
            } catch {
                Self.logger.error("Failed to apply bypass domains via helper: \(error.localizedDescription)")
            }
        } else {
            applyBypassDomainsViaNetworkSetup(domains)
        }
    }

    /// Start observing bypass list changes for live updates while proxy is running.
    func startBypassListObserver() {
        bypassObserver = NotificationCenter.default.addObserver(
            forName: .bypassProxyListDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }
            Task {
                guard self.systemProxyEnabled else {
                    return
                }
                await self.applyBypassDomains()
            }
        }
    }

    /// Stop observing bypass list changes.
    func stopBypassListObserver() {
        if let observer = bypassObserver {
            NotificationCenter.default.removeObserver(observer)
            bypassObserver = nil
        }
    }

    /// Loads a previously persisted direct backup from disk, returning nil if missing or corrupt.
    func loadDirectBackup() -> DirectProxyBackup? {
        let url = Self.directBackupURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(DirectProxyBackup.self, from: data)
        } catch {
            Self.logger.warning("Corrupt direct backup, clearing: \(error.localizedDescription)")
            self.clearDirectBackup()
            return nil
        }
    }

    /// Removes the on-disk direct backup after successful restore.
    func clearDirectBackup() {
        let url = Self.directBackupURL
        try? FileManager.default.removeItem(at: url)
        Self.logger.info("Cleared direct backup plist")
    }

    // MARK: - Ownership Detection

    /// Determines who currently owns the system proxy override by checking
    /// on-disk backup (direct mode) and helper status.
    func effectiveOverrideOwner() async -> ProxyOverrideOwner {
        // Check in-memory state first for fast path
        lock.lock()
        let wasEnabled = isEnabled
        let wasUsingHelper = usingHelper
        lock.unlock()

        if wasEnabled, wasUsingHelper {
            return .helper(port: 0)
        }

        if let backup = loadDirectBackup() {
            let backedUpServices = backup.services.map(\.service)
            if wasEnabled || currentProxyMatchesRockxy(port: backup.rockxyPort, backedUpServices: backedUpServices) {
                return .direct(backup: backup)
            }
        }

        if let helperStatus = try? await HelperConnection.shared.getProxyStatus(),
           helperStatus.isOverridden
        {
            return .helper(port: helperStatus.port)
        }

        return .none
    }

    /// Checks whether the system proxy on any backed-up service currently points to Rockxy.
    func currentProxyMatchesRockxy(port: Int, backedUpServices: [String]) -> Bool {
        for service in backedUpServices {
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

    // MARK: - Launch-Time Recovery

    /// Called at app launch to detect and restore stale direct-mode proxy overrides
    /// left behind by a crash or force-quit.
    func recoverStaleProxyIfNeeded() async {
        if let backup = loadDirectBackup() {
            if Date().timeIntervalSince(backup.timestamp) > 86_400 {
                Self.logger.info("Stale direct backup >24h old, clearing without restore")
                clearDirectBackup()
            } else {
                let backedUpServices = backup.services.map(\.service)
                if currentProxyMatchesRockxy(port: backup.rockxyPort, backedUpServices: backedUpServices) {
                    Self.logger.info("Recovering stale direct-mode proxy override from crash")
                    do {
                        try await disableSystemProxy()
                    } catch {
                        Self.logger.error("Stale direct proxy recovery failed: \(error.localizedDescription)")
                    }
                } else {
                    Self.logger.info("Proxy no longer Rockxy-owned, clearing stale direct backup")
                    clearDirectBackup()
                }
            }
        }

        if let helperStatus = try? await HelperConnection.shared.getProxyStatus(),
           helperStatus.isOverridden
        {
            Self.logger.warning("Recovering stale helper-owned proxy override from previous session")
            do {
                try await HelperConnection.shared.restoreSystemProxy()
            } catch {
                Self.logger.error("Stale helper proxy recovery failed: \(error.localizedDescription)")
            }
        }
    }

    /// Best-effort cleanup used during late termination fallback and signal handling.
    func performEmergencyTerminationCleanup(reason: String) {
        stopBypassListObserver()

        if let backup = loadDirectBackup() {
            let backedUpServices = backup.services.map(\.service)
            if currentProxyMatchesRockxy(port: backup.rockxyPort, backedUpServices: backedUpServices) {
                Self.logger.warning("\(reason): restoring direct-mode proxy backup during shutdown")
                restoreDirectMode(using: backup)

                if anyLoopbackProxyEnabled(on: backedUpServices) {
                    Self.logger.warning("\(reason): direct restore incomplete, forcing proxy states off")
                    try? disableSystemProxyViaNetworkSetup()
                }
                return
            }

            Self.logger.info("\(reason): clearing stale direct backup because proxy no longer matches Rockxy")
            clearDirectBackup()
        }

        if helperEmergencyRestoreNeeded() {
            Self.logger.warning("\(reason): requesting helper-owned proxy restore during shutdown")
            if HelperConnection.performEmergencyProxyRestore() {
                return
            }

            Self.logger.error("\(reason): helper emergency restore did not complete, continuing fallback cleanup")
        }

        if anyLoopbackProxyEnabled(on: nil) {
            Self.logger.warning("\(reason): loopback proxy still enabled without backup, forcing proxy states off")
            try? disableSystemProxyViaNetworkSetup()
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "SystemProxyManager")
    private static let networkSetupPath = "/usr/sbin/networksetup"
    private static let routePath = "/sbin/route"
    private static let helperBackupPath = "/Library/Application Support/\(RockxyIdentity.current.sharedSupportDirectoryName)/proxy-backup.plist"

    // MARK: - Direct Backup Persistence

    private static var directBackupURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("proxy-backup-direct.plist")
    }

    private let lock = NSLock()
    private var isEnabled = false
    private var usingHelper = false
    private var activeServices: [String] = []
    private var directRestorePending = false
    private var originalBypassDomains: [String: [String]] = [:]
    private var originalProxyState: [String: ServiceProxySnapshot] = [:]
    private var bypassObserver: NSObjectProtocol?

    /// Shared direct-mode restore routine used by both same-session cleanup and ownership-based cleanup.
    private func restoreDirectMode(using backup: DirectProxyBackup) {
        let backedUpServices = backup.services.map(\.service)
        lock.lock()
        let hasInMemoryState = !originalProxyState.isEmpty
        let inMemoryProxy = originalProxyState
        let inMemoryBypass = originalBypassDomains
        lock.unlock()

        var allSucceeded = true

        if hasInMemoryState {
            for (service, snapshot) in inMemoryProxy {
                do {
                    try restoreServiceProxyState(service: service, snapshot: snapshot)
                } catch {
                    allSucceeded = false
                    Self.logger.error("Failed to restore proxy state for '\(service)': \(error.localizedDescription)")
                }
            }
            for (service, domains) in inMemoryBypass {
                do {
                    try restoreServiceBypassDomains(service: service, domains: domains)
                } catch {
                    allSucceeded = false
                    Self.logger.error("Failed to restore bypass for '\(service)': \(error.localizedDescription)")
                }
            }
        } else {
            for entry in backup.services {
                let snapshot = ServiceProxySnapshot(
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
                    try restoreServiceProxyState(service: entry.service, snapshot: snapshot)
                } catch {
                    allSucceeded = false
                    Self.logger
                        .error("Failed to restore proxy state for '\(entry.service)': \(error.localizedDescription)")
                }
                do {
                    try restoreServiceBypassDomains(service: entry.service, domains: entry.bypassDomains)
                } catch {
                    allSucceeded = false
                    Self.logger.error("Failed to restore bypass for '\(entry.service)': \(error.localizedDescription)")
                }
            }
        }

        let proxyStillPointsAtRockxy: Bool
        if allSucceeded {
            proxyStillPointsAtRockxy = directProxyStillOwnedAfterRestoreVerification(
                port: backup.rockxyPort,
                backedUpServices: backedUpServices
            )
        } else {
            proxyStillPointsAtRockxy = true
        }

        lock.lock()
        if Self.shouldClearDirectBackupAfterRestoreAttempt(
            commandsSucceeded: allSucceeded,
            proxyStillPointsAtRockxy: proxyStillPointsAtRockxy
        ) {
            clearDirectBackup()
            directRestorePending = false
        } else {
            if allSucceeded {
                Self.logger.warning(
                    "Direct restore commands completed but proxy still points at Rockxy — keeping backup on disk for watchdog retry"
                )
            } else {
                Self.logger.warning("Partial restore failure — keeping backup on disk for retry")
            }
            // directRestorePending stays true for same-session retry
        }
        lock.unlock()
    }

    // MARK: - NetworkSetup — Enable on ALL Enabled Services

    private func enableSystemProxyViaNetworkSetup(port: Int) throws {
        let services = try detectAllEnabledServices()
        guard !services.isEmpty else {
            throw SystemProxyError.noActiveNetworkService
        }

        Self.logger.info("Setting proxy on all \(services.count) enabled services")

        try persistDirectBackup(port: port)

        var mutatedServices: [String] = []
        do {
            for service in services {
                try runNetworkSetup(["-setwebproxy", service, "127.0.0.1", String(port)])
                try runNetworkSetup(["-setwebproxystate", service, "on"])
                try runNetworkSetup(["-setsecurewebproxy", service, "127.0.0.1", String(port)])
                try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
                try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
                mutatedServices.append(service)
                Self.logger.info("System proxy set on '\(service)' -> 127.0.0.1:\(port)")
            }
        } catch {
            Self.logger.error("Proxy setup failed after \(mutatedServices.count) service(s), rolling back")
            for service in mutatedServices {
                lock.lock()
                let snapshot = originalProxyState[service]
                let bypass = originalBypassDomains[service]
                lock.unlock()
                if let snapshot {
                    try? restoreServiceProxyState(service: service, snapshot: snapshot)
                }
                if let bypass {
                    try? restoreServiceBypassDomains(service: service, domains: bypass)
                }
            }
            clearDirectBackup()
            lock.lock()
            directRestorePending = false
            lock.unlock()
            throw error
        }

        guard !mutatedServices.isEmpty else {
            clearDirectBackup()
            throw SystemProxyError.noActiveNetworkService
        }

        lock.lock()
        isEnabled = true
        usingHelper = false
        activeServices = mutatedServices
        directRestorePending = true
        lock.unlock()

        startDirectProxyWatchdog()
    }

    // MARK: - NetworkSetup — Disable on ALL Configured Services

    private func disableSystemProxyViaNetworkSetup() throws {
        lock.lock()
        let services = activeServices
        lock.unlock()

        let targetServices = services.isEmpty ? (try? detectAllEnabledServices()) ?? [] : services

        for service in targetServices {
            do {
                try runNetworkSetup(["-setwebproxystate", service, "off"])
                try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
                try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
                Self.logger.info("System proxy disabled on '\(service)'")
            } catch {
                Self.logger.debug("Failed to disable proxy for '\(service)': \(error.localizedDescription)")
            }
        }

        lock.lock()
        isEnabled = false
        usingHelper = false
        activeServices = []
        lock.unlock()

        try? Self.removeDirectProxyWatchdog(tolerateMissing: true)
    }

    /// Snapshots bypass domains and proxy state for all detected target services
    /// BEFORE any proxy mutation occurs. Must be called before `enableSystemProxyViaNetworkSetup`.
    private func saveOriginalState() {
        guard let services = try? detectAllEnabledServices(), !services.isEmpty else {
            return
        }

        var bypassMap: [String: [String]] = [:]
        var proxyMap: [String: ServiceProxySnapshot] = [:]

        for service in services {
            // Save bypass domains per service
            if let output = try? runNetworkSetup(["-getproxybypassdomains", service]) {
                let domains = output.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("There aren't any bypass domains") }
                bypassMap[service] = domains
            }

            // Save proxy state per service
            let snapshot = captureProxySnapshot(for: service)
            proxyMap[service] = snapshot
        }

        lock.lock()
        originalBypassDomains = bypassMap
        originalProxyState = proxyMap
        lock.unlock()

        Self.logger.info("Saved original state for \(services.count) service(s)")
    }

    /// Parses `-getwebproxy` or `-getsecurewebproxy` output into (enabled, host, port).
    private func parseProxyOutput(_ output: String) -> (enabled: Bool, host: String, port: Int) {
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
                let portStr = trimmed.replacingOccurrences(of: "Port:", with: "").trimmingCharacters(in: .whitespaces)
                port = Int(portStr) ?? 0
            }
        }

        return (enabled, host, port)
    }

    /// Captures the current HTTP and HTTPS proxy settings for a single service.
    private func captureProxySnapshot(for service: String) -> ServiceProxySnapshot {
        let httpOutput = (try? runNetworkSetup(["-getwebproxy", service])) ?? ""
        let httpsOutput = (try? runNetworkSetup(["-getsecurewebproxy", service])) ?? ""
        let socksOutput = (try? runNetworkSetup(["-getsocksfirewallproxy", service])) ?? ""

        let http = parseProxyOutput(httpOutput)
        let https = parseProxyOutput(httpsOutput)
        let socks = parseProxyOutput(socksOutput)

        return ServiceProxySnapshot(
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

    /// Restores the proxy state for a single service from its snapshot.
    private func restoreServiceProxyState(service: String, snapshot: ServiceProxySnapshot) throws {
        for command in ProxyRestoreCommandBuilder.commands(service: service, snapshot: snapshot) {
            try runNetworkSetup(command)
        }
        Self.logger.info("Restored original proxy state for '\(service)'")
    }

    /// Restores the bypass domain list for a single service.
    private func restoreServiceBypassDomains(service: String, domains: [String]) throws {
        if domains.isEmpty {
            try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
        } else {
            let args = ["-setproxybypassdomains", service] + domains
            try runNetworkSetup(args)
        }
        Self.logger.info("Restored \(domains.count) bypass domain(s) for '\(service)'")
    }

    private func applyBypassDomainsViaNetworkSetup(_ domains: [String]) {
        lock.lock()
        let services = activeServices
        lock.unlock()

        let targetServices = services.isEmpty ? ((try? detectAllEnabledServices()) ?? []) : services

        for service in targetServices {
            do {
                if domains.isEmpty {
                    try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
                } else {
                    let args = ["-setproxybypassdomains", service] + domains
                    try runNetworkSetup(args)
                }
            } catch {
                Self.logger.debug("Failed to set bypass domains for '\(service)': \(error.localizedDescription)")
            }
        }

        Self.logger.info("Applied \(domains.count) bypass domain(s) via networksetup")
    }

    // MARK: - Network Service Detection

    /// Returns ALL enabled (non-disabled) network services. Matches Charles/Proxyman behavior
    /// of configuring proxy on every adapter so traffic is captured regardless of active interface.
    private func detectAllEnabledServices() throws -> [String] {
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
        Self.logger.info("Enabled network services: \(services)")
        return services
    }

    /// Uses the routing table (`route -n get 0.0.0.0`) to find the network interface
    /// carrying default traffic. Returns the interface name (e.g., "en0") or nil.
    private func detectPrimaryInterface() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.routePath)
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
                        Self.logger.info("Primary interface from route table: \(iface)")
                        return iface
                    }
                }
            }
        } catch {
            Self.logger.warning("Failed to detect primary interface via route: \(error.localizedDescription)")
        }
        return nil
    }

    /// Detects the primary network service by mapping the routing table interface
    /// to a service name. Falls back to the first enabled service.
    private func detectPrimaryNetworkService() throws -> String {
        if let primaryIface = detectPrimaryInterface() {
            let output = try runNetworkSetup(["-listnetworkserviceorder"])
            let serviceMap = parseNetworkServiceMap(from: output)
            if let serviceName = serviceMap[primaryIface] {
                return serviceName
            }
        }

        let services = try detectAllEnabledServices()
        guard let first = services.first else {
            throw SystemProxyError.noActiveNetworkService
        }
        return first
    }

    /// Parses `-listnetworkserviceorder` output into a map of device name → service name.
    /// e.g., "en0" → "Wi-Fi", "en1" → "Ethernet"
    private func parseNetworkServiceMap(from output: String) -> [String: String] {
        var result: [String: String] = [:]
        var lastServiceName: String?
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("(Hardware Port:"), let serviceName = lastServiceName {
                if let deviceRange = trimmed.range(of: "Device: ") {
                    let afterDevice = trimmed[deviceRange.upperBound...]
                    let device = String(afterDevice.prefix(while: { $0 != ")" }))
                    if !device.isEmpty {
                        result[device] = serviceName
                    }
                }
            } else if let openParen = trimmed.firstIndex(of: "("),
                      let closeParen = trimmed.firstIndex(of: ")"),
                      openParen == trimmed.startIndex
            {
                let afterParen = trimmed.index(after: closeParen)
                let serviceName = String(trimmed[afterParen...]).trimmingCharacters(in: .whitespaces)
                if !serviceName.isEmpty {
                    lastServiceName = serviceName
                }
            }
        }

        return result
    }

    private func parseNetworkServices(from output: String) -> [String] {
        var services: [String] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Lines like "(1) Wi-Fi" or "(2) Ethernet"
            if let openParen = trimmed.firstIndex(of: "("),
               let closeParen = trimmed.firstIndex(of: ")"),
               openParen == trimmed.startIndex
            {
                let afterParen = trimmed.index(after: closeParen)
                let serviceName = String(trimmed[afterParen...]).trimmingCharacters(in: .whitespaces)
                if !serviceName.isEmpty {
                    services.append(serviceName)
                }
            }
        }

        return services
    }

    /// Writes the current in-memory original state to disk as a plist backup.
    private func persistDirectBackup(port: Int) throws {
        lock.lock()
        let proxyState = originalProxyState
        let bypassState = originalBypassDomains
        lock.unlock()

        var serviceBackups: [DirectServiceBackup] = []
        for (service, snapshot) in proxyState {
            let bypass = bypassState[service] ?? []
            serviceBackups.append(DirectServiceBackup(
                service: service,
                httpEnabled: snapshot.httpEnabled,
                httpHost: snapshot.httpHost,
                httpPort: snapshot.httpPort,
                httpsEnabled: snapshot.httpsEnabled,
                httpsHost: snapshot.httpsHost,
                httpsPort: snapshot.httpsPort,
                socksEnabled: snapshot.socksEnabled,
                socksHost: snapshot.socksHost,
                socksPort: snapshot.socksPort,
                bypassDomains: bypass
            ))
        }

        let backup = DirectProxyBackup(
            services: serviceBackups,
            timestamp: Date(),
            rockxyPort: port
        )

        let url = Self.directBackupURL
        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: parentDir.path
        )
        let data = try PropertyListEncoder().encode(backup)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        Self.logger.info("Persisted direct backup for \(serviceBackups.count) service(s) at port \(port)")
    }

    private func startDirectProxyWatchdog() {
        let executableURL = Self.directWatchdogExecutableURL
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            Self.logger.warning("Could not resolve helper executable for direct proxy watchdog")
            return
        }

        do {
            try Self.submitDirectProxyWatchdog(
                label: Self.directWatchdogLabel,
                executableURL: executableURL,
                parentPID: ProcessInfo.processInfo.processIdentifier,
                backupPath: Self.directBackupURL.path
            )
            Self.logger
                .info(
                    "Registered direct proxy watchdog '\(Self.directWatchdogLabel)' for pid \(ProcessInfo.processInfo.processIdentifier)"
                )
        } catch {
            Self.logger.warning("Failed to start direct proxy watchdog: \(error.localizedDescription)")
        }
    }

    private static var directWatchdogExecutableURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HelperTools", isDirectory: true)
            .appendingPathComponent("RockxyHelperTool", isDirectory: false)
    }

    private func directProxyStillOwnedAfterRestoreVerification(
        port: Int,
        backedUpServices: [String],
        maxAttempts: Int = 5,
        pollInterval: TimeInterval = 0.2
    ) -> Bool {
        guard !backedUpServices.isEmpty else {
            return anyLoopbackProxyEnabled(on: nil)
        }

        for attempt in 0..<maxAttempts {
            if !currentProxyMatchesRockxy(port: port, backedUpServices: backedUpServices) {
                return false
            }

            if attempt < maxAttempts - 1 {
                Thread.sleep(forTimeInterval: pollInterval)
            }
        }

        return true
    }

    nonisolated static var directWatchdogLabel: String {
        "\(RockxyIdentity.current.appBundleIdentifier).direct-proxy-watchdog"
    }

    nonisolated static func directWatchdogSubmitArguments(
        label: String,
        executablePath: String,
        parentPID: pid_t,
        backupPath: String
    ) -> [String] {
        [
            "submit",
            "-l",
            label,
            "--",
            executablePath,
            "--rockxy-direct-proxy-watchdog",
            String(parentPID),
            backupPath,
        ]
    }

    private static func submitDirectProxyWatchdog(
        label: String,
        executableURL: URL,
        parentPID: pid_t,
        backupPath: String
    ) throws {
        try removeDirectProxyWatchdog(label: label, tolerateMissing: true)
        _ = try runLaunchctl(directWatchdogSubmitArguments(
            label: label,
            executablePath: executableURL.path,
            parentPID: parentPID,
            backupPath: backupPath
        ))
    }

    private static func removeDirectProxyWatchdog(
        label: String = directWatchdogLabel,
        tolerateMissing: Bool
    ) throws {
        do {
            _ = try runLaunchctl(["remove", label], toleratedExitCodes: tolerateMissing ? [3] : [])
        } catch {
            if tolerateMissing {
                return
            }
            throw error
        }
    }

    @discardableResult
    private static func runLaunchctl(
        _ arguments: [String],
        toleratedExitCodes: Set<Int32> = []
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw SystemProxyError.unexpectedOutput("Failed to launch launchctl: \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        let terminationStatus = process.terminationStatus
        if terminationStatus == 0 || toleratedExitCodes.contains(terminationStatus) {
            return stdout
        }

        let combined = stderr.isEmpty ? stdout : stderr
        throw SystemProxyError.unexpectedOutput(
            "launchctl \(arguments.joined(separator: " ")) failed (exit \(terminationStatus)): \(combined)"
        )
    }

    // MARK: - Process Execution

    @discardableResult
    private func runNetworkSetup(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.networkSetupPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            Self.logger.error("Failed to launch networksetup: \(error.localizedDescription)")
            throw SystemProxyError.networkSetupFailed(
                command: arguments.joined(separator: " "),
                output: error.localizedDescription,
                exitCode: -1
            )
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let combined = stderr.isEmpty ? stdout : stderr
            Self.logger.error("networksetup failed: \(combined)")
            throw SystemProxyError.networkSetupFailed(
                command: arguments.joined(separator: " "),
                output: combined,
                exitCode: process.terminationStatus
            )
        }

        return stdout
    }

    private func anyLoopbackProxyEnabled(on services: [String]?) -> Bool {
        let targetServices = services ?? ((try? detectAllEnabledServices()) ?? [])

        for service in targetServices {
            let snapshot = captureProxySnapshot(for: service)
            let httpMatch = snapshot.httpEnabled && snapshot.httpHost == "127.0.0.1"
            let httpsMatch = snapshot.httpsEnabled && snapshot.httpsHost == "127.0.0.1"
            let socksMatch = snapshot.socksEnabled && snapshot.socksHost == "127.0.0.1"

            if httpMatch || httpsMatch || socksMatch {
                return true
            }
        }

        return false
    }

    private func helperEmergencyRestoreNeeded() -> Bool {
        lock.lock()
        let wasUsingHelper = usingHelper
        lock.unlock()

        let helperBackupExists = FileManager.default.fileExists(atPath: Self.helperBackupPath)
        let loopbackProxyDetected = helperBackupExists ? anyLoopbackProxyEnabled(on: nil) : false

        return Self.shouldAttemptHelperEmergencyRestore(
            wasUsingHelper: wasUsingHelper,
            helperBackupExists: helperBackupExists,
            loopbackProxyDetected: loopbackProxyDetected
        )
    }
}
