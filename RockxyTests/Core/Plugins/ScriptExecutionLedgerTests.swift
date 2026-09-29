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
