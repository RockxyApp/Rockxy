import CFNetwork
import Darwin
import Foundation
import os
import SystemConfiguration

// swiftlint:disable file_length

// Defines `SystemProxyManager`, which coordinates system proxy behavior in traffic capture
// and system proxy coordination.

// MARK: - SystemProxyError

/// Errors raised when configuring macOS system proxy settings via `networksetup`.
enum SystemProxyError: LocalizedError {
    case networkSetupFailed(command: String, output: String, exitCode: Int32)
    case noActiveNetworkService
    case proxyActivationNotConfirmed(port: Int)
    case proxyRestoreFailed
    case previousHelperUnavailable
    case unexpectedOutput(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .networkSetupFailed(command, output, exitCode):
            "networksetup \(command) failed (exit \(exitCode)): \(output)"
        case .noActiveNetworkService:
            "Could not detect an active network service"
        case let .proxyActivationNotConfirmed(port):
            "macOS did not confirm the Rockxy system proxy on port \(port)"
        case .proxyRestoreFailed:
            "Rockxy could not restore one or more system proxy settings"
        case .previousHelperUnavailable:
            "Rockxy cannot safely reclaim system routing with the installed helper. Quit and reopen Rockxy, then update or repair the helper in Advanced Proxy Settings."
        case let .unexpectedOutput(output):
            "Unexpected networksetup output: \(output)"
        }
    }
}

// MARK: - ProxyActivationConfirmation

