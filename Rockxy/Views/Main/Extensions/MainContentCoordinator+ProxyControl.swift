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
        proxyError = nil

        Task {
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
                    self.evictOldestTransactions(count: count)
                }

                readiness.startObserving()
                readiness.setCaptureActive(true)

                Self.logger.info("Configuring system proxy...")
                do {
                    try await SystemProxyManager.shared.enableSystemProxy(port: resolvedPort)
                    isSystemProxyConfigured = true
                    Self.logger.info("System proxy enabled on port \(resolvedPort)")
                } catch {
                    isSystemProxyConfigured = false
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
                Self.logger.info("System proxy enabled on retry")
            } catch {
                isSystemProxyConfigured = false
                readiness.setProxyEnableFailed(message: error.localizedDescription)
                Self.logger.warning("System proxy retry failed: \(error.localizedDescription)")
            }
        }
    }

    func clearSession() {
        transactions.removeAll()
        selectedTransactionIDs.removeAll()
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
        proxyServer = ProxyServer(
            configuration: configuration,
            certificateManager: certificateManager,
            ruleEngine: RuleEngine.shared,
            onTransactionComplete: { transaction in
                Task {
                    await manager.addTransaction(transaction)
                }
            },
            onBreakpointHit: { @Sendable data in
                await bpManager.enqueueAndWait(data)
            }
        )

        await sessionManager.setOnBatchReady { [weak self] batch in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.processBatch(batch)
            }
        }
        await sessionManager.setOnClientAppEnriched { [weak self] enrichedIDs in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.handleClientAppEnrichment(enrichedIDs)
            }
        }
        let effectiveBufferSize = min(settings.maxBufferSize, policy.maxLiveHistoryEntries)
        await sessionManager.setMaxBufferSize(effectiveBufferSize)
        await sessionManager.setProxyPort(resolvedPort)
        await sessionManager.startBatchTimer()

        Self.logger.info("Proxy configured on \(settings.effectiveListenAddress):\(resolvedPort)")
    }

    // MARK: - Transaction Processing

    private func processBatch(_ batch: [HTTPTransaction]) {
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

        updateAllWorkspaces(with: filteredBatch)

        headerColumnStore.updateDiscoveredHeaders(fromBatch: filteredBatch)

        if transactions.count > policy.maxLiveHistoryEntries {
            let overflow = transactions.count - policy.maxLiveHistoryEntries
            evictOldestTransactions(count: overflow)
        }
    }

    func handleClientAppEnrichment(_ enrichedIDs: [UUID]) {
        guard !enrichedIDs.isEmpty else {
            return
        }
        // clientApp is already mutated on the HTTPTransaction objects.
        // Rebuild sidebar app indexes for all workspaces (app counts/names may have changed).
        // If a workspace has an active app filter, recompute its filtered transactions
        // because membership depends on clientApp.
        for workspace in workspaceStore.workspaces {
            rebuildSidebarIndexes(for: workspace)
            if workspace.filterCriteria.sidebarApp != nil {
                recomputeFilteredTransactions(for: workspace)
            } else {
                workspace.lastDeriveWasAppendOnly = false
                deriveFilteredRows(for: workspace)
            }
        }
    }

    func updateDomainTree(for transaction: HTTPTransaction) {
        let domain = transaction.request.host
        guard !domain.isEmpty else {
            return
        }

        if let index = domainIndexMap[domain] {
            domainTree[index].requestCount += 1
        } else {
            let node = DomainNode(
                id: domain,
                domain: domain,
                requestCount: 1,
                children: []
            )
            domainIndexMap[domain] = domainTree.count
            domainTree.append(node)
        }
    }

    func updateAppNodes(for transaction: HTTPTransaction) {
        let appName = transaction.clientApp ?? String(localized: "Unknown")
        let host = transaction.request.host

        if let index = appNodeIndexMap[appName] {
            appNodes[index].requestCount += 1
            if !host.isEmpty, !appNodes[index].domains.contains(host) {
                appNodes[index].domains.append(host)
                appNodes[index].domains.sort()
            }
        } else {
            let info = AppInfo(
                name: appName,
                domains: host.isEmpty ? [] : [host],
                requestCount: 1
            )
            appNodeIndexMap[appName] = appNodes.count
            appNodes.append(info)
        }
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
