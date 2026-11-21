import Foundation
@testable import Rockxy
import Testing

// MARK: - ScriptExecutionLedgerTests

struct ScriptExecutionLedgerTests {
    @Test("Names are recorded once per flow in first-run order and bounded by capacity")
    func recordsAndBounds() {
        let ledger = ScriptExecutionLedger(capacity: 2)
        let first = UUID()
        let second = UUID()
        let third = UUID()

        ledger.record(scriptName: "Auth", flowID: first)
        ledger.record(scriptName: "CORS", flowID: first)
        ledger.record(scriptName: "Auth", flowID: first)
        ledger.record(scriptName: "Mock", flowID: second)
        ledger.record(scriptName: "Mock", flowID: third)

        #expect(ledger.scriptNames(for: first).isEmpty)
        #expect(ledger.scriptNames(for: second) == ["Mock"])
        #expect(ledger.scriptNames(for: third) == ["Mock"])
    }

    @Test("Preview tabs are bounded by bytes as well as by flow count")
    func previewsAreByteBounded() {
        // `ScriptPreviewTab` bounds a single tab (8 per panel, 2 panels, 256 KiB of text), so a
        // count-only cap of 2,048 flows admits ~8 GiB. The byte bound evicts the oldest flows in
        // the same FIFO order the count cap uses.
        let ledger = ScriptExecutionLedger(capacity: 64, previewByteCapacity: 4_096)
        let flows = (0 ..< 8).map { _ in UUID() }
        let tab = ScriptPreviewTab(
            title: "Decoded",
            text: String(repeating: "x", count: 1_024),
            panel: .request
        )

        for flow in flows {
            ledger.recordPreviews([tab], panel: .request, flowID: flow)
        }

        // 4,096 bytes holds three tabs of 1,031 bytes (1,024 of text plus the title), and the
        // flow just recorded is never the victim.
        #expect(ledger.previews(for: flows[7]).count == 1)
        let retained = flows.filter { !ledger.previews(for: $0).isEmpty }
        #expect(retained == Array(flows.suffix(3)))
    }

    @Test("Replacing a panel releases the bytes the previous tabs held")
    func replacingAPanelReleasesItsBytes() {
        // The per-flow byte accounting has to be subtracted before the replacement is measured,
        // or a flow that republishes its panel would evict healthy flows on every hook.
        let ledger = ScriptExecutionLedger(capacity: 64, previewByteCapacity: 4_096)
        let busy = UUID()
        let other = UUID()
        let large = ScriptPreviewTab(title: "T", text: String(repeating: "x", count: 1_500), panel: .request)

        ledger.recordPreviews([large], panel: .request, flowID: other)
        for _ in 0 ..< 10 {
            ledger.recordPreviews([large], panel: .request, flowID: busy)
        }

        #expect(ledger.previews(for: busy).count == 1)
        #expect(ledger.previews(for: other).count == 1)
    }

    @Test("The attribution callback stamps script names and persists through session files")
    func attributionCallbackAndCodable() throws {
        let ledger = ScriptExecutionLedger()
        let transaction = TestFixtures.makeTransaction()
        ledger.record(scriptName: "Add CORS", flowID: transaction.request.flowID)
        let received = LockedTransactions()
        let callback = ProxyServer.makeScriptAttributionCallback(ledger: ledger) { received.append($0) }

        callback(transaction)

        #expect(received.first?.appliedScriptNames == ["Add CORS"])
        let data = try JSONEncoder().encode(CodableTransaction(from: transaction))
        let decoded = try JSONDecoder().decode(CodableTransaction.self, from: data).toLiveModel()
        #expect(decoded.appliedScriptNames == ["Add CORS"])
    }
}

// MARK: - LockedTransactions

private final class LockedTransactions: @unchecked Sendable {
    var first: HTTPTransaction? {
        lock.withLock { items.first }
    }

    func append(_ transaction: HTTPTransaction) {
        lock.withLock { items.append(transaction) }
    }

    private let lock = NSLock()
    private var items: [HTTPTransaction] = []
}

// MARK: - NoCachingAttributionTests

struct NoCachingAttributionTests {
    @Test("No Caching attribution survives session save and load and stays off by default")
    func noCachingAttributionRoundTrips() throws {
        let marked = TestFixtures.makeTransaction()
        marked.noCachingApplied = true
        let plain = TestFixtures.makeTransaction()

        let decodedMarked = try JSONDecoder().decode(
            CodableTransaction.self,
            from: JSONEncoder().encode(CodableTransaction(from: marked))
        ).toLiveModel()
        let plainData = try JSONEncoder().encode(CodableTransaction(from: plain))
        let decodedPlain = try JSONDecoder().decode(CodableTransaction.self, from: plainData).toLiveModel()

        #expect(decodedMarked.noCachingApplied)
        #expect(!decodedPlain.noCachingApplied)
        #expect(String(bytes: plainData, encoding: .utf8)?.contains("noCachingApplied") == false)
    }
}
