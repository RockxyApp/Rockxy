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
    case proxySessionInUse
    case proxyStateChangedDuringCommit(service: String)
    case previousHelperUnavailable
    case unexpectedOutput(String)
    /// The direct-mode watchdog could not be armed for this process, so no override was left in
    /// place without something to restore it.
    case directProxyWatchdogUnavailable(reason: String)
    /// An override attempt failed and could not put every service it had already changed back on
    /// its captured settings. The restore point survives, and the failure says so.
    case overrideRollbackIncomplete(reason: String)

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
        case .proxySessionInUse:
            "Another running Rockxy instance owns the current system proxy session"
        case let .proxyStateChangedDuringCommit(service):
            "The proxy settings for \(service) changed before Rockxy could apply its recorded update"
        case .previousHelperUnavailable:
            "Rockxy cannot safely reclaim system routing with the installed helper. Quit and reopen Rockxy, then update or repair the helper in Advanced Proxy Settings."
        case let .unexpectedOutput(output):
            "Unexpected networksetup output: \(output)"
        case let .directProxyWatchdogUnavailable(reason):
            "Rockxy could not arm the watchdog that restores your proxy settings, so the system proxy was left unchanged: \(reason)"
        case let .overrideRollbackIncomplete(reason):
            "Rockxy could not set the system proxy and could not fully undo the services it had already changed (\(reason)). Your previous settings were kept so they can still be restored."
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

// MARK: - ProxyOverrideOwner

/// Describes who currently owns the system proxy override.
enum ProxyOverrideOwner {
    case none
    case direct(backup: DirectProxyBackup)
    case helper(port: Int)
}

// MARK: - DirectOverrideEnableOutcome

/// How a direct-mode enable attempt ended once every service it touched has been answered.
enum DirectOverrideEnableOutcome: Equatable {
    /// The override is applied and a watchdog armed before the first change is watching the
    /// process that took it.
    case enabled
    /// The attempt failed and every service it mutated is back on its captured settings.
    case rolledBack
    /// The attempt failed and at least one mutated service is still overridden, so the backup
    /// survives and the failure is reported rather than swallowed.
    case rollbackIncomplete
}

// MARK: - DirectOverrideApplicationStep

/// The three things applying a direct override does, in the only order that leaves nothing
/// stranded.
enum DirectOverrideApplicationStep: String, Equatable {
    /// The restore point is published first, so the watchdog has something to observe from the
    /// moment it starts.
    case persistBackup
    /// The watchdog is armed second — before any setting can change, never after.
    case armWatchdog
    /// The proxy commands run last.
    case mutateServices
}

// MARK: - DirectOverrideApplication

/// Runs the steps of a direct override in order, and reports the one that stopped it.
///
/// The order is the whole guarantee. A failure at `persistBackup` or `armWatchdog` has not
/// touched a single setting, so there is nothing to roll back; any failure from `mutateServices`
/// on has, and the watchdog that puts it back is already running by then. Arming the watchdog
/// after the commands would leave a window in which the process can die with the override applied
/// and nothing watching it — recoverable only at the next launch, if there is one.
enum DirectOverrideApplication {
    static func run(
        persistBackup: () throws -> Void,
        armWatchdog: () throws -> Void,
        mutateServices: () throws -> Void
    )
        -> (step: DirectOverrideApplicationStep, error: any Error)?
    {
        do {
            try persistBackup()
        } catch {
            return (.persistBackup, error)
        }

        do {
            try armWatchdog()
        } catch {
            return (.armWatchdog, error)
        }

        do {
            try mutateServices()
        } catch {
            return (.mutateServices, error)
        }

        return nil
    }
}

enum SystemProxyReclaimMode: Equatable {
    case none
    case direct
    case helper
}

private enum DirectStaleRecoveryOutcome {
    case noBackup
    case preserved
    case cleared
    case restored
    case restoreIncomplete
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

    /// Whether a direct override may be applied at all: the watcher that restores it has to be
    /// resolvable first.
    ///
    /// Both halves are required before anything is mutated. An override applied without a live
    /// watchdog is only recovered at the next launch, and one armed against a bare identifier
    /// watches whatever process later inherits it — which is the same as not watching at all.
    nonisolated static func directWatchdogPreflightIsSatisfied(
        executableIsAvailable: Bool,
        parentStartSignature: String?
    )
        -> Bool
    {
        guard executableIsAvailable, let parentStartSignature, !parentStartSignature.isEmpty else {
            return false
        }
        return true
    }