enum ProxyActivationConfirmation {
    static func confirm(
        maxAttempts: Int = 5,
        delay: Duration = .milliseconds(200),
        probe: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        guard maxAttempts > 0 else {
            return false
        }

        for attempt in 0 ..< maxAttempts {
            if await probe() {
                return true
            }
            guard attempt + 1 < maxAttempts else {
                break
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return false
            }
        }
        return false
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

    func markedRecoveryPending() -> DirectProxyBackup {
        DirectProxyBackup(
            services: services,
            timestamp: timestamp,
            rockxyPort: rockxyPort,
            recoveryPending: true
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

enum SystemProxyReclaimMode: Equatable {
    case none
    case direct
    case helper
}

// MARK: - SystemProxyStartupRecovery

/// One process-wide recovery barrier shared by app services and the capture UI. A single task
/// prevents launch-time restore from racing a new proxy enable when both surfaces appear together.
enum SystemProxyStartupRecovery {
    static let task = Task.detached(priority: .userInitiated) {
        await SystemProxyManager.shared.recoverStaleProxyIfNeeded()
    }
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
    let pacEnabled: Bool
    let pacURL: String
    let autoDiscoveryEnabled: Bool
}

// MARK: - SystemProxyManager

/// Manages the macOS system HTTP/HTTPS proxy by shelling out to `/usr/sbin/networksetup`.
/// Configures both HTTP and HTTPS proxy settings on all enabled network services
/// (Wi-Fi, Ethernet, USB LAN, etc.) so traffic is captured regardless of which
/// interface the browser uses.
final class SystemProxyManager: @unchecked Sendable {
    // MARK: Internal

    static let shared = SystemProxyManager()

    nonisolated static var directWatchdogLabel: String {
        "\(RockxyIdentity.current.appBundleIdentifier).direct-proxy-watchdog"
    }

    var systemProxyEnabled: Bool {
        lock.withLock { isEnabled }
    }

    var usingHelperProxyOverride: Bool {
        lock.withLock { usingHelper }
    }

    /// Starts one process-wide observer for the live macOS proxy dictionary. Unlike
    /// `.systemProxyDidChange`, this also detects changes made by System Settings,
    /// VPN software, or another debugging proxy while Rockxy's listener is running.
    func startMonitoringSystemProxyConfiguration() {
        proxyConfigurationMonitor.start()
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

    nonisolated static func reclaimMode(
        directRestorePending: Bool,
        directBackupExists: Bool,
        usingHelper: Bool,
        isEnabled: Bool
    ) -> SystemProxyReclaimMode {
        if directRestorePending, directBackupExists {
            return .direct
        }
        if usingHelper, !isEnabled {
            return .helper
        }
        return .none
    }

    nonisolated static func directProxyWatchdogAction(
        parentAlive: Bool,
        backupExists: Bool
    )
        -> DirectProxyWatchdogAction
    {
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
    )
        -> Bool
    {
        commandsSucceeded && !proxyStillPointsAtRockxy
    }

    nonisolated static func helperOverrideIsConfirmed(
        requestedPort: Int,
        status: (isOverridden: Bool, port: Int)?
    )
        -> Bool
    {
        guard let status else {
            return false
        }
        return status.isOverridden && status.port == requestedPort
    }

    @discardableResult
    nonisolated static func runDirectProxyWatchdogIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    )
        -> Bool
    {
        guard arguments.count >= 3,
              arguments[1] == "--rockxy-direct-proxy-watchdog",
              let parentPID = Int32(arguments[2]) else
        {
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

    nonisolated static func directWatchdogSubmitArguments(
        label: String,
        executablePath: String,
        parentPID: pid_t,
        backupPath: String
    )
        -> [String]
    {
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

    // MARK: - Public API

    func enableSystemProxy(port: Int) async throws {
        Self.logger.info("enableSystemProxy called for port \(port)")

        lock.lock()
        let directRestoreWasPending = directRestorePending
        let helperWasUsed = usingHelper
        let overrideWasEnabled = isEnabled
        lock.unlock()
        let reclaimMode = Self.reclaimMode(
            directRestorePending: directRestoreWasPending,
            directBackupExists: loadDirectBackup() != nil,
            usingHelper: helperWasUsed,
            isEnabled: overrideWasEnabled
        )
        let reclaimingDirectSession = reclaimMode == .direct
        let reclaimingHelperSession = reclaimMode == .helper

        // A reclaim must retain the snapshot from before Rockxy's first override. Capturing
        // again here would turn the foreign takeover into the state restored on quit.
        if !reclaimingDirectSession, !reclaimingHelperSession {
            saveOriginalState()
        }

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

        if reclaimingDirectSession {
            Self.logger.info("Reclaiming direct-mode system routing with the existing backup")
            try enableSystemProxyViaNetworkSetup(port: port)
        } else if reclaimingHelperSession {
            let info = try await HelperConnection.shared.getHelperInfo()
            guard HelperCompatibilityPolicy.supportsSafeProxyRouting(
                protocolVersion: info.protocolVersion
            ) else {
                throw SystemProxyError.previousHelperUnavailable
            }
            Self.logger.info("Reclaiming helper-owned system routing with the existing backup")
            try await HelperConnection.shared.overrideSystemProxy(port: port)
            lock.lock()
            isEnabled = true
            usingHelper = true
            lock.unlock()
        } else if helperStatus == .installedCompatible || helperStatus == .installedOutdated {
            if let info = try? await HelperConnection.shared.getHelperInfo(),
               HelperCompatibilityPolicy.supportsSafeProxyRouting(protocolVersion: info.protocolVersion)
            {
                Self.logger.info("Enabling system proxy via helper tool on port \(port)")
                try await HelperConnection.shared.overrideSystemProxy(port: port)

                lock.lock()
                isEnabled = true
                usingHelper = true
                lock.unlock()
            } else {
                Self.logger.warning("Helper cannot safely own this proxy session, falling back to networksetup")
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

        // Bypass settings are part of effective routing. Apply Rockxy's bounded list before
        // confirmation so a foreign catch-all exception can be repaired instead of deadlocking
        // the recovery flow behind the very check it needs to satisfy.
        do {
            try await applyBypassDomains()
            guard await activeOverrideMatches(port: port) else {
                throw SystemProxyError.proxyActivationNotConfirmed(port: port)
            }
        } catch {
            await rollbackUnconfirmedOverride()
            clearInMemoryOverrideState()
            throw error
        }

        startBypassListObserver()

        Self.logger.info("System proxy enabled on port \(port)")
        NotificationCenter.default.post(name: .systemProxyDidChange, object: nil, userInfo: ["enabled": true])
    }

    func disableSystemProxy() async throws {
        // Same-session shortcut: if we know we own a direct override, skip ownership detection
        lock.lock()
        let pending = directRestorePending
        let helperSession = usingHelper
        lock.unlock()

        if pending, let backup = loadDirectBackup() {
            Self.logger.info("Direct restore pending — restoring \(backup.services.count) service(s)")
            guard restoreDirectMode(using: backup) else {
                throw SystemProxyError.proxyRestoreFailed
            }
        } else if helperSession {
            // Live routing may have been replaced by a VPN, PAC, or another proxy app. The
            // helper's persisted snapshot still belongs to this capture session and is the only
            // authoritative route back to the user's pre-Rockxy configuration.
            Self.logger.info("Helper session ending — restoring its original proxy snapshot")
            try await HelperConnection.shared.restoreSystemProxy()
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
                guard restoreDirectMode(using: backup) else {
                    throw SystemProxyError.proxyRestoreFailed
                }
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

    private func isSystemProxyEnabled() -> Bool {
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

    func isSystemProxyEnabledAsync() async -> Bool {
        await Task.detached(priority: .utility) {
            self.isSystemProxyEnabled()
        }.value
    }

    // MARK: - Bypass Domain Management

    /// Apply bypass domains from BypassProxyManager to the system proxy.
    /// Uses helper tool if available, otherwise runs networksetup directly.
    func applyBypassDomains() async throws {
        let domains = await BypassProxyManager.shared.enabledDomainStringsForSystemProxy()

        lock.lock()
        let currentlyUsingHelper = usingHelper
        lock.unlock()

        if currentlyUsingHelper {
            try await HelperConnection.shared.setBypassDomains(domains)
            Self.logger.info("Applied \(domains.count) bypass domain(s) via helper")
        } else {
            try applyBypassDomainsViaNetworkSetup(domains)
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
                try? await self.applyBypassDomains()
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
        // In-memory ownership is only a hint. The proxy can be changed outside
        // Rockxy, or a helper watchdog can restore it after an app restart.
        // Always reconcile against live state before exposing an active override.
        lock.lock()
        let wasEnabled = isEnabled
        let wasUsingHelper = usingHelper
        lock.unlock()

        if let backup = loadDirectBackup() {
            let backedUpServices = backup.services.map(\.service)
            if currentProxyMatchesRockxy(port: backup.rockxyPort, backedUpServices: backedUpServices),
               effectiveSystemProxyMatchesRockxy(port: backup.rockxyPort) {
                return .direct(backup: backup)
            }
        }

        if let helperStatus = try? await HelperConnection.shared.getProxyStatus(),
           helperStatus.isOverridden,
           effectiveSystemProxyMatchesRockxy(port: helperStatus.port)
        {
            return .helper(port: helperStatus.port)
        }

        if wasEnabled || wasUsingHelper {
            clearInMemoryOverrideState(preserveOverrideMethod: true)
        }

        return .none
    }

    private func activeOverrideMatches(port: Int) async -> Bool {
        await ProxyActivationConfirmation.confirm { [self] in
            await activeOverrideMatchesOnce(port: port)
        }
    }

    private func activeOverrideMatchesOnce(port: Int) async -> Bool {
        lock.lock()
        let helper = usingHelper
        let services = activeServices
        lock.unlock()

        if helper {
            let status = try? await HelperConnection.shared.getProxyStatus()
            return Self.helperOverrideIsConfirmed(requestedPort: port, status: status)
                && effectiveSystemProxyMatchesRockxy(port: port)
        }

        return !services.isEmpty
            && currentProxyMatchesRockxy(port: port, backedUpServices: services)
            && effectiveSystemProxyMatchesRockxy(port: port)
    }

    private func clearInMemoryOverrideState(preserveOverrideMethod: Bool = false) {
        lock.lock()
        isEnabled = false
        if !preserveOverrideMethod {
            usingHelper = false
        }
        activeServices = []
        lock.unlock()
    }

    private func rollbackUnconfirmedOverride() async {
        lock.lock()
        let helper = usingHelper
        lock.unlock()

        if helper {
            do {
                try await HelperConnection.shared.restoreSystemProxy()
            } catch {
                Self.logger.error(
                    "Could not roll back an unconfirmed helper proxy override: \(error.localizedDescription)"
                )
            }
            return
        }

        if let backup = loadDirectBackup() {
            restoreDirectMode(using: backup)
        }
    }

    /// Checks the routed service when it can be identified. If route-to-service mapping is
    /// unavailable, every backed-up service must match so an arbitrary secondary service can
    /// never make the UI claim that automatic capture is ready.
    func currentProxyMatchesRockxy(port: Int, backedUpServices: [String]) -> Bool {
        let servicesToCheck: [String]
        if let primaryInterface = detectPrimaryInterface(),
           let orderOutput = try? runNetworkSetup(["-listnetworkserviceorder"]),
           let primaryService = parseNetworkServiceMap(from: orderOutput)[primaryInterface],
           backedUpServices.contains(primaryService)
        {
            servicesToCheck = [primaryService]
        } else {
            servicesToCheck = backedUpServices
        }
        return Self.proxySnapshotsMatchRockxy(
            port: port,
            snapshots: servicesToCheck.map(captureProxySnapshot)
        )
    }

    nonisolated static func proxySnapshotsMatchRockxy(
        port: Int,
        snapshots: [ServiceProxySnapshot]
    ) -> Bool {
        !snapshots.isEmpty && snapshots.allSatisfy { snapshot in
            snapshot.httpEnabled
                && snapshot.httpHost == "127.0.0.1"
                && snapshot.httpPort == port
                && snapshot.httpsEnabled
                && snapshot.httpsHost == "127.0.0.1"
                && snapshot.httpsPort == port
                && !snapshot.socksEnabled
                && !snapshot.pacEnabled
                && !snapshot.autoDiscoveryEnabled
        }
    }

    /// Verifies the effective proxy dictionary used by the current default route. Helper
    /// status alone is not authoritative because an older helper or another proxy app can
    /// retain stale ownership metadata after macOS routing has already changed.
    func effectiveSystemProxyMatchesRockxy(port: Int) -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
            as? [String: Any]
        else {
            return false
        }
        return Self.effectiveProxyDictionaryMatchesRockxy(port: port, settings: settings)
    }

    nonisolated static func effectiveProxyDictionaryMatchesRockxy(
        port: Int,
        settings: [String: Any]
    ) -> Bool {
        func enabled(_ key: CFString) -> Bool {
            (settings[key as String] as? NSNumber)?.boolValue == true
        }
        func host(_ key: CFString) -> String? {
            settings[key as String] as? String
        }
        func configuredPort(_ key: CFString) -> Int? {
            (settings[key as String] as? NSNumber)?.intValue
        }
        let hasGlobalBypass = (settings[kCFNetworkProxiesExceptionsList as String] as? [String])?
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "*" }
            ?? false

        return enabled(kCFNetworkProxiesHTTPEnable)
            && host(kCFNetworkProxiesHTTPProxy) == "127.0.0.1"
            && configuredPort(kCFNetworkProxiesHTTPPort) == port
            && enabled(kCFNetworkProxiesHTTPSEnable)
            && host(kCFNetworkProxiesHTTPSProxy) == "127.0.0.1"
            && configuredPort(kCFNetworkProxiesHTTPSPort) == port
            && !enabled(kCFNetworkProxiesSOCKSEnable)
            && !enabled(kCFNetworkProxiesProxyAutoConfigEnable)
            && !enabled(kCFNetworkProxiesProxyAutoDiscoveryEnable)
            && !hasGlobalBypass
    }

    // MARK: - Launch-Time Recovery

    /// Called at app launch to detect and restore stale direct-mode proxy overrides
    /// left behind by a crash or force-quit.
    func recoverStaleProxyIfNeeded() async {
        if let backup = loadDirectBackup() {
            let residualOwnedServices = recoverableDirectServices(in: backup)
            // The session that wrote this backup is by definition gone: this app process is the
            // only one that can own a direct-mode override, and it has just launched.
            switch ProxyBackupRecoveryPolicy.action(
                residualOwnedServicesExist: !residualOwnedServices.isEmpty,
                ownerSessionIsLive: false
            ) {
            case .restore:
                Self.logger
                    .info(
                        "Recovering \(residualOwnedServices.count) stale direct-mode service(s) from a previous session"
                    )
                if recoverOwnedDirectServices(backup: backup, ownedServices: residualOwnedServices) {
                    stopBypassListObserver()
                    clearInMemoryOverrideState()
                    NotificationCenter.default.post(
                        name: .systemProxyDidChange,
                        object: nil,
                        userInfo: ["enabled": false]
                    )
                } else {
                    Self.logger.error("Stale direct proxy recovery incomplete — backup preserved for retry")
                }
            case .clear:
                Self.logger.info("No backed-up service is still Rockxy-owned, clearing stale direct backup")
                clearDirectBackup()
            case .preserve:
                break
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
            let residualOwnedServices = recoverableDirectServices(in: backup)
            if !residualOwnedServices.isEmpty {
                Self.logger
                    .warning(
                        "\(reason): restoring \(residualOwnedServices.count) owned direct-mode service(s) during shutdown"
                    )
                if !recoverOwnedDirectServices(backup: backup, ownedServices: residualOwnedServices) {
                    Self.logger.warning("\(reason): direct restore incomplete, leaving the narrowed backup for retry")
                }
                return
            }

            Self.logger.info("\(reason): clearing stale direct backup because no service is still Rockxy-owned")
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

    private let proxyConfigurationMonitor = SystemProxyConfigurationMonitor()
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

    private static var directWatchdogExecutableURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HelperTools", isDirectory: true)
            .appendingPathComponent("RockxyHelperTool", isDirectory: false)
    }

    private let lock = NSLock()
    private var isEnabled = false
    private var usingHelper = false
    private var activeServices: [String] = []
    private var directRestorePending = false
    private var originalBypassDomains: [String: [String]] = [:]
    private var originalProxyState: [String: ServiceProxySnapshot] = [:]
    private var bypassObserver: NSObjectProtocol?

    private static func submitDirectProxyWatchdog(
        label: String,
        executableURL: URL,
        parentPID: pid_t,
        backupPath: String
    )
        throws
    {
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
    )
        throws
    {
        _ = try runLaunchctl(["remove", label], toleratedExitCodes: tolerateMissing ? [3] : [])
    }

    @discardableResult
    private static func runLaunchctl(
        _ arguments: [String],
        toleratedExitCodes: Set<Int32> = []
    )
        throws -> String
    {
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

    /// Shared direct-mode restore routine used by both same-session cleanup and ownership-based cleanup.
    @discardableResult
    private func restoreDirectMode(using sourceBackup: DirectProxyBackup) -> Bool {
        let backup = sourceBackup.markedRecoveryPending()
        do {
            try writeDirectBackup(backup)
        } catch {
            Self.logger.error("Could not mark direct recovery pending — leaving settings untouched: \(error.localizedDescription)")
            return false
        }
        let backedUpServices = backup.services.map(\.service)

        var allSucceeded = true
        var failedServices: Set<String> = []

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
                socksPort: entry.socksPort,
                pacEnabled: entry.pacEnabled,
                pacURL: entry.pacURL,
                autoDiscoveryEnabled: entry.autoDiscoveryEnabled
            )
            do {
                try restoreServiceProxyState(service: entry.service, snapshot: snapshot)
            } catch {
                allSucceeded = false
                failedServices.insert(entry.service)
                Self.logger.error("Failed to restore proxy state for '\(entry.service)': \(error.localizedDescription)")
            }
            do {
                try restoreServiceBypassDomains(service: entry.service, domains: entry.bypassDomains)
            } catch {
                allSucceeded = false
                failedServices.insert(entry.service)
                Self.logger.error("Failed to restore bypass for '\(entry.service)': \(error.localizedDescription)")
            }
        }

        // Any service still pointing at Rockxy keeps the backup alive, even when the others
        // restored cleanly — that service has no other restore point.
        let stillOwnedServices = allSucceeded
            ? residualOwnedServicesAfterRestore(port: backup.rockxyPort, backedUpServices: backedUpServices)
            : residualRockxyOwnedServices(port: backup.rockxyPort, backedUpServices: backedUpServices)

        let proxyStillPointsAtRockxy: Bool = if allSucceeded {
            backedUpServices.isEmpty ? anyLoopbackProxyEnabled(on: nil) : !stillOwnedServices.isEmpty
        } else {
            true
        }

        let restored = Self.shouldClearDirectBackupAfterRestoreAttempt(
            commandsSucceeded: allSucceeded,
            proxyStillPointsAtRockxy: proxyStillPointsAtRockxy
        )
        lock.lock()
        if restored {
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
            retainUnresolvedDirectBackup(
                backup: backup,
                failedServices: failedServices,
                stillOwnedServices: Set(stillOwnedServices)
            )
            // directRestorePending stays true for same-session retry
        }
        lock.unlock()
        return restored
    }

    // MARK: - NetworkSetup — Enable on ALL Enabled Services

    private func enableSystemProxyViaNetworkSetup(port: Int) throws {
        let services = try detectAllEnabledServices()
        guard !services.isEmpty else {
            throw SystemProxyError.noActiveNetworkService
        }

        Self.logger.info("Setting proxy on all \(services.count) enabled services")

        try prepareDirectBackup(port: port, services: services)

        var mutatedServices: [String] = []
        do {
            for service in services {
                try runNetworkSetup(["-setwebproxy", service, "127.0.0.1", String(port)])
                try runNetworkSetup(["-setwebproxystate", service, "on"])
                try runNetworkSetup(["-setsecurewebproxy", service, "127.0.0.1", String(port)])
                try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
                try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
                try runNetworkSetup(["-setautoproxystate", service, "off"])
                try runNetworkSetup(["-setproxyautodiscovery", service, "off"])
                mutatedServices.append(service)
                Self.logger.info("System proxy set on '\(service)' -> 127.0.0.1:\(port)")
            }
        } catch {
            Self.logger.error("Proxy setup failed after \(mutatedServices.count) service(s), rolling back")
            if let backup = loadDirectBackup() {
                restoreDirectMode(using: backup)
            }
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
                try runNetworkSetup(["-setautoproxystate", service, "off"])
                try runNetworkSetup(["-setproxyautodiscovery", service, "off"])
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
        let pacOutput = (try? runNetworkSetup(["-getautoproxyurl", service])) ?? ""
        let autoDiscoveryOutput = (try? runNetworkSetup(["-getproxyautodiscovery", service])) ?? ""

        let http = parseProxyOutput(httpOutput)
        let https = parseProxyOutput(httpsOutput)
        let socks = parseProxyOutput(socksOutput)
        let pac = ProxyRestoreCommandBuilder.parsePACOutput(pacOutput)

        return ServiceProxySnapshot(
            httpEnabled: http.enabled,
            httpHost: http.host,
            httpPort: http.port,
            httpsEnabled: https.enabled,
            httpsHost: https.host,
            httpsPort: https.port,
            socksEnabled: socks.enabled,
            socksHost: socks.host,
            socksPort: socks.port,
            pacEnabled: pac.enabled,
            pacURL: pac.url,
            autoDiscoveryEnabled: ProxyRestoreCommandBuilder.parseAutoDiscoveryOutput(autoDiscoveryOutput)
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

    private func applyBypassDomainsViaNetworkSetup(_ domains: [String]) throws {
        lock.lock()
        let services = activeServices
        lock.unlock()

        let targetServices = services.isEmpty ? ((try? detectAllEnabledServices()) ?? []) : services

        for service in targetServices {
            if domains.isEmpty {
                try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
            } else {
                let args = ["-setproxybypassdomains", service] + domains
                try runNetworkSetup(args)
            }
        }

        Self.logger.info("Applied \(domains.count) bypass domain(s) via networksetup")
    }

    // MARK: - Network Service Detection

    /// Returns every enabled network service so proxy settings cover whichever adapter is active.
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

    /// Extends the session backup before mutating newly enabled services. Existing entries
    /// remain authoritative until the whole session has restored successfully.
    private func prepareDirectBackup(port: Int, services: [String]) throws {
        let existingBackup = loadDirectBackup()
        let existingServices = Set(existingBackup?.services.map(\.service) ?? [])
        let missingServices = services.filter { !existingServices.contains($0) }
        let additions = try missingServices.map(captureDirectServiceBackup)
        let backup = DirectProxyBackup(
            services: (existingBackup?.services ?? []) + additions,
            timestamp: existingBackup?.timestamp ?? Date(),
            rockxyPort: port
        )

        if additions.isEmpty, existingBackup?.rockxyPort == port {
            Self.logger.info("Preserving direct backup for \(existingServices.count) service(s)")
            return
        }

        try writeDirectBackup(backup)
    }

    private func captureDirectServiceBackup(service: String) throws -> DirectServiceBackup {
        let http = parseProxyOutput(try runNetworkSetup(["-getwebproxy", service]))
        let https = parseProxyOutput(try runNetworkSetup(["-getsecurewebproxy", service]))
        let socks = parseProxyOutput(try runNetworkSetup(["-getsocksfirewallproxy", service]))
        let pac = ProxyRestoreCommandBuilder.parsePACOutput(
            try runNetworkSetup(["-getautoproxyurl", service])
        )
        let autoDiscovery = ProxyRestoreCommandBuilder.parseAutoDiscoveryOutput(
            try runNetworkSetup(["-getproxyautodiscovery", service])
        )
        let bypassOutput = try runNetworkSetup(["-getproxybypassdomains", service])
        let bypass = bypassOutput.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("There aren't any bypass domains") }

        return DirectServiceBackup(
            service: service,
            httpEnabled: http.enabled,
            httpHost: http.host,
            httpPort: http.port,
            httpsEnabled: https.enabled,
            httpsHost: https.host,
            httpsPort: https.port,
            socksEnabled: socks.enabled,
            socksHost: socks.host,
            socksPort: socks.port,
            pacEnabled: pac.enabled,
            pacURL: pac.url,
            autoDiscoveryEnabled: autoDiscovery,
            bypassDomains: bypass
        )
    }

    private func writeDirectBackup(_ backup: DirectProxyBackup) throws {
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
        Self.logger.info("Persisted direct backup for \(backup.services.count) service(s) at port \(backup.rockxyPort)")
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

// MARK: - Direct-Mode Recovery

/// Ownership and subset-restore behavior for direct-mode backups. Recovery asks a different
/// question from readiness — which backed-up services still need their restore point — so it
/// lives apart from the enable/disable flow it supports.
extension SystemProxyManager {
    /// Recovery's per-service ownership view of a backup. `currentProxyMatchesRockxy` answers a
    /// readiness question — is capture actually routed through Rockxy — and deliberately requires
    /// the routed service, or every backed-up service, to match. Recovery asks something else:
    /// which backed-up services are still pointing at Rockxy and therefore still need their
    /// restore point. One service the user re-pointed must not make the rest look unowned.
    func residualRockxyOwnedServices(port: Int, backedUpServices: [String]) -> [String] {
        ProxyOverrideOwnership.residualOwnedServices(
            in: backedUpServices.map(currentOverrideState(for:)),
            port: port
        )
    }

    /// Once a restore has started, every retained entry is known unresolved even if a partial
    /// command already changed the live shape enough that strict ownership no longer matches.
    private func recoverableDirectServices(in backup: DirectProxyBackup) -> [String] {
        if backup.recoveryPending {
            return backup.services.map(\.service)
        }
        return residualRockxyOwnedServices(
            port: backup.rockxyPort,
            backedUpServices: backup.services.map(\.service)
        )
    }

    /// Reads only the fields ownership depends on for one service.
    private func currentOverrideState(for service: String) -> ProxyServiceOverrideState {
        let snapshot = captureProxySnapshot(for: service)
        let bypassOutput = (try? runNetworkSetup(["-getproxybypassdomains", service])) ?? ""
        let hasGlobalBypass = bypassOutput.components(separatedBy: "\n").contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "*"
        }
        return ProxyServiceOverrideState(
            service: service,
            httpEnabled: snapshot.httpEnabled,
            httpHost: snapshot.httpHost,
            httpPort: snapshot.httpPort,
            httpsEnabled: snapshot.httpsEnabled,
            httpsHost: snapshot.httpsHost,
            httpsPort: snapshot.httpsPort,
            socksEnabled: snapshot.socksEnabled,
            pacEnabled: snapshot.pacEnabled,
            autoDiscoveryEnabled: snapshot.autoDiscoveryEnabled,
            hasGlobalBypass: hasGlobalBypass
        )
    }

    /// Narrows the on-disk backup to the services recovery still owns, then restores exactly
    /// those. Persisting the reduced backup first is what keeps a later retry from replaying
    /// stale settings onto a service the user has changed in the meantime; if that write fails,
    /// the original backup stays put and no setting is touched.
    @discardableResult
    private func recoverOwnedDirectServices(backup: DirectProxyBackup, ownedServices: [String]) -> Bool {
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
        guard !ownedBackup.services.isEmpty else {
            clearDirectBackup()
            return true
        }

        do {
            try writeDirectBackup(ownedBackup)
        } catch {
            Self.logger
                .error(
                    "Could not narrow the direct backup — leaving settings untouched: \(error.localizedDescription)"
                )
            return false
        }

        return restoreDirectMode(using: ownedBackup)
    }

    /// Keeps only the services a restore attempt left unresolved, so the retry cannot write the
    /// captured settings back onto a service that already restored.
    private func retainUnresolvedDirectBackup(
        backup: DirectProxyBackup,
        failedServices: Set<String>,
        stillOwnedServices: Set<String>
    ) {
        let unresolvedEntries = ProxyBackupSubset.unresolvedEntries(
            backup.services,
            failedServices: failedServices,
            stillOwnedServices: stillOwnedServices,
            serviceName: \.service
        )
        guard !unresolvedEntries.isEmpty, unresolvedEntries.count < backup.services.count else {
            return
        }

        do {
            try writeDirectBackup(DirectProxyBackup(
                services: unresolvedEntries,
                timestamp: backup.timestamp,
                rockxyPort: backup.rockxyPort,
                recoveryPending: true
            ))
        } catch {
            Self.logger
                .error("Could not narrow the retained direct backup: \(error.localizedDescription)")
        }
    }

    /// Polls the backed-up services after a restore attempt and reports whichever ones are still
    /// Rockxy-owned. macOS applies `networksetup` writes asynchronously, so a single read right
    /// after the commands can still show the old override.
    private func residualOwnedServicesAfterRestore(
        port: Int,
        backedUpServices: [String],
        maxAttempts: Int = 5,
        pollInterval: TimeInterval = 0.2
    )
        -> [String]
    {
        guard !backedUpServices.isEmpty else {
            return []
        }

        var stillOwnedServices: [String] = []
        for attempt in 0 ..< maxAttempts {
            stillOwnedServices = residualRockxyOwnedServices(port: port, backedUpServices: backedUpServices)
            if stillOwnedServices.isEmpty {
                return []
            }

            if attempt < maxAttempts - 1 {
                Thread.sleep(forTimeInterval: pollInterval)
            }
        }

        return stillOwnedServices
    }
}

// MARK: - SystemProxyConfigurationMonitor

/// Observes the effective proxy dictionary maintained by SystemConfiguration.
///
/// Rockxy's own notifications only describe mutations initiated by Rockxy. This observer
/// closes the external-change gap without polling or taking ownership back from another app.
private final class SystemProxyConfigurationMonitor: @unchecked Sendable {
    deinit {
        lock.lock()
        if let store {
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        store = nil
        lock.unlock()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        guard store == nil else {
            return
        }

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let newStore = SCDynamicStoreCreate(
            nil,
            "Rockxy.SystemProxyConfigurationMonitor" as CFString,
            systemProxyConfigurationCallback,
            &context
        ) else {
            Self.logger.error("Could not create the macOS proxy configuration observer")
            return
        }

        let proxyKey = SCDynamicStoreKeyCreateProxies(nil)
        guard SCDynamicStoreSetNotificationKeys(newStore, [proxyKey] as CFArray, nil),
              SCDynamicStoreSetDispatchQueue(newStore, queue)
        else {
            Self.logger.error("Could not subscribe to macOS proxy configuration changes")
            return
        }

        store = newStore
        Self.logger.info("Observing macOS proxy configuration changes")
    }

    fileprivate func configurationDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .systemProxyConfigurationDidChange, object: nil)
        }
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "SystemProxyConfigurationMonitor"
    )

    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "\(RockxyIdentity.current.appBundleIdentifier).system-proxy-monitor",
        qos: .utility
    )
    private var store: SCDynamicStore?
}

private func systemProxyConfigurationCallback(
    _: SCDynamicStore,
    _: CFArray,
    info: UnsafeMutableRawPointer?
) {
    guard let info else {
        return
    }
    let monitor = Unmanaged<SystemProxyConfigurationMonitor>.fromOpaque(info).takeUnretainedValue()
    monitor.configurationDidChange()
}
