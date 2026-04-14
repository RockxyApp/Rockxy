import Foundation
import os

/// Batches incoming HTTP transactions from the proxy engine before delivering them to the UI layer.
/// Transactions are flushed either when the batch reaches 50 items or every 100ms, whichever comes
/// first. This prevents per-request UI updates that would bottleneck SwiftUI at high traffic volumes.
/// When the accepted-count exceeds `maxBufferSize`, the actor posts a single eviction request
/// sized to the exact overflow so the main-actor live history converges to the cap in one round.
actor TrafficSessionManager {
    // MARK: Internal

    var onBatchReady: (@Sendable ([HTTPTransaction], _ generation: UInt) -> Void)?
    var onClientAppEnriched: (@Sendable ([UUID]) -> Void)?
    var onBeginNewSession: (@Sendable (_ generation: UInt) async -> Void)?

    var currentGeneration: UInt {
        generation
    }

    // MARK: - Configuration

    func setOnBatchReady(_ callback: @escaping @Sendable ([HTTPTransaction], _ generation: UInt) -> Void) {
        onBatchReady = callback
    }

    func setOnClientAppEnriched(_ callback: @escaping @Sendable ([UUID]) -> Void) {
        onClientAppEnriched = callback
    }

    func setOnBeginNewSession(_ callback: (@Sendable (_ generation: UInt) async -> Void)?) {
        onBeginNewSession = callback
    }

    func setMaxBufferSize(_ size: Int) {
        maxBufferSize = size
    }

    func setProxyPort(_ port: Int) {
        proxyPort = port
    }

    // MARK: - Transaction Intake

    func addTransaction(_ transaction: HTTPTransaction) {
        pendingUpdates.append(transaction)

        if pendingUpdates.count >= batchSize {
            flushAndDeliver()
        }
    }

    func flushPendingUpdates() -> [HTTPTransaction] {
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
        totalBuffered = 0
        generation &+= 1
    }

    /// Clears pending updates, resets buffered counts, bumps the generation, and invokes
    /// `onBeginNewSession(generation)` when set. Returns the new generation so the caller
    /// can align its own generation tag with the actor's. Use this for production session
    /// rollovers where the callback must run before the new generation is observed.
    func beginNewSession() async -> UInt {
        pendingUpdates.removeAll()
        totalBuffered = 0
        generation &+= 1
        if let onBeginNewSession {
            await onBeginNewSession(generation)
        }
        return generation
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
    private let batchSize = 50
    private let batchInterval: TimeInterval = 0.1
    private var maxBufferSize: Int = 50_000
    private var totalBuffered: Int = 0
    private var generation: UInt = 0
    private var proxyPort: Int = 9_090
    private var batchTimerTask: Task<Void, Never>?

    // MARK: - Flush and Deliver

    private func flushAndDeliver() {
        guard !pendingUpdates.isEmpty else {
            return
        }

        let batch = pendingUpdates
        let batchGeneration = generation
        pendingUpdates.removeAll()

        onBatchReady?(batch, batchGeneration)

        let port = proxyPort
        let enrichCallback = onClientAppEnriched
        Task {
            let portMap = await ProcessResolver.shared.resolveProcessesAsync(proxyPort: port)
            var enrichedIDs: [UUID] = []
            for transaction in batch where transaction.clientApp == nil {
                if let srcPort = transaction.sourcePort, let app = portMap[srcPort] {
                    transaction.clientApp = app
                    enrichedIDs.append(transaction.id)
                }
            }
            if !enrichedIDs.isEmpty {
                enrichCallback?(enrichedIDs)
            }
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