    /// What an enable attempt reports once every service it touched has been answered.
    ///
    /// The watchdog is armed before the first proxy command, so by the time this is asked the
    /// only open question is whether the services this attempt changed are back where they
    /// started. A rollback that did not finish is never reported as a plain failure: the backup
    /// is still on disk precisely because those services still need it.
    nonisolated static func directOverrideAttemptOutcome(
        applySucceeded: Bool,
        rollbackSucceeded: Bool
    )
        -> DirectOverrideEnableOutcome
    {
        if applySucceeded {
            return .enabled
        }
        return rollbackSucceeded ? .rolledBack : .rollbackIncomplete
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

    /// The `launchctl submit` invocation for the direct-mode watchdog.
    ///
    /// The arguments the watchdog itself reads come from `DirectProxyWatchdogInvocation`, which
    /// is also what the helper binary parses them back with. Only the `launchctl` wrapper is
    /// built here: a flag or a field position spelled out twice is one that can disagree, and the
    /// disagreement would be a watcher silently watching the wrong process.
    ///
    /// The parent's kernel start signature travels with its identifier so the watcher can tell
    /// the process that took the override from whatever later inherits its identifier.
    nonisolated static func directWatchdogSubmitArguments(
        label: String,
        executablePath: String,
        parentPID: pid_t,
        parentStartSignature: String,
        backupPath: String
    )
        -> [String]
    {
        ["submit", "-l", label, "--"] + DirectProxyWatchdogInvocation.watchArguments(
            executablePath: executablePath,
            parentPID: parentPID,
            backupPath: backupPath,
            parentStartSignature: parentStartSignature
        )
    }

    // MARK: - Public API

    func enableSystemProxy(port: Int) async throws {
        try await Self.lifecycleGate.withOperation { [self] in
            try await enableSystemProxyLocked(port: port)
        }
    }

    private func enableSystemProxyLocked(port: Int) async throws {
        Self.logger.info("enableSystemProxy called for port \(port)")

        let backupAtStart = loadDirectBackup()
        if directBackupFileExists, backupAtStart == nil {
            throw SystemProxyError.proxyRestoreFailed
        }
        if let backupAtStart, !directBackupBelongsToCurrentProcess(backupAtStart) {
            switch recoverStaleDirectProxyIfNeeded() {
            case .noBackup, .cleared, .restored:
                break
            case .preserved:
                throw SystemProxyError.proxySessionInUse
            case .restoreIncomplete:
                lock.withLock { directRestorePending = true }
                throw SystemProxyError.proxyRestoreFailed
            }
        }

        lock.lock()
        let directRestoreWasPending = directRestorePending
            || loadDirectBackup().map(directBackupBelongsToCurrentProcess) == true
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
            let info: HelperInfo
            do {
                info = try await HelperConnection.shared.getHelperInfo()
            } catch {
                // An installed helper may already own another app instance's live session. A
                // failed probe is therefore not permission to create an unrelated direct backup
                // from that helper's loopback override.
                Self.logger.error("Installed helper could not be verified; refusing direct fallback")
                throw SystemProxyError.previousHelperUnavailable
            }
            guard HelperCompatibilityPolicy.supportsSafeProxyRouting(protocolVersion: info.protocolVersion) else {
                throw SystemProxyError.previousHelperUnavailable
            }
            Self.logger.info("Enabling system proxy via helper tool on port \(port)")
            try await HelperConnection.shared.overrideSystemProxy(port: port)

            lock.lock()
            isEnabled = true
            usingHelper = true
            lock.unlock()
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
        try await Self.lifecycleGate.withOperation { [self] in
            try await disableSystemProxyLocked()
        }
    }

    private func disableSystemProxyLocked() async throws {
        // Same-session shortcut: if we know we own a direct override, skip ownership detection
        lock.lock()
        let pending = directRestorePending
        let helperSession = usingHelper
        lock.unlock()

        if pending {
            // Serialized against an enable loop and against termination cleanup: the three of
            // them write the same services and the same backup file from different threads.
            guard try Self.operationGate.withOperation({
                try DirectProxySessionLock.withExclusiveAccess(backupURL: Self.directBackupURL) {
                    invalidateQueuedDirectProxyWork()
                    guard let currentBackup = loadDirectBackup() else {
                        return !directBackupFileExists
                    }
                    if directBackupOwnerIsLive(currentBackup),
                       !directBackupBelongsToCurrentProcess(currentBackup)
                    {
                        throw SystemProxyError.proxySessionInUse
                    }
                    Self.logger.info("Direct restore pending — restoring \(currentBackup.services.count) service(s)")
                    return restoreDirectMode(using: currentBackup)
                }
            }) else {
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

            case .direct:
                guard try Self.operationGate.withOperation({
                    try DirectProxySessionLock.withExclusiveAccess(backupURL: Self.directBackupURL) {
                        invalidateQueuedDirectProxyWork()
                        guard let currentBackup = loadDirectBackup() else {
                            return !directBackupFileExists
                        }
                        if directBackupOwnerIsLive(currentBackup),
                           !directBackupBelongsToCurrentProcess(currentBackup)
                        {
                            throw SystemProxyError.proxySessionInUse
                        }
                        Self.logger
                            .info(
                                "Disabling direct-mode system proxy, restoring \(currentBackup.services.count) service(s)"
                            )
                        return restoreDirectMode(using: currentBackup)
                    }
                }) else {
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
        sessionGeneration &+= 1
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
        lock.lock()
        let queuedGeneration = sessionGeneration
        let queuedForHelper = usingHelper
        let overrideWasActive = isEnabled
        lock.unlock()

        guard overrideWasActive else {
            return
        }

        let domains = await BypassProxyManager.shared.enabledDomainStringsForSystemProxy()

        // Domain calculation may suspend. Re-check the exact session before dispatch so work that
        // began before a disable cannot become a mutation request after the restore completed.
        lock.lock()
        let sessionIsCurrent = ProxyOperationSessionPolicy.mayRun(
            queuedGeneration: queuedGeneration,
            currentGeneration: sessionGeneration,
            overrideIsActive: isEnabled
        ) && usingHelper == queuedForHelper
        lock.unlock()

        guard sessionIsCurrent else {
            Self.logger.info("Skipping a bypass write queued for a proxy session that has already ended")
            return
        }

        if queuedForHelper {
            try await HelperConnection.shared.setBypassDomains(domains)
            Self.logger.info("Applied \(domains.count) bypass domain(s) via helper")
        } else {
            try applyBypassDomainsViaNetworkSetup(domains, queuedGeneration: queuedGeneration)
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
            Self.logger.warning("Direct backup is temporarily unreadable, preserving it: \(error.localizedDescription)")
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

        if let backup = loadDirectBackup(), directBackupBelongsToCurrentProcess(backup) {
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
        sessionGeneration &+= 1
        lock.unlock()
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

    /// Best-effort cleanup used during late termination fallback and signal handling.
    ///
    /// It runs as one operation, and it waits for any enable or disable already in progress. That
    /// wait is the point: restoring every service and clearing the backup while an enable loop
    /// still has proxy commands left to write would put the settings back, delete the restore
    /// point, and then let the loop re-apply the override with nothing on disk to undo it.
    func performEmergencyTerminationCleanup(reason: String) {
        Self.operationGate.withOperation {
            performEmergencyTerminationCleanupLocked(reason: reason)
        }
    }

    /// The cleanup itself. Only ever reached with the operation gate held.
    private func performEmergencyTerminationCleanupLocked(reason: String) {
        stopBypassListObserver()
        // Anything queued for the session being torn down stops here. It is bumped inside the gate
        // this cleanup holds, so a bypass write already waiting on that gate reads the new value
        // and issues nothing.
        lock.lock()
        isEnabled = false
        sessionGeneration &+= 1
        lock.unlock()

        do {
            let handledDirectSession = try DirectProxySessionLock.withExclusiveAccess(
                backupURL: Self.directBackupURL
            ) {
                guard let backup = loadDirectBackup() else {
                    return false
                }
                if directBackupOwnerIsLive(backup), !directBackupBelongsToCurrentProcess(backup) {
                    Self.logger.info("\(reason): preserving the direct proxy session owned by another live app process")
                    return true
                }
                let residualOwnedServices = recoverableDirectServices(in: backup)
                if !residualOwnedServices.isEmpty {
                    Self.logger
                        .warning(
                            "\(reason): restoring \(residualOwnedServices.count) owned direct-mode service(s) during shutdown"
                        )
                    if !recoverOwnedDirectServices(backup: backup, ownedServices: residualOwnedServices) {
                        Self.logger.warning("\(reason): direct restore incomplete, leaving the narrowed backup for retry")
                    }
                    return true
                }

                Self.logger.info("\(reason): clearing stale direct backup because no service is still Rockxy-owned")
                clearDirectBackup()
                return true
            }
            if handledDirectSession {
                return
            }
        } catch {
            Self.logger.error("\(reason): could not acquire direct proxy session lock: \(error.localizedDescription)")
            return
        }

        if helperEmergencyRestoreNeeded() {
            Self.logger.warning("\(reason): requesting helper-owned proxy restore during shutdown")
            if HelperConnection.performEmergencyProxyRestore() {
                return
            }

            Self.logger.error("\(reason): helper emergency restore did not complete")
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

    /// Serializes enable, disable, and termination cleanup against each other. It is static
    /// because the signal handler and the capture task both reach the same shared manager, and
    /// the thing being protected is the one machine's proxy settings.
    private static let operationGate = ProxyOperationGate()
    /// Keeps helper-backed and startup lifecycle operations ordered across their suspension
    /// points. The blocking gate above still guards synchronous direct-mode mutations and signal
    /// cleanup, while this one prevents an older async continuation from ending a newer session.
    private static let lifecycleGate = ProxyAsyncOperationGate()

    private let lock = NSLock()
    private var isEnabled = false
    private var usingHelper = false
    private var activeServices: [String] = []
    private var directRestorePending = false
    /// Which override session the manager is on. Bumped by everything that ends one, and read
    /// inside the operation gate, so work queued for a session that has since ended never runs.
    private var sessionGeneration: UInt64 = 0
    private var originalBypassDomains: [String: [String]] = [:]
    private var originalProxyState: [String: ServiceProxySnapshot] = [:]
    private var bypassObserver: NSObjectProtocol?
    /// The watchdog job currently guarding this session's override, if one was installed. Held so
    /// the next arming knows which job it supersedes and the disable path removes the right one.
    private var activeDirectWatchdogLabel: String?

    /// A label no `launchctl` job is using yet, so a watcher can be submitted before the one it
    /// replaces is removed.
    private static func uniqueDirectWatchdogLabel() -> String {
        "\(directWatchdogLabel).\(UUID().uuidString)"
    }

    // MARK: - NetworkSetup — Enable on ALL Enabled Services

    private func enableSystemProxyViaNetworkSetup(port: Int) throws {
        // The whole enable runs as one operation. A termination cleanup arriving on the signal
        // thread has to wait for it: restoring and clearing the backup while this loop still has
        // proxy commands to write would leave the user overridden with no restore point at all.
        try Self.operationGate.withOperation {
            try applyDirectOverride(port: port)
        }
    }

    private func applyDirectOverride(port: Int) throws {
        try DirectProxySessionLock.withExclusiveAccess(backupURL: Self.directBackupURL) {
            try applyDirectOverrideLocked(port: port)
        }
    }

    /// The complete ownership claim and mutation sequence, held under the cross-process lock.
    private func applyDirectOverrideLocked(port: Int) throws {
        // Never use another loopback proxy as the restoration baseline. This also closes the
        // cross-mode race where a helper-backed session becomes visible while direct fallback is
        // being considered but before a direct restore point is published.
        if loadDirectBackup() == nil, anyLoopbackProxyEnabled(on: nil) {
            throw SystemProxyError.proxySessionInUse
        }

        let services = try detectAllEnabledServices()
        guard !services.isEmpty else {
            throw SystemProxyError.noActiveNetworkService
        }

        // The watchdog is the only thing that puts these settings back when this process dies, so
        // it is armed before a single service is mutated. An override applied first and watched
        // afterwards is an override that can outlive the app with nothing watching it at all —
        // and a death anywhere in the mutation loop would be exactly that.
        let arming = try directWatchdogArming()
        let existingBackup = loadDirectBackup()
        let hadBackupBefore = existingBackup != nil
        // The services that already had a restore point. Only their entries may outlive a failed
        // attempt: an entry this attempt captures for a service it never touches describes
        // settings nobody overrode, and keeping it is how a later enable comes to replay a stale
        // snapshot over a newer user setting.
        let preAttemptServices = Set(existingBackup?.services.map(\.service) ?? [])

        Self.logger.info("Setting proxy on all \(services.count) enabled services")

        var touchedServices: [String] = []
        var configuredServices: [String] = []
        var skippedServices: [String] = []

        // The restore point is published first so the watchdog has something to observe from the
        // moment it starts: it sees the backup, waits while this process's identity is live, and
        // exits once a successful rollback or restore clears it. Only then does the first proxy
        // command run.
        let failure = DirectOverrideApplication.run(
            persistBackup: {
                try prepareDirectBackup(
                    port: port,
                    services: services,
                    ownerPID: arming.parentPID,
                    ownerStartSignature: arming.parentStartSignature
                )
            },
            armWatchdog: { try armDirectProxyWatchdog(arming, hadBackupBefore: hadBackupBefore) },
            mutateServices: {
                for service in services {
                    // The capture this backup holds was taken earlier — moments ago for a service
                    // just added, a whole session ago for one being reclaimed. What the override
                    // is about to start from is a fact about the machine now, so the settings are
                    // re-read in full and compared against what this process can actually prove
                    // about them. A service that answers neither leaves without a command.
                    guard let baseline = directOverrideBaseline(for: service, port: port) else {
                        skippedServices.append(service)
                        continue
                    }
                    // The record comes before the first command, and it is what makes a crash in
                    // the middle of the seven recoverable at all: a service stopped half-way is
                    // neither Rockxy's nor the user's, so nothing but this record can tell a
                    // later relaunch that these settings are Rockxy's own work to undo.
                    try advanceDirectApplicationJournal(
                        service: service,
                        baseline: baseline,
                        to: .applying,
                        port: port
                    )
                    guard restorationState(for: service) == baseline else {
                        throw SystemProxyError.proxyStateChangedDuringCommit(service: service)
                    }
                    touchedServices.append(service)
                    try runNetworkSetup(["-setwebproxy", service, "127.0.0.1", String(port)])
                    try runNetworkSetup(["-setwebproxystate", service, "on"])
                    try runNetworkSetup(["-setsecurewebproxy", service, "127.0.0.1", String(port)])
                    try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
                    try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
                    try runNetworkSetup(["-setautoproxystate", service, "off"])
                    try runNetworkSetup(["-setproxyautodiscovery", service, "off"])
                    configuredServices.append(service)
                    Self.logger.info("System proxy set on '\(service)' -> 127.0.0.1:\(port)")
                }
            }
        )

        if let failure {
            switch failure.step {
            case .persistBackup, .armWatchdog:
                // Not one setting was touched, so there is nothing to undo.
                throw failure.error
            case .mutateServices:
                Self.logger.error("Proxy setup failed after \(configuredServices.count) service(s), rolling back")
                // The rollback's answer decides what this attempt may claim. A service it could
                // not put back still carries proxy state Rockxy wrote, and reporting only the
                // original failure would leave that state on the machine with nothing said
                // about it.
                let rollbackSucceeded = rollBackDirectOverride(
                    touchedServices: touchedServices,
                    preAttemptServices: preAttemptServices
                )
                clearInMemoryOverrideState()
                lock.lock()
                directRestorePending = !rollbackSucceeded
                lock.unlock()

                switch Self.directOverrideAttemptOutcome(
                    applySucceeded: false,
                    rollbackSucceeded: rollbackSucceeded
                ) {
                case .enabled, .rolledBack:
                    throw failure.error
                case .rollbackIncomplete:
                    throw SystemProxyError.overrideRollbackIncomplete(
                        reason: failure.error.localizedDescription
                    )
                }
            }
        }

        guard !configuredServices.isEmpty else {
            // Not one service could be configured, and none was touched. Whatever this attempt
            // captured for itself must not outlive it, but an entry that predates it is still the
            // only restore point its own service has — and clearing the file outright is how a
            // service still carrying an earlier session's override loses it.
            _ = rollBackDirectOverride(
                touchedServices: touchedServices,
                preAttemptServices: preAttemptServices
            )
            clearInMemoryOverrideState()
            throw SystemProxyError.noActiveNetworkService
        }

        // An entry this attempt captured for a service it then skipped describes settings nobody
        // overrode. Keeping it would hand the next enable a snapshot older than whatever the user
        // has set in the meantime, and the enable after that would write it back over their change.
        dropUntouchedCapturedEntries(skippedServices.filter { !preAttemptServices.contains($0) })

        lock.lock()
        isEnabled = true
        usingHelper = false
        activeServices = configuredServices
        directRestorePending = true
        lock.unlock()
    }

    /// Removes the entries this attempt captured for services it never issued a command against.
    ///
    /// Only those: an entry that was already on disk belongs to a service some earlier session may
    /// still be overriding, and this attempt never touched it either way. A failed write simply
    /// leaves the backup as it is, which is the safe direction — a spare restore point costs a
    /// deferred service, a missing one costs the settings.
    private func dropUntouchedCapturedEntries(_ services: [String]) {
        guard !services.isEmpty, let backup = loadDirectBackup() else {
            return
        }
        let dropped = Set(services)
        let retained = backup.services.map(\.service).filter { !dropped.contains($0) }
        guard retained.count != backup.services.count else {
            return
        }
        do {
            try writeDirectBackup(backup.with(
                services: ProxyBackupSubset.select(
                    backup.services,
                    services: Set(retained),
                    serviceName: \.service
                ),
                journal: ProxyBackupSubset.select(
                    backup.journal,
                    services: Set(retained),
                    serviceName: \.service
                )
            ))
        } catch {
            Self.logger
                .error(
                    "Could not drop the freshly captured entries for skipped services: \(error.localizedDescription)"
                )
        }
    }

    /// The state this service's override sequence may start from, or nil when it may not start at
    /// all.
    ///
    /// A service that still reads exactly as captured is a fresh one and answers with the capture.
    /// A service that has moved on answers only when the record of this machine's own earlier
    /// override still explains what is live — which is what a reclaim is. Anything else is the
    /// user's configuration or another tool's, and it is left with no command issued against it.
    private func directOverrideBaseline(for service: String, port: Int) -> ProxyServiceRestorationState? {
        guard let backup = loadDirectBackup(),
              let entry = backup.services.first(where: { $0.service == service })
        else {
            Self.logger.warning("Skipping proxy for '\(service)' — it has no captured restore point")
            return nil
        }

        guard case let .apply(baseline) = ProxyOverrideApplicationPreflight.decision(
            captured: entry.restorationTarget,
            live: restorationState(for: service),
            priorEntry: backup.journal.first { $0.service == service },
            port: port
        ) else {
            Self.logger
                .warning(
                    "Skipping proxy for '\(service)' — its live settings are neither the ones captured for it nor any this process wrote"
                )
            return nil
        }
        return baseline
    }

    /// Moves one service's override record on, and refuses to go further if it cannot be stored.
    ///
    /// The write is the permission to issue the command. A command nothing on disk accounts for
    /// is exactly the shape recovery has no way to reason about, so the sequence stops here
    /// rather than mutating a service it could not record.
    ///
    /// Only this service's record changes. Every other one is left exactly where it is: the backup
    /// can already be mid-recovery from an earlier session, or already carry an override this
    /// attempt is reclaiming, and those records are the only thing that says which live states may
    /// still be written.
    private func advanceDirectApplicationJournal(
        service: String,
        baseline: ProxyServiceRestorationState,
        to stage: ProxyRecoveryStage,
        port: Int
    ) throws {
        guard let backup = loadDirectBackup(),
              let entry = backup.services.first(where: { $0.service == service })
        else {
            throw SystemProxyError.proxyRestoreFailed
        }
        var journal = backup.journal.filter { $0.service != service }
        journal.append(ProxyServiceRecoveryJournalEntry(
            overrideApplicationFor: entry.restorationTarget,
            baseline: baseline,
            stage: stage,
            port: port
        ))
        try writeDirectBackup(backup.with(journal: journal))
    }

    /// Submits the watchdog against the backup that was just published, before the first proxy
    /// command runs.
    ///
    /// The new watcher goes in under a label nothing is using yet, and the one it supersedes is
    /// only removed once the replacement is known installed. Removing first and submitting after
    /// is what could leave an override — this attempt's, or one already on the machine — with no
    /// watcher at all the moment the submit failed.
    ///
    /// A failure here costs nothing but the restore point this very attempt created: no setting
    /// has been touched, so there is nothing to undo, and whatever was watching before still is.
    /// An earlier session's backup is left exactly where it is — it belongs to an override this
    /// attempt did not apply.
    private func armDirectProxyWatchdog(
        _ arming: DirectWatchdogArming,
        hadBackupBefore: Bool
    ) throws {
        let newLabel = Self.uniqueDirectWatchdogLabel()
        lock.lock()
        let supersededLabel = activeDirectWatchdogLabel
        lock.unlock()

        let outcome = DirectProxyWatchdogInstallation.install(
            newLabel: newLabel,
            supersededLabel: supersededLabel,
            submit: { label in
                try Self.submitDirectProxyWatchdog(
                    label: label,
                    executableURL: arming.executableURL,
                    parentPID: arming.parentPID,
                    parentStartSignature: arming.parentStartSignature,
                    backupPath: Self.directBackupURL.path
                )
            },
            remove: { label in
                try Self.removeDirectProxyWatchdog(label: label, tolerateMissing: true)
            }
        )

        switch outcome {
        case let .installed(activeLabel, supersededLabel):
            lock.lock()
            activeDirectWatchdogLabel = activeLabel
            lock.unlock()
            Self.logger
                .info(
                    "Registered direct proxy watchdog '\(activeLabel)' for pid \(arming.parentPID) before the first proxy change, superseding '\(supersededLabel ?? "none")'"
                )
            // A build before the label became unique left one job behind under the fixed name. It
            // is only asked to go once a replacement is already watching.
            if supersededLabel == nil {
                try? Self.removeDirectProxyWatchdog(label: Self.directWatchdogLabel, tolerateMissing: true)
            }
        case let .failed(activeLabel, error):
            Self.logger
                .error(
                    "Failed to start direct proxy watchdog: \(error.localizedDescription) — '\(activeLabel ?? "no")' watcher left in place"
                )
            if !hadBackupBefore {
                clearDirectBackup()
            }
            throw SystemProxyError.directProxyWatchdogUnavailable(
                reason: "the watchdog could not be registered, so no proxy setting was changed"
            )
        }
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
    private func prepareDirectBackup(
        port: Int,
        services: [String],
        ownerPID: Int32,
        ownerStartSignature: String
    ) throws {
        let existingBackup = loadDirectBackup()
        guard existingBackup != nil || !directBackupFileExists else {
            throw SystemProxyError.proxyRestoreFailed
        }
        if let existingBackup,
           !DirectProxyBackupOwnerPolicy.belongsToSession(
               existingBackup,
               processIdentifier: ownerPID,
               processStartSignature: ownerStartSignature
           )
        {
            throw SystemProxyError.proxySessionInUse
        }
        let existingServices = Set(existingBackup?.services.map(\.service) ?? [])
        let missingServices = services.filter { !existingServices.contains($0) }
        let additions = try missingServices.map(captureDirectServiceBackup)
        // Whatever the previous attempt recorded travels with the extended backup.
        let backup = DirectProxyBackup.extending(
            existingBackup,
            with: additions,
            rockxyPort: port,
            now: Date(),
            ownerPID: ownerPID,
            ownerStartSignature: ownerStartSignature
        )

        if additions.isEmpty, existingBackup?.rockxyPort == port {
            Self.logger.info("Preserving direct backup for \(existingServices.count) service(s)")
            return
        }

        try writeDirectBackup(backup)
    }

    /// Publishes the direct backup, permissions and all, in a single act.
    ///
    /// Everything that can fail happens before the new contents become visible, so a throw from
    /// here always means the file on disk is still the previous record — which is what the
    /// callers that treat a successful write as their permission to issue a command depend on.
    private func writeDirectBackup(_ backup: DirectProxyBackup) throws {
        let url = Self.directBackupURL
        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: ProxyBackupFilePublication.ownerOnlyDirectoryPermissions],
            ofItemAtPath: parentDir.path
        )
        try ProxyBackupFilePublication.publish(PropertyListEncoder().encode(backup), to: url)
        Self.logger.info("Persisted direct backup for \(backup.services.count) service(s) at port \(backup.rockxyPort)")
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

// MARK: - Direct Backup Capture

extension SystemProxyManager {
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
}

// MARK: - Direct Bypass Writes

/// Rockxy's own bypass list, written onto the services a direct-mode session overrode.
///
/// It lives apart from the enable and restore flow because it is a different act with the same
/// hazards: it is part of the effective routing, it runs long after the enable that authorized it,
/// and it can be queued behind a disable that has already put everything back.
extension SystemProxyManager {
    private func rollbackUnconfirmedOverride() async {
        lock.lock()
        let helper = usingHelper
        let mutatedServices = Set(activeServices)
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

        // This session wrote those services itself, so undoing its own unconfirmed work does not
        // depend on the live settings still proving ownership — which they may no longer do if
        // the very change that broke confirmation is what is sitting on them.
        // Serialized with everything else that writes these services and this file. The gate is
        // reentrant, so an enable already holding it can still roll itself back without waiting on
        // itself, while a rollback reached from the confirmation check — where the enable has long
        // since let go — takes it for real.
        _ = Self.operationGate.withOperation {
            invalidateQueuedDirectProxyWork()
            if let currentBackup = loadDirectBackup() {
                restoreDirectMode(using: currentBackup, locallyMutatedServices: mutatedServices)
            }
        }
    }

    /// Ends the direct session from the perspective of work waiting on the operation gate.
    ///
    /// This must run while the gate is held and before restoration starts. A bypass write queued
    /// behind that restore then observes both a new generation and an inactive override when it
    /// acquires the gate, so it cannot write after the backup has been consumed.
    private func invalidateQueuedDirectProxyWork() {
        lock.lock()
        isEnabled = false
        sessionGeneration &+= 1
        lock.unlock()
    }

    /// Writes Rockxy's bounded bypass list onto the services this session overrode.
    ///
    /// It runs as one operation for the same reason the enable loop does: the bypass list is part
    /// of the effective routing, and a disable or a termination cleanup writing the captured
    /// settings back at the same time would interleave with it. The gate alone is not enough
    /// though — it only orders the two, and losing the race means this write lands *after* the
    /// cleanup restored every service and deleted the restore point, leaving Rockxy's bypass list
    /// on the user's machine with nothing left to undo it. So the session is re-checked inside the
    /// gate, where nothing can end it between the check and the commands.
    private func applyBypassDomainsViaNetworkSetup(_ domains: [String], queuedGeneration: UInt64) throws {
        try Self.operationGate.withOperation {
            lock.lock()
            let services = activeServices
            let generation = sessionGeneration
            let overrideIsActive = isEnabled
            lock.unlock()

            guard ProxyOperationSessionPolicy.mayRun(
                queuedGeneration: queuedGeneration,
                currentGeneration: generation,
                overrideIsActive: overrideIsActive
            ) else {
                Self.logger
                    .info("Skipping a bypass write queued for a proxy session that has already ended")
                return
            }

            guard !services.isEmpty, var backup = loadDirectBackup() else {
                throw SystemProxyError.proxyRestoreFailed
            }

            for service in services {
                guard let entry = backup.journal.first(where: { $0.service == service }) else {
                    throw SystemProxyError.proxyRestoreFailed
                }

                let live = restorationState(for: service)
                switch ProxyBypassUpdatePreflight.decision(
                    entry: entry,
                    live: live,
                    ownedPort: backup.rockxyPort,
                    requestedDomains: domains
                ) {
                case .abort:
                    throw SystemProxyError.proxyStateChangedDuringCommit(service: service)
                case .unchanged:
                    if entry.previousAppliedBypassDomains != nil {
                        let stable = entry.completingAppliedBypassUpdate(at: domains)
                        backup = backup.with(journal: replacingDirectJournal(backup.journal, entry: stable))
                        try writeDirectBackup(backup)
                    }
                case let .apply(baseline):
                    let pending = entry.recordingAppliedBypassDomains(
                        domains,
                        from: baseline.bypassDomains
                    )
                    backup = backup.with(journal: replacingDirectJournal(backup.journal, entry: pending))
                    try writeDirectBackup(backup)

                    // The record publication can take long enough for another actor to change the
                    // service. Re-read every field before the command and refuse that foreign state.
                    guard restorationState(for: service) == baseline else {
                        throw SystemProxyError.proxyStateChangedDuringCommit(service: service)
                    }

                    if domains.isEmpty {
                        try runNetworkSetup(["-setproxybypassdomains", service, "Empty"])
                    } else {
                        try runNetworkSetup(["-setproxybypassdomains", service] + domains)
                    }

                    let stable = pending.completingAppliedBypassUpdate(at: domains)
                    backup = backup.with(journal: replacingDirectJournal(backup.journal, entry: stable))
                    try writeDirectBackup(backup)
                }
            }

            Self.logger.info("Applied \(domains.count) bypass domain(s) via networksetup")
        }
    }

    private func replacingDirectJournal(
        _ journal: [ProxyServiceRecoveryJournalEntry],
        entry: ProxyServiceRecoveryJournalEntry
    )
        -> [ProxyServiceRecoveryJournalEntry]
    {
        journal.filter { $0.service != entry.service } + [entry]
    }
}

// MARK: - Direct Watchdog Job Control

/// The `launchctl` plumbing behind the direct-mode watchdog. It sits apart from the enable and
/// restore flows because it answers a different question: not what the override is, but which job
/// is currently watching it.
extension SystemProxyManager {
    private static func submitDirectProxyWatchdog(
        label: String,
        executableURL: URL,
        parentPID: pid_t,
        parentStartSignature: String,
        backupPath: String
    )
        throws
    {
        _ = try runLaunchctl(directWatchdogSubmitArguments(
            label: label,
            executablePath: executableURL.path,
            parentPID: parentPID,
            parentStartSignature: parentStartSignature,
            backupPath: backupPath
        ))
    }

    private static func removeDirectProxyWatchdog(
        label: String,
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
}

// MARK: - Direct-Mode Recovery

/// Ownership and subset-restore behavior for direct-mode backups. Recovery asks a different
/// question from readiness — which backed-up services still need their restore point — so it
/// lives apart from the enable/disable flow it supports.
extension SystemProxyManager {
    /// Shared direct-mode restore routine used by both same-session cleanup and ownership-based
    /// cleanup.
    ///
    /// Every service is planned against the recovery journal first. The narrowed backup and an
    /// `inFlight` record for each service about to be written are persisted before the first
    /// command, and each service's record advances to `restored` as soon as its commands return.
    /// A process that dies anywhere in between leaves a record the next attempt can read: live
    /// settings this restore could have produced are written again, and settings it could not are
    /// left to whoever made them.
    ///
    /// `preAttemptServices` names the services the backup already held before the caller captured
    /// anything. Only those preserved entries may outlive this attempt: an entry the same attempt
    /// captured for a service it then never touched describes settings nobody overrode, and
    /// keeping it would hand the next enable a snapshot to write back over a change made in the
    /// meantime.
    @discardableResult
    private func restoreDirectMode(
        using sourceBackup: DirectProxyBackup,
        authorizedServices: Set<String>? = nil,
        locallyMutatedServices: Set<String> = [],
        preAttemptServices: Set<String>? = nil
    )
        -> Bool
    {
        // A caller may authorize part of the backup — the services one failed attempt touched,
        // say. The rest is not merely left unwritten: its entries stay in the backup on disk for
        // the whole run, because a crash or a failed write during this restore must never be the
        // moment a service that was never touched loses the only restore point it has.
        let authorized = authorizedServices ?? Set(sourceBackup.services.map(\.service))
        let authorizedEntries = sourceBackup.services.filter { authorized.contains($0.service) }
        let preservedServices = sourceBackup.services
            .map(\.service)
            .filter { !authorized.contains($0) }

        // A service with no usable record enters recovery only when the live settings still prove
        // Rockxy owns it on the persisted port — or when they are exactly one of the states this
        // process's own override commands pass through. Anything else keeps its restore point
        // rather than being adopted as the state a restore begins from.
        let plan = ProxyRecoveryPlanner.plan(
            targets: authorizedEntries.map(\.restorationTarget),
            journal: sourceBackup.journal,
            liveStates: currentRestorationStates(for: authorizedEntries.map(\.service)),
            ownedPort: sourceBackup.rockxyPort,
            locallyMutatedServices: locallyMutatedServices
        )

        if !plan.abandonedServices.isEmpty {
            Self.logger
                .warning(
                    "Leaving \(plan.abandonedServices.count) service(s) out of direct recovery — their proxy settings were changed outside this restore"
                )
        }

        // Every planned service is recorded at the stage it was planned at. A service nothing has
        // been issued for stays `pending`, so a crash while an earlier service is being written
        // cannot make it look half-restored and hand a later attempt a licence to write over a
        // change made in the meantime.
        let plannedJournal = plan.entriesToRestore + ProxyBackupSubset.select(
            sourceBackup.journal,
            services: Set(plan.deferredServices + preservedServices),
            serviceName: \.service
        )
        let retention = ProxyBackupRetention(
            authorized: plan.servicesKeepingBackup,
            preserved: preservedServices,
            preAttemptServices: preAttemptServices
        )

        guard !plan.entriesToRestore.isEmpty else {
            // Nothing may be written this time. A service whose settings could not be read keeps
            // its restore point; everything else has already left recovery. The backup keeps the
            // flag it arrived with, because no write has begun.
            let proxyStillPointsAtRockxy = authorizedEntries.isEmpty
                ? anyLoopbackProxyEnabled(on: nil)
                : !plan.deferredServices.isEmpty
            return finishDirectRestore(
                backup: sourceBackup.with(
                    journal: plannedJournal,
                    recoveryPending: sourceBackup.recoveryPending
                ),
                unresolvedServices: plan.deferredServices,
                retention: retention,
                preservedRecoveryPending: sourceBackup.recoveryPending,
                journal: plannedJournal,
                commandsSucceeded: true,
                proxyStillPointsAtRockxy: proxyStillPointsAtRockxy
            )
        }

        let narrowedBackup = sourceBackup.with(
            services: ProxyBackupSubset.select(
                sourceBackup.services,
                services: Set(retention.services),
                serviceName: \.service
            ),
            journal: plannedJournal,
            recoveryPending: true
        )
        do {
            try writeDirectBackup(narrowedBackup)
        } catch {
            Self.logger.error("Could not mark direct recovery pending — leaving settings untouched: \(error.localizedDescription)")
            return false
        }

        // The loop below is the one the watchdog binary runs too. It is shared rather than
        // reimplemented because the state it leaves behind is only ever observed after a crash,
        // which is exactly where two copies would be found to have drifted.
        let outcome = DirectProxyRecoveryRunner.run(
            entriesToRestore: plan.entriesToRestore,
            backup: narrowedBackup,
            journal: plannedJournal,
            retention: retention,
            deferredServices: plan.deferredServices,
            effects: directRecoveryEffects()
        )

        // Any service still pointing at Rockxy keeps the backup alive, even when the others
        // restored cleanly — that service has no other restore point.
        let stillOwnedServices = outcome.allSucceeded
            ? residualOwnedServicesAfterRestore(
                port: outcome.backup.rockxyPort,
                backedUpServices: outcome.attemptedServices
            )
            : residualRockxyOwnedServices(
                port: outcome.backup.rockxyPort,
                backedUpServices: outcome.attemptedServices
            )

        let unresolvedServices = ProxyBackupSubset.unresolvedEntries(
            outcome.attemptedServices,
            failedServices: outcome.failedServices,
            stillOwnedServices: Set(stillOwnedServices),
            serviceName: { $0 }
        ) + outcome.deferredServices

        return finishDirectRestore(
            backup: outcome.backup,
            unresolvedServices: unresolvedServices,
            retention: outcome.retention,
            preservedRecoveryPending: sourceBackup.recoveryPending,
            journal: outcome.journal,
            commandsSucceeded: outcome.allSucceeded,
            proxyStillPointsAtRockxy: outcome.allSucceeded ? !unresolvedServices.isEmpty : true
        )
    }

    /// How the app reaches `networksetup` and the direct backup file during a recovery run.
    private func directRecoveryEffects() -> DirectProxyRecoveryEffects {
        DirectProxyRecoveryEffects(
            readState: { [weak self] service in self?.restorationState(for: service) },
            publishBackup: { [weak self] backup in
                guard let self else {
                    throw SystemProxyError.proxyRestoreFailed
                }
                try writeDirectBackup(backup)
            },
            restoreProxyState: { [weak self] entry in
                guard let self else {
                    throw SystemProxyError.proxyRestoreFailed
                }
                try restoreServiceProxyState(
                    service: entry.service,
                    snapshot: Self.restorationSnapshot(for: entry)
                )
            },
            restoreBypassDomains: { [weak self] entry in
                guard let self else {
                    throw SystemProxyError.proxyRestoreFailed
                }
                try restoreServiceBypassDomains(service: entry.service, domains: entry.bypassDomains)
            },
            log: { event in
                switch event {
                case let .droppedChangedService(service):
                    Self.logger
                        .warning(
                            "Dropping '\(service)' from this direct restore — its proxy settings are no longer the ones this recovery planned for"
                        )
                case let .deferredUnreadableService(service):
                    Self.logger
                        .warning("Deferring '\(service)' — its proxy settings could not be read before restoring")
                case let .uncommittedService(service, error):
                    Self.logger
                        .error(
                            "Could not record the restore of '\(service)' — issuing no command for it: \(error.localizedDescription)"
                        )
                case let .failedStep(service, step, error):
                    Self.logger
                        .error(
                            "Stopped restoring '\(service)' at the \(step.rawValue) step: \(error?.localizedDescription ?? "unknown error")"
                        )
                case let .backupUpdateFailed(error):
                    Self.logger.error("Could not update the retained direct backup: \(error.localizedDescription)")
                }
            }
        )
    }

    /// The captured settings for one service in the shape the restore commands take.
    private static func restorationSnapshot(for entry: DirectServiceBackup) -> ServiceProxySnapshot {
        ServiceProxySnapshot(
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
    }

    /// Clears the direct backup when nothing is left to recover, or narrows it to exactly the
    /// services that still need a restore point.
    ///
    /// What survives the attempt is not the same set that survived inside it. Every preserved
    /// entry was kept for the whole run so no untouched service could lose its restore point
    /// mid-flight, but only the entries that were already on disk beforehand may outlive it: one
    /// this attempt captured itself belongs to a service nobody overrode, and leaving it behind
    /// is how a later enable comes to write a stale snapshot over a newer user setting.
    private func finishDirectRestore(
        backup: DirectProxyBackup,
        unresolvedServices: [String],
        retention: ProxyBackupRetention,
        preservedRecoveryPending: Bool,
        journal: [ProxyServiceRecoveryJournalEntry],
        commandsSucceeded: Bool,
        proxyStillPointsAtRockxy: Bool
    )
        -> Bool
    {
        let restored = Self.shouldClearDirectBackupAfterRestoreAttempt(
            commandsSucceeded: commandsSucceeded,
            proxyStillPointsAtRockxy: proxyStillPointsAtRockxy
        )
        let survivingPreservedServices = retention.preservedServicesPredatingAttempt
        lock.lock()
        if restored {
            // The authorized services are back where they started. Entries that predate this
            // attempt are still the only restore point their own services have, so the file is
            // narrowed to them rather than deleted.
            if survivingPreservedServices.isEmpty {
                clearDirectBackup()
            } else {
                // They keep the flag they arrived with. This attempt did not start a recovery for
                // them, and claiming it had would keep them in play at every later launch.
                retainUnresolvedDirectBackup(
                    backup: backup,
                    unresolvedServices: survivingPreservedServices,
                    journal: journal,
                    recoveryPending: preservedRecoveryPending
                )
            }
            directRestorePending = false
        } else {
            if commandsSucceeded {
                Self.logger.warning(
                    "Direct restore commands completed but proxy still points at Rockxy — keeping backup on disk for watchdog retry"
                )
            } else {
                Self.logger.warning("Partial restore failure — keeping backup on disk for retry")
            }
            // Nothing is removed when there is nothing to keep: an attempt that could not show
            // the settings are back is not one whose word to delete a restore point is worth
            // taking.
            retainUnresolvedDirectBackup(
                backup: backup,
                unresolvedServices: retention.retainedAfterAttempt(unresolvedServices: unresolvedServices),
                journal: journal
            )
            // directRestorePending stays true for same-session retry
        }
        lock.unlock()
        return restored
    }

    // MARK: - Direct Override Rollback

    /// Puts back every service an enable attempt mutated, and reports whether it managed to.
    ///
    /// Only the mutated services are authorized, and only they are written. The entries for
    /// services the attempt never reached stay in the backup on disk for the whole rollback
    /// rather than being removed and added back at the end: a crash or a failed write in between
    /// would otherwise be the moment an untouched service lost the restore point it still needs.
    ///
    /// Being touched is not on its own a licence to write. A service is recorded as touched
    /// before its first command runs, so each one has to show that its live settings really are
    /// one of the states the override sequence passes through — which leaves a command that never
    /// mutated anything, and a change somebody else made in the meantime, exactly as they are.
    @discardableResult
    private func rollBackDirectOverride(
        touchedServices: [String],
        preAttemptServices: Set<String>
    ) -> Bool {
        guard let backup = loadDirectBackup() else {
            return !directBackupFileExists
        }
        guard !touchedServices.isEmpty else {
            // Nothing was written, so nothing needs undoing — but this attempt may have captured
            // entries for services it never reached, and those describe settings nobody
            // overrode. Narrowing to what predates the attempt is what keeps a later enable from
            // replaying them over a newer user setting.
            return finishDirectRestore(
                backup: backup,
                unresolvedServices: [],
                retention: ProxyBackupRetention(
                    authorized: [],
                    preserved: backup.services.map(\.service),
                    preAttemptServices: preAttemptServices
                ),
                preservedRecoveryPending: backup.recoveryPending,
                journal: backup.journal,
                commandsSucceeded: true,
                proxyStillPointsAtRockxy: false
            )
        }

        let touched = Set(touchedServices)
        return restoreDirectMode(
            using: backup,
            authorizedServices: touched,
            locallyMutatedServices: touched,
            preAttemptServices: preAttemptServices
        )
    }

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

    /// Once a restore has started, every retained entry stays in play even if a partial command
    /// already changed the live shape enough that strict ownership no longer matches. Which of
    /// them may still be written is decided per service against the recovery journal, so a
    /// service the user changed between attempts is dropped rather than overwritten.
    private func recoverableDirectServices(in backup: DirectProxyBackup) -> [String] {
        if backup.recoveryPending || !backup.journal.isEmpty {
            return backup.services.map(\.service)
        }

        let backedUpServices = backup.services.map(\.service)
        let liveStates = currentRestorationStates(for: backedUpServices)
        guard liveStates.count == backedUpServices.count else {
            // A transient read failure is not evidence that the override disappeared. Keep every
            // entry recoverable so the planner can defer unreadable services without discarding
            // the only restore point.
            return backedUpServices
        }
        return ProxyOverrideOwnership.residualOwnedServices(
            in: backedUpServices.compactMap { liveStates[$0]?.overrideState },
            port: backup.rockxyPort
        )
    }

    /// Reads only the fields ownership depends on for one service. A service whose settings
    /// cannot be read reports as not overridden, which keeps recovery from claiming ownership it
    /// cannot prove.
    private func currentOverrideState(for service: String) -> ProxyServiceOverrideState {
        restorationState(for: service)?.overrideState
            ?? ProxyServiceOverrideState.unreadable(service: service)
    }

    /// The full restoration-relevant shape of each service, keyed by service name.
    ///
    /// A service whose settings cannot be read is left out rather than reported as empty: an
    /// unreadable service is not a changed one, and an empty state would look exactly like a user
    /// who had just turned every proxy off — which is the difference between deferring a service
    /// and writing over it.
    fileprivate func currentRestorationStates(
        for services: [String]
    )
        -> [String: ProxyServiceRestorationState]
    {
        var states: [String: ProxyServiceRestorationState] = [:]
        for service in services {
            states[service] = restorationState(for: service)
        }
        return states
    }

    /// Reads every proxy field of one service, or nothing at all. A single failed `networksetup`
    /// read makes the whole state nil: a partially read service cannot be compared against a
    /// journal without inventing values for the fields that were not read.
    fileprivate func restorationState(for service: String) -> ProxyServiceRestorationState? {
        guard let httpOutput = try? runNetworkSetup(["-getwebproxy", service]),
              let httpsOutput = try? runNetworkSetup(["-getsecurewebproxy", service]),
              let socksOutput = try? runNetworkSetup(["-getsocksfirewallproxy", service]),
              let pacOutput = try? runNetworkSetup(["-getautoproxyurl", service]),
              let autoDiscoveryOutput = try? runNetworkSetup(["-getproxyautodiscovery", service]),
              let bypassOutput = try? runNetworkSetup(["-getproxybypassdomains", service])
        else {
            return nil
        }

        let http = parseProxyOutput(httpOutput)
        let https = parseProxyOutput(httpsOutput)
        let socks = parseProxyOutput(socksOutput)
        let pac = ProxyRestoreCommandBuilder.parsePACOutput(pacOutput)

        return ProxyServiceRestorationState(
            service: service,
            http: ProxyEndpointState(enabled: http.enabled, host: http.host, port: http.port),
            https: ProxyEndpointState(enabled: https.enabled, host: https.host, port: https.port),
            socks: ProxyEndpointState(enabled: socks.enabled, host: socks.host, port: socks.port),
            pacEnabled: pac.enabled,
            pacURL: pac.url,
            autoDiscoveryEnabled: ProxyRestoreCommandBuilder.parseAutoDiscoveryOutput(autoDiscoveryOutput),
            bypassDomains: ProxyBypassDomainOutput.parse(bypassOutput)
        )
    }

    /// Narrows the on-disk backup to the services recovery still owns, then restores exactly
    /// those. Persisting the reduced backup first is what keeps a later retry from replaying
    /// stale settings onto a service the user has changed in the meantime; if that write fails,
    /// the original backup stays put and no setting is touched.
    @discardableResult
    private func recoverOwnedDirectServices(backup: DirectProxyBackup, ownedServices: [String]) -> Bool {
        let retainedServices = Set(ownedServices)
        let ownedBackup = backup.with(
            services: ProxyBackupSubset.select(
                backup.services,
                services: retainedServices,
                serviceName: \.service
            ),
            journal: ProxyBackupSubset.select(
                backup.journal,
                services: retainedServices,
                serviceName: \.service
            )
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

    /// Keeps only the services a restore attempt left unresolved, along with their journal
    /// records, so the retry cannot write the captured settings back onto a service that already
    /// restored — or onto one the user has since changed.
    private func retainUnresolvedDirectBackup(
        backup: DirectProxyBackup,
        unresolvedServices: [String],
        journal: [ProxyServiceRecoveryJournalEntry],
        recoveryPending: Bool? = nil
    ) {
        guard !unresolvedServices.isEmpty else {
            return
        }

        let retainedServices = Set(unresolvedServices)
        do {
            try writeDirectBackup(backup.with(
                services: ProxyBackupSubset.select(
                    backup.services,
                    services: retainedServices,
                    serviceName: \.service
                ),
                journal: ProxyBackupSubset.select(
                    journal,
                    services: retainedServices,
                    serviceName: \.service
                ),
                recoveryPending: recoveryPending
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

// MARK: - Launch-Time Recovery

extension SystemProxyManager {
    /// The identity and executable a direct-mode watchdog is submitted with, resolved before any
    /// service is mutated.
    private struct DirectWatchdogArming {
        let executableURL: URL
        let parentPID: pid_t
        let parentStartSignature: String
    }

    /// Resolves that arming, or refuses the override outright. Both halves have to be in hand
    /// before anything is written: an override applied first and watched afterwards can outlive
    /// the app with nothing watching it at all.
    private func directWatchdogArming() throws -> DirectWatchdogArming {
        let executableURL = Self.directWatchdogExecutableURL
        let parentPID = ProcessInfo.processInfo.processIdentifier
        let parentStartSignature = ProcessStartIdentity.startSignature(for: parentPID)

        guard Self.directWatchdogPreflightIsSatisfied(
            executableIsAvailable: FileManager.default.isExecutableFile(atPath: executableURL.path),
            parentStartSignature: parentStartSignature
        ), let parentStartSignature else {
            throw SystemProxyError.directProxyWatchdogUnavailable(
                reason: "this process could not be identified to the watchdog, or the watchdog executable is missing"
            )
        }

        return DirectWatchdogArming(
            executableURL: executableURL,
            parentPID: parentPID,
            parentStartSignature: parentStartSignature
        )
    }

    private var directBackupFileExists: Bool {
        FileManager.default.fileExists(atPath: Self.directBackupURL.path)
    }

    private func directBackupBelongsToCurrentProcess(_ backup: DirectProxyBackup) -> Bool {
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        return DirectProxyBackupOwnerPolicy.belongsToSession(
            backup,
            processIdentifier: processIdentifier,
            processStartSignature: ProcessStartIdentity.startSignature(for: processIdentifier)
        )
    }

    private func directBackupOwnerIsLive(_ backup: DirectProxyBackup) -> Bool {
        DirectProxyBackupOwnerPolicy.ownerIsLive(
            backup,
            processIsAlive: ProcessStartIdentity.isAlive,
            liveStartSignature: ProcessStartIdentity.startSignature
        )
    }

    /// Called at app launch to detect and restore stale direct-mode proxy overrides left behind
    /// by a crash or force-quit.
    func recoverStaleProxyIfNeeded() async {
        await Self.lifecycleGate.withOperation { [self] in
            await recoverStaleProxyIfNeededLocked()
        }
    }

    private func recoverStaleProxyIfNeededLocked() async {
        switch recoverStaleDirectProxyIfNeeded() {
        case .restored:
            stopBypassListObserver()
            clearInMemoryOverrideState()
            NotificationCenter.default.post(
                name: .systemProxyDidChange,
                object: nil,
                userInfo: ["enabled": false]
            )
        case .restoreIncomplete:
            lock.withLock { directRestorePending = true }
        case .preserved:
            Self.logger.info("A live app process owns the direct proxy backup — preserving its session")
        case .noBackup, .cleared:
            break
        }

        // Helper startup recovery and its owner watchdog make this decision from the persisted
        // PID and start signature. An app-side status probe cannot distinguish a stale override
        // from another live Rockxy instance, so it must never restore one unconditionally.
    }

    private func recoverStaleDirectProxyIfNeeded() -> DirectStaleRecoveryOutcome {
        Self.operationGate.withOperation { [self] in
            do {
                return try DirectProxySessionLock.withExclusiveAccess(backupURL: Self.directBackupURL) {
                    guard directBackupFileExists else {
                        return .noBackup
                    }
                    guard let backup = loadDirectBackup() else {
                        Self.logger.error("Stale direct backup could not be read — preserving it for retry")
                        return .restoreIncomplete
                    }
                    guard !directBackupOwnerIsLive(backup) else {
                        return .preserved
                    }

                    let residualOwnedServices = recoverableDirectServices(in: backup)
                    switch ProxyBackupRecoveryPolicy.action(
                        residualOwnedServicesExist: !residualOwnedServices.isEmpty,
                        ownerSessionIsLive: false
                    ) {
                    case .restore:
                        Self.logger
                            .info(
                                "Recovering \(residualOwnedServices.count) stale direct-mode service(s) from a previous session"
                            )
                        guard recoverOwnedDirectServices(backup: backup, ownedServices: residualOwnedServices) else {
                            Self.logger.error("Stale direct proxy recovery incomplete — backup preserved for retry")
                            return .restoreIncomplete
                        }
                        return .restored
                    case .clear:
                        Self.logger.info("No backed-up service is still Rockxy-owned, clearing stale direct backup")
                        clearDirectBackup()
                        return .cleared
                    case .preserve:
                        return .preserved
                    }
                }
            } catch {
                Self.logger.error("Could not acquire direct proxy recovery lock: \(error.localizedDescription)")
                return .restoreIncomplete
            }
        }
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
