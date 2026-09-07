import Foundation
import NIOCore
import NIOEmbedded
import NIOHTTP1
@testable import Rockxy
import Testing

@Suite(.serialized, .sharedPolicyState)
@MainActor
struct ProxyDisplayStateTests {
    @Test("Coordinator reports stopped by default")
    func stoppedByDefault() {
        let coordinator = MainContentCoordinator()

        #expect(coordinator.proxyDisplayState == .stopped)
    }

    @Test("Coordinator reports starting while proxy startup is in flight")
    func startingDuringProxyStartup() {
        let coordinator = MainContentCoordinator()

        coordinator.isProxyStarting = true

        #expect(coordinator.proxyDisplayState == .starting)
    }

    @Test("Coordinator reports running after proxy start")
    func runningAfterProxyStart() {
        let coordinator = MainContentCoordinator()

        coordinator.isProxyRunning = true
        coordinator.isRecording = true

        #expect(coordinator.proxyDisplayState == .running)
    }

    @Test("Coordinator reports paused when proxy runs but recording is off")
    func pausedWhenRecordingOff() {
        let coordinator = MainContentCoordinator()

        coordinator.isProxyRunning = true
        coordinator.isRecording = false

        #expect(coordinator.proxyDisplayState == .paused)
    }

    @Test("Recording cannot be toggled while the proxy is stopped")
    func recordingToggleRequiresRunningProxy() {
        let coordinator = MainContentCoordinator()
        coordinator.isRecording = true

        coordinator.toggleRecording()

        #expect(coordinator.isRecording)

        coordinator.isProxyRunning = true
        coordinator.toggleRecording()

        #expect(!coordinator.isRecording)
    }

    @Test("Coordinator reports stopped after failed start clears startup state")
    func stoppedAfterFailedStart() {
        let coordinator = MainContentCoordinator()

        coordinator.isProxyStarting = false
        coordinator.isProxyRunning = false

        #expect(coordinator.proxyDisplayState == .stopped)
    }

    @Test("Proxy start remains gated until asynchronous stop cleanup finishes")
    func startGateIncludesStoppingState() {
        let coordinator = MainContentCoordinator()

        coordinator.isProxyStopping = true

        #expect(!coordinator.canStartProxy)
        #expect(coordinator.proxyDisplayState == .stopping)
        #expect(coordinator.proxyDisplayState.captureActionTitle == "Stopping…")
    }

    @Test("Capture presentation explains wildcard reachability and stopped readiness")
    func stoppedCapturePresentation() {
        let presentation = CaptureStatusPresentation(
            displayState: .stopped,
            listenAddress: "0.0.0.0",
            port: 8_888,
            certReadiness: .trusted,
            helperReadiness: .installedCompatible,
            isSystemProxyConfigured: false
        )

        #expect(presentation.title == "Capture Stopped")
        #expect(presentation.listener == "0.0.0.0:8888")
        #expect(presentation.listenerLabel == "Configured endpoint")
        #expect(presentation.listenerScope == "This Mac and local network")
        #expect(presentation.listenerScopeLabel == "Configured access")
        #expect(presentation.https.level == .ready)
        #expect(presentation.systemRouting.level == .ready)
        #expect(presentation.actionTitle == "Start Capture")
        #expect(presentation.isActionEnabled)
    }

    @Test("Stopped capture describes configured listener values without claiming they are live")
    func stoppedCaptureUsesConfiguredEndpointLabels() {
        let presentation = CaptureStatusPresentation(
            displayState: .stopped,
            listenAddress: "127.0.0.1",
            port: 8_888,
            certReadiness: .trusted,
            helperReadiness: .installedCompatible,
            isSystemProxyConfigured: false
        )

        #expect(presentation.listenerLabel == "Configured endpoint")
        #expect(presentation.listenerScopeLabel == "Configured access")
        #expect(presentation.listener == "127.0.0.1:8888")
    }

    @Test("Running capture surfaces degraded readiness without relying on color")
    func degradedRunningCapturePresentation() {
        let presentation = CaptureStatusPresentation(
            displayState: .running,
            listenAddress: "127.0.0.1",
            port: 9_090,
            certReadiness: .installedNotTrusted,
            helperReadiness: .notInstalled,
            isSystemProxyConfigured: false
        )

        #expect(presentation.title == "Capture Needs Attention")
        #expect(presentation.listenerScope == "This Mac only")
        #expect(presentation.https.level == .attention)
        #expect(presentation.https.value == "Root CA installed but not trusted")
        #expect(presentation.systemRouting.level == .attention)
        #expect(presentation.systemRouting.value == "Manual app setup")
        #expect(presentation.actionTitle == "Stop Capture")
    }

