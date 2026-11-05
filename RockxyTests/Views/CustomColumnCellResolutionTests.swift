import Foundation
@testable import Rockxy
import Testing

// The AppKit cell callback is a thin consumer of `CustomColumnCellResolution` and
// `CustomColumnCellScheduler`. The failure these guard against is visible only as blank or wrong
// cells in a running table, so the decisions are proven here without a table: what a cell shows
// before and after a value exists, and that a late value is only ever delivered under the identity
// of the row it was requested for.

// MARK: - CustomColumnCellResolutionTests

@MainActor
struct CustomColumnCellResolutionTests {
    // MARK: Internal

    @Test("An unresolved body column is pending with a placeholder, and nothing is evaluated")
    func unresolvedBodyColumnIsPending() {
        let (transaction, row) = Self.makeRow(body: #"{"id":11}"#)

        let state = CustomColumnCellResolution.value(columnID: Self.column, row: row)

        #expect(state == .pending)
        #expect(state.displayText == CustomColumnCellValue.placeholder)
        #expect(!state.displayText.isEmpty, "a pending cell must never look like an empty column")
        #expect(transaction.customColumnValueCache.value(for: "req:.id") == nil)
    }

    @Test("A cached body column shows its value at once, including a legitimately empty one")
    func cachedBodyColumnIsResolved() {
        let (transaction, row) = Self.makeRow(body: #"{"id":11}"#)
        transaction.customColumnValueCache.store("11", for: "req:.id")
        #expect(CustomColumnCellResolution.value(columnID: Self.column, row: row) == .resolved("11"))

        transaction.customColumnValueCache.store("", for: "req:.id")
        #expect(CustomColumnCellResolution.value(columnID: Self.column, row: row) == .resolved(""))
    }

    @Test("A row whose transaction is gone resolves to empty instead of staying pending forever")
    func releasedTransactionDoesNotStayPending() throws {
        var transaction: HTTPTransaction? = TestFixtures.makeTransaction(url: "https://a.example.com/x")
        let row = try RequestListRow(from: #require(transaction))
        transaction = nil

        #expect(CustomColumnCellResolution.value(columnID: Self.column, row: row) == .resolved(""))
    }

    @Test("Header and query columns are never pending")
    func cheapColumnsResolveImmediately() {
        // Named and kept alive below: `row.source` is weak, so a discarded transaction is released
        // at once and the query column then correctly reads as empty.
        let (transaction, row) = Self.makeRow(body: "{}", url: "https://a.example.com/x?page=3")
        defer { withExtendedLifetime(transaction) {} }

        #expect(CustomColumnCellResolution.value(columnID: "reqQuery.page", row: row) == .resolved("3"))
        #expect(CustomColumnCellResolution.value(columnID: "reqHeader.X-Absent", row: row) == .resolved(""))
    }

    @Test("Locating by identity ignores index position and refuses a row that left the screen")
    func visibleRowLookupIsByIdentity() {
        let ids = (0 ..< 10).map { _ in UUID() }
        let visible = 3 ..< 7

        #expect(CustomColumnCellResolution.visibleRowIndex(of: ids[5], among: visible) { ids[$0] } == 5)
        #expect(CustomColumnCellResolution.visibleRowIndex(of: ids[1], among: visible) { ids[$0] } == nil)

        // The same position now holds a different transaction: the old id is not found there.
        var shifted = ids
        shifted.insert(UUID(), at: 0)
        #expect(CustomColumnCellResolution.visibleRowIndex(of: ids[5], among: visible) { shifted[$0] } == 6)
        // ids[3] moved to position 4, still on screen, so it is found there by identity.
        #expect(CustomColumnCellResolution.visibleRowIndex(of: ids[3], among: visible) { shifted[$0] } == 4)
        // ids[6] moved to position 7, past the visible range: gone, so a late value is dropped.
        #expect(CustomColumnCellResolution.visibleRowIndex(of: ids[6], among: visible) { shifted[$0] } == nil)
    }

    @Test("A resolved value is delivered under the requesting row's identity and fills the cache")
    func deliveryCarriesIdentityAndFillsCache() async {
        let (transaction, row) = Self.makeRow(body: #"{"id":11}"#)
        let recorder = Recorder()
        let scheduler = CustomColumnCellScheduler(isStillWanted: { _ in true }, deliver: recorder.record)

        scheduler.request(columnID: Self.column, row: row)
        await recorder.waitForDeliveries(1)

        #expect(recorder.delivered == [Delivery(
            key: CustomColumnCellKey(rowID: row.id, columnID: Self.column),
            value: "11"
        )])
        // A recycled cell repopulating this row now reads the value synchronously.
        #expect(CustomColumnCellResolution.value(columnID: Self.column, row: row) == .resolved("11"))
        #expect(scheduler.inFlight.isEmpty)
        _ = transaction
    }

    @Test("Out-of-order arrival: each value is delivered to its own row, not to the latest")
    func outOfOrderArrivalKeepsIdentity() async {
        let (txA, rowA) = Self.makeRow(body: #"{"id":"A"}"#)
        let (txB, rowB) = Self.makeRow(body: #"{"id":"B"}"#)
        let gateA = Gate()
        let gateB = Gate()
        let recorder = Recorder()
        let scheduler = CustomColumnCellScheduler(
            evaluate: { _, _, transaction in
                let isA = transaction.request.body.flatMap { String(data: $0, encoding: .utf8) }?.contains("A") == true
                await (isA ? gateA : gateB).wait()
                return isA ? "value-A" : "value-B"
            },
            isStillWanted: { _ in true },
            deliver: recorder.record
        )

        scheduler.request(columnID: Self.column, row: rowA)
        scheduler.request(columnID: Self.column, row: rowB)
        #expect(scheduler.inFlight.count == 2)

        await gateB.open() // B finishes first although A was requested first.
        await recorder.waitForDeliveries(1)
        await gateA.open()
        await recorder.waitForDeliveries(2)

        let byRow = Dictionary(uniqueKeysWithValues: recorder.delivered.map { ($0.key.rowID, $0.value) })
        #expect(byRow[rowA.id] == "value-A")
        #expect(byRow[rowB.id] == "value-B")
        #expect(recorder.delivered.first?.key.rowID == rowB.id)
        _ = (txA, txB)
    }

    @Test("A late result for a recycled row is delivered under the old identity, never as a new row's")
    func recycledRowResultIsKeyedToTheOldRow() async {
        // Position 0 held `old` when the request started and holds `new` when the value lands.
        let (txOld, old) = Self.makeRow(body: #"{"id":"old"}"#)
        let (txNew, new) = Self.makeRow(body: #"{"id":"new"}"#)
        var rowsAtPositionZero = [old.id]
        let gate = Gate()
        let recorder = Recorder()
        let scheduler = CustomColumnCellScheduler(
            evaluate: { _, _, _ in
                await gate.wait()
                return "value-old"
            },
            isStillWanted: { _ in true },
            deliver: recorder.record
        )

        scheduler.request(columnID: Self.column, row: old)
        rowsAtPositionZero = [new.id] // AppKit recycled the cell to a different transaction.
        await gate.open()
        await recorder.waitForDeliveries(1)

        let key = recorder.delivered[0].key
        #expect(key.rowID == old.id)
        // This is the check the table performs before writing: the key no longer maps to position 0.
        let located = CustomColumnCellResolution.visibleRowIndex(of: key.rowID, among: 0 ..< 1) {
            rowsAtPositionZero[$0]
        }
        #expect(located == nil, "the late value would have been written into the new row's cell")
        #expect(CustomColumnCellResolution.value(columnID: Self.column, row: new) == .pending)
        _ = (txOld, txNew)
    }

    @Test("A cell already in flight is not evaluated twice, and a scrolled-away row is skipped")
    func duplicatesAndOffscreenRowsAreNotEvaluated() async {
        let (tx, row) = Self.makeRow(body: #"{"id":1}"#)
        let counter = Counter()
        let gate = Gate()
        var wanted = true
        let recorder = Recorder()
        let scheduler = CustomColumnCellScheduler(
            evaluate: { _, _, _ in
                await counter.increment()
                await gate.wait()
                return "1"
            },
            isStillWanted: { _ in wanted },
            deliver: recorder.record
        )

        scheduler.request(columnID: Self.column, row: row)
        scheduler.request(columnID: Self.column, row: row)
        #expect(scheduler.inFlight.count == 1)
        await gate.open()
        await recorder.waitForDeliveries(1)
        #expect(await counter.value == 1)

        // Off screen by the time the task starts: nothing is evaluated and the slot is released.
        let (tx2, row2) = Self.makeRow(body: #"{"id":2}"#)
        wanted = false
        scheduler.request(columnID: Self.column, row: row2)
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        #expect(await counter.value == 1)
        #expect(scheduler.inFlight.isEmpty)
        _ = (tx, tx2)
    }

    @Test("Cached and non-body columns are not scheduled")
    func nothingToScheduleForResolvedColumns() {
        let (tx, row) = Self.makeRow(body: #"{"id":1}"#)
        tx.customColumnValueCache.store("1", for: "req:.id")
        let scheduler = CustomColumnCellScheduler(isStillWanted: { _ in true }, deliver: { _, _ in })

        scheduler.request(columnID: Self.column, row: row)
        scheduler.request(columnID: "reqHeader.Accept", row: row)
        scheduler.request(columnID: "reqQuery.page", row: row)

        #expect(scheduler.inFlight.isEmpty)
    }

    @Test("The cache refuses a store computed before its evidence was cleared")
    func cacheRefusesStoreFromAnEarlierGeneration() {
        let cache = CustomColumnValueCache()
        let generation = cache.generation

        cache.removeAll()

        #expect(!cache.store("stale", for: "req:.id", ifGeneration: generation))
        #expect(cache.value(for: "req:.id") == nil)
        #expect(cache.store("fresh", for: "req:.id", ifGeneration: cache.generation))
        #expect(cache.value(for: "req:.id") == "fresh")
    }

    @Test("Evidence changing mid-evaluation never leaves the stale value in the cache or the cell")
    func staleResultIsNeverCachedOrDelivered() async {
        let (transaction, row) = Self.makeRow(body: "OLD")
        let gate = Gate()
        let counter = Counter()
        let recorder = Recorder()
        let scheduler = CustomColumnCellScheduler(
            evaluate: { expression, response, transaction in
                // Evaluates the body text itself, so the value says which evidence it came from.
                await CustomColumnValueResolver.resolveBodyValue(
                    expression: expression,
                    response: response,
                    transaction: transaction,
                    evaluator: { _, data in
                        let text = String(data: data, encoding: .utf8) ?? ""
                        if await counter.increment() == 1 {
                            await gate.wait() // hold the first evaluation, on the OLD evidence
                        }
                        return text
                    }
                )
            },
            isStillWanted: { _ in true },
            deliver: recorder.record
        )

        scheduler.request(columnID: Self.column, row: row)
        for _ in 0 ..< 200 where await counter.value == 0 {
            await Task.yield()
        }
        #expect(await counter.value == 1, "the first evaluation never started")

        transaction.request.body = Data("NEW".utf8) // evidence changes while it is in flight
        #expect(transaction.customColumnValueCache.value(for: "req:.id") == nil)
        await gate.open()
        await recorder.waitForDeliveries(1)

        #expect(recorder.delivered[0].value == "NEW", "the cell was handed the stale value")
        #expect(transaction.customColumnValueCache.value(for: "req:.id") == "NEW")
        #expect(CustomColumnCellResolution.value(columnID: Self.column, row: row) == .resolved("NEW"))
    }

    @Test("A pending cell has a spoken value, and the glyph is not it")
    func pendingCellHasAccessibilityValue() {
        let spoken = CustomColumnCellValue.pendingAccessibilityValue

        #expect(!spoken.isEmpty)
        #expect(spoken != CustomColumnCellValue.placeholder)
    }

    // MARK: Private

    private static let column = "reqBody..id"

    private static func makeRow(
        body: String,
        url: String = "https://api.example.com/orders"
    )
        -> (HTTPTransaction, RequestListRow)
    {
        let transaction = TestFixtures.makeTransaction(method: "POST", url: url)
        transaction.request.body = Data(body.utf8)
        return (transaction, RequestListRow(from: transaction))
    }
}

// MARK: - Delivery

private struct Delivery: Equatable {
    let key: CustomColumnCellKey
    let value: String
}

// MARK: - Recorder

@MainActor
private final class Recorder {
    private(set) var delivered: [Delivery] = []

    func record(_ key: CustomColumnCellKey, _ value: String) {
        delivered.append(Delivery(key: key, value: value))
    }

    func waitForDeliveries(_ count: Int) async {
        for _ in 0 ..< 5_000 where delivered.count < count {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(delivered.count >= count, "timed out waiting for \(count) deliveries")
    }
}

// MARK: - Gate

private actor Gate {
    // MARK: Internal

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    // MARK: Private

    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
}

// MARK: - Counter

private actor Counter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}
