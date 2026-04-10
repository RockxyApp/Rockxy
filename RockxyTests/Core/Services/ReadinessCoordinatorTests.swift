import AppKit
import Foundation
@testable import Rockxy
import Testing

// MARK: - ReadinessCoordinatorTests

/// Tests use shared singleton state, so must run serially.
@Suite(.serialized)
struct ReadinessCoordinatorTests {
    // MARK: - Warning State Machine (fully deterministic, no machine-state dependency)

    @Test("no warning when capture is not active")
    @MainActor
    func noWarningWhenIdle() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(false)
        #expect(coordinator.activeWarning == nil)
    }

    @Test("proxy failure warning activates and clears correctly")
    @MainActor
    func proxyFailureLifecycle() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(true)

        coordinator.setProxyEnableFailed(message: "Port in use")
        #expect(coordinator.activeWarning != nil)
        #expect(coordinator.activeWarning?.action == .retry)
        #expect(coordinator.activeWarning?.message == "Port in use")
        #expect(coordinator.activeWarning?.isDismissible == true)

        coordinator.clearProxyEnableFailure()
        #expect(coordinator.activeWarning?.action != .retry)

        coordinator.setCaptureActive(false)
    }

    @Test("proxy failure has highest priority over other warnings")
    @MainActor
    func proxyFailurePriorityOverAll() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(true)

        coordinator.setProxyEnableFailed(message: "Test failure")
        #expect(coordinator.activeWarning?.action == .retry)
        #expect(coordinator.activeWarning?.message == "Test failure")

        coordinator.clearProxyEnableFailure()
        #expect(coordinator.activeWarning?.message != "Test failure")

        coordinator.setCaptureActive(false)
    }

    @Test("capture stop clears all transient warning state")
    @MainActor
    func captureStopClearsAllState() {
        let coordinator = ReadinessCoordinator.shared

        coordinator.setCaptureActive(true)
        coordinator.setProxyEnableFailed(message: "error")
        #expect(coordinator.activeWarning != nil)

        coordinator.setCaptureActive(false)
        #expect(coordinator.activeWarning == nil)
    }

    @Test("dismiss only works on dismissible warnings")
    @MainActor
    func dismissOnlyDismissible() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(true)

        coordinator.setProxyEnableFailed(message: "Port in use")
        #expect(coordinator.activeWarning?.isDismissible == true)
        coordinator.dismissWarning()
        #expect(coordinator.activeWarning == nil)

        coordinator.setCaptureActive(false)
    }

    @Test("warning transitions: failure → clear → next priority shown")
    @MainActor
    func warningTransitionSequence() async {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(true)
        await coordinator.refresh()

        let baselineWarning = coordinator.activeWarning

        coordinator.setProxyEnableFailed(message: "port conflict")
        #expect(coordinator.activeWarning?.action == .retry)

        coordinator.clearProxyEnableFailure()
        #expect(coordinator.activeWarning == baselineWarning)

        coordinator.setCaptureActive(false)
    }

    // MARK: - Derived Capabilities

    @Test("canInterceptHTTPS reflects cert readiness")
    @MainActor
    func canInterceptReflectsCert() {
        let coordinator = ReadinessCoordinator.shared
        #expect(coordinator.canInterceptHTTPS == (coordinator.certReadiness == .trusted))
    }

    @Test("hasOptimalProxyControl reflects helper readiness")
    @MainActor
    func optimalProxyControlReflectsHelper() {
        let coordinator = ReadinessCoordinator.shared
        #expect(coordinator.hasOptimalProxyControl == (coordinator.helperReadiness == .installedCompatible))
    }

    @Test("hasBlockingReadinessIssue false when idle")
    @MainActor
    func blockingIssueRequiresActiveCapture() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(false)
        #expect(coordinator.hasBlockingReadinessIssue == false)
    }

    // MARK: - TLS Rejection

    @Test("clearTLSRejections removes TLS rejection warning source")
    @MainActor
    func clearTLSRejectionsResets() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(true)
        coordinator.clearTLSRejections()
        if let warning = coordinator.activeWarning {
            #expect(!warning.message.contains("Multiple HTTPS hosts rejected"))
        }
        coordinator.setCaptureActive(false)
    }

    // MARK: - Observer Lifecycle

    @Test("startObserving is idempotent")
    @MainActor
    func startObservingIdempotent() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.startObserving()
        coordinator.startObserving()
        coordinator.startObserving()
        coordinator.stopObserving()
    }

    // MARK: - Notification Pipeline

    @Test("certificateStatusChanged notification refreshes cert snapshot")
    @MainActor
    func certNotificationRefreshesSnapshot() async throws {
        let coordinator = ReadinessCoordinator.shared
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        NotificationCenter.default.post(name: .certificateStatusChanged, object: nil)

        for _ in 0 ..< 60 {
            if coordinator.lastCertSnapshot != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(coordinator.lastCertSnapshot != nil)
    }

    @Test("helperStatusChanged notification refreshes helper state")
    @MainActor
    func helperNotificationRefreshesState() async throws {
        let coordinator = ReadinessCoordinator.shared
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        NotificationCenter.default.post(name: .helperStatusChanged, object: nil)

        for _ in 0 ..< 40 {
            if coordinator.helperReadiness == HelperManager.shared.status {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(coordinator.helperReadiness == HelperManager.shared.status)
    }

    @Test("app-active refresh updates cert state without proxy start")
    @MainActor
    func appActiveRefreshUpdatesCertState() async throws {
        let coordinator = ReadinessCoordinator.shared
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: nil
        )

        for _ in 0 ..< 100 {
            if coordinator.lastCertSnapshot != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(coordinator.lastCertSnapshot != nil)
    }

    @Test("activation refresh is skipped while one is already in flight")
    func activationRefreshIsSkippedWhenInFlight() {
        let clock = ContinuousClock()
        #expect(
            !ReadinessCoordinator.shouldPerformActivationDeepRefresh(
                lastCompletedAt: nil,
                now: clock.now,
                isInFlight: true
            )
        )
    }

    @Test("activation refresh is skipped during cooldown window")
    func activationRefreshIsSkippedDuringCooldown() {
        let clock = ContinuousClock()
        let now = clock.now
        let recent = now - .seconds(1)

        #expect(
            !ReadinessCoordinator.shouldPerformActivationDeepRefresh(
                lastCompletedAt: recent,
                now: now,
                isInFlight: false
            )
        )
    }

    @Test("activation refresh runs after cooldown window elapses")
    func activationRefreshRunsAfterCooldown() {
        let clock = ContinuousClock()
        let now = clock.now
        let earlier = now - .seconds(3)

        #expect(
            ReadinessCoordinator.shouldPerformActivationDeepRefresh(
                lastCompletedAt: earlier,
                now: now,
                isInFlight: false
            )
        )
    }

    // MARK: - State Consistency

    @Test("certReadiness is consistent with lastCertSnapshot after refresh")
    @MainActor
    func certReadinessMatchesSnapshotAfterRefresh() async throws {
        let coordinator = ReadinessCoordinator.shared
        await coordinator.refresh()

        let snapshot = try #require(coordinator.lastCertSnapshot)

        if snapshot.isSystemTrustValidated {
            #expect(coordinator.certReadiness == .trusted)
        } else if snapshot.hasTrustSettings || snapshot.isInstalledInKeychain {
            #expect(coordinator.certReadiness == .installedNotTrusted)
        } else if snapshot.hasGeneratedCertificate {
            #expect(coordinator.certReadiness == .generatedNotInstalled)
        } else {
            #expect(coordinator.certReadiness == .notGenerated)
        }
    }

    @Test("mid-capture passthrough matches cert readiness")
    @MainActor
    func midCaptureTrustChangeAffectsFuture() async {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(true)
        await coordinator.refresh()
        let passthrough = SSLProxyingManager.shared.forceGlobalPassthrough
        #expect(passthrough == !coordinator.canInterceptHTTPS)
        coordinator.setCaptureActive(false)
    }

    // MARK: - Integration

    @Test("clearSession resets selectedTransactionIDs")
    @MainActor
    func clearSessionResetsSelectedIDs() {
        let coordinator = MainContentCoordinator()
        coordinator.selectedTransactionIDs.insert(UUID())
        coordinator.selectedTransactionIDs.insert(UUID())
        #expect(coordinator.selectedTransactionIDs.count == 2)
        coordinator.clearSession()
        #expect(coordinator.selectedTransactionIDs.isEmpty)
    }
}

