import Foundation
import os

/// Batches incoming HTTP transactions from the proxy engine before delivering them to the UI layer.
/// Transactions are flushed either when the batch reaches 50 items or every 100ms, whichever comes
/// first. This prevents per-request UI updates that would bottleneck SwiftUI at high traffic volumes.
/// When the in-memory buffer exceeds `maxBufferSize` (default 50k), the oldest 10% are evicted.
actor TrafficSessionManager {
    // MARK: Internal

    var onBatchReady: (@Sendable ([HTTPTransaction]) -> Void)?
    var onClientAppEnriched: (@Sendable ([UUID]) -> Void)?

    // MARK: - Configuration

    func setOnBatchReady(_ callback: @escaping @Sendable ([HTTPTransaction]) -> Void) {
        onBatchReady = callback
    }

    func setOnClientAppEnriched(_ callback: @escaping @Sendable ([UUID]) -> Void) {
        onClientAppEnriched = callback
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
                try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
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

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "TrafficSessionManager")

    private var pendingUpdates: [HTTPTransaction] = []
    private let batchSize = 50
    private let batchInterval: TimeInterval = 0.1
    private var maxBufferSize: Int = 50000
    private var totalBuffered: Int = 0
    private var proxyPort: Int = 9090
    private var batchTimerTask: Task<Void, Never>?

    // MARK: - Flush and Deliver

    private func flushAndDeliver() {
        guard !pendingUpdates.isEmpty else {
            return
        }

        let batch = pendingUpdates
        pendingUpdates.removeAll()
        totalBuffered += batch.count

        if totalBuffered > maxBufferSize {
            evictOldest()
        }

        onBatchReady?(batch)

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
        let evictionCount = maxBufferSize / 10
        Self.logger.info("Buffer exceeded \(self.maxBufferSize), evicting \(evictionCount) oldest transactions")

        Task {
            do {
                let store = try SessionStore()
                let evictedTransactions = await MainActor.run {
                    NotificationCenter.default.post(
                        name: .bufferEvictionRequested,
                        object: nil,
                        userInfo: ["count": evictionCount]
                    )
                }
                _ = evictedTransactions
            } catch {
                Self.logger.error("Failed to create SessionStore for eviction: \(error.localizedDescription)")
            }
        }

        totalBuffered = max(0, totalBuffered - evictionCount)
    }
}
