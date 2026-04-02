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
        systemProxyWarning = nil

        Task {
            let settings = AppSettingsStorage.load()
            do {

                try await certificateManager.ensureRootCA()
                Self.logger.info("Root CA ready")

                await certificateManager.validateCertificateChain()

                let isTrusted = await certificateManager.isRootCATrustValidated()
                SSLProxyingManager.shared.forceGlobalPassthrough = !isTrusted
                if !isTrusted {
                    Self.logger.warning(
                        "Root CA is not trusted (real SecTrust validation) — all HTTPS passes through"
                    )
                    NotificationCenter.default.post(name: .rootCANotTrusted, object: nil)
                } else {
                    if await certificateManager.rootCAFreshlyInstalled {
                        SSLProxyingManager.shared.clearAutoPassthrough()
                    }
                }

                if !rulesLoaded {
                    rulesLoaded = true
                    await RuleSyncService.loadFromDisk()
                }
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
                    let count = notification.userInfo?["count"] as? Int ?? 5000
                    self.evictOldestTransactions(count: count)
                }

                tlsRejectionHosts = []
                tlsRejectionObserver = NotificationCenter.default.addObserver(
                    forName: .tlsMitmRejected,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let self, let host = notification.userInfo?["host"] as? String else {
                        return
                    }
                    self.tlsRejectionHosts.insert(host)
                    if self.tlsRejectionHosts.count == 3 {
                        let isFresh = Task { await self.certificateManager.rootCAFreshlyInstalled }
                        Task { @MainActor in
                            let fresh = await isFresh.value
                            if fresh {
                                self.systemProxyWarning = .init(
                                    message: String(
                                        localized: "Multiple HTTPS hosts rejected the proxy certificate. Restart your browser to trust the new Rockxy Root CA."
                                    ),
                                    action: nil,
                                    isDismissible: true
                                )
                            } else {
                                self.systemProxyWarning = .init(
                                    message: String(
                                        localized: """
                                        Multiple HTTPS hosts rejected the proxy certificate. \
                                        Check that the Rockxy Root CA is trusted in Keychain Access, then restart your browser.
                                        """
                                    ),
                                    action: nil,
                                    isDismissible: true
                                )
                            }
                        }
                    }
                }

                let helperStatus = await HelperManager.shared.status
                Self.logger.info("Helper status at proxy start: \(String(describing: helperStatus))")

                Self.logger.info("Configuring system proxy...")
                var vpnObserver: NSObjectProtocol?
                vpnObserver = NotificationCenter.default.addObserver(
                    forName: .systemProxyVPNWarning,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    let iface = notification.userInfo?["interface"] as? String ?? "unknown"
                    self?.systemProxyWarning = .init(
                        message: String(
                            localized: "VPN or iCloud Private Relay detected (\(iface)). Traffic may not be captured. Disable VPN/Private Relay to use Rockxy."
                        ),
                        action: nil,
                        isDismissible: true
                    )
                }
                do {
                    try await SystemProxyManager.shared.enableSystemProxy(port: resolvedPort)
                    isSystemProxyConfigured = true
                    Self.logger.info("System proxy enabled on port \(resolvedPort)")
                } catch {
                    isSystemProxyConfigured = false
                    systemProxyWarning = .init(
                        message: error.localizedDescription,
                        action: .retry,
                        isDismissible: true
                    )
                    Self.logger.warning(
                        "System proxy not configured: \(error.localizedDescription). Proxy still running on 127.0.0.1:\(resolvedPort)"
                    )
                }

                if let vpnObserver {
                    NotificationCenter.default.removeObserver(vpnObserver)
                }

                let postProxyHelperStatus = await HelperManager.shared.status
                if isSystemProxyConfigured, !SystemProxyManager.shared.usingHelperProxyOverride {
                    systemProxyWarning = directModeWarning(for: postProxyHelperStatus)
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
            if let tlsRejectionObserver {
                NotificationCenter.default.removeObserver(tlsRejectionObserver)
                self.tlsRejectionObserver = nil
            }
            tlsRejectionHosts = []

            do {
                try await SystemProxyManager.shared.disableSystemProxy()
                Self.logger.info("System proxy disabled")
            } catch {
                Self.logger.error("Failed to restore proxy: \(error.localizedDescription)")
            }
            isSystemProxyConfigured = false
            systemProxyWarning = nil
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
        systemProxyWarning = nil

        Task {
            do {
                try await SystemProxyManager.shared.enableSystemProxy(port: self.activeProxyPort)
                isSystemProxyConfigured = true
                let helperStatus = await HelperManager.shared.status
                if !SystemProxyManager.shared.usingHelperProxyOverride {
                    systemProxyWarning = directModeWarning(for: helperStatus)
                }
                Self.logger.info("System proxy enabled on retry")
            } catch {
                isSystemProxyConfigured = false
                systemProxyWarning = .init(
                    message: error.localizedDescription,
                    action: .retry,
                    isDismissible: true
                )
                Self.logger.warning("System proxy retry failed: \(error.localizedDescription)")
            }
        }
    }

    func clearSession() {
        transactions.removeAll()
        logEntries.removeAll()
        errorCount = 0
        sessionProvenance = nil
        importPreview = nil
        showExportScope = false
        exportScopeContext = nil
        activeToast = nil
        clearAllWorkspaces()
        resetTrafficMetrics()
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
        await sessionManager.setMaxBufferSize(settings.maxBufferSize)
        await sessionManager.setProxyPort(resolvedPort)
        await sessionManager.startBatchTimer()

        Self.logger.info("Proxy configured on \(settings.effectiveListenAddress):\(resolvedPort)")
    }

    private func directModeWarning(for helperStatus: HelperManager.HelperStatus) -> SystemProxyWarning {
        let reason = switch helperStatus {
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
        }

        return SystemProxyWarning(
            message: String(
                localized: """
                Rockxy is using direct macOS proxy changes because \(reason). \
                If Rockxy or Xcode stops unexpectedly, your Mac may stay behind a dead proxy until Rockxy restores it. \
                Install or repair the helper tool for safer automatic cleanup.
                """
            ),
            action: .openAdvancedProxySettings,
            isDismissible: false
        )
    }

    // MARK: - Transaction Processing

    private func processBatch(_ batch: [HTTPTransaction]) {
        guard isRecording else {
            Self.logger.debug("Batch of \(batch.count) dropped — recording paused")
            return
        }

        let filteredBatch: [HTTPTransaction]
        if AllowListManager.shared.isActive {
            filteredBatch = batch.filter { AllowListManager.shared.isHostAllowed($0.request.host) }
            if filteredBatch.count < batch.count {
                Self.logger.debug(
                    "Allow list filtered \(batch.count - filteredBatch.count) of \(batch.count) transactions"
                )
            }
        } else {
            filteredBatch = batch
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
            transactions.append(transaction)

            if let statusCode = transaction.response?.statusCode, statusCode >= 400 {
                errorCount += 1
            }
        }

        updateAllWorkspaces(with: filteredBatch)

        headerColumnStore.updateDiscoveredHeaders(from: transactions)
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
}
