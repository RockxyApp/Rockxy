import Foundation
@testable import Rockxy
import Testing

struct BlockAndHideTests {
    @Test("Rules saved before the hide option decode as visible, and the flag round-trips")
    func codableCompatibility() throws {
        let legacy = ProxyRule(name: "Old", matchCondition: RuleMatchCondition(urlPattern: ".*"), action: .block(statusCode: 403))
        let legacyData = try JSONEncoder().encode(legacy)
        #expect(!String(decoding: legacyData, as: UTF8.self).contains("hidesMatchedTraffic"))
        #expect(try JSONDecoder().decode(ProxyRule.self, from: legacyData).hidesMatchedTraffic == false)

        var hidden = legacy
        hidden.hidesMatchedTraffic = true
        let decoded = try JSONDecoder().decode(ProxyRule.self, from: JSONEncoder().encode(hidden))
        #expect(decoded.hidesMatchedTraffic)
        #expect(decoded.id == legacy.id)
    }

    @Test("A hiding Block rule drops the row; other rules and visible blocks deliver it")
    func callbackSeam() {
        let delivered = LockedCounter()
        var block = ProxyRule(name: "B", matchCondition: RuleMatchCondition(urlPattern: ".*"), action: .block(statusCode: 0))
        let tx = TestFixtures.makeTransaction()

        ProxyHandlerShared.makeTransactionCallback(for: block) { _ in delivered.increment() }(tx)
        #expect(delivered.value == 1)

        block.hidesMatchedTraffic = true
        ProxyHandlerShared.makeTransactionCallback(for: block) { _ in delivered.increment() }(tx)
        #expect(delivered.value == 1)

        var mapRemote = ProxyRule(
            name: "M",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .mapRemote(configuration: MapRemoteConfiguration())
        )
        mapRemote.hidesMatchedTraffic = true
        ProxyHandlerShared.makeTransactionCallback(for: mapRemote) { _ in delivered.increment() }(tx)
        #expect(delivered.value == 2)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
