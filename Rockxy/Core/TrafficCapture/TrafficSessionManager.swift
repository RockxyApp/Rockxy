import Foundation
import os

// MARK: - TrafficSessionManager

/// Batches incoming HTTP transactions from the proxy engine before delivering them to the UI layer.
/// Transactions are flushed either when the batch reaches 50 items or every 100ms, whichever comes
/// first. This prevents per-request UI updates that would bottleneck SwiftUI at high traffic volumes.
/// When the accepted-count exceeds `maxBufferSize`, the actor posts a single eviction request
/// sized to the exact overflow so the main-actor live history converges to the cap in one round.
actor TrafficSessionManager {
    // MARK: Internal

    var onBatchReady: (@Sendable ([HTTPTransaction], _ generation: UInt) -> Void)?
    var onClientAppEnriched: (@Sendable ([HTTPTransaction]) -> Void)?
    var onLiveTransactionUpdated: (@Sendable ([HTTPTransaction]) -> Void)?
    var onBeginNewSession: (@Sendable (_ generation: UInt) async -> Void)?

    var currentGeneration: UInt {
        generation
    }

    // MARK: - Configuration

    func setOnBatchReady(_ callback: @escaping @Sendable ([HTTPTransaction], _ generation: UInt) -> Void) {
        onBatchReady = callback
    }

    func setOnClientAppEnriched(_ callback: @escaping @Sendable ([HTTPTransaction]) -> Void) {
        onClientAppEnriched = callback
    }

    /// Receives long-lived transactions (WebSocket connections) that were already delivered as
    /// live rows and have since changed state, so the UI refreshes them in place.
    func setOnLiveTransactionUpdated(_ callback: @escaping @Sendable ([HTTPTransaction]) -> Void) {
        onLiveTransactionUpdated = callback
    }

    func setOnBeginNewSession(_ callback: (@Sendable (_ generation: UInt) async -> Void)?) {
        onBeginNewSession = callback
    }

    func setMaxBufferSize(_ size: Int) {
        maxBufferSize = max(1, size)
        completedLiveTransactionIDs.setCapacity(maxBufferSize)
        dismissedLiveTransactionIDs.setCapacity(maxBufferSize)
    }

    func setProxyPort(_ port: Int) {
        proxyPort = port
    }

    // MARK: - Transaction Intake

    /// Takes in one delivered transaction.
    ///
    /// - Parameter acceptsNewRows: `false` while recording is paused. A paused capture still
    ///   finishes rows it already shows — otherwise a stream or WebSocket that closes during the
    ///   pause would stay `Active` in the list — but it never adds a new one.
    func addTransaction(_ transaction: HTTPTransaction, acceptsNewRows: Bool = true) {
        // A proxied WebSocket, and a streaming (SSE/NDJSON) response, is delivered once when it
        // opens and once when it finishes, through independent tasks that can arrive in either
        // order. Whichever delivery comes first adds the row; the other one is an in-place
        // update. A delivery for a row dismissed by Clear Session is dropped so the finished
        // connection cannot resurface as a new row.
        if dismissedLiveTransactionIDs.contains(transaction.id)
            || completedLiveTransactionIDs.contains(transaction.id)
        {
            return
        }
        if liveTransactionIDs.contains(transaction.id) {
            if transaction.state != .active, transaction.state != .pending {
                liveTransactionIDs.remove(transaction.id)
                liveCaptureContexts.removeValue(forKey: transaction.id)
                completedLiveTransactionIDs.insert(transaction.id)
            }
            if let index = pendingLiveUpdateIndices[transaction.id] {
                pendingLiveUpdates[index] = transaction
            } else {
                pendingLiveUpdateIndices[transaction.id] = pendingLiveUpdates.count
                pendingLiveUpdates.append(transaction)
            }
            if pendingLiveUpdates.count >= batchSize {
                flushAndDeliver()
            }
            return
        }
        guard acceptsNewRows else {
            return
        }
        if transaction.deliversLiveRow {
            if transaction.state == .active || transaction.state == .pending {
                liveTransactionIDs.insert(transaction.id)
                liveCaptureContexts[transaction.id] = transaction.captureContext
            } else {
                // The close can overtake the open, or be the only accepted delivery
                // after Pause. Publish its final row once without retaining an open ID.
                completedLiveTransactionIDs.insert(transaction.id)
            }
        }
        pendingUpdates.append(transaction)

        if pendingUpdates.count >= batchSize {
            flushAndDeliver()
        }
    }

    func flushPendingUpdates() -> [HTTPTransaction] {
        defer { flushLiveUpdates() }
        let updates = pendingUpdates
        pendingUpdates.removeAll()
        return updates
    }

    // MARK: - Batch Timer

    func startBatchTimer() {
        batchTimerTask?.cancel()

        let interval = batchInterval
        batchTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(interval * 1_000)))
                guard !Task.isCancelled else {
                    break
                }
                await self?.flushAndDeliver()
            }
        }
    }

    func stopBatchTimer() {
        batchTimerTask?.cancel()
        batchTimerTask = nil
    }

    /// Clears pending updates, resets buffered counts, and bumps the generation.
    /// Synchronous. Does not invoke `onBeginNewSession`. Use when the caller only needs
    /// local state cleared (e.g. tests) and does not rely on the rollover callback.
    func resetBufferState() {
        pendingUpdates.removeAll()
        pendingLiveUpdates.removeAll()
        pendingLiveUpdateIndices.removeAll()
        dismissLiveTransactions()
        totalBuffered = 0
        generation &+= 1
    }

    /// Clears pending updates, resets buffered counts, bumps the generation, and invokes
    /// `onBeginNewSession(generation)` when set. Returns the new generation so the caller
    /// can align its own generation tag with the actor's. Use this for production session
    /// rollovers where the callback must run before the new generation is observed.
    func beginNewSession() async -> UInt {
        let rollover = await beginNewSessionPreservingPending()
        return rollover.generation
    }

    /// Atomically advances the global delivery generation while returning the
    /// pending transactions that had already completed. Project-scoped clear uses
    /// this to retain only explicitly routed transactions owned by other Projects;
    /// unowned and active-Project pending work is still discarded.
    func beginNewSessionPreservingPending() async -> (generation: UInt, pending: [HTTPTransaction]) {
        await beginNewSessionPreservingPending(clearingProjectInto: nil)
    }

    /// Retains streams belonging to other Projects and requests already stamped with the
    /// target Project's new context while its clear crosses the actor boundary.
    func beginNewSessionPreservingPending(
        clearingProjectInto nextContext: TrafficCaptureContext?
    )
        async -> (generation: UInt, pending: [HTTPTransaction])
    {
        let pending = pendingUpdates
        pendingUpdates.removeAll()
        pendingLiveUpdates.removeAll { !Self.survivesClear($0.captureContext, into: nextContext) }
        pendingLiveUpdateIndices = Dictionary(uniqueKeysWithValues: pendingLiveUpdates.enumerated().map {
            ($0.element.id, $0.offset)
        })
        dismissLiveTransactions(clearingProjectInto: nextContext)
        totalBuffered = 0
        generation &+= 1
        if let onBeginNewSession {
            await onBeginNewSession(generation)
        }
        return (generation, pending)
    }

    func reportAcceptedCount(_ count: Int, generation: UInt) {
        guard generation == self.generation else {
            return
        }
        totalBuffered += count
        if totalBuffered > maxBufferSize {
            evictOldest()
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "TrafficSessionManager"
    )

    private var pendingUpdates: [HTTPTransaction] = []
    /// Closing many streams during Stop must not enqueue one full-history UI refresh per row.
    /// Bound completion delivery by the same batch size and timer as new rows.
    private var pendingLiveUpdates: [HTTPTransaction] = []
    private var pendingLiveUpdateIndices: [UUID: Int] = [:]
    /// Live (still open) connections already delivered as rows, keyed for update routing.
    private var liveTransactionIDs: Set<UUID> = []
    private var liveCaptureContexts: [UUID: TrafficCaptureContext] = [:]
    /// Live connections whose rows were cleared; their close delivery must not resurface them.
    private var dismissedLiveTransactionIDs = RecentLiveTransactionIDs(capacity: 50_000)
    /// Remember finalized live identities so duplicate terminal deliveries stay idempotent.
    /// This is bounded by the configured history cap, rather than growing across a long session.
    private var completedLiveTransactionIDs = RecentLiveTransactionIDs(capacity: 50_000)
    private let batchSize = 50
    private let batchInterval: TimeInterval = 0.1
    private var maxBufferSize: Int = 50_000
    private var totalBuffered: Int = 0
    private var generation: UInt = 0
    private var proxyPort: Int = 9_090
    private var batchTimerTask: Task<Void, Never>?

    private static func survivesClear(
        _ context: TrafficCaptureContext?,
        into nextContext: TrafficCaptureContext?
    )
        -> Bool
    {
        guard let nextContext, let context else {
            return false
        }
        return context.projectID != nextContext.projectID || context == nextContext
    }

    // MARK: - Flush and Deliver

    private func flushAndDeliver() {
        // Publish new rows first when a short stream opens and closes inside one interval.
        defer { flushLiveUpdates() }
        guard !pendingUpdates.isEmpty else {
            return
        }

        let batch = pendingUpdates
        let batchGeneration = generation
        pendingUpdates.removeAll()

        onBatchReady?(batch, batchGeneration)

        let port = proxyPort
        let enrichCallback = onClientAppEnriched
        let unresolvedSourcePorts = Set(batch.compactMap { transaction in
            transaction.clientApp == nil ? transaction.sourcePort : nil
        })
        guard !unresolvedSourcePorts.isEmpty else {
            return
        }
        Task {
            let portMap = await ProcessResolver.shared.resolveProcessesAsync(
                proxyPort: port,
                requiring: unresolvedSourcePorts
            )
            await MainActor.run {
                var enrichedTransactions: [HTTPTransaction] = []
                for transaction in batch where transaction.clientApp == nil {
                    if let srcPort = transaction.sourcePort, let app = portMap[srcPort] {
                        transaction.clientApp = app
                        enrichedTransactions.append(transaction)
                    }
                }
                if !enrichedTransactions.isEmpty {
                    enrichCallback?(enrichedTransactions)
                }
            }
        }
    }

    private func flushLiveUpdates() {
        guard !pendingLiveUpdates.isEmpty else {
            return
        }
        let updates = pendingLiveUpdates
        pendingLiveUpdates.removeAll(keepingCapacity: true)
        pendingLiveUpdateIndices.removeAll(keepingCapacity: true)
        onLiveTransactionUpdated?(updates)
    }

    private func dismissLiveTransactions(clearingProjectInto nextContext: TrafficCaptureContext? = nil) {
        let dismissed = liveTransactionIDs.filter {
            !Self.survivesClear(liveCaptureContexts[$0], into: nextContext)
        }
        for id in dismissed {
            dismissedLiveTransactionIDs.insert(id)
            liveTransactionIDs.remove(id)
            liveCaptureContexts.removeValue(forKey: id)
        }
    }

    // MARK: - Eviction

    private func evictOldest() {
        let overflow = totalBuffered - maxBufferSize
        guard overflow > 0 else {
            return
        }
        Self.logger.info("Buffer exceeded \(self.maxBufferSize), evicting \(overflow) oldest transactions")

        Task {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .bufferEvictionRequested,
                    object: nil,
                    userInfo: ["count": overflow]
                )
            }
        }

        totalBuffered = maxBufferSize
    }
}

// MARK: - RecentLiveTransactionIDs

/// A bounded identity window with amortized constant-time insertion and retirement.
/// Keep tombstones across Clear so repeated old completions cannot resurrect discarded rows.
struct RecentLiveTransactionIDs {
    // MARK: Lifecycle

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    // MARK: Internal

    var count: Int {
        identities.count
    }

    func contains(_ id: UUID) -> Bool {
        identities.contains(id)
    }

    mutating func insert(_ id: UUID) {
        guard identities.insert(id).inserted else {
            return
        }
        order.append(id)
        trim()
    }

    mutating func setCapacity(_ capacity: Int) {
        self.capacity = max(1, capacity)
        trim()
    }

    // MARK: Private

    private var capacity: Int
    private var identities: Set<UUID> = []
    private var order: [UUID] = []
    private var head = 0

    private mutating func trim() {
        while identities.count > capacity {
            identities.remove(order[head])
            head += 1
        }
        // Compact in chunks so a full window never shifts an array for each completion.
        if head >= max(1_024, order.count / 2) {
            order.removeFirst(head)
            head = 0
        }
    }
}
