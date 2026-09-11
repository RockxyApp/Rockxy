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
    /// The certificate, Keychain, or trust state could not be read. Never treated as an absent
    /// or untrusted root: the recovery is a recheck, not another install and approval.
    case unknown

    // MARK: Internal

    var localizedDescription: String {
        switch self {
        case .unknown:
            String(localized: "Root CA status unavailable", bundle: RockxyLocalization.bundle)
        case .notGenerated:
            String(localized: "Root CA not generated", bundle: RockxyLocalization.bundle)
        case .generatedNotInstalled:
            String(localized: "Root CA generated but not installed", bundle: RockxyLocalization.bundle)
        case .installedNotTrusted:
            String(localized: "Root CA installed but not trusted", bundle: RockxyLocalization.bundle)
        case .trusted:
            String(localized: "Root CA trusted", bundle: RockxyLocalization.bundle)
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

// MARK: - CaptureHealthState

/// Result of Rockxy's private loopback request through the live proxy listener.
/// This verifies the local request/response capture path without contacting the internet
/// or adding a diagnostic row to the user's session.
enum CaptureHealthState: Equatable {
    case idle
    case checking
    case verified
    case failed
}

// MARK: - ReadinessWarning

/// A single readiness warning shown in the main workspace banner. Only the
/// highest-priority warning is active at any time.
struct ReadinessWarning: Equatable {
    enum Action: Equatable {
        case retry
        case retryStop
        case retryDisableSystemRouting
        case retryCaptureCheck
        case restoreSystemRouting
        case openHTTPSDecryption
        case retryHTTPSInterception
        case openGeneralSettings
        case openAdvancedProxySettings
        case reinstallAndTrust

        // MARK: Internal

        var title: String {
            switch self {
            case .retry:
                String(localized: "Retry", bundle: RockxyLocalization.bundle)
            case .retryStop:
                String(localized: "Stop Capture", bundle: RockxyLocalization.bundle)
            case .retryDisableSystemRouting:
                String(localized: "Switch Off", bundle: RockxyLocalization.bundle)
            case .retryCaptureCheck:
                String(localized: "Run Capture Check", bundle: RockxyLocalization.bundle)
            case .restoreSystemRouting:
                String(localized: "Restore System Routing", bundle: RockxyLocalization.bundle)
            case .openHTTPSDecryption:
                String(localized: "Open HTTPS Decryption", bundle: RockxyLocalization.bundle)
            case .retryHTTPSInterception:
                String(localized: "Retry", bundle: RockxyLocalization.bundle)
            case .openGeneralSettings:
                String(localized: "Open Certificate Settings", bundle: RockxyLocalization.bundle)
            case .openAdvancedProxySettings:
                String(localized: "Open Advanced Proxy Settings", bundle: RockxyLocalization.bundle)
            case .reinstallAndTrust:
                String(localized: "Install & Trust Certificate", bundle: RockxyLocalization.bundle)
            }
        }
    }

    let message: String
    let action: Action?
    let isDismissible: Bool
}

// MARK: - TLSRejectionEvidence

/// Aggregates certificate rejection and TLS compatibility evidence per originating application.
///
/// Identified clients are isolated from each other so one application's pinning failures cannot
/// become another application's warning. Unattributed local failures are tracked separately and
/// never receive a retry action that would clear another client's persisted recovery state.
struct TLSRejectionEvidence: Equatable {
    static let warningThreshold = 3
    static let maximumTrackedClients = 128

    private(set) var rejectedHostsByClient: [String: Set<String>] = [:]
    private(set) var unattributedRejectedHosts: Set<String> = []
    private(set) var clientsAcceptingCurrentCA: Set<String> = []
    private var acceptingClientOrder: [String] = []

    var hasMultiHostClientFailure: Bool {
        rejectedHostsByClient.contains { $0.value.count >= Self.warningThreshold }
    }

    var clientIdentifiersNeedingRetry: Set<String> {
        Set(rejectedHostsByClient.compactMap { clientIdentifier, hosts in
            hosts.count >= Self.warningThreshold ? clientIdentifier : nil
        })
    }

    var hasUnattributedMultiHostFailure: Bool {
        unattributedRejectedHosts.count >= Self.warningThreshold
    }

    @discardableResult
    mutating func recordRejection(host: String, clientIdentifier: String?) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return false
        }
        guard let clientIdentifier = normalizedClientIdentifier(clientIdentifier) else {
            guard unattributedRejectedHosts.count < Self.warningThreshold else {
                return false
            }
            return unattributedRejectedHosts.insert(normalizedHost).inserted
        }
        // A successful intercepted handshake from this client during the current capture/CA
        // epoch proves that macOS trust is not failing globally for that client. Later failures
        // are host-specific pinning or TLS-shape limitations and already recover as raw tunnels;
        // they must not resurrect the broad setup warning from issue #345.
        guard !clientsAcceptingCurrentCA.contains(clientIdentifier) else {
            return false
        }
        guard rejectedHostsByClient[clientIdentifier] != nil
            || rejectedHostsByClient.count < Self.maximumTrackedClients else {
            return false
        }
        var hosts = rejectedHostsByClient[clientIdentifier, default: []]
        if hosts.count < Self.warningThreshold {
            let inserted = hosts.insert(normalizedHost).inserted
            rejectedHostsByClient[clientIdentifier] = hosts
            return inserted
        }
        return false
    }

    @discardableResult
    mutating func recordSuccessfulHandshake(host: String, clientIdentifier: String?) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty,
              let normalizedIdentifier = normalizedClientIdentifier(clientIdentifier)
        else {
            return false
        }

        // A host that later succeeds after identity resolution no longer contributes to the
        // unattributed warning bucket.
        var changed = unattributedRejectedHosts.remove(normalizedHost) != nil

        // One completed interception proves the active CA works for this client in the current
        // epoch, so all earlier host failures from that client are compatibility-specific.
        if rejectedHostsByClient.removeValue(forKey: normalizedIdentifier) != nil {
            changed = true
        }

        acceptingClientOrder.removeAll { $0 == normalizedIdentifier }
        if clientsAcceptingCurrentCA.insert(normalizedIdentifier).inserted {
            changed = true
        }
        acceptingClientOrder.append(normalizedIdentifier)
        if clientsAcceptingCurrentCA.count > Self.maximumTrackedClients,
           let evicted = acceptingClientOrder.first
        {
            clientsAcceptingCurrentCA.remove(evicted)
            acceptingClientOrder.removeFirst()
        }
        return changed
    }

    mutating func reset() {
        rejectedHostsByClient.removeAll()
        unattributedRejectedHosts.removeAll()
        clientsAcceptingCurrentCA.removeAll()
        acceptingClientOrder.removeAll()
    }

    mutating func clearRejections(clientIdentifiers: Set<String>) {
        let normalizedIdentifiers = Set(clientIdentifiers.compactMap(normalizedClientIdentifier))
        for clientIdentifier in normalizedIdentifiers {
            rejectedHostsByClient.removeValue(forKey: clientIdentifier)
        }
    }

    private func normalizedClientIdentifier(_ clientIdentifier: String?) -> String? {
        guard let normalized = clientIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalized.isEmpty
        else {
            return nil
        }
        return normalized
    }
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
    private(set) var systemRoutingReady = false
    private(set) var systemRoutingExpected = true
    private(set) var captureHealth: CaptureHealthState = .idle
    private(set) var httpsDecryptionConfigured = false
    private(set) var activeWarning: ReadinessWarning?

    var tlsRetryClientIdentifiers: Set<String> {
        tlsRejectionEvidence.clientIdentifiersNeedingRetry
    }
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
    /// Certificate trust, exact system routing, and an end-to-end probe failure are blocking.
    /// Direct-mode fallback and helper issues are degraded but not blocking by themselves.
    var hasBlockingReadinessIssue: Bool {
        guard isCaptureActive else {
            return false
        }
        return certReadiness != .trusted
            || (systemRoutingExpected && !systemRoutingReady)
            || captureHealth == .failed
    }

    /// Pure decision function: returns the warning that Priority 2 (cert-not-trusted)
    /// would produce, or nil if the cert is trusted. Extracted for deterministic testing.
    ///
    /// Each readable state names the step that is actually missing. Reporting "not trusted" for
    /// a root that was never generated, or for one that is not in any keychain, describes a
    /// trust decision the user never made and hides which recovery step is outstanding. The
    /// unreadable state stays separate: it is a failed read, so it offers a recheck instead of
    /// asking for administrator approval.
    nonisolated static func certNotTrustedWarning(
        certReadiness: CertReadiness,
        isCaptureActive: Bool
    )
        -> ReadinessWarning?
    {
        guard isCaptureActive else {
            return nil
        }
        switch certReadiness {
        case .trusted:
            return nil
        case .unknown:
            // Nothing is known to be wrong with the certificate, so the offer is a status check
            // rather than a reinstall that would ask for administrator approval on the strength
            // of a failed read. HTTPS interception stays paused either way.
            return ReadinessWarning(
                message: String(
                    localized: """
                    Rockxy cannot verify the Root CA trust status, so HTTPS interception is paused. \
                    HTTP traffic and logs are still captured.
                    """, bundle: RockxyLocalization.bundle
                ),
                action: .openGeneralSettings,
                isDismissible: false
            )
        case .notGenerated:
            return ReadinessWarning(
                message: String(
                    localized: """
                    HTTPS interception is unavailable because the Rockxy Root CA has not been generated yet. \
                    HTTP traffic and logs are still captured.
                    """, bundle: RockxyLocalization.bundle
                ),
                action: .reinstallAndTrust,
                isDismissible: false
            )
        case .generatedNotInstalled:
            return ReadinessWarning(
                message: String(
                    localized: """
                    HTTPS interception is unavailable because the Rockxy Root CA is not installed in the \
                    login or System keychain. HTTP traffic and logs are still captured.
                    """, bundle: RockxyLocalization.bundle
                ),
                action: .reinstallAndTrust,
                isDismissible: false
            )
        case .installedNotTrusted:
            return ReadinessWarning(
                message: String(
                    localized: """
                    HTTPS interception is unavailable because the Rockxy Root CA is installed but not \
                    trusted for SSL. HTTP traffic and logs are still captured.
                    """, bundle: RockxyLocalization.bundle
                ),
                action: .reinstallAndTrust,
                isDismissible: false
            )
        }
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
        SystemProxyManager.shared.startMonitoringSystemProxyConfiguration()
        guard observers.isEmpty else {
            return
        }

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .certificateStatusChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.tlsRejectionEvidence.reset()
                    RecentFailureTracker.certificateRejections.reset()
                    await self?.refreshCertState()
                    self?.recomputeWarning()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .sslProxyingStateDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshHTTPSDecryptionState()
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
                guard let host = notification.userInfo?[TLSMITMNotificationUserInfoKey.host] as? String else {
                    return
                }
                let clientIdentifier = notification
                    .userInfo?[TLSMITMNotificationUserInfoKey.clientIdentifier] as? String
                MainActor.assumeIsolated {
                    let evidenceChanged = self?.tlsRejectionEvidence.recordRejection(
                        host: host,
                        clientIdentifier: clientIdentifier
                    ) ?? false
                    if evidenceChanged {
                        self?.recomputeWarning()
                    }
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .tlsMitmAccepted, object: nil, queue: .main
            ) { [weak self] notification in
                guard let host = notification.userInfo?[TLSMITMNotificationUserInfoKey.host] as? String else {
                    return
                }
                let clientIdentifier = notification
                    .userInfo?[TLSMITMNotificationUserInfoKey.clientIdentifier] as? String
                MainActor.assumeIsolated {
                    let evidenceChanged = self?.tlsRejectionEvidence.recordSuccessfulHandshake(
                        host: host,
                        clientIdentifier: clientIdentifier
                    ) ?? false
                    if evidenceChanged {
                        self?.recomputeWarning()
                    }
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
        await refreshProxyMode(isEnabled: systemProxyEnabledProbe())
        refreshHTTPSDecryptionState()
        recomputeWarning()
    }

    /// Forced certificate revalidation: re-snapshots certificate state and, when positive trust
    /// metadata exists, runs a real `SecTrust` evaluation instead of reusing the last cached
    /// validation result. Known-absent trust metadata still fails closed without the expensive
    /// evaluation.
    ///
    /// `refresh()` is deliberately cheap and may answer from a cached negative that a trust
    /// approval since then has already invalidated. Capture start decides HTTPS passthrough for
    /// a whole session from this answer, so it evaluates trust for real. Narrower than
    /// `deepRefresh()` on purpose: no helper XPC probe and no system-proxy read, because neither
    /// participates in the passthrough decision. This never requests certificate installation or
    /// changes trust settings.
    func refreshCertificateTrustValidation() async {
        await refreshCertState(performValidation: true)
        recomputeWarning()
    }

    /// Deep refresh: explicitly probes helper status via XPC and re-snapshots certificate state.
    /// Use for app-activation refresh and user-triggered actions where external state may have changed.
    func deepRefresh() async {
        await HelperManager.shared.checkStatus()
        await refreshCertState(performValidation: true)
        refreshHelperState()
        await refreshProxyMode(isEnabled: systemProxyEnabledProbe())
        refreshHTTPSDecryptionState()
        recomputeWarning()
        Self.logger.debug("ReadinessCoordinator deep-refreshed all state")
    }

    func setCaptureActive(_ active: Bool) {
        isCaptureActive = active
        refreshHTTPSDecryptionState()
        if !active {
            tlsRejectionEvidence.reset()
            RecentFailureTracker.certificateRejections.reset()
            vpnInterface = nil
            proxyEnableFailed = false
            proxyEnableErrorMessage = nil
            proxyRestoreFailed = false
            proxyRestoreRetryAction = nil
            systemRoutingReady = false
            systemRoutingExpected = true
            captureHealth = .idle
        }
        recomputeWarning()
    }

    func setSystemRoutingReady(_ ready: Bool) {
        systemRoutingReady = ready
        recomputeWarning()
    }

    func setSystemRoutingExpected(_ expected: Bool) {
        systemRoutingExpected = expected
        recomputeWarning()
    }

    func setCaptureHealth(_ state: CaptureHealthState) {
        captureHealth = state
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

    func setProxyRestoreFailed(retryAction: ReadinessWarning.Action) {
        proxyRestoreFailed = true
        proxyRestoreRetryAction = retryAction
        recomputeWarning()
    }

    func clearProxyRestoreFailure() {
        proxyRestoreFailed = false
        proxyRestoreRetryAction = nil
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

    /// Clears TLS rejection state after the user explicitly retries interception.
    func clearTLSRejections() {
        tlsRejectionEvidence.reset()
        RecentFailureTracker.certificateRejections.reset()
        recomputeWarning()
    }

    /// Clears only the evidence represented by the retry action. New failures from those
    /// clients can accumulate immediately; unrelated client warnings remain intact.
    func clearTLSRejections(clientIdentifiers: Set<String>) {
        tlsRejectionEvidence.clearRejections(clientIdentifiers: clientIdentifiers)
        recomputeWarning()
    }

    #if DEBUG
    func injectSystemProxyEnabledProbeForTests(_ probe: @escaping () async -> Bool) {
        systemProxyEnabledProbe = probe
    }

    func resetSystemProxyEnabledProbeForTests() {
        systemProxyEnabledProbe = {
            await SystemProxyManager.shared.isSystemProxyEnabledAsync()
        }
    }
    #endif

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ReadinessCoordinator")

    private var observers: [NSObjectProtocol] = []
    private var tlsRejectionEvidence = TLSRejectionEvidence()
    private var vpnInterface: String?
    private var proxyEnableFailed = false
    private var proxyEnableErrorMessage: String?
    private var proxyRestoreFailed = false
    private var proxyRestoreRetryAction: ReadinessWarning.Action?
    private var dismissedWarningMessage: String?
    private let activationRefreshClock = ContinuousClock()
    private var isActivationRefreshInFlight = false
    private var lastActivationRefreshFinishedAt: ContinuousClock.Instant?
    private var systemProxyEnabledProbe: () async -> Bool = {
        await SystemProxyManager.shared.isSystemProxyEnabledAsync()
    }

    // MARK: - State Refresh

    private func refreshCertState(performValidation: Bool = false) async {
        let snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: performValidation)
        lastCertSnapshot = snapshot

        let previousReadiness = certReadiness

        // An unreadable status outranks the booleans: they are fail-closed defaults, not
        // findings, so reporting them would present a trusted root as missing or untrusted.
        if snapshot.isStatusUnavailable {
            certReadiness = .unknown
        } else if snapshot.isSystemTrustValidated {
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

    private func refreshHTTPSDecryptionState() {
        httpsDecryptionConfigured = SSLProxyingManager.shared.hasEnabledDecryptRules()
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

        if activeWarning != warning {
            activeWarning = warning
        }
    }

    private func computeHighestPriorityWarning() -> ReadinessWarning? {
        guard isCaptureActive else {
            return nil
        }

        // Priority 1: A failed restore keeps capture alive so macOS is never left
        // pointing at a listener that Rockxy has already stopped.
        if proxyRestoreFailed, let retryAction = proxyRestoreRetryAction {
            return ReadinessWarning(
                message: String(
                    localized: "Rockxy could not restore the previous system proxy settings. Capture remains running so network traffic stays reachable.",
                    bundle: RockxyLocalization.bundle
                ),
                action: retryAction,
                isDismissible: false
            )
        }

        // Priority 2: Proxy enable failure
        if proxyEnableFailed, let message = proxyEnableErrorMessage {
            return ReadinessWarning(
                message: message,
                action: .retry,
                isDismissible: true
            )
        }

        // Priority 3: The private end-to-end loopback check could not traverse the
        // running listener and complete as a captured transaction.
        if captureHealth == .failed {
            return ReadinessWarning(
                message: String(
                    localized: "Rockxy could not verify its local capture path. The listener is running, but capture is not confirmed.",
                    bundle: RockxyLocalization.bundle
                ),
                action: .retryCaptureCheck,
                isDismissible: false
            )
        }

        // Priority 4: The listener may be healthy while ordinary macOS traffic is routed
        // elsewhere. Do not reclaim the proxy automatically; make the takeover visible.
        if systemRoutingExpected, !systemRoutingReady {
            return ReadinessWarning(
                message: String(
                    localized: """
                    macOS system traffic is not routed to Rockxy. The listener may still accept manually configured apps, \
                    but browser traffic will not be captured automatically.
                    """,
                    bundle: RockxyLocalization.bundle
                ),
                action: .restoreSystemRouting,
                isDismissible: false
            )
        }

        // Priority 4: Certificate not trusted — blocks HTTPS interception
        if let certWarning = Self.certNotTrustedWarning(
            certReadiness: certReadiness,
            isCaptureActive: isCaptureActive
        ) {
            return certWarning
        }

        // Priority 5: A trusted Root CA is necessary but not sufficient. With no
        // enabled Decrypt rule, HTTPS is deliberately visible only as CONNECT tunnels.
        if certReadiness == .trusted, !httpsDecryptionConfigured {
            return ReadinessWarning(
                message: String(
                    localized: "HTTPS traffic is staying as CONNECT tunnels because no Decrypt rule is enabled.",
                    bundle: RockxyLocalization.bundle
                ),
                action: .openHTTPSDecryption,
                isDismissible: true
            )
        }

        // Priority 6: Direct mode fallback — degraded but not blocking
        if proxyMode == .direct {
            return directModeWarning()
        }

        // Priority 7: TLS rejection accumulation
        if tlsRejectionEvidence.hasMultiHostClientFailure {
            return tlsRejectionWarning()
        }

        if tlsRejectionEvidence.hasUnattributedMultiHostFailure {
            return Self.unattributedTLSRejectionWarning()
        }

        // Priority 8: VPN detected
        if let iface = vpnInterface {
            return ReadinessWarning(
                message: String(
                    localized: """
                    VPN or iCloud Private Relay detected (\(iface)). \
                    Traffic may not be captured. Disable VPN/Private Relay to use Rockxy.
                    """, bundle: RockxyLocalization.bundle
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
            String(localized: "the helper tool is not installed", bundle: RockxyLocalization.bundle)
        case .requiresApproval:
            String(localized: "the helper tool still needs approval", bundle: RockxyLocalization.bundle)
        case .installedOutdated:
            String(localized: "the helper tool needs to be updated", bundle: RockxyLocalization.bundle)
        case .installedIncompatible:
            String(localized: "the helper tool version is incompatible", bundle: RockxyLocalization.bundle)
        case .unreachable:
            String(localized: "the helper tool is unreachable", bundle: RockxyLocalization.bundle)
        case .installedCompatible:
            String(localized: "the helper tool could not be used", bundle: RockxyLocalization.bundle)
        case .signingMismatch:
            HelperManager.signingMismatchWarningReason(issue: helperSigningIssue)
        }

        return ReadinessWarning(
            message: String(
                localized: """
                Rockxy is using direct macOS proxy changes because \(reason). \
                If Rockxy or Xcode stops unexpectedly, your Mac may stay behind a dead proxy until \
                Rockxy restores it. Install or repair the helper tool for safer automatic cleanup.
                """, bundle: RockxyLocalization.bundle
            ),
            action: .openAdvancedProxySettings,
            isDismissible: false
        )
    }

    /// TLS rejection warning based only on multiple-host evidence from one identified client.
    /// Unattributed connections are intentionally excluded because they cannot prove that the
    /// failures share one trust store.
    nonisolated static func tlsRejectionWarning(isSystemTrustValidated: Bool) -> ReadinessWarning {
        let detail = if isSystemTrustValidated {
            String(
                localized: """
                Rockxy could not decrypt multiple HTTPS hosts for one or more clients. \
                The macOS Root CA is trusted, so an affected client may use a separate trust store, certificate pinning, or TLS requirements Rockxy cannot intercept. \
                Connectivity continues through a client-scoped tunnel. Restart or configure that client before retrying interception.
                """, bundle: RockxyLocalization.bundle
            )
        } else {
            String(
                localized: """
                Rockxy could not decrypt multiple HTTPS hosts for one or more clients. \
                Check the Rockxy Root CA in Keychain Access and any client-specific trust store, then restart the affected client.
                """, bundle: RockxyLocalization.bundle
            )
        }
        return ReadinessWarning(
            message: detail,
            action: .retryHTTPSInterception,
            isDismissible: true
        )
    }

    private func tlsRejectionWarning() -> ReadinessWarning {
        Self.tlsRejectionWarning(
            isSystemTrustValidated: lastCertSnapshot?.isSystemTrustValidated == true
        )
    }

    nonisolated static func unattributedTLSRejectionWarning() -> ReadinessWarning {
        ReadinessWarning(
            message: String(
                localized: """
                Rockxy could not identify one or more local clients after TLS interception failed on multiple HTTPS hosts. \
                Their traffic remains tunneled. Restart the affected client, then review its trust store and HTTPS Decryption rules.
                """,
                bundle: RockxyLocalization.bundle
            ),
            action: .openHTTPSDecryption,
            isDismissible: true
        )
    }
}
