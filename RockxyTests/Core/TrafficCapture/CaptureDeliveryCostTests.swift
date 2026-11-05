import Foundation
@testable import Rockxy
import Testing

// MARK: - CaptureDeliveryCostTests

/// Pins the main-thread cost of one capture batch as counted work, not elapsed time: how many
/// AI signal evaluations and row projections the main thread performs, and how often delivery
/// wiring is installed. Counts do not depend on machine speed, so they cannot flake in CI.
@MainActor
struct CaptureDeliveryCostTests {
    // MARK: Internal

    @Test("A delivered batch costs the main thread no AI signal evaluations")
    func deliveredBatchArrivesWithSignalsCached() async {
        let batch = Self.settled(Self.batchSize, prefix: "warm")
        let delivered = await Self.deliverThroughSessionActor(batch)
        #expect(delivered.count == Self.batchSize)

        let coordinator = MainContentCoordinator()
        let evaluationsBefore = AITrafficDetector.signalEvaluationCounts.onMainThread
        coordinator.processActiveProjectTestBatch(delivered)
        let evaluationsOnMain = AITrafficDetector.signalEvaluationCounts.onMainThread - evaluationsBefore

        #expect(evaluationsOnMain == 0)
        #expect(coordinator.filteredRows.count == Self.batchSize)
    }

    @Test("Without the session actor's warm-up the same batch evaluates once per row on the main thread")
    func coldBatchEvaluatesOnMainThread() {
        let batch = Self.settled(Self.batchSize, prefix: "cold")
        let coordinator = MainContentCoordinator()
        let evaluationsBefore = AITrafficDetector.signalEvaluationCounts.onMainThread
        coordinator.processActiveProjectTestBatch(batch)
        let evaluationsOnMain = AITrafficDetector.signalEvaluationCounts.onMainThread - evaluationsBefore

        // This is the cost the warm-up removes; it also proves the counter observes the work.
        #expect(evaluationsOnMain == Self.batchSize)
    }

    @Test("Open streams are not read off the main actor while they can still change")
    func liveRowsAreNotWarmed() async {
        let live = TestFixtures.makeTransaction(state: .active)
        live.deliversLiveRow = true
        let settled = Self.settled(Self.batchSize - 1, prefix: "mixed")
        let manager = TrafficSessionManager()
        let received = LockedBox<[HTTPTransaction]>([])
        await manager.setOnBatchReady { delivered, _ in received.set(delivered) }
        await manager.addTransaction(live)
        for transaction in settled {
            await manager.addTransaction(transaction)
        }

        #expect(received.get().count == Self.batchSize)
        #expect(AITrafficDetector.cachedSignal(transaction: live) == nil)
        #expect(settled.allSatisfy { AITrafficDetector.cachedSignal(transaction: $0) != nil })
    }

    @Test("Appending a batch at the history cap projects only the new rows")
    func capBatchProjectsOnlyNewRows() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 1_000
        coordinator.processActiveProjectTestBatch(Self.settled(1_000, prefix: "fill"))
        #expect(coordinator.transactions.count == 1_000)

        let incoming = Self.settled(20, prefix: "next")
        let projectionsBefore = RequestListRow.mainThreadProjectionCount
        coordinator.processActiveProjectTestBatch(incoming)
        let projections = RequestListRow.mainThreadProjectionCount - projectionsBefore

        // Eviction ran, yet no retained row was rebuilt: 20 arrived, 20 were projected.
        #expect(coordinator.transactions.count <= 1_000)
        #expect(coordinator.transactions.suffix(20).map(\.id) == incoming.map(\.id))
        #expect(projections == incoming.count)
    }

    @Test("Delivery wiring is installed once, not once per batch")
    func deliveryCallbacksAreInstalledOnce() async {
        let coordinator = MainContentCoordinator()
        await coordinator.configureSessionDeliveryCallbacks()
        let installsAfterSetup = await coordinator.sessionManager.batchCallbackInstallCount
        let context = coordinator.activeCaptureContext

        for batchIndex in 0 ..< 3 {
            for transaction in Self.settled(Self.batchSize, prefix: "wire\(batchIndex)") {
                transaction.assignCaptureContextIfMissing(context)
                await coordinator.sessionManager.addTransaction(transaction)
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while coordinator.transactions.count < Self.batchSize * 3, ContinuousClock.now < deadline {
            await Task.yield()
        }

        #expect(coordinator.transactions.count == Self.batchSize * 3)
        #expect(installsAfterSetup == 1)
        let installsAfterTraffic = await coordinator.sessionManager.batchCallbackInstallCount
        #expect(installsAfterTraffic == installsAfterSetup)
    }

    // MARK: Private

    private static let batchSize = 50

    private static func settled(_ count: Int, prefix: String) -> [HTTPTransaction] {
        (0 ..< count).map { index in
            let transaction = TestFixtures.makeTransaction(
                method: "POST",
                url: "https://api.example.com/\(prefix)/\(index)"
            )
            transaction.request.body = Data(repeating: UInt8(ascii: "a"), count: 4_096)
            transaction.response?.body = Data(repeating: UInt8(ascii: "b"), count: 4_096)
            return transaction
        }
    }

    /// Runs one full flush on the session actor and returns what the delivery callback saw.
    private static func deliverThroughSessionActor(_ batch: [HTTPTransaction]) async -> [HTTPTransaction] {
        let manager = TrafficSessionManager()
        let received = LockedBox<[HTTPTransaction]>([])
        let seenCachedBeforeDelivery = LockedBox<[Bool]>([])
        await manager.setOnBatchReady { delivered, _ in
            received.set(delivered)
            seenCachedBeforeDelivery.set(delivered.map { AITrafficDetector.cachedSignal(transaction: $0) != nil })
        }
        for transaction in batch {
            await manager.addTransaction(transaction)
        }
        // Reaching the batch size flushes synchronously inside the last addTransaction.
        #expect(seenCachedBeforeDelivery.get().count == batch.count)
        #expect(seenCachedBeforeDelivery.get().allSatisfy { $0 })
        return received.get()
    }
}

// MARK: - LockedBox

private final class LockedBox<Value>: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ value: Value) {
        self.value = value
    }

    // MARK: Internal

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var value: Value
}
