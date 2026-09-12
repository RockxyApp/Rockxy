import AppKit
import Foundation
@testable import Rockxy
import Testing

// MARK: - ReadinessCoordinatorTests

/// Tests use shared singleton state, so must run serially.
@Suite(.serialized, .sharedPolicyState)
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

    @Test("proxy restore failure is blocking and exposes the requested recovery action")
    @MainActor
    func proxyRestoreFailureLifecycle() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(false)
        coordinator.setCaptureActive(true)

        coordinator.setProxyRestoreFailed(retryAction: .retryStop)
        #expect(coordinator.activeWarning?.action == .retryStop)
        #expect(coordinator.activeWarning?.isDismissible == false)
        #expect(coordinator.activeWarning?.message.contains("Capture remains running") == true)

        coordinator.clearProxyRestoreFailure()
        #expect(coordinator.activeWarning?.action != .retryStop)
        coordinator.setCaptureActive(false)
    }

    @Test("capture stop clears proxy restore failure state")
    @MainActor
    func captureStopClearsProxyRestoreFailure() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(true)
        coordinator.setProxyRestoreFailed(retryAction: .retryDisableSystemRouting)
        #expect(coordinator.activeWarning?.action == .retryDisableSystemRouting)

        coordinator.setCaptureActive(false)
        #expect(coordinator.activeWarning == nil)
    }

    @Test("routing takeover remains visible after an enable failure clears")
    @MainActor
    func routingTakeoverWarning() {
        let coordinator = ReadinessCoordinator.shared
        defer { coordinator.setCaptureActive(false) }

        coordinator.setCaptureActive(false)
        coordinator.setSystemRoutingExpected(true)
        coordinator.setSystemRoutingReady(true)
        coordinator.setCaptureHealth(.verified)
        coordinator.setCaptureActive(true)

        coordinator.setSystemRoutingReady(false)

        #expect(coordinator.activeWarning?.action == .restoreSystemRouting)
        #expect(coordinator.hasBlockingReadinessIssue)
    }

    @Test("deliberate manual-app routing does not produce a takeover warning")
    @MainActor
    func deliberateManualRouting() {
        let coordinator = ReadinessCoordinator.shared
        defer {
            coordinator.setCaptureActive(false)
            coordinator.setSystemRoutingExpected(true)
        }

        coordinator.setCaptureActive(false)
        coordinator.setSystemRoutingExpected(false)
        coordinator.setSystemRoutingReady(false)
        coordinator.setCaptureHealth(.verified)
        coordinator.setCaptureActive(true)

        #expect(coordinator.activeWarning?.action != .restoreSystemRouting)
    }

    @Test("failed local capture check outranks lost system routing")
    @MainActor
    func captureHealthFailurePriority() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(false)
        coordinator.setSystemRoutingReady(false)
        coordinator.setCaptureActive(true)
        coordinator.setCaptureHealth(.failed)

        #expect(coordinator.activeWarning?.action == .retryCaptureCheck)
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

    @Test("refresh uses async proxy probe for proxy mode")
    @MainActor
    func refreshUsesAsyncProxyProbe() async {
        let coordinator = ReadinessCoordinator.shared
        coordinator.injectSystemProxyEnabledProbeForTests { true }
        defer { coordinator.resetSystemProxyEnabledProbeForTests() }

        await coordinator.refresh()

        #expect(coordinator.proxyMode == .direct)
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

    @Test("TLS rejection evidence never combines unrelated applications")
    func tlsRejectionEvidenceIsApplicationScoped() {
        var evidence = TLSRejectionEvidence()
        evidence.recordRejection(host: "one.example", clientIdentifier: "app.one")
        evidence.recordRejection(host: "two.example", clientIdentifier: "app.two")
        evidence.recordRejection(host: "three.example", clientIdentifier: "app.three")

        #expect(!evidence.hasMultiHostClientFailure)
    }

    @Test("three rejected hosts from one application produce trust evidence")
    func tlsRejectionEvidenceRequiresMultipleHostsFromOneApplication() {
        var evidence = TLSRejectionEvidence()
        let insertedFirstRejection = evidence.recordRejection(
            host: "one.example",
            clientIdentifier: "app.one"
        )
        evidence.recordRejection(host: "two.example", clientIdentifier: "app.one")
        evidence.recordRejection(host: "THREE.EXAMPLE", clientIdentifier: "app.one")
        let insertedDuplicateRejection = evidence.recordRejection(
            host: "three.example",
            clientIdentifier: "app.one"
        )

        #expect(insertedFirstRejection)
        #expect(!insertedDuplicateRejection)
        #expect(evidence.hasMultiHostClientFailure)
        #expect(evidence.rejectedHostsByClient["app.one"]?.count == 3)
    }

    @Test("successful interception clears only the matching host and application evidence")
    func tlsSuccessClearsOnlyMatchingHostEvidence() {
        var evidence = TLSRejectionEvidence()
        for host in ["one.example", "two.example", "three.example"] {
            evidence.recordRejection(host: host, clientIdentifier: "app.one")
            evidence.recordRejection(host: host, clientIdentifier: "app.two")
        }
        #expect(evidence.hasMultiHostClientFailure)

        evidence.recordSuccessfulHandshake(host: "one.example", clientIdentifier: "app.one")

        #expect(evidence.rejectedHostsByClient["app.one"] == ["two.example", "three.example"])
        #expect(evidence.rejectedHostsByClient["app.two"]?.count == 3)
        #expect(evidence.hasMultiHostClientFailure)
    }

    @Test("one accepted host does not suppress later pinned-host failures from the same application")
    func tlsSuccessDoesNotSuppressLaterPinnedHostFailures() {
        var evidence = TLSRejectionEvidence()
        evidence.recordRejection(host: "recovered.example", clientIdentifier: "app.one")
        let firstSuccess = evidence.recordSuccessfulHandshake(
            host: "recovered.example",
            clientIdentifier: "app.one"
        )
        let duplicateSuccess = evidence.recordSuccessfulHandshake(
            host: "recovered.example",
            clientIdentifier: "app.one"
        )
        #expect(firstSuccess)
        #expect(!duplicateSuccess)

        for host in ["pinned-one.example", "pinned-two.example", "pinned-three.example"] {
            evidence.recordRejection(host: host, clientIdentifier: "app.one")
        }

        #expect(evidence.rejectedHostsByClient["app.one"]?.count == 3)
        #expect(evidence.hasMultiHostClientFailure)
    }

    @Test("a new certificate epoch clears old rejection evidence before collecting fresh failures")
    func newCertificateEpochResetsRejectionEvidence() {
        var evidence = TLSRejectionEvidence()
        for host in ["old-one.example", "old-two.example", "old-three.example"] {
            evidence.recordRejection(host: host, clientIdentifier: "app.one")
        }
        #expect(evidence.hasMultiHostClientFailure)

        evidence.reset()
        #expect(!evidence.hasMultiHostClientFailure)
        for host in ["new-one.example", "new-two.example", "new-three.example"] {
            evidence.recordRejection(host: host, clientIdentifier: "app.one")
        }

        #expect(evidence.clientIdentifiersNeedingRetry == ["app.one"])
    }

    @Test("unattributed TLS rejections produce separate bounded evidence")
    func unattributedTLSRejectionsAreBounded() {
        var evidence = TLSRejectionEvidence()
        for host in ["one.example", "two.example", "three.example", "four.example", "five.example"] {
            evidence.recordRejection(host: host, clientIdentifier: nil)
        }

        #expect(!evidence.hasMultiHostClientFailure)
        #expect(evidence.rejectedHostsByClient.isEmpty)
        #expect(evidence.hasUnattributedMultiHostFailure)
        #expect(evidence.unattributedRejectedHosts.count == TLSRejectionEvidence.warningThreshold)
    }

    @Test("a later identified success clears the matching unattributed host")
    func identifiedSuccessClearsMatchingUnattributedEvidence() {
        var evidence = TLSRejectionEvidence()
        for host in ["one.example", "two.example", "three.example"] {
            evidence.recordRejection(host: host, clientIdentifier: nil)
        }
        #expect(evidence.hasUnattributedMultiHostFailure)

        evidence.recordSuccessfulHandshake(host: "TWO.EXAMPLE", clientIdentifier: "app.one")

        #expect(evidence.unattributedRejectedHosts == ["one.example", "three.example"])
        #expect(!evidence.hasUnattributedMultiHostFailure)
    }

    @Test("an unattributed success clears its host without suppressing a later identified client")
    func unattributedTLSSuccessClearsOnlyItsHost() {
        var evidence = TLSRejectionEvidence()
        evidence.recordRejection(host: "one.example", clientIdentifier: nil)

        let evidenceChanged = evidence.recordSuccessfulHandshake(
            host: "ONE.EXAMPLE",
            clientIdentifier: nil
        )
        #expect(evidenceChanged)
        #expect(evidence.unattributedRejectedHosts.isEmpty)

        evidence.recordRejection(host: "two.example", clientIdentifier: "app.one")
        #expect(evidence.rejectedHostsByClient["app.one"] == ["two.example"])
    }

    @Test("TLS rejection client evidence remains bounded")
    func tlsRejectionClientEvidenceRemainsBounded() {
        var evidence = TLSRejectionEvidence()
        for index in 0 ..< TLSRejectionEvidence.maximumTrackedClients {
            evidence.recordRejection(host: "one.example", clientIdentifier: "app.\(index)")
        }

        let overflowInserted = evidence.recordRejection(host: "one.example", clientIdentifier: "app.overflow")

        #expect(!overflowInserted)
        #expect(evidence.rejectedHostsByClient.count == TLSRejectionEvidence.maximumTrackedClients)
        #expect(evidence.rejectedHostsByClient["app.overflow"] == nil)
    }

    @Test("retry targets and clears only clients that reached the multi-host threshold")
    func tlsRetryTargetsAreClientScoped() {
        var evidence = TLSRejectionEvidence()
        for host in ["one.example", "two.example", "three.example"] {
            evidence.recordRejection(host: host, clientIdentifier: "APP.ONE")
            evidence.recordRejection(host: host, clientIdentifier: "app.two")
        }
        evidence.recordRejection(host: "single.example", clientIdentifier: "app.three")

        #expect(evidence.clientIdentifiersNeedingRetry == ["app.one", "app.two"])

        evidence.clearRejections(clientIdentifiers: ["App.One"])

        #expect(evidence.clientIdentifiersNeedingRetry == ["app.two"])
        #expect(evidence.rejectedHostsByClient["app.one"] == nil)
        #expect(evidence.rejectedHostsByClient["app.two"]?.count == 3)
        #expect(evidence.rejectedHostsByClient["app.three"] == ["single.example"])
    }

    @Test("clearTLSRejections removes TLS rejection warning source")
    @MainActor
    func clearTLSRejectionsResets() {
        let coordinator = ReadinessCoordinator.shared
        coordinator.setCaptureActive(true)
        coordinator.clearTLSRejections()
        #expect(coordinator.activeWarning?.action != .retryHTTPSInterception)
        coordinator.setCaptureActive(false)
    }

    @Test("capture start restores persisted client-scoped rejection evidence")
    @MainActor
    func captureStartRestoresPersistedRejectionEvidence() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-restored-rejections-\(UUID().uuidString)", isDirectory: true)
        let settingsURL = directory.appendingPathComponent("settings.json")
        let passthroughURL = directory.appendingPathComponent("passthrough.json")
        let firstRun = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        for host in ["one.example", "two.example", "three.example"] {
            firstRun.markHostForPassthrough(host, clientIdentifier: "app.one")
        }
        #expect(firstRun.flushPassthroughPersistence())
        let relaunched = SSLProxyingManager(
            storageURL: settingsURL,
            passthroughStorageURL: passthroughURL
        )
        let coordinator = ReadinessCoordinator.shared
        defer {
            coordinator.setCaptureActive(false)
            try? FileManager.default.removeItem(at: directory)
        }

        coordinator.setCaptureActive(true, sslProxyingManager: relaunched)

        #expect(coordinator.tlsRetryClientIdentifiers == ["app.one"])
    }

    @Test("HTTPS retry warning outranks direct-mode helper guidance")
    func tlsRetryOutranksDirectModeWarning() {
        var evidence = TLSRejectionEvidence()
        for host in ["one.example", "two.example", "three.example"] {
            evidence.recordRejection(host: host, clientIdentifier: "app.one")
        }

        let warning = ReadinessCoordinator.degradedCaptureWarning(
            tlsRejectionEvidence: evidence,
            isSystemTrustValidated: true,
            proxyMode: .direct,
            helperReadiness: .notInstalled,
            helperSigningIssue: nil
        )

        #expect(warning?.action == .retryHTTPSInterception)
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

    @Test("trust restoration clears sticky HTTPS fallbacks during capture")
    @MainActor
    func trustRestorationClearsFallbacks() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-trust-recovery-\(UUID().uuidString)", isDirectory: true)
        let manager = SSLProxyingManager(
            storageURL: directory.appendingPathComponent("settings.json"),
            passthroughStorageURL: directory.appendingPathComponent("passthrough.json")
        )
        let coordinator = ReadinessCoordinator.shared
        defer {
            coordinator.setCaptureActive(false)
            try? FileManager.default.removeItem(at: directory)
        }

        manager.reconcileCertificateState(isTrusted: false, fingerprint: "old")
        manager.markHostForPassthrough("sticky.example", clientIdentifier: "app.one")
        manager.markHostForTransientPassthrough("temporary.example", clientIdentifier: nil)
        coordinator.setCaptureActive(true)
        coordinator.reconcileTLSRecoveryAfterCertificateRefresh(
            previousReadiness: .installedNotTrusted,
            currentReadiness: .trusted,
            previousFingerprint: "old",
            currentFingerprint: "old",
            sslProxyingManager: manager
        )

        #expect(!manager.isAutoPassthrough("sticky.example", clientIdentifier: "app.one"))
        #expect(!manager.isAutoPassthrough("temporary.example", clientIdentifier: nil))
    }

    @Test("same trusted certificate epoch preserves client-scoped fallback")
    @MainActor
    func unchangedCertificateEpochPreservesFallback() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-same-trust-\(UUID().uuidString)", isDirectory: true)
        let manager = SSLProxyingManager(
            storageURL: directory.appendingPathComponent("settings.json"),
            passthroughStorageURL: directory.appendingPathComponent("passthrough.json")
        )
        let coordinator = ReadinessCoordinator.shared
        defer {
            coordinator.setCaptureActive(false)
            try? FileManager.default.removeItem(at: directory)
        }

        manager.reconcileCertificateState(isTrusted: true, fingerprint: "same")
        manager.markHostForPassthrough("pinned.example", clientIdentifier: "app.one")
        coordinator.setCaptureActive(true)
        coordinator.reconcileTLSRecoveryAfterCertificateRefresh(
            previousReadiness: .trusted,
            currentReadiness: .trusted,
            previousFingerprint: "same",
            currentFingerprint: "same",
            sslProxyingManager: manager
        )

        #expect(manager.isAutoPassthrough("pinned.example", clientIdentifier: "app.one"))
    }

    @Test("rotating a trusted Root CA clears fallbacks tied to the old identity")
    @MainActor
    func trustedCertificateRotationClearsFallback() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-rotated-trust-\(UUID().uuidString)", isDirectory: true)
        let manager = SSLProxyingManager(
            storageURL: directory.appendingPathComponent("settings.json"),
            passthroughStorageURL: directory.appendingPathComponent("passthrough.json")
        )
        let coordinator = ReadinessCoordinator.shared
        defer {
            coordinator.setCaptureActive(false)
            try? FileManager.default.removeItem(at: directory)
        }

        manager.reconcileCertificateState(isTrusted: true, fingerprint: "old-fingerprint")
        manager.markHostForPassthrough("old-ca.example", clientIdentifier: "app.one")
        coordinator.setCaptureActive(true)
        coordinator.reconcileTLSRecoveryAfterCertificateRefresh(
            previousReadiness: .trusted,
            currentReadiness: .trusted,
            previousFingerprint: "old-fingerprint",
            currentFingerprint: "new-fingerprint",
            sslProxyingManager: manager
        )

        #expect(!manager.isAutoPassthrough("old-ca.example", clientIdentifier: "app.one"))
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

    @Test("signing issue subtype change propagates through notification path")
    @MainActor
    func signingIssueSubtypeChangePropagates() async throws {
        let coordinator = ReadinessCoordinator.shared
        let manager = HelperManager.shared
        coordinator.startObserving()

        // Wrap assertions so cleanup always runs even on thrown errors.
        var caughtError: (any Error)?
        do {
            // First state: signingMismatch + appSignatureInvalid
            manager.injectHelperStateForTests(
                status: .signingMismatch,
                signingIssue: .appSignatureInvalid(detail: "stale")
            )

            for _ in 0 ..< 40 {
                if coordinator.helperSigningIssue == .appSignatureInvalid(detail: "stale") {
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(coordinator.helperReadiness == .signingMismatch)
            #expect(coordinator.helperSigningIssue == .appSignatureInvalid(detail: "stale"))

            // Subtype-only change: same status, different issue
            manager.injectHelperStateForTests(
                status: .signingMismatch,
                signingIssue: .identityMismatch(appSigner: "Dev", helperSigner: "Prod")
            )

            for _ in 0 ..< 40 {
                if coordinator.helperSigningIssue == .identityMismatch(
                    appSigner: "Dev",
                    helperSigner: "Prod"
                ) {
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(coordinator.helperReadiness == .signingMismatch)
            #expect(
                coordinator.helperSigningIssue == .identityMismatch(
                    appSigner: "Dev",
                    helperSigner: "Prod"
                )
            )
        } catch {
            caughtError = error
        }

        // Async cleanup: reset baseline and wait for the coordinator to reflect
        // it before stopping the observer. Uses try? so cleanup itself cannot throw.
        manager.injectHelperStateForTests(
            status: .notInstalled,
            signingIssue: nil,
            isReachable: false,
            installedInfo: nil,
            lastErrorMessage: nil
        )
        for _ in 0 ..< 40 {
            if coordinator.helperReadiness == .notInstalled,
               coordinator.helperSigningIssue == nil
            {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        coordinator.stopObserving()

        if let caughtError {
            throw caughtError
        }
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

        if snapshot.isStatusUnavailable {
            // The booleans below are fail-closed defaults for a read that did not complete, so
            // the readiness has to say "unknown" rather than pick one of them.
            #expect(coordinator.certReadiness == .unknown)
        } else if snapshot.isSystemTrustValidated {
            #expect(coordinator.certReadiness == .trusted)
        } else if snapshot.hasTrustSettings || snapshot.isInstalledInKeychain {
            #expect(coordinator.certReadiness == .installedNotTrusted)
        } else if snapshot.hasGeneratedCertificate {
            #expect(coordinator.certReadiness == .generatedNotInstalled)
        } else {
            #expect(coordinator.certReadiness == .notGenerated)
        }
    }

    @Test("forced trust revalidation refreshes the snapshot and derived capability")
    @MainActor
    func forcedTrustRevalidationRefreshesSnapshot() async throws {
        let coordinator = ReadinessCoordinator.shared
        // This path never requests installation or changes trust settings. Positive trust
        // metadata triggers SecTrust evaluation; known absence fails closed before that work.
        await coordinator.refreshCertificateTrustValidation()

        let snapshot = try #require(coordinator.lastCertSnapshot)
        #expect(coordinator.canInterceptHTTPS == snapshot.isSystemTrustValidated)
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
    func clearSessionResetsSelectedIDs() async {
        let coordinator = MainContentCoordinator()
        coordinator.selectedTransactionIDs.insert(UUID())
        coordinator.selectedTransactionIDs.insert(UUID())
        let workspace = coordinator.workspaceStore.createWorkspace(title: "Other")
        coordinator.selectedTransactionIDs.insert(UUID())
        #expect(coordinator.workspaceStore.workspaces[0].selectedTransactionIDs.count == 2)
        #expect(coordinator.selectedTransactionIDs.count == 1)
        await coordinator.clearSession()
        #expect(coordinator.selectedTransactionIDs.isEmpty)
        #expect(coordinator.workspaceStore.workspaces[0].selectedTransactionIDs.isEmpty)
        #expect(workspace.selectedTransactionIDs.isEmpty)
    }
}

// MARK: - ReadinessWarningTests

struct ReadinessWarningTests {
    @Test("action titles are non-empty including TLS retry and reinstallAndTrust")
    func actionTitlesNonEmpty() {
        #expect(!ReadinessWarning.Action.retry.title.isEmpty)
        #expect(!ReadinessWarning.Action.retryHTTPSInterception.title.isEmpty)
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

    @Test("TLS rejection warning retries interception instead of reinstalling the certificate")
    func tlsRejectionWarningOffersInterceptionRetry() {
        let warning = ReadinessCoordinator.tlsRejectionWarning(isSystemTrustValidated: true)

        #expect(warning.action == .retryHTTPSInterception)
        #expect(warning.isDismissible)
        #expect(warning.message.contains("Root CA is trusted"))
    }

    @Test("unattributed TLS warning does not clear another client's recovery state")
    func unattributedTLSWarningOpensConfiguration() {
        let warning = ReadinessCoordinator.unattributedTLSRejectionWarning()

        #expect(warning.action == .openHTTPSDecryption)
        #expect(warning.isDismissible)
        #expect(warning.message.contains("could not identify"))
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
        #expect(!CertReadiness.unknown.localizedDescription.isEmpty)
    }

    @Test("each readable certificate state names the step that is actually missing")
    func readableCertStatesProduceDistinctWarnings() throws {
        let notGenerated = try #require(ReadinessCoordinator.certNotTrustedWarning(
            certReadiness: .notGenerated,
            isCaptureActive: true
        ))
        let generatedNotInstalled = try #require(ReadinessCoordinator.certNotTrustedWarning(
            certReadiness: .generatedNotInstalled,
            isCaptureActive: true
        ))
        let installedNotTrusted = try #require(ReadinessCoordinator.certNotTrustedWarning(
            certReadiness: .installedNotTrusted,
            isCaptureActive: true
        ))
        let unknown = try #require(ReadinessCoordinator.certNotTrustedWarning(
            certReadiness: .unknown,
            isCaptureActive: true
        ))

        // Each readable state describes its own missing step. "Not trusted" for a root that was
        // never generated, or for one that is in no keychain, names a decision the user never made.
        #expect(notGenerated.message.contains("has not been generated"))
        #expect(generatedNotInstalled.message.contains("not installed in the login or System keychain"))
        #expect(installedNotTrusted.message.contains("SSL trust or client compatibility checks"))

        let messages = [
            notGenerated.message,
            generatedNotInstalled.message,
            installedNotTrusted.message,
            unknown.message,
        ]
        #expect(Set(messages).count == messages.count)

        for warning in [notGenerated, generatedNotInstalled, installedNotTrusted, unknown] {
            // HTTP and log capture keep running in every one of these states, and none of the
            // warnings may be dismissed away while HTTPS interception is paused.
            #expect(warning.message.contains("HTTP traffic and logs are still captured"))
            #expect(warning.isDismissible == false)
        }

        // The recovery stays as it was: a readable missing step offers the install, an
        // unreadable status offers only a recheck.
        #expect(notGenerated.action == .reinstallAndTrust)
        #expect(generatedNotInstalled.action == .reinstallAndTrust)
        #expect(installedNotTrusted.action == .reinstallAndTrust)
        #expect(unknown.action == .openGeneralSettings)
    }

    @Test("no certificate warning is produced while capture is idle, in any readable state")
    func certWarningsRequireActiveCaptureInEveryState() {
        for readiness in [
            CertReadiness.notGenerated,
            .generatedNotInstalled,
            .installedNotTrusted,
            .trusted,
            .unknown,
        ] {
            #expect(
                ReadinessCoordinator.certNotTrustedWarning(
                    certReadiness: readiness,
                    isCaptureActive: false
                ) == nil
            )
        }
    }

    @Test("a trusted root produces no certificate warning during capture")
    func trustedRootProducesNoWarningDuringCapture() {
        #expect(
            ReadinessCoordinator.certNotTrustedWarning(
                certReadiness: .trusted,
                isCaptureActive: true
            ) == nil
        )
    }

    @Test("an unreadable cert status warns that verification failed and offers a status check")
    func unknownCertReadinessOffersStatusCheck() throws {
        let warning = try #require(ReadinessCoordinator.certNotTrustedWarning(
            certReadiness: .unknown,
            isCaptureActive: true
        ))

        // Not "Install & Trust": that would ask for administrator approval on the strength of a
        // read that failed. Capture stays up for HTTP.
        #expect(warning.action == .openGeneralSettings)
        #expect(warning.isDismissible == false)
        #expect(warning.message.contains("cannot verify"))
        #expect(warning.message.contains("HTTP traffic and logs are still captured"))
        // A known-untrusted root still offers the install, so the two paths stay distinct.
        #expect(ReadinessCoordinator.certNotTrustedWarning(
            certReadiness: .installedNotTrusted,
            isCaptureActive: true
        )?.action == .reinstallAndTrust)
    }
}

