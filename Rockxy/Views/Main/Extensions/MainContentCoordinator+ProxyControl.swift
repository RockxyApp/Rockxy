import Foundation
import os

// Extends `MainContentCoordinator` with proxy control behavior for the main workspace.

// MARK: - MainContentCoordinator + ProxyControl

/// Coordinator extension for proxy server lifecycle: start, stop, recording toggle,
/// session clearing, and the NIO proxy configuration pipeline. Incoming transactions
/// flow through `TrafficSessionManager` which batches updates (every 100ms or 50
/// transactions) before delivering them to the main actor to avoid UI churn.
extension MainContentCoordinator {
    // MARK: - Proxy Lifecycle

    func startProxy() {
        guard !isProxyRunning, !isProxyStarting else {
            return
        }
        proxyError = nil
        isProxyStarting = true

        Task {
            defer {
                isProxyStarting = false
            }

            let settings = AppSettingsStorage.load()
            do {
                try await certificateManager.ensureRootCA()
                Self.logger.info("Root CA ready")

                await certificateManager.validateCertificateChain()

                // Evaluate certificate trust via the readiness layer.
                // Only new HTTPS connections are affected — existing TLS sessions
                // are not re-intercepted after trust changes.
                await readiness.refresh()
                SSLProxyingManager.shared.forceGlobalPassthrough = !readiness.canInterceptHTTPS
                if !readiness.canInterceptHTTPS {
                    Self.logger.warning(
                        "Root CA is not trusted (real SecTrust validation) — all HTTPS passes through"
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

                await configureProxy(port: resolvedPort)

                try await proxyServer.start()
                isProxyRunning = true
                proxyStartedAt = Date()
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
                readiness.setCaptureActive(true)

                Self.logger.info("Configuring system proxy...")
                do {
                    try await SystemProxyManager.shared.enableSystemProxy(port: resolvedPort)
                    isSystemProxyConfigured = true
                    isProxyOverridden = true
                    Self.logger.info("System proxy enabled on port \(resolvedPort)")
                } catch {
                    isSystemProxyConfigured = false
                    isProxyOverridden = false
                    readiness.setProxyEnableFailed(message: error.localizedDescription)
                    Self.logger.warning(
                        "System proxy not configured: \(error.localizedDescription). Proxy still running on 127.0.0.1:\(resolvedPort)"
                    )
                }

                NotificationCenter.default.post(name: .proxyDidStart, object: nil)
                Self.logger.info("Proxy started on port \(resolvedPort)")
            } catch {
                Self.logger.error("Failed to start proxy: \(error.localizedDescription)")
                proxyError = error.localizedDescription
                activeProxyPort = settings.proxyPort
            }
        }
    }

    func stopProxy() {
        guard isProxyRunning else {
            return
        }
        isProxyRunning = false

        Task {
            if let evictionObserver {
                NotificationCenter.default.removeObserver(evictionObserver)
                self.evictionObserver = nil
            }

            do {
                try await SystemProxyManager.shared.disableSystemProxy()
                Self.logger.info("System proxy disabled")
            } catch {
                Self.logger.error("Failed to restore proxy: \(error.localizedDescription)")
            }
            isSystemProxyConfigured = false
            isProxyOverridden = false
            readiness.setCaptureActive(false)
            SSLProxyingManager.shared.forceGlobalPassthrough = false

            await proxyServer.stop()
            stopLogCapture()
            stopBandwidthTimer()
            resetInstantaneousSpeeds()
            proxyStartedAt = nil
            activeProxyPort = AppSettingsStorage.load().proxyPort
            NotificationCenter.default.post(name: .proxyDidStop, object: nil)
            Self.logger.info("Proxy stopped")
        }
    }

    func toggleRecording() {
        isRecording.toggle()
    }

    func retrySystemProxy() {
        guard isProxyRunning else {
            return
        }
        readiness.clearProxyEnableFailure()

        Task {
            do {
                try await SystemProxyManager.shared.enableSystemProxy(port: self.activeProxyPort)
                isSystemProxyConfigured = true
                isProxyOverridden = true
                Self.logger.info("System proxy enabled on retry")
            } catch {
                isSystemProxyConfigured = false
                isProxyOverridden = false
                readiness.setProxyEnableFailed(message: error.localizedDescription)
                Self.logger.warning("System proxy retry failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshProxyOverrideStatus() {
        Task { @MainActor in
            let owner = await SystemProxyManager.shared.effectiveOverrideOwner()
            let overridden = switch owner {
            case .none:
                false
            case .direct,
                 .helper:
                true
            }
            isProxyOverridden = overridden
            isSystemProxyConfigured = overridden
        }
    }

    func switchOffSystemProxyOverride() {
        Task { @MainActor in
            do {
                try await SystemProxyManager.shared.disableSystemProxy()
                isSystemProxyConfigured = false
                isProxyOverridden = false
                await readiness.refresh()
                Self.logger.info("System proxy override switched off")
            } catch {
                readiness.setProxyEnableFailed(message: error.localizedDescription)
                Self.logger.error("Failed to switch off system proxy override: \(error.localizedDescription)")
            }
        }
    }

    func switchOnSystemProxyOverride() {
        guard isProxyRunning else {
            return
        }
        readiness.clearProxyEnableFailure()

        Task { @MainActor in
            do {
                try await SystemProxyManager.shared.enableSystemProxy(port: self.activeProxyPort)
                isSystemProxyConfigured = true
                isProxyOverridden = true
                await readiness.refresh()
                Self.logger.info("System proxy override switched on")
            } catch {
                isSystemProxyConfigured = false
                isProxyOverridden = false
                readiness.setProxyEnableFailed(message: error.localizedDescription)
                Self.logger.error("Failed to switch on system proxy override: \(error.localizedDescription)")
            }
        }
    }

    func toggleSystemProxyOverride() {
        if isProxyOverridden {
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
        isClearingSession = true
        clearingTargetGeneration = targetGeneration
        deferredSessionBatches.removeAll()

        // Advance the actor-side generation first so any traffic arriving while
        // the main actor is suspended joins the new session instead of being
        // stamped with an old generation.
        let resolvedGeneration = await sessionManager.beginNewSession()

        // Validate that this clear is still the authoritative in-flight clear
        // after the suspension. A different generation here would mean state
        // has been reset out from under us; abandon the rest of the clear.
        guard clearingTargetGeneration == targetGeneration else {
            return
        }
        sessionGeneration = resolvedGeneration

        transactions.removeAll()
        rebuildObservedDomainsByApp()
        logEntries.removeAll()
        errorCount = 0
        sessionProvenance = nil
        importPreview = nil
        showExportScope = false
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

        let deferredBatches = deferredSessionBatches
        deferredSessionBatches.removeAll()
        clearingTargetGeneration = nil
        isClearingSession = false

        for deferredBatch in deferredBatches {
            processBatch(deferredBatch.transactions, generation: deferredBatch.generation)
        }

        NotificationCenter.default.post(name: .sessionCleared, object: nil)
    }

    // MARK: - Proxy Configuration

    func configureProxy(port: Int? = nil) async {
        let settings = AppSettingsStorage.load()
        let resolvedPort = port ?? settings.proxyPort
        let manager = sessionManager

        let configuration = ProxyConfiguration(
            port: resolvedPort,
            listenAddress: settings.effectiveListenAddress,
            listenIPv6: settings.listenIPv6
        )

        let bpManager = breakpointManager
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
            onTransactionComplete: { transaction in
                Task {
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
        await sessionManager.setMaxBufferSize(effectiveBufferSize)
        await sessionManager.setProxyPort(resolvedPort)
        await sessionManager.startBatchTimer()

        Self.logger.info("Proxy configured on \(settings.effectiveListenAddress):\(resolvedPort)")
    }

    // MARK: - Transaction Processing

    func processBatch(_ batch: [HTTPTransaction], generation: UInt) {
        if isClearingSession {
            guard generation == clearingTargetGeneration else {
                Self.logger.debug("Batch of \(batch.count) dropped — stale clear-session generation")
                return
            }

            deferredSessionBatches.append(.init(transactions: batch, generation: generation))
            return
        }

        guard generation == sessionGeneration else {
            Self.logger.debug("Batch of \(batch.count) dropped — stale session generation")
            return
        }
        guard isRecording else {
            Self.logger.debug("Batch of \(batch.count) dropped — recording paused")
            return
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

        // Report only accepted transactions back to the actor for buffer accounting.
        // This ensures paused/filtered batches do not consume the live-history budget.
        // The generation tag prevents stale reports from a pre-clear batch affecting
        // post-clear accounting.
        let acceptedCount = filteredBatch.count
        Task { await sessionManager.reportAcceptedCount(acceptedCount, generation: generation) }

        recordTrafficMetrics(for: filteredBatch)

        Self.logger
            .info(
                "Processing batch of \(filteredBatch.count) transactions (total: \(self.transactions.count + filteredBatch.count))"
            )

        for transaction in filteredBatch {
            transaction.sequenceNumber = nextSequenceNumber
            nextSequenceNumber += 1
            transactions.append(transaction)

            if let statusCode = transaction.response?.statusCode, statusCode >= 400 {
                errorCount += 1
            }
        }
        appendObservedDomainsByApp(from: filteredBatch)

        updateAllWorkspaces(with: filteredBatch)

        headerColumnStore.updateDiscoveredHeaders(fromBatch: filteredBatch)
    }

    func handleClientAppEnrichment(_ enrichedTransactions: [HTTPTransaction]) {
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
                workspace.lastDeriveWasAppendOnly = false
                workspace.refreshToken += 1
            }
        }
        TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)
    }

    private func updateAppGroupingForEnrichedTransactions(
        _ transactions: [HTTPTransaction],
        in workspace: WorkspaceState
    ) {
        let unknownApp = String(localized: "Unknown")
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
