import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import os

// Extends `MainContentCoordinator` with proxy control behavior for the main workspace.

// MARK: - ProxyOverrideReconciliation

/// Result of comparing a live system proxy override with this session's proxy port.
struct ProxyOverrideReconciliation: Equatable, Sendable {
    let isOverridden: Bool
    let matchesActiveProxyPort: Bool
}

// MARK: - CaptureProbeTracker

/// Keeps the diagnostic request out of the user's session while proving that the live
/// proxy completed it. A small lock keeps NIO callbacks safe to compare with the
/// main-actor health-check task without introducing asynchronous callback races.
final class CaptureProbeTracker: @unchecked Sendable {
    func begin(token: String) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        expectedToken = token
        diagnosticTokens.insert(token)
        diagnosticTokenOrder.append(token)
        if diagnosticTokenOrder.count > Self.maximumRetainedTokens {
            diagnosticTokens.remove(diagnosticTokenOrder.removeFirst())
        }
        observedGeneration = nil
        return generation
    }

    func consumeIfExpected(_ transaction: HTTPTransaction) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let token = transaction.request.headers.first(where: {
            $0.name.caseInsensitiveCompare(Self.headerName) == .orderedSame
        })?.value,
            diagnosticTokens.contains(token)
        else {
            return false
        }

        if token == expectedToken {
            observedGeneration = generation
            expectedToken = nil
        }
        diagnosticTokens.remove(token)
        diagnosticTokenOrder.removeAll { $0 == token }
        return true
    }

    func wasObserved(generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return observedGeneration == generation
    }

    func shouldBypassUserModifications(_ request: HTTPRequestData) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let token = request.headers.first(where: {
            $0.name.caseInsensitiveCompare(Self.headerName) == .orderedSame
        })?.value else {
            return false
        }
        return diagnosticTokens.contains(token)
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        expectedToken = nil
        observedGeneration = nil
        diagnosticTokens.removeAll()
        diagnosticTokenOrder.removeAll()
    }

    nonisolated static let headerName = "X-Rockxy-Capture-Probe"

    private static let maximumRetainedTokens = 8
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var expectedToken: String?
    private var observedGeneration: UInt64?
    private var diagnosticTokens: Set<String> = []
    private var diagnosticTokenOrder: [String] = []
}

// MARK: - MainContentCoordinator + ProxyControl

/// Coordinator extension for proxy server lifecycle: start, stop, recording toggle,
/// session clearing, and the NIO proxy configuration pipeline. Incoming transactions
/// flow through `TrafficSessionManager` which batches updates (every 100ms or 50
/// transactions) before delivering them to the main actor to avoid UI churn.
extension MainContentCoordinator {
    // MARK: - Proxy Lifecycle

