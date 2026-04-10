import Foundation
@testable import Rockxy
import Testing

// Tests for `InMemorySessionBuffer`: append/retrieve, ordering, count, clear,
// capacity-based eviction, and unknown-ID lookup.

// MARK: - TrafficCaptureTests

struct TrafficCaptureTests {
    @Test("InMemorySessionBuffer append and retrieve by id")
    func appendAndRetrieve() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)
        let transaction = TestFixtures.makeTransaction()

        await buffer.append(transaction)
        let retrieved = await buffer.transaction(for: transaction.id)

        #expect(retrieved?.id == transaction.id)
    }

    @Test("InMemorySessionBuffer allTransactions returns in order")
    func allTransactionsOrder() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)
        let t1 = TestFixtures.makeTransaction(url: "https://api.example.com/first")
        let t2 = TestFixtures.makeTransaction(url: "https://api.example.com/second")
        let t3 = TestFixtures.makeTransaction(url: "https://api.example.com/third")

        await buffer.append(t1)
        await buffer.append(t2)
        await buffer.append(t3)

        let all = await buffer.allTransactions()

        #expect(all.count == 3)
        #expect(all[0].id == t1.id)
        #expect(all[1].id == t2.id)
        #expect(all[2].id == t3.id)
    }

    @Test("InMemorySessionBuffer count property")
    func countProperty() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)

        let initialCount = await buffer.count
        #expect(initialCount == 0)

        await buffer.append(TestFixtures.makeTransaction())
        await buffer.append(TestFixtures.makeTransaction())

        let afterCount = await buffer.count
        #expect(afterCount == 2)
    }

    @Test("InMemorySessionBuffer clear removes all transactions")
    func clearRemovesAll() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)
        await buffer.append(TestFixtures.makeTransaction())
        await buffer.append(TestFixtures.makeTransaction())

        await buffer.clear()

        let count = await buffer.count
        #expect(count == 0)

        let all = await buffer.allTransactions()
        #expect(all.isEmpty)
    }

    @Test("InMemorySessionBuffer evicts when exceeding capacity")
    func evictionOnCapacityExceeded() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 10)

        for _ in 0 ..< 12 {
            await buffer.append(TestFixtures.makeTransaction())
        }

        let count = await buffer.count
        #expect(count <= 10)
    }

    @Test("InMemorySessionBuffer transaction(for:) returns nil for unknown id")
    func unknownIdReturnsNil() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)
        await buffer.append(TestFixtures.makeTransaction())

        let result = await buffer.transaction(for: UUID())

        #expect(result == nil)
    }
}

// MARK: - TrafficSessionManagerTests

struct TrafficSessionManagerTests {
    @Test("onBatchReady callback receives transactions after setup")
    func batchCallbackReceivesTransactions() async {
        let manager = TrafficSessionManager()

        await manager.setOnBatchReady { _ in }
        await manager.setMaxBufferSize(50_000)

        let transaction = TestFixtures.makeTransaction()
        await manager.addTransaction(transaction)

        let flushed = await manager.flushPendingUpdates()
        #expect(flushed.count == 1)
        #expect(flushed[0].id == transaction.id)
    }

    @Test("onBatchReady nil drops batch silently without crash")
    func nilCallbackDoesNotCrash() async {
        let manager = TrafficSessionManager()

        for _ in 0 ..< 51 {
            await manager.addTransaction(TestFixtures.makeTransaction())
        }
    }

    @Test("batch timer delivers transactions")
    func batchTimerDeliversTransactions() async {
        let manager = TrafficSessionManager()

        let delivered = await withCheckedContinuation { continuation in
            var resumed = false

            Task {
                await manager.setOnBatchReady { batch in
                    guard !batch.isEmpty, !resumed else {
                        return
                    }
                    resumed = true
                    continuation.resume(returning: true)
                }
                await manager.setMaxBufferSize(50_000)
                await manager.startBatchTimer()
                await manager.addTransaction(TestFixtures.makeTransaction())
            }

            Task {
                try? await Task.sleep(for: .seconds(2))
                guard !resumed else {
                    return
                }
                resumed = true
                continuation.resume(returning: false)
            }
        }

        await manager.stopBatchTimer()
        #expect(delivered == true)
    }
}
