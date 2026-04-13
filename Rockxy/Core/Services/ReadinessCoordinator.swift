import AppKit
import Foundation
import os

// MARK: - CertReadiness

/// Describes the current state of the root CA certificate lifecycle.
enum CertReadiness: Equatable {
    case notGenerated
    case generatedNotInstalled
    case installedNotTrusted
    case trusted

    // MARK: Internal

    var localizedDescription: String {
        switch self {
        case .notGenerated:
            String(localized: "Root CA not generated")
        case .generatedNotInstalled:
            String(localized: "Root CA generated but not installed")
        case .installedNotTrusted:
            String(localized: "Root CA installed but not trusted")
        case .trusted:
            String(localized: "Root CA trusted")
        }
    }
}

// MARK: - ProxyMode

/// Describes how the system proxy is being managed.
enum ProxyMode: Equatable {
    case helper
    case direct
    case unavailable
}

// MARK: - ReadinessWarning

/// A single readiness warning shown in the main workspace banner. Only the
/// highest-priority warning is active at any time.
struct ReadinessWarning: Equatable {
    enum Action: Equatable {
        case retry
        case openGeneralSettings
        case openAdvancedProxySettings
        case reinstallAndTrust

        // MARK: Internal

        var title: String {
            switch self {
            case .retry:
                String(localized: "Retry")
            case .openGeneralSettings:
                String(localized: "Open Certificate Settings")
            case .openAdvancedProxySettings:
                String(localized: "Open Advanced Proxy Settings")
            case .reinstallAndTrust:
                String(localized: "Install & Trust Certificate")
            }
        }
    }

    let message: String
    let action: Action?
    let isDismissible: Bool
}

// MARK: - ReadinessCoordinator

/// Single source of truth for app-wide readiness state. Bridges helper, certificate, and
/// proxy subsystems into one reactive model that the main workspace and settings views observe.
///
/// Uses explicit notification observation (not @Observable property tracking) to trigger
/// state recomputation. One centralized `didBecomeActiveNotification` observer handles
/// external state changes made in Keychain Access or System Settings.
@MainActor @Observable
final class ReadinessCoordinator {
    // MARK: Internal

    static let shared = ReadinessCoordinator()
    nonisolated static let activationRefreshCooldown: Duration = .seconds(2)

    // MARK: - State

    private(set) var certReadiness: CertReadiness = .notGenerated
    private(set) var helperReadiness: HelperManager.HelperStatus = .notInstalled
    private(set) var helperSigningIssue: HelperManager.SigningIssue?
    private(set) var proxyMode: ProxyMode = .unavailable
    private(set) var activeWarning: ReadinessWarning?
    private(set) var isCaptureActive: Bool = false
    private(set) var lastCertSnapshot: RootCAStatusSnapshot?

    // MARK: - Derived Capabilities

    /// True when the root CA is trusted and HTTPS interception is possible for new connections.
    var canInterceptHTTPS: Bool {
        certReadiness == .trusted
    }

    /// True when the helper tool is installed, compatible, and reachable.
    var hasOptimalProxyControl: Bool {
        helperReadiness == .installedCompatible
    }

    /// True when there is a readiness issue that materially blocks capture capability.
    /// Only cert-untrusted during active capture is truly blocking.
    /// Direct-mode fallback and helper issues are degraded but not blocking.
    var hasBlockingReadinessIssue: Bool {
        guard isCaptureActive else {
            return false
        }
        return certReadiness != .trusted
    }

    /// Pure decision function: returns the warning that Priority 2 (cert-not-trusted)
    /// would produce, or nil if the cert is trusted. Extracted for deterministic testing.
    nonisolated static func certNotTrustedWarning(
        certReadiness: CertReadiness,
        isCaptureActive: Bool
    )
        -> ReadinessWarning?
    {
        guard isCaptureActive, certReadiness != .trusted else {
            return nil
        }
        return ReadinessWarning(
            message: String(
                localized: """
                HTTPS interception is unavailable because the Rockxy Root CA is not trusted. \
                HTTP traffic and logs are still captured.
                """
            ),
            action: .reinstallAndTrust,
            isDismissible: false
        )
    }

    nonisolated static func shouldPerformActivationDeepRefresh(
        lastCompletedAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        isInFlight: Bool,
        cooldown: Duration = activationRefreshCooldown
    )
        -> Bool
    {
        guard !isInFlight else {
            return false
        }
        guard let lastCompletedAt else {
            return true
        }
        return now - lastCompletedAt >= cooldown
    }