    /// Revalidates the active Root CA before removing protected TLS fallbacks. Clearing
    /// auto-passthrough posts the policy-change notification that closes matching live raw
    /// tunnels, so the client's next CONNECT can attempt interception immediately.
    func retryHTTPSInterception() {
        guard isProxyRunning,
              !isProxyStopping,
              !isRetryingHTTPSInterception
        else {
            return
        }
        let clientIdentifiers = readiness.tlsRetryClientIdentifiers
        guard !clientIdentifiers.isEmpty else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(
                    localized: "No HTTPS interception recovery is pending.",
                    bundle: RockxyLocalization.bundle
                )
            )
            return
        }

        httpsInterceptionRetryGeneration &+= 1
        let retryGeneration = httpsInterceptionRetryGeneration
        let readiness = self.readiness
        isRetryingHTTPSInterception = true
        httpsInterceptionRetryTask = Task { [weak self] in
            await readiness.refreshCertificateTrustValidation()
            guard let self else {
                return
            }
            defer {
                if self.httpsInterceptionRetryGeneration == retryGeneration {
                    self.isRetryingHTTPSInterception = false
                    self.httpsInterceptionRetryTask = nil
                }
            }
            guard !Task.isCancelled,
                  httpsInterceptionRetryGeneration == retryGeneration,
                  isProxyRunning,
                  !isProxyStopping,
                  readiness.isCaptureActive
            else {
                return
            }
            guard readiness.canInterceptHTTPS else {
                activeToast = ToastMessage(
                    style: .error,
                    text: ReadinessCoordinator.certNotTrustedWarning(
                        certReadiness: readiness.certReadiness,
                        isCaptureActive: true
                    )?.message ?? String(
                        localized: "Rockxy cannot verify the Root CA trust status, so HTTPS interception is paused. HTTP traffic and logs are still captured.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                return
            }

            // Keep the retry scoped to the clients represented by this warning. Clearing the
            // suppression cache before invalidating their tunnels ensures a persistent rejection
            // can produce fresh evidence instead of disappearing behind the previous 30-second
            // duplicate window.
            readiness.clearTLSRejections(clientIdentifiers: clientIdentifiers)
            RecentFailureTracker.certificateRejections.reset(clientIdentifiers: clientIdentifiers)
            SSLProxyingManager.shared.retryInterception(
                clientIdentifiers: clientIdentifiers
            )
            activeToast = ToastMessage(
                style: .success,
                text: String(
                    localized: "HTTPS retry is ready. Repeat the request or reconnect the affected client.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    func startProxy() {
        guard canStartProxy else {
            return
        }
        proxyError = nil
        isProxyStarting = true
        readiness.clearProxyRestoreFailure()
        RecentFailureTracker.certificateRejections.reset()

        proxyStartTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                isProxyStarting = false
                proxyStartTask = nil
            }

            guard await ensureProjectCatalogReadyForDataIntake() else {
                proxyError = String(
                    localized: "Projects could not be loaded. Repair Projects before starting capture.",
                    bundle: RockxyLocalization.bundle
                )
                return
            }

            let settings = AppSettingsStorage.load()
            do {
                try await certificateManager.ensureRootCA()
                Self.logger.info("Root CA ready")

                await certificateManager.validateCertificateChain()

                // Evaluate certificate trust via the readiness layer, forcing a fresh trust-state
                // resolution and a real SecTrust evaluation when positive trust metadata exists.
                // The cheap refresh can answer from a cached negative recorded before the user
                // approved the root, and that stale answer would pass every HTTPS connection
                // through for the whole session.
                // Only new HTTPS connections are affected — existing TLS sessions
                // are not re-intercepted after trust changes.
                await readiness.refreshCertificateTrustValidation()
                SSLProxyingManager.shared.forceGlobalPassthrough = !readiness.canInterceptHTTPS
                if !readiness.canInterceptHTTPS {
                    Self.logger.warning(
                        "Root CA failed SSL trust or client compatibility validation — all HTTPS passes through"
                    )
                } else {
                    if await certificateManager.rootCAFreshlyInstalled {
                        SSLProxyingManager.shared.clearAutoPassthrough()
                        await certificateManager.clearFreshlyInstalledFlag()
                    }
                }

                await ensureRulesLoaded()
                Self.logger.info("Rules loaded")

                let resolution = try ProxyPortResolver.resolve(
                    preferred: settings.proxyPort,
                    address: settings.effectiveListenAddress,
                    autoSelect: settings.autoSelectPort,
                    listenIPv6: settings.listenIPv6
                )
                let resolvedPort = resolution.port
                self.activeProxyPort = resolvedPort

                if resolution.isFallback {
                    Self.logger.info(
                        "Preferred port \(settings.proxyPort) occupied, using fallback port \(resolvedPort)"
                    )
                }

                // Configure with the exact settings snapshot resolved above so
                // the running server cannot drift from a settings reload mid-start.
                await configureProxy(port: resolvedPort, settings: settings)

                try await proxyServer.start()
                await sessionManager.startBatchTimer()
                isProxyRunning = true
                proxyStartedAt = Date()
                runtimeListenerSnapshot = ProxyListenerSnapshot(
                    requestedPort: settings.proxyPort,
                    resolvedPort: resolvedPort,
                    listenAddress: settings.effectiveListenAddress,
                    autoSelectPort: settings.autoSelectPort
                )
                startBandwidthTimer()
                startLogCapture()

                evictionObserver = NotificationCenter.default.addObserver(
                    forName: .bufferEvictionRequested,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let self else {
                        return
                    }
                    let count = notification.userInfo?["count"] as? Int ?? Int(5e3)
                    Task { @MainActor in
                        self.evictOldestTransactions(count: count)
                    }
                }

                readiness.startObserving()
                readiness.setSystemRoutingExpected(true)

                Self.logger.info("Configuring system proxy...")
                do {
                    try await SystemProxyManager.shared.enableSystemProxy(port: resolvedPort)
                    isSystemProxyConfigured = true
                    isProxyOverridden = true
                    readiness.setSystemRoutingReady(true)
                    Self.logger.info("System proxy enabled on port \(resolvedPort)")
                } catch {
                    isSystemProxyConfigured = false
                    isProxyOverridden = false
                    readiness.setSystemRoutingReady(false)
                    readiness.setProxyEnableFailed(message: error.localizedDescription)
                    Self.logger.warning(
                        "System proxy not configured: \(error.localizedDescription). Proxy still running on 127.0.0.1:\(resolvedPort)"
                    )
                }

                readiness.setCaptureActive(true)
                runCaptureHealthCheck()

                NotificationCenter.default.post(name: .proxyDidStart, object: nil)
                Self.logger.info("Proxy started on port \(resolvedPort)")
            } catch {
                Self.logger.error("Failed to start proxy: \(error.localizedDescription)")
                proxyError = error.localizedDescription
                activeProxyPort = settings.proxyPort
            }
        }
    }

    /// Makes the Welcome system-routing action safe when capture is stopped. The listener is
    /// started first, its exact resolved port is awaited, and only then may macOS routing change.
    /// This also coalesces with an in-flight start instead of enabling a configured-but-dead port.
    func enableSystemProxyFromWelcome() async throws {
        if !isProxyRunning {
            if canStartProxy {
                startProxy()
            }
            if let proxyStartTask {
                await proxyStartTask.value
            }
        }

        guard isProxyRunning else {
            throw NSError(
                domain: RockxyIdentity.current.appBundleIdentifier,
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: proxyError ?? String(
                        localized: "System routing is unavailable while the proxy server is stopped.",
                        bundle: RockxyLocalization.bundle
                    ),
                ]
            )
        }

        guard !isSystemProxyConfigured else {
            return
        }

        readiness.clearProxyEnableFailure()
        readiness.setSystemRoutingExpected(true)
        do {
            try await SystemProxyManager.shared.enableSystemProxy(port: activeProxyPort)
            isSystemProxyConfigured = true
            isProxyOverridden = true
            readiness.setSystemRoutingReady(true)
            runCaptureHealthCheck()
        } catch {
            isSystemProxyConfigured = false
            isProxyOverridden = false
            readiness.setSystemRoutingReady(false)
            readiness.setProxyEnableFailed(message: error.localizedDescription)
            throw error
        }
    }

    func stopProxy() {
        guard isProxyRunning, !isProxyStopping else {
            return
        }
        isProxyStopping = true
        captureHealthTask?.cancel()
        captureHealthTask = nil
        proxyConfigurationRefreshTask?.cancel()
        proxyConfigurationRefreshTask = nil
        httpsInterceptionRetryGeneration &+= 1
        httpsInterceptionRetryTask?.cancel()
        httpsInterceptionRetryTask = nil
        isRetryingHTTPSInterception = false
        let serverToStop = proxyServer
        let probeServer = captureProbeServer
        let probeTracker = captureProbeTracker

        Task {
            defer {
                isProxyStopping = false
            }
            do {
                try await SystemProxyManager.shared.disableSystemProxy()
                readiness.clearProxyRestoreFailure()
                Self.logger.info("System proxy disabled")
            } catch {
                Self.logger.error("Failed to restore proxy: \(error.localizedDescription)")
                readiness.setProxyRestoreFailed(retryAction: .retryStop)
                isProxyStopping = false
                _ = await reconcileProxyOverrideStatus()
                runCaptureHealthCheck()
                return
            }

            isProxyRunning = false
            if let evictionObserver {
                NotificationCenter.default.removeObserver(evictionObserver)
                self.evictionObserver = nil
            }
            probeTracker.cancel()
            await probeServer.stop()
            isSystemProxyConfigured = false
            isProxyOverridden = false
            readiness.setCaptureActive(false)
            SSLProxyingManager.shared.forceGlobalPassthrough = false

            // Order matters. Stopping the server closes every downstream channel first,
            // which fires each handler's `channelInactive`/cancellation path and drains
            // the paused item with `.cancel`. Only after the channels are inactive do we
            // run `resolveAll(.cancel)` as a fallback for any item that outlived its
            // channel: by then the handler's `channel.isActive` gate is false, so the
            // resolution can never forward the original request to the origin. Resolving
            // before the stop would complete promises while channels were still active
            // and initiate exactly that origin work.
            await serverToStop.stop()
            breakpointManager.resolveAll(decision: .cancel)
            stopLogCapture()
            stopBandwidthTimer()
            resetInstantaneousSpeeds()
            proxyStartedAt = nil
            runtimeListenerSnapshot = nil
            activeProxyPort = AppSettingsStorage.load().proxyPort
            NotificationCenter.default.post(name: .proxyDidStop, object: nil)
            Self.logger.info("Proxy stopped")
        }
    }

    func toggleRecording() {
        guard isProxyRunning else {
            return
        }
        isRecording.toggle()
    }

    /// Sends a private, synthetic HTTP request through the live listener to a loopback-only
    /// origin. Passing requires both a real HTTP response and observation of the completed
    /// transaction inside `ProxyServer`; the diagnostic transaction is consumed before it can
    /// enter the user's session buffer.
    func runCaptureHealthCheck() {
        guard isProxyRunning, !isProxyStopping else {
            return
        }

        captureHealthTask?.cancel()
        readiness.setCaptureHealth(.checking)

        let proxyPort = activeProxyPort
        let probeServer = captureProbeServer
        let probeTracker = captureProbeTracker
        captureHealthTask = Task { @MainActor [weak self] in
            var activeProbeSession: DeveloperSetupProbeSession?
            do {
                let probeSession = try await probeServer.start(targetID: .curl)
                activeProbeSession = probeSession
                try Task.checkCancellation()
                let generation = probeTracker.begin(token: probeSession.token)
                let receivedHTTPResponse = try await Self.performCaptureHealthProbe(
                    session: probeSession,
                    proxyPort: proxyPort
                )

                var observed = probeTracker.wasObserved(generation: generation)
                for _ in 0 ..< 20 where !observed {
                    try await Task.sleep(for: .milliseconds(50))
                    observed = probeTracker.wasObserved(generation: generation)
                }

                await probeServer.stop(ifCurrent: probeSession)
                try Task.checkCancellation()
                guard let self, self.isProxyRunning, self.activeProxyPort == proxyPort else {
                    return
                }
                self.readiness.setCaptureHealth(receivedHTTPResponse && observed ? .verified : .failed)
            } catch is CancellationError {
                if let activeProbeSession {
                    await probeServer.stop(ifCurrent: activeProbeSession)
                }
            } catch {
                if let activeProbeSession {
                    await probeServer.stop(ifCurrent: activeProbeSession)
                }
                guard !Task.isCancelled,
                      let self,
                      self.isProxyRunning,
                      self.activeProxyPort == proxyPort
                else {
                    return
                }
                Self.logger.warning("Capture health check failed: \(error.localizedDescription)")
                self.readiness.setCaptureHealth(.failed)
            }
        }
    }

    nonisolated static func performCaptureHealthProbe(
        session: DeveloperSetupProbeSession,
        proxyPort: Int
    ) async throws
        -> Bool
    {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let responsePromise = group.next().makePromise(of: Bool.self)

        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(DeveloperSetupProbeSession.host):\(session.port)")
        headers.add(name: CaptureProbeTracker.headerName, value: session.token)
        headers.add(name: "Connection", value: "close")
        let requestHead = HTTPRequestHead(
            version: .http1_1,
            method: .GET,
            uri: session.url.absoluteString,
            headers: headers
        )
        let responseHandler = CaptureHealthProbeResponseHandler(
            requestHead: requestHead,
            responsePromise: responsePromise
        )

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(4))
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(responseHandler)
                }
            }

        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: "127.0.0.1", port: proxyPort).get()
        } catch {
            responsePromise.fail(error)
            try? await group.shutdownGracefully()
            throw error
        }

        let timeout = channel.eventLoop.scheduleTask(in: .seconds(5)) {
            responseHandler.timeout()
        }

        do {
            let receivedHTTPResponse = try await responsePromise.futureResult.get()
            timeout.cancel()
            try? await channel.close().get()
            try? await group.shutdownGracefully()
            return receivedHTTPResponse
        } catch {
            timeout.cancel()
            try? await channel.close().get()
            try? await group.shutdownGracefully()
            throw error
        }
    }

    func retrySystemProxy() {
        guard isProxyRunning else {
            return
        }
        readiness.clearProxyEnableFailure()
        readiness.setSystemRoutingExpected(true)

        Task {
            do {
                try await SystemProxyManager.shared.enableSystemProxy(port: self.activeProxyPort)
                isSystemProxyConfigured = true
                isProxyOverridden = true
                readiness.setSystemRoutingReady(true)
                runCaptureHealthCheck()
                Self.logger.info("System proxy enabled on retry")
            } catch {
                isSystemProxyConfigured = false
                isProxyOverridden = false
                readiness.setSystemRoutingReady(false)
                readiness.setProxyEnableFailed(message: error.localizedDescription)
                Self.logger.warning("System proxy retry failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshProxyOverrideStatus() {
        Task { @MainActor in
            _ = await reconcileProxyOverrideStatus()
        }
    }

    /// Coalesces the several SystemConfiguration callbacks macOS may emit while one
    /// HTTP/HTTPS proxy update is being applied. This prevents a transient half-written
    /// dictionary from becoming a false takeover warning.
    func scheduleProxyOverrideRefresh() {
        proxyConfigurationRefreshTask?.cancel()
        proxyConfigurationRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self, self.isProxyRunning else {
                return
            }
            _ = await self.reconcileProxyOverrideStatus()
        }
    }

    @discardableResult
    func reconcileProxyOverrideStatus() async -> Bool {
        let owner = await SystemProxyManager.shared.effectiveOverrideOwner()
        let reconciliation = Self.reconcileProxyOverride(
            overridePort: Self.proxyOverridePort(for: owner),
            activeProxyPort: activeProxyPort
        )
        isProxyOverridden = reconciliation.isOverridden
        isSystemProxyConfigured = reconciliation.matchesActiveProxyPort
        readiness.setSystemRoutingReady(reconciliation.matchesActiveProxyPort)
        return reconciliation.matchesActiveProxyPort
    }

    /// The port a live Rockxy override points at, or `nil` when nothing overrides the proxy.
    nonisolated static func proxyOverridePort(for owner: ProxyOverrideOwner) -> Int? {
        switch owner {
        case .none:
            nil
        case let .direct(backup):
            backup.rockxyPort
        case let .helper(port):
            port
        }
    }

    /// Separates "a Rockxy override exists" from "the override points at this session's proxy".
    /// A stale override left by an earlier session or a differently ported one still counts as an
    /// override the user can switch off, but it must never be reported as capture-ready.
    nonisolated static func reconcileProxyOverride(
        overridePort: Int?,
        activeProxyPort: Int
    )
        -> ProxyOverrideReconciliation
    {
        guard let overridePort else {
            return ProxyOverrideReconciliation(isOverridden: false, matchesActiveProxyPort: false)
        }
        return ProxyOverrideReconciliation(
            isOverridden: true,
            matchesActiveProxyPort: overridePort == activeProxyPort
        )
    }

    func switchOffSystemProxyOverride() {
        Task { @MainActor in
            do {
                try await SystemProxyManager.shared.disableSystemProxy()
                isSystemProxyConfigured = false
                isProxyOverridden = false
                readiness.setSystemRoutingExpected(false)
                readiness.setSystemRoutingReady(false)
                await readiness.refresh()
                Self.logger.info("System proxy override switched off")
            } catch {
                readiness.setProxyRestoreFailed(retryAction: .retryDisableSystemRouting)
                Self.logger.error("Failed to switch off system proxy override: \(error.localizedDescription)")
            }
        }
    }

    func switchOnSystemProxyOverride() {
        guard isProxyRunning else {
            return
        }
        readiness.clearProxyEnableFailure()
        readiness.setSystemRoutingExpected(true)

        Task { @MainActor in
            do {
                try await SystemProxyManager.shared.enableSystemProxy(port: self.activeProxyPort)
                isSystemProxyConfigured = true
                isProxyOverridden = true
                readiness.setSystemRoutingReady(true)
                runCaptureHealthCheck()
                await readiness.refresh()
                Self.logger.info("System proxy override switched on")
            } catch {
                isSystemProxyConfigured = false
                isProxyOverridden = false
                readiness.setSystemRoutingReady(false)
                readiness.setProxyEnableFailed(message: error.localizedDescription)
                Self.logger.error("Failed to switch on system proxy override: \(error.localizedDescription)")
            }
        }
    }

    func toggleSystemProxyOverride() {
        // Only disable when the live routing is confirmed to point at this listener.
        // A stale/foreign override must be reclaimed, not switched off as if Rockxy owned it.
        if isSystemProxyConfigured {
            switchOffSystemProxyOverride()
        } else {
            switchOnSystemProxyOverride()
        }
    }

    func clearSession() async {
        // Reentry guard: if a clear is already in flight, skip so the in-flight
        // clear's deferredSessionBatches and clearingTargetGeneration are not clobbered.
        guard !isClearingSession else {
            return
        }

        // Mark the rollover intent synchronously so batches delivered while the
        // main actor is suspended can be classified deterministically.
        let targetGeneration = sessionGeneration &+ 1
        let activeProjectID = projectStore.activeProjectID
        captureGenerationByProjectID[activeProjectID, default: 0] &+= 1
        refreshCaptureContextSnapshot()
        isClearingSession = true
        clearingProjectID = activeProjectID
        clearingTargetGeneration = targetGeneration
        deferredSessionBatches.removeAll()

        // Advance the actor-side generation first so any traffic arriving while
        // the main actor is suspended joins the new session instead of being
        // stamped with an old generation.
        let rollover = await sessionManager.beginNewSessionPreservingPending()
        let resolvedGeneration = rollover.generation

        // Validate that this clear is still the authoritative in-flight clear
        // after the suspension. A different generation here would mean state
        // has been reset out from under us; abandon the rest of the clear.
        guard clearingTargetGeneration == targetGeneration else {
            clearingProjectID = nil
            clearingTargetGeneration = nil
            deferredSessionBatches.removeAll()
            isClearingSession = false
            return
        }
        sessionGeneration = resolvedGeneration

        // Defer everything that had completed before the rollover. Per-Project
        // ownership and generations are the authoritative stale check after clear:
        // old target-Project work is dropped, unchanged inactive-Project work is
        // retained, and newly stamped target-Project work is accepted.
        if !rollover.pending.isEmpty {
            deferredSessionBatches.append(
                .init(transactions: rollover.pending, generation: resolvedGeneration)
            )
        }

        transactionsByProjectID[activeProjectID] = []
        nextSequenceNumberByProjectID[activeProjectID] = 0
        logEntriesByProjectID[activeProjectID] = []
        sessionProvenanceByProjectID.removeValue(forKey: activeProjectID)

        // Normal UI paths serialize Project transitions while clearing. Keep this
        // identity check as a second line of defense so a future direct store
        // mutation cannot clear another Project's active projection.
        if projectStore.activeProjectID == activeProjectID {
            transactions.removeAll()
            rebuildObservedDomainsByApp()
            logEntries.removeAll()
            errorCount = 0
            sessionProvenance = nil
            importPreview = nil
            exportScopeContext = nil
            activeToast = nil
            clearAllWorkspaces()
            resetTrafficMetrics()

            // Advance nextSequenceNumber past highest assigned to any remaining persisted favorite
            if persistedFavorites.isEmpty {
                nextSequenceNumber = 0
            } else {
                let maxSeq = persistedFavorites.map(\.sequenceNumber).max() ?? 0
                nextSequenceNumber = maxSeq + 1
            }
        } else {
            Self.logger.error("Active Project changed during clear; protected the new projection")
        }

        let deferredBatches = deferredSessionBatches
        deferredSessionBatches.removeAll()
        clearingProjectID = nil
        clearingTargetGeneration = nil
        isClearingSession = false

        for deferredBatch in deferredBatches {
            processBatch(deferredBatch.transactions, generation: deferredBatch.generation)
        }

        NotificationCenter.default.post(name: .sessionCleared, object: nil)
    }

    func clearCaptureAndFilters() async {
        await clearSession()
        clearFiltersAcrossAllWorkspaces()
    }

    func recomputeErrorCount() {
        errorCount = transactions.count { transaction in
            (transaction.response?.statusCode ?? 0) >= 400
        }
    }

    // MARK: - Proxy Configuration

    func configureProxy(port: Int? = nil, settings: AppSettings? = nil) async {
        let settings = settings ?? AppSettingsStorage.load()
        let resolvedPort = port ?? settings.proxyPort
        let manager = sessionManager
        let captureProbeTracker = captureProbeTracker
        let captureRecordingGate = captureRecordingGate

        let configuration = ProxyConfiguration(
            port: resolvedPort,
            listenAddress: settings.effectiveListenAddress,
            listenIPv6: settings.listenIPv6
        )

        let bpManager = breakpointManager
        refreshCaptureContextSnapshot()
        // Ensure scripts are loaded before the proxy starts accepting connections,
        // so the first captured request sees the same script state as every later one.
        // After the first call this is a fast no-op.
        await PluginManager.shared.ensureLoadedOnce()
        let upstreamProxySnapshotProvider = UpstreamProxyStore.shared.resolvedSnapshot
        proxyServer = ProxyServer(
            configuration: configuration,
            certificateManager: certificateManager,
            ruleEngine: RuleEngine.shared,
            scriptPluginManager: PluginManager.shared.scriptManager,
            upstreamProxySnapshotProvider: upstreamProxySnapshotProvider,
            captureContextProvider: { [captureContextStore] in
                captureContextStore.snapshot()
            },
            shouldBypassUserModifications: { request in
                captureProbeTracker.shouldBypassUserModifications(request)
            },
            onTransactionComplete: { transaction in
                Task {
                    if captureProbeTracker.consumeIfExpected(transaction) {
                        return
                    }
                    guard captureRecordingGate.allowsCapture() else {
                        return
                    }
                    await manager.addTransaction(transaction)
                }
            },
            onBreakpointHit: { @Sendable data in
                await bpManager.enqueueAndWait(data)
            }
        )

        await sessionManager.setOnBatchReady { [weak self] batch, generation in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.processBatch(batch, generation: generation)
            }
        }
        await sessionManager.setOnClientAppEnriched { [weak self] enrichedTransactions in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.handleClientAppEnrichment(enrichedTransactions)
            }
        }
        let effectiveBufferSize = min(settings.maxBufferSize, policy.maxLiveHistoryEntries)
        liveHistoryLimit = max(1, effectiveBufferSize)
        await sessionManager.setMaxBufferSize(effectiveBufferSize)
        await sessionManager.setProxyPort(resolvedPort)
        Self.logger.info("Proxy configured on \(settings.effectiveListenAddress):\(resolvedPort)")
    }

    // MARK: - Transaction Processing

    func processBatch(_ batch: [HTTPTransaction], generation: UInt) {
        if isClearingSession {
            guard let targetGeneration = clearingTargetGeneration else {
                Self.logger.error("Dropped batch because clear state had no target generation")
                return
            }

            // Restamp only the batch-delivery generation. Immutable per-Project
            // ownership still decides which transactions survive after the clear.
            deferredSessionBatches.append(.init(transactions: batch, generation: targetGeneration))
            return
        }

        if generation != sessionGeneration {
            Self.logger.debug("Evaluating an older delivery batch by its Project ownership")
        }
        let filteredBatch = Self.filterBatchThroughAllowList(batch, using: AllowListManager.shared)
        if filteredBatch.count < batch.count {
            Self.logger.debug(
                "Allow list filtered \(batch.count - filteredBatch.count) of \(batch.count) transactions"
            )
        }

        guard !filteredBatch.isEmpty else {
            return
        }

        // Tests, startup restoration, and bounded local integrations may seed the
        // active projection directly before the first routed proxy batch. Adopt
        // that history once so the first completion appends instead of replacing it.
        seedActiveProjectCaptureStateIfNeeded()
        let knownProjectIDs = Set(projectStore.projects.map(\.id))
        var routedBatches: [UUID: [HTTPTransaction]] = [:]

        for transaction in filteredBatch {
            guard let context = transaction.captureContext else {
                Self.logger.error("Dropped transaction without request-start Project ownership")
                continue
            }
            guard knownProjectIDs.contains(context.projectID),
                  context.sessionID == context.projectID,
                  context.generation == captureGenerationByProjectID[context.projectID, default: 0] else
            {
                Self.logger.debug("Dropped transaction with stale or unknown Project capture route")
                continue
            }
            routedBatches[context.projectID, default: []].append(transaction)
        }

        for (projectID, projectBatch) in routedBatches {
            var history = transactionsByProjectID[projectID] ?? []
            var sequence = nextSequenceNumberByProjectID[projectID]
                ?? ((history.map(\.sequenceNumber).max() ?? -1) + 1)
            for transaction in projectBatch {
                transaction.sequenceNumber = sequence
                sequence += 1
                history.append(transaction)
            }
            nextSequenceNumberByProjectID[projectID] = sequence

            let overflow = max(0, history.count - liveHistoryLimit)
            let evictionCount: Int
            if overflow > 0 {
                let evictionHeadroom = min(
                    liveHistoryLimit,
                    max(2, min(100, (liveHistoryLimit + 9) / 10))
                )
                evictionCount = min(history.count, max(overflow, evictionHeadroom))
                history.removeFirst(evictionCount)
            } else {
                evictionCount = 0
            }
            transactionsByProjectID[projectID] = history

            guard projectID == projectStore.activeProjectID else {
                Self.logger.debug("Routed \(projectBatch.count) late transaction(s) to an inactive Project")
                continue
            }

            transactions = history
            nextSequenceNumber = sequence
            if evictionCount > 0 {
                rebuildObservedDomainsByApp()
                debugAssistantTransactionsByHost.removeAll()
                debugAssistantIndexedTransactionIDs.removeAll()
                debugAssistantIndexedLiveCount = 0
                debugAssistantTrafficIndexGeneration &+= 1
                appendToDebugAssistantTrafficIndex(history)
                rebuildAllWorkspacesForCaptureReplacement()
            } else {
                updateAllWorkspaces(with: projectBatch)
                appendToDebugAssistantTrafficIndex(projectBatch)
                appendObservedDomainsByApp(from: projectBatch)
            }

            recordTrafficMetrics(for: projectBatch)
            recomputeErrorCount()
            followLatestVisibleTransaction(from: projectBatch)
            headerColumnStore.updateDiscoveredHeaders(fromBatch: projectBatch)
        }
    }

    func handleClientAppEnrichment(_ enrichedTransactions: [HTTPTransaction]) {
        let activeIDs = Set(transactions.map(\.id))
        let enrichedTransactions = enrichedTransactions.filter { activeIDs.contains($0.id) }
        guard !enrichedTransactions.isEmpty else {
            return
        }

        let enrichedByID = Dictionary(
            enrichedTransactions.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let enrichedIDs = Set(enrichedByID.keys)
        for transaction in enrichedTransactions {
            moveObservedDomainFromUnknown(for: transaction)
        }

        for workspace in workspaceStore.workspaces {
            updateAppGroupingForEnrichedTransactions(enrichedTransactions, in: workspace)
            refreshAppNodes(for: workspace)

            if workspaceUsesClientDependentOrderingOrFiltering(workspace) {
                recomputeFilteredTransactions(for: workspace)
            } else {
                var didUpdateRows = false
                for index in workspace.filteredRows.indices
                    where enrichedIDs.contains(workspace.filteredRows[index].id)
                {
                    guard let transaction = enrichedByID[workspace.filteredRows[index].id] else {
                        continue
                    }
                    workspace.filteredRows[index] = RequestListRow(
                        from: transaction,
                        sslState: sslState(for: transaction)
                    )
                    didUpdateRows = true
                }
                guard didUpdateRows else {
                    continue
                }
                // In-place enrichment rewrites existing rows without a full derive, so it must
                // invalidate the append provenance itself — otherwise a later coalesced append
                // could insert against a prefix this enrichment already mutated.
                workspace.lastDeriveWasAppendOnly = false
                workspace.appendChainOriginToken = nil
                workspace.refreshToken += 1
            }
        }
        TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)
    }

    private func updateAppGroupingForEnrichedTransactions(
        _ transactions: [HTTPTransaction],
        in workspace: WorkspaceState
    ) {
        let unknownApp = String(localized: "Unknown", bundle: RockxyLocalization.bundle)
        for transaction in transactions {
            let destinationApp = transaction.clientApp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !destinationApp.isEmpty else {
                continue
            }

            switch workspace.filterCriteria.sidebarApp {
            case nil:
                workspace.appGroupingIndex.remove(transaction, appName: unknownApp)
                workspace.appGroupingIndex.add(transaction, appName: destinationApp)
            case unknownApp:
                workspace.appGroupingIndex.remove(transaction, appName: unknownApp)
            case destinationApp:
                // The row was omitted from this app-scoped index while attribution was unknown.
                workspace.appGroupingIndex.add(transaction, appName: destinationApp)
            default:
                break
            }
        }
    }

    private func workspaceUsesClientDependentOrderingOrFiltering(_ workspace: WorkspaceState) -> Bool {
        if workspace.filterCriteria.sidebarApp != nil
            || workspace.filterCriteria.isSearchEnabled
            && workspace.filterCriteria.searchField == .clientApp
            || workspace.activeSortDescriptors.contains(where: { $0.key == "client" })
            || workspace.activeFocusSet != nil
            || !workspace.mutedTrafficSources.isEmpty
        {
            return true
        }

        return FilterRuleEvaluator.activeRules(
            in: workspace.filterRules,
            isFilterBarVisible: workspace.isFilterBarVisible
        )
        .contains { $0.field == .clientApp }
    }

    func updateDomainTree(for transaction: HTTPTransaction) {
        updateDomainTree(for: transaction, in: activeWorkspace)
    }

    func updateAppNodes(for transaction: HTTPTransaction) {
        updateAppNodes(for: transaction, in: activeWorkspace)
    }

    // MARK: - Allow List Filtering (pure helper for processBatch + tests)

    /// Applies the Allow List capture filter to a batch of transactions.
    ///
    /// This is the single code path used by `processBatch` to decide which
    /// transactions enter the session. Extracted as a pure static helper so
    /// tests can verify the filter contract with an injected `AllowListManager`
    /// instance — no `.shared` singleton reliance in test code.
    ///
    /// - When the allow list is inactive: every transaction passes through.
    /// - When the allow list is active: only transactions whose `method` + `url`
    ///   match at least one enabled rule via `isRequestAllowed(method:url:)` pass.
    nonisolated static func filterBatchThroughAllowList(
        _ batch: [HTTPTransaction],
        using manager: AllowListManager
    )
        -> [HTTPTransaction]
    {
        batch.filter {
            manager.isRequestAllowed(method: $0.request.method, url: $0.request.url)
        }
    }
}