    @Test("Running listener never claims capture while the local path is unverified")
    func failedCaptureHealthPresentation() {
        let presentation = CaptureStatusPresentation(
            displayState: .running,
            listenAddress: "127.0.0.1",
            port: 8_888,
            certReadiness: .trusted,
            helperReadiness: .installedCompatible,
            isSystemProxyConfigured: true,
            captureHealth: .failed
        )

        #expect(presentation.title == "Capture Needs Attention")
        #expect(presentation.capturePath.level == .attention)
        #expect(presentation.capturePath.value == "Check failed")
    }

    @Test("Deliberate manual routing keeps capture truthful without a false warning header")
    func manualRoutingPresentation() {
        let presentation = CaptureStatusPresentation(
            displayState: .running,
            listenAddress: "127.0.0.1",
            port: 8_888,
            certReadiness: .trusted,
            helperReadiness: .installedCompatible,
            isSystemProxyConfigured: false,
            isSystemRoutingExpected: false,
            captureHealth: .verified
        )

        #expect(presentation.title == "Capturing Traffic")
        #expect(presentation.systemRouting.value == "Manual app setup")
    }

    @Test("Diagnostic transactions are consumed only for registered private tokens")
    func captureProbeTrackerIsolation() async {
        let tracker = CaptureProbeTracker()
        let generation = tracker.begin(token: "private-token")
        let diagnostic = HTTPTransaction(request: HTTPRequestData(
            method: "GET",
            url: URL(string: "http://127.0.0.1/probe")!,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: CaptureProbeTracker.headerName, value: "private-token")]
        ))
        let ordinary = HTTPTransaction(request: HTTPRequestData(
            method: "GET",
            url: URL(string: "http://127.0.0.1/ordinary")!,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: CaptureProbeTracker.headerName, value: "user-token")]
        ))

        #expect(!tracker.shouldBypassUserModifications(ordinary.request))
        #expect(tracker.shouldBypassUserModifications(diagnostic.request))
        let consumedOrdinary = tracker.consumeIfExpected(ordinary)
        let consumedDiagnostic = tracker.consumeIfExpected(diagnostic)
        let observed = tracker.wasObserved(generation: generation)

        #expect(!consumedOrdinary)
        #expect(consumedDiagnostic)
        #expect(observed)
    }

    @Test("Private health check traverses the real listener without polluting traffic")
    func captureHealthCheckIntegration() async throws {
        let coordinator = MainContentCoordinator()
        var settings = AppSettings()
        settings.onlyListenOnLocalhost = true
        settings.listenIPv6 = false
        settings.enableLogCapture = false
        let resolution = try ProxyPortResolver.resolve(
            preferred: 58_200,
            address: settings.effectiveListenAddress,
            autoSelect: true
        )

        await coordinator.configureProxy(port: resolution.port, settings: settings)
        let broadThrottle = ProxyRule(
            name: "Broad user throttle",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .throttle(delayMs: 10_000)
        )
        await RuleEngine.shared.addRule(broadThrottle)
        do {
            try await coordinator.proxyServer.start()
            coordinator.activeProxyPort = resolution.port
            coordinator.isProxyRunning = true
            coordinator.runCaptureHealthCheck()
            coordinator.runCaptureHealthCheck()

            for _ in 0 ..< 70 where coordinator.readiness.captureHealth == .checking {
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .milliseconds(200))

            #expect(coordinator.readiness.captureHealth == .verified)
            #expect(coordinator.transactions.isEmpty)
        } catch {
            await cleanUpCaptureHealthCheck(coordinator, ruleID: broadThrottle.id)
            throw error
        }
        await cleanUpCaptureHealthCheck(coordinator, ruleID: broadThrottle.id)
    }

    @Test("Health probe fails promptly when the peer closes before the response ends")
    func captureHealthProbeHandlesEarlyClose() throws {
        let channel = EmbeddedChannel()
        let promise = channel.eventLoop.makePromise(of: Bool.self)
        let requestHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/")
        let handler = CaptureHealthProbeResponseHandler(
            requestHead: requestHead,
            responsePromise: promise
        )
        try channel.pipeline.addHandler(handler).wait()

        try channel.close().wait()
        channel.embeddedEventLoop.run()

        #expect(throws: CaptureHealthProbeError.self) {
            _ = try promise.futureResult.wait()
        }
        _ = try? channel.finish(acceptAlreadyClosed: true)
    }

    @Test("Capture listener formats IPv6 endpoints without ambiguity")
    func ipv6ListenerFormatting() {
        #expect(CaptureStatusPresentation.listener(address: "::1", port: 8_888) == "[::1]:8888")
    }

    private func cleanUpCaptureHealthCheck(_ coordinator: MainContentCoordinator, ruleID: UUID) async {
        await RuleEngine.shared.removeRule(id: ruleID)
        coordinator.captureHealthTask?.cancel()
        await coordinator.captureProbeServer.stop()
        coordinator.captureProbeTracker.cancel()
        await coordinator.sessionManager.stopBatchTimer()
        await coordinator.proxyServer.stop()
        coordinator.isProxyRunning = false
        coordinator.readiness.setCaptureActive(false)
    }
}