    /// Begins observing readiness-related notifications. Idempotent — safe to call
    /// multiple times from workspace lifecycle without creating duplicate observers.
    func startObserving() {
        guard observers.isEmpty else {
            return
        }

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .certificateStatusChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshCertState()
                    self?.recomputeWarning()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .helperStatusChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshHelperState()
                    self?.recomputeWarning()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .systemProxyDidChange, object: nil, queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    let enabled = notification.userInfo?["enabled"] as? Bool ?? false
                    self?.refreshProxyMode(isEnabled: enabled)
                    self?.recomputeWarning()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .tlsMitmRejected, object: nil, queue: .main
            ) { [weak self] notification in
                guard let host = notification.userInfo?["host"] as? String else {
                    return
                }
                Task { @MainActor in
                    self?.tlsRejectionHosts.insert(host)
                    self?.recomputeWarning()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .systemProxyVPNWarning, object: nil, queue: .main
            ) { [weak self] notification in
                let iface = notification.userInfo?["interface"] as? String ?? "unknown"
                Task { @MainActor in
                    self?.vpnInterface = iface
                    self?.recomputeWarning()
                }
            }
        )

        // Centralized app-activation refresh. Replaces all per-view didBecomeActive observers.
        // External changes (Keychain Access trust, System Settings helper approval) do not emit
        // in-app notifications, so we deep-refresh on every app activation.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshOnActivationIfNeeded()
                }
            }
        )

        Self.logger.info("ReadinessCoordinator started observing")
    }

    func stopObserving() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        Self.logger.info("ReadinessCoordinator stopped observing")
    }

    /// Cheap refresh: reads cached helper state and current cert snapshot without XPC probes.
    /// Use for notification-triggered updates where the source already changed its own state.
    func refresh() async {
        await refreshCertState()
        refreshHelperState()
        refreshProxyMode(isEnabled: SystemProxyManager.shared.isSystemProxyEnabled())
        recomputeWarning()
    }

    /// Deep refresh: explicitly probes helper status via XPC and re-snapshots certificate state.
    /// Use for app-activation refresh and user-triggered actions where external state may have changed.
    func deepRefresh() async {
        await HelperManager.shared.checkStatus()
        await refreshCertState(performValidation: true)
        refreshHelperState()
        refreshProxyMode(isEnabled: SystemProxyManager.shared.isSystemProxyEnabled())
        recomputeWarning()
        Self.logger.debug("ReadinessCoordinator deep-refreshed all state")
    }

    func setCaptureActive(_ active: Bool) {
        isCaptureActive = active
        if !active {
            tlsRejectionHosts.removeAll()
            vpnInterface = nil
            proxyEnableFailed = false
            proxyEnableErrorMessage = nil
        }
        recomputeWarning()
    }

    func setProxyEnableFailed(message: String) {
        proxyEnableFailed = true
        proxyEnableErrorMessage = message
        recomputeWarning()
    }

    func clearProxyEnableFailure() {
        proxyEnableFailed = false
        proxyEnableErrorMessage = nil
        recomputeWarning()
    }

    /// Called when the user dismisses a dismissible warning.
    func dismissWarning() {
        guard activeWarning?.isDismissible == true else {
            return
        }
        dismissedWarningMessage = activeWarning?.message
        activeWarning = nil
    }

    /// Clears TLS rejection state. Called when proxy restarts or session clears.
    func clearTLSRejections() {
        tlsRejectionHosts.removeAll()
        recomputeWarning()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ReadinessCoordinator")

    private var observers: [NSObjectProtocol] = []
    private var tlsRejectionHosts: Set<String> = []
    private var vpnInterface: String?
    private var proxyEnableFailed = false
    private var proxyEnableErrorMessage: String?
    private var dismissedWarningMessage: String?
    private let activationRefreshClock = ContinuousClock()
    private var isActivationRefreshInFlight = false
    private var lastActivationRefreshFinishedAt: ContinuousClock.Instant?

    // MARK: - State Refresh

    private func refreshCertState(performValidation: Bool = false) async {
        let snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: performValidation)
        lastCertSnapshot = snapshot

        let previousReadiness = certReadiness

        if snapshot.isSystemTrustValidated {
            certReadiness = .trusted
        } else if snapshot.hasTrustSettings || snapshot.isInstalledInKeychain {
            certReadiness = .installedNotTrusted
        } else if snapshot.hasGeneratedCertificate {
            certReadiness = .generatedNotInstalled
        } else {
            certReadiness = .notGenerated
        }

        // Reconcile HTTPS interception passthrough for running proxy.
        // Always sync to current cert state during active capture so passthrough
        // cannot drift if refresh is called without a readiness enum transition.
        // Only new HTTPS connections are affected — existing TLS sessions are not re-intercepted.
        if isCaptureActive {
            let shouldPassthrough = certReadiness != .trusted
            SSLProxyingManager.shared.forceGlobalPassthrough = shouldPassthrough
            if certReadiness != previousReadiness, !shouldPassthrough {
                Self.logger.info(
                    "Certificate trust detected during capture — new HTTPS connections will be intercepted"
                )
            }
        }
    }

    private func refreshHelperState() {
        helperReadiness = HelperManager.shared.status
        helperSigningIssue = HelperManager.shared.signingIssue
    }

    private func refreshProxyMode(isEnabled: Bool) {
        if !isEnabled {
            proxyMode = .unavailable
        } else if SystemProxyManager.shared.usingHelperProxyOverride {
            proxyMode = .helper
        } else {
            proxyMode = .direct
        }
    }

    private func refreshOnActivationIfNeeded() async {
        let now = activationRefreshClock.now
        guard Self.shouldPerformActivationDeepRefresh(
            lastCompletedAt: lastActivationRefreshFinishedAt,
            now: now,
            isInFlight: isActivationRefreshInFlight
        ) else {
            if isActivationRefreshInFlight {
                Self.logger.debug("Skipping activation deep refresh because one is already in flight")
            } else {
                Self.logger.debug("Skipping activation deep refresh because the last one completed recently")
            }
            return
        }

        isActivationRefreshInFlight = true
        defer {
            isActivationRefreshInFlight = false
            lastActivationRefreshFinishedAt = activationRefreshClock.now
        }

        await deepRefresh()
    }

    // MARK: - Warning Priority

    private func recomputeWarning() {
        let warning = computeHighestPriorityWarning()

        // If the user dismissed a warning and the same message reappears, keep it dismissed
        if let warning, warning.message == dismissedWarningMessage {
            activeWarning = nil
            return
        }

        // Clear dismissed state when the warning changes
        if warning?.message != dismissedWarningMessage {
            dismissedWarningMessage = nil
        }

        activeWarning = warning
    }

    private func computeHighestPriorityWarning() -> ReadinessWarning? {
        guard isCaptureActive else {
            return nil
        }

        // Priority 1: Proxy enable failure
        if proxyEnableFailed, let message = proxyEnableErrorMessage {
            return ReadinessWarning(
                message: message,
                action: .retry,
                isDismissible: true
            )
        }

        // Priority 2: Certificate not trusted — blocks HTTPS interception
        if let certWarning = Self.certNotTrustedWarning(
            certReadiness: certReadiness,
            isCaptureActive: isCaptureActive
        ) {
            return certWarning
        }

        // Priority 3: Direct mode fallback — degraded but not blocking
        if proxyMode == .direct {
            return directModeWarning()
        }

        // Priority 4: TLS rejection accumulation
        if tlsRejectionHosts.count >= 3 {
            return tlsRejectionWarning()
        }

        // Priority 5: VPN detected
        if let iface = vpnInterface {
            return ReadinessWarning(
                message: String(
                    localized: """
                    VPN or iCloud Private Relay detected (\(iface)). \
                    Traffic may not be captured. Disable VPN/Private Relay to use Rockxy.
                    """
                ),
                action: nil,
                isDismissible: true
            )
        }

        return nil
    }

    private func directModeWarning() -> ReadinessWarning? {
        let reason = switch helperReadiness {
        case .notInstalled:
            String(localized: "the helper tool is not installed")
        case .requiresApproval:
            String(localized: "the helper tool still needs approval")
        case .installedOutdated:
            String(localized: "the helper tool needs to be updated")
        case .installedIncompatible:
            String(localized: "the helper tool version is incompatible")
        case .unreachable:
            String(localized: "the helper tool is unreachable")
        case .installedCompatible:
            String(localized: "the helper tool could not be used")
        case .signingMismatch:
            HelperManager.signingMismatchWarningReason(issue: helperSigningIssue)
        }

        return ReadinessWarning(
            message: String(
                localized: """
                Rockxy is using direct macOS proxy changes because \(reason). \
                If Rockxy or Xcode stops unexpectedly, your Mac may stay behind a dead proxy until \
                Rockxy restores it. Install or repair the helper tool for safer automatic cleanup.
                """
            ),
            action: .openAdvancedProxySettings,
            isDismissible: false
        )
    }

    /// TLS rejection warning with contextual messaging based on certificate trust state.
    /// Existing TLS sessions are not re-intercepted — only new connections are affected
    /// after trust changes, so browser restart guidance is always included.
    private func tlsRejectionWarning() -> ReadinessWarning? {
        let message = if lastCertSnapshot?.isSystemTrustValidated == true {
            String(
                localized: """
                Multiple HTTPS hosts rejected the proxy certificate. \
                Restart your browser to pick up the new Rockxy Root CA trust settings.
                """
            )
        } else {
            String(
                localized: """
                Multiple HTTPS hosts rejected the proxy certificate. \
                Check that the Rockxy Root CA is trusted in Keychain Access, then restart your browser.
                """
            )
        }

        return ReadinessWarning(
            message: message,
            action: .openGeneralSettings,
            isDismissible: true
        )
    }
}