// MARK: - ProxyStartTrustValidationContractTests

/// Source-contract coverage for the Start Capture trust gate.
///
/// Starting the real proxy would bind a port, replace the system proxy configuration, and
/// launch a second capture session on this machine, so the call path is pinned at the source
/// level instead: capture start must force a fresh trust resolution (including real `SecTrust`
/// evaluation when trust metadata is present) before it decides global passthrough and before the
/// server accepts connections. A cached negative recorded before the user approved the root would
/// otherwise pass every HTTPS connection through for the whole session.
struct ProxyStartTrustValidationContractTests {
    // MARK: Internal

    @Test("Start Capture forces certificate revalidation before passthrough and server start")
    func startProxyForcesFreshTrustValidation() throws {
        let source = try String(
            contentsOf: resolveProjectRoot()
                .appendingPathComponent("Rockxy/Views/Main/Extensions/MainContentCoordinator+ProxyControl.swift"),
            encoding: .utf8
        )
        let startBody = try #require(bodyOfStartProxy(in: source))

        let validation = try #require(startBody.range(of: "await readiness.refreshCertificateTrustValidation()"))
        let passthrough = try #require(
            startBody.range(of: "SSLProxyingManager.shared.forceGlobalPassthrough = !readiness.canInterceptHTTPS")
        )
        let serverStart = try #require(startBody.range(of: "try await proxyServer.start()"))