// MARK: - ReadinessWarningTests

struct ReadinessWarningTests {
    @Test("action titles are non-empty including reinstallAndTrust")
    func actionTitlesNonEmpty() {
        #expect(!ReadinessWarning.Action.retry.title.isEmpty)
        #expect(!ReadinessWarning.Action.openGeneralSettings.title.isEmpty)
        #expect(!ReadinessWarning.Action.openAdvancedProxySettings.title.isEmpty)
        #expect(!ReadinessWarning.Action.reinstallAndTrust.title.isEmpty)
    }

    @Test("cert-not-trusted warning uses reinstallAndTrust action")
    func certNotTrustedUsesReinstallAction() {
        let warning = ReadinessCoordinator.certNotTrustedWarning(
            certReadiness: .installedNotTrusted,
            isCaptureActive: true
        )
        #expect(warning != nil)
        #expect(warning?.action == .reinstallAndTrust)
        #expect(warning?.isDismissible == false)
    }

    @Test("cert-trusted state produces no cert warning")
    func certTrustedNoWarning() {
        let warning = ReadinessCoordinator.certNotTrustedWarning(
            certReadiness: .trusted,
            isCaptureActive: true
        )
        #expect(warning == nil)
    }

    @Test("cert warning suppressed when capture is not active")
    func certWarningRequiresActiveCapture() {
        let warning = ReadinessCoordinator.certNotTrustedWarning(
            certReadiness: .notGenerated,
            isCaptureActive: false
        )
        #expect(warning == nil)
    }

    @Test("CertReadiness descriptions are non-empty")
    func certReadinessDescriptions() {
        #expect(!CertReadiness.notGenerated.localizedDescription.isEmpty)
        #expect(!CertReadiness.generatedNotInstalled.localizedDescription.isEmpty)
        #expect(!CertReadiness.installedNotTrusted.localizedDescription.isEmpty)
        #expect(!CertReadiness.trusted.localizedDescription.isEmpty)
    }
}
