import Foundation
import os

// Extends `MainContentCoordinator` with replay behavior for the main workspace.

// MARK: - MainContentCoordinator + Replay

/// Coordinator extension for replaying captured HTTP requests against the original server.
extension MainContentCoordinator {
    // MARK: - Request Replay

    /// Most requests one Repeat sends, so a large accidental selection cannot flood a server.
    static let maximumBatchReplayCount = 50

    func replaySelectedRequest() {
        let selected = resolveSelectedTransactions()
        if selected.count > 1 {
            performReplay(for: selected)
            return
        }
        guard let transaction = selectedTransaction else {
            return
        }
        performReplay(for: transaction)
    }

    /// Repeats several rows one after another, in list order, and reports one summary.
    func performReplay(for transactions: [HTTPTransaction]) {
        let eligible = transactions.filter(Self.canReplay)
        guard !eligible.isEmpty else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(
                    localized: "Replay is not supported for this request type.",
                    bundle: RockxyLocalization.bundle
                )
            )
            return
        }
        guard eligible.count <= Self.maximumBatchReplayCount else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(
                    localized: "Select at most \(Self.maximumBatchReplayCount) requests to repeat at once.",
                    bundle: RockxyLocalization.bundle
                )
            )
            return
        }
        let skipped = transactions.count - eligible.count
        Task { @MainActor in
            var failed = 0
            for transaction in eligible {
                let startedAt = Date()
                do {
                    let response = try await RequestReplay.replay(transaction.request)
                    await recordReplayResult(of: transaction, response: response, startedAt: startedAt, state: .completed)
                } catch {
                    failed += 1
                    Self.logger.error("Replay failed: \(error.localizedDescription)")
                    await recordReplayResult(of: transaction, response: nil, startedAt: startedAt, state: .failed)
                }
            }
            activeToast = Self.batchReplayToast(sent: eligible.count, failed: failed, skipped: skipped)
        }
    }

    /// Sends the selected requests again through Rockxy's own listener, so the active rules
    /// apply exactly as they would to the app. The proxy records each one as a new row.
    func replaySelectedThroughRules() {
        let selected = resolveSelectedTransactions()
        replayThroughRules(selected.isEmpty ? [selectedTransaction].compactMap(\.self) : selected)
    }

    /// Row menu: the right-clicked row, or the whole selection when the row is part of it.
    func replayThroughRules(clicked transaction: HTTPTransaction) {
        replayThroughRules(contextExportTransactions(clicked: transaction))
    }

    func replayThroughRules(_ targets: [HTTPTransaction]) {
        let eligible = targets.filter(Self.canReplay)
        guard isProxyRunning else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(
                    localized: "Start the proxy to repeat requests through your rules.",
                    bundle: RockxyLocalization.bundle
                )
            )
            return
        }
        guard !eligible.isEmpty, eligible.count <= Self.maximumBatchReplayCount else {
            activeToast = ToastMessage(
                style: .warning,
                text: eligible.isEmpty
                    ? String(localized: "Replay is not supported for this request type.", bundle: RockxyLocalization.bundle)
                    : String(
                        localized: "Select at most \(Self.maximumBatchReplayCount) requests to repeat at once.",
                        bundle: RockxyLocalization.bundle
                    )
            )
            return
        }
        let port = activeProxyPort
        Task { @MainActor in
            var failed = 0
            for transaction in eligible {
                do {
                    _ = try await RequestReplay.replay(transaction.request, throughProxyPort: port)
                } catch {
                    failed += 1
                    Self.logger.error("Replay through rules failed: \(error.localizedDescription)")
                }
            }
            activeToast = Self.batchReplayToast(
                sent: eligible.count,
                failed: failed,
                skipped: targets.count - eligible.count
            )
        }
    }

    nonisolated static func batchReplayToast(sent: Int, failed: Int, skipped: Int) -> ToastMessage {
        var text = String(
            AttributedString(localized: "Repeated ^[\(sent) request](inflect: true)", bundle: RockxyLocalization.bundle)
                .characters
        )
        if failed > 0 {
            text += " — " + String(
                AttributedString(localized: "^[\(failed) request](inflect: true) failed", bundle: RockxyLocalization.bundle)
                    .characters
            )
        }
        if skipped > 0 {
            text += " — " + String(
                AttributedString(
                    localized: "^[\(skipped) request](inflect: true) can't be repeated",
                    bundle: RockxyLocalization.bundle
                ).characters
            )
        }
        return ToastMessage(style: failed > 0 ? .warning : .success, text: text)
    }

    func performReplay(for transaction: HTTPTransaction) {
        guard Self.canReplay(transaction) else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(
                    localized: "Replay is not supported for this request type.",
                    bundle: RockxyLocalization.bundle
                )
            )
            return
        }
        Task { @MainActor in
            let startedAt = Date()
            do {
                let response = try await RequestReplay.replay(transaction.request)
                Self.logger.info("Replay completed: \(response.statusCode)")
                await recordReplayResult(
                    of: transaction,
                    response: response,
                    startedAt: startedAt,
                    state: .completed
                )
                activeToast = ToastMessage(
                    style: .success,
                    text: captureRecordingGate.allowsCapture()
                        ? String(
                            localized: "Replay completed — \(response.statusCode)",
                            bundle: RockxyLocalization.bundle
                        )
                        : String(
                            localized: "Replay completed — \(response.statusCode). Recording is paused, so it was not added to the session.",
                            bundle: RockxyLocalization.bundle
                        )
                )
            } catch {
                Self.logger.error("Replay failed: \(error.localizedDescription)")
                await recordReplayResult(of: transaction, response: nil, startedAt: startedAt, state: .failed)
                activeToast = ToastMessage(
                    style: .error,
                    text: String(
                        localized: "Replay failed — \(error.localizedDescription)",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
        }
    }

    /// Appends the replay outcome to the live session as its own row so the new response can be
    /// inspected, diffed, and exported like any captured flow. The request still bypasses the
    /// proxy pipeline (no rules apply), so the row is attributed to Rockxy itself rather than to
    /// the client that sent the original.
    private func recordReplayResult(
        of original: HTTPTransaction,
        response: HTTPResponseData?,
        startedAt: Date,
        state: TransactionState
    ) async {
        guard captureRecordingGate.allowsCapture(),
              await ensureProjectCatalogReadyForDataIntake() else
        {
            return
        }

        let replay = Self.makeReplayTransaction(
            from: original,
            response: response,
            startedAt: startedAt,
            state: state
        )
        replay.assignCaptureContextIfMissing(activeCaptureContext)
        pendingReplaySelectionIDs.insert(replay.id)
        await sessionManager.addTransaction(replay)
    }

    /// Lists a Compose or Edit and Repeat result in the live session, like a Repeat.
    func recordComposeExchange(_ transaction: HTTPTransaction) async {
        guard captureRecordingGate.allowsCapture(),
              await ensureProjectCatalogReadyForDataIntake() else
        {
            return
        }
        transaction.assignCaptureContextIfMissing(activeCaptureContext)
        await sessionManager.addTransaction(transaction)
    }

    func setupComposeExchangeObserver() {
        guard composeExchangeObserver == nil else {
            return
        }
        composeExchangeObserver = NotificationCenter.default.addObserver(
            forName: .composeExchangeDidComplete, object: nil, queue: .main
        ) { [weak self] notification in
            guard let transaction = notification.object as? HTTPTransaction else {
                return
            }
            Task { @MainActor in
                await self?.recordComposeExchange(transaction)
            }
        }
    }

    /// Builds the session row for a replay. The request is copied without the original's
    /// capture context so the row routes to the currently active Project instead of being
    /// dropped as a stale delivery.
    nonisolated static func makeReplayTransaction(
        from original: HTTPTransaction,
        response: HTTPResponseData?,
        startedAt: Date,
        state: TransactionState,
        now: Date = Date()
    )
        -> HTTPTransaction
    {
        let source = original.request
        let request = HTTPRequestData(
            method: source.method,
            url: source.url,
            httpVersion: source.httpVersion,
            headers: source.headers,
            body: source.body,
            contentType: source.contentType
        )
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let replay = HTTPTransaction(
            timestamp: startedAt,
            request: request,
            response: response,
            state: state,
            timingInfo: TimingInfo(
                dnsLookup: 0,
                tcpConnection: 0,
                tlsHandshake: 0,
                timeToFirstByte: elapsed,
                contentTransfer: 0
            )
        )
        replay.measuredDuration = elapsed
        replay.clientApp = RockxyIdentity.current.displayName
        replay.graphQLInfo = original.graphQLInfo
        replay.sslCapture = request.url.scheme?.lowercased() == "https" ? .intercepted : nil
        return replay
    }

    func editAndReplaySelectedRequest() {
        guard let transaction = selectedTransaction else {
            return
        }
        editAndReplayTransaction(transaction)
    }

    /// Selects a replay row once its batch reaches the active list, provided the current
    /// filter still shows it.
    func selectPendingReplayTransaction(from batch: [HTTPTransaction]) {
        guard !pendingReplaySelectionIDs.isEmpty else {
            return
        }
        let arrived = batch.filter { pendingReplaySelectionIDs.contains($0.id) }
        guard !arrived.isEmpty else {
            return
        }
        pendingReplaySelectionIDs.subtract(arrived.map(\.id))
        guard let latest = arrived.last,
              filteredTransactions.contains(where: { $0.id == latest.id }) else
        {
            return
        }
        selectedTransactionIDs = [latest.id]
        selectTransaction(latest)
    }

    nonisolated static func canReplay(_ transaction: HTTPTransaction) -> Bool {
        transaction.webSocketConnection == nil
            && transaction.request.method.caseInsensitiveCompare("CONNECT") != .orderedSame
    }
}