// MARK: - CaptureHealthProbeResponseHandler

enum CaptureHealthProbeError: Error {
    case connectionClosed
    case timeout
}

/// Sends an absolute-form HTTP request directly to the active proxy listener. Foundation's
/// URL loading system may bypass configured proxies for loopback destinations, which would
/// make the readiness check report a false success without traversing Rockxy.
final class CaptureHealthProbeResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    init(
        requestHead: HTTPRequestHead,
        responsePromise: EventLoopPromise<Bool>
    ) {
        self.requestHead = requestHead
        self.responsePromise = responsePromise
    }

    func channelActive(context: ChannelHandlerContext) {
        context.write(wrapOutboundOut(.head(requestHead)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head:
            receivedResponseHead = true
        case .body:
            break
        case .end:
            succeed(receivedResponseHead)
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        fail(CaptureHealthProbeError.connectionClosed)
        context.fireChannelInactive()
    }

    func timeout() {
        fail(CaptureHealthProbeError.timeout)
    }

    private let requestHead: HTTPRequestHead
    private let responsePromise: EventLoopPromise<Bool>
    private var receivedResponseHead = false
    private var isCompleted = false

    private func succeed(_ value: Bool) {
        guard !isCompleted else {
            return
        }
        isCompleted = true
        responsePromise.succeed(value)
    }

    private func fail(_ error: Error) {
        guard !isCompleted else {
            return
        }
        isCompleted = true
        responsePromise.fail(error)
    }
}
