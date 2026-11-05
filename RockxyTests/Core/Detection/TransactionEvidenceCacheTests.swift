import Foundation
@testable import Rockxy
import Testing

struct TransactionEvidenceCacheTests {
    // MARK: Internal

    @Test("Inserting past the count limit retains no more than the limit")
    func insertsPastTheLimitAreBounded() {
        let cache = TransactionEvidenceCache<Entry>(countLimit: 10)
        for _ in 0 ..< 200 {
            cache.store(Entry())
        }
        #expect(cache.count <= 10)
        #expect(!cache.isEmpty)
    }

    @Test("Discarding ids removes exactly those entries and reports how many were held")
    func discardRemovesOnlyTheNamedEntries() {
        let cache = TransactionEvidenceCache<Entry>(countLimit: 100)
        let entries = (0 ..< 8).map { _ in Entry() }
        entries.forEach { cache.store($0) }
        #expect(cache.count == 8)

        let removed = cache.discard(entries.prefix(5).map(\.cacheID))

        #expect(removed == 5)
        #expect(cache.count == 3)
        #expect(entries.prefix(5).allSatisfy { cache.entry(for: $0.cacheID) == nil })
        #expect(entries.suffix(3).allSatisfy { cache.entry(for: $0.cacheID) === $0 })
    }

    @Test("Discarding an id that was never cached is a no-op")
    func discardingAnUnknownIDChangesNothing() {
        let cache = TransactionEvidenceCache<Entry>(countLimit: 100)
        let kept = Entry()
        cache.store(kept)

        let removed = cache.discard([UUID(), UUID()])
        let removedFromEmpty = cache.discard([UUID]())

        #expect(removed == 0)
        #expect(removedFromEmpty == 0)
        #expect(cache.count == 1)
        #expect(cache.entry(for: kept.cacheID) === kept)
    }

    @Test("Discarding the same id twice counts it once")
    func repeatedDiscardIsIdempotent() {
        let cache = TransactionEvidenceCache<Entry>(countLimit: 100)
        let entry = Entry()
        cache.store(entry)

        #expect(cache.discard([entry.cacheID]) == 1)
        #expect(cache.discard([entry.cacheID]) == 0)
        // `count` is documented as an upper bound, so zero is the strong assertion here:
        // it cannot overcount to zero.
        #expect(cache.isEmpty)
    }

    @Test("Replacing an entry for the same id keeps one tracked key")
    func replacingAnEntryKeepsOneKey() {
        let cache = TransactionEvidenceCache<Entry>(countLimit: 100)
        let id = UUID()
        let first = Entry(id: id)
        let second = Entry(id: id)
        cache.store(first)
        cache.store(second)

        #expect(cache.count == 1)
        #expect(cache.entry(for: id) === second)
        #expect(cache.discard([id]) == 1)
        #expect(cache.entry(for: id) == nil)
    }

    @Test("Discarding evicted rows drops their cached signal and filter facts")
    func detectorDiscardDropsBothCaches() {
        let kept = makeTransaction()
        let evicted = makeTransaction()
        _ = AITrafficDetector.signal(transaction: kept)
        _ = AITrafficDetector.signal(transaction: evicted)
        _ = AITrafficDetector.filterFacts(transaction: kept)
        _ = AITrafficDetector.filterFacts(transaction: evicted)
        #expect(AITrafficDetector.cachedSignal(transaction: evicted) != nil)
        #expect(AITrafficDetector.cachedFilterFacts(transaction: evicted) != nil)

        AITrafficDetector.discardCachedEvidence(for: [evicted.id, UUID()])

        #expect(AITrafficDetector.cachedSignal(transaction: evicted) == nil)
        #expect(AITrafficDetector.cachedFilterFacts(transaction: evicted) == nil)
        #expect(AITrafficDetector.cachedSignal(transaction: kept) != nil)
        #expect(AITrafficDetector.cachedFilterFacts(transaction: kept) != nil)
    }

    @Test("A discarded row is re-evaluated, not served stale")
    func discardedRowIsEvaluatedAgain() {
        let transaction = makeTransaction()
        _ = AITrafficDetector.signal(transaction: transaction)
        AITrafficDetector.discardCachedEvidence(for: [transaction.id])
        #expect(AITrafficDetector.cachedSignal(transaction: transaction) == nil)

        _ = AITrafficDetector.signal(transaction: transaction)

        #expect(AITrafficDetector.cachedSignal(transaction: transaction) != nil)
    }

    // MARK: Private

    private final class Entry: TransactionCacheEntry {
        // MARK: Lifecycle

        init(id: UUID = UUID()) {
            cacheID = id
        }

        // MARK: Internal

        let cacheID: UUID
    }

    private func makeTransaction() -> HTTPTransaction {
        let request = HTTPRequestData(
            method: "GET",
            url: URL(string: "https://example.test/evidence-\(UUID().uuidString)")!,
            httpVersion: "HTTP/1.1",
            headers: [],
            body: nil,
            contentType: nil
        )
        return HTTPTransaction(request: request, response: nil, state: .completed)
    }
}