        #expect(validation.upperBound <= passthrough.lowerBound)
        #expect(passthrough.upperBound <= serverStart.lowerBound)
        // The cheap cached refresh must not be what decides this gate.
        #expect(!startBody.contains("await readiness.refresh()"))
    }

    @Test("the forced revalidation entry point requests fresh validation")
    func forcedRevalidationRequestsRealValidation() throws {
        let source = try String(
            contentsOf: resolveProjectRoot()
                .appendingPathComponent("Rockxy/Core/Services/ReadinessCoordinator.swift"),
            encoding: .utf8
        )
        let declaration = try #require(source.range(of: "func refreshCertificateTrustValidation() async {"))
        let body = source[declaration.upperBound...].prefix(400)

        #expect(body.contains("refreshCertState(performValidation: true)"))
    }

    // MARK: Private

    private enum ContractError: Error {
        case rootNotFound(filePath: String)
    }

    /// The text of `startProxy()`, bounded by the next function declaration so later lifecycle
    /// code cannot satisfy or break an ordering assertion about capture start.
    private func bodyOfStartProxy(in source: String) -> String? {
        guard let start = source.range(of: "func startProxy() {") else {
            return nil
        }
        let remainder = source[start.upperBound...]
        guard let end = remainder.range(of: "func stopProxy() {") else {
            return String(remainder)
        }
        return String(remainder[..<end.lowerBound])
    }

    private func resolveProjectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        guard url.lastPathComponent == "RockxyTests" else {
            throw ContractError.rootNotFound(filePath: #filePath)
        }
        url.deleteLastPathComponent()
        return url
    }
}
