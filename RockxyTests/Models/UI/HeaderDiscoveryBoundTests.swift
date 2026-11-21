import Foundation
@testable import Rockxy
import Testing

@MainActor
struct HeaderDiscoveryBoundTests {
    @Test("Default stores isolate coordinator test writes from the user's column configuration")
    func defaultTestStoreIsolation() {
        let key = RockxyIdentity.current.defaultsKey("headerColumns")
        let before = UserDefaults.standard.data(forKey: key)
        let store = HeaderColumnStore()
        let column = store.addColumn(headerName: "X-Isolated-\(UUID().uuidString)", source: .request)
        defer { store.removeColumn(id: column.id) }
        let userConfigurationUnchanged = UserDefaults.standard.data(forKey: key) == before
        #expect(userConfigurationUnchanged)
        #expect(store.columns.contains { $0.id == column.id })
    }

    @Test("Header suggestions remain bounded without trimming captured headers or manual columns")
    func discoveryBound() {
        let store = HeaderColumnStore(defaults: IsolatedDefaultsSuite.make(prefix: "Rockxy.HeaderDiscoveryBoundTests"))
        let transaction = TestFixtures.makeTransaction()
        let headers = (0 ..< (DiscoveredHeaderNames.maximumCount + 100)).map {
            HTTPHeader(name: "X-Unique-\($0)", value: "value")
        }
        transaction.request.headers = headers
        transaction.response = HTTPResponseData(statusCode: 200, statusMessage: "OK", headers: headers, body: nil)
        store.updateDiscoveredHeaders(fromBatch: [transaction])
        #expect(store.discoveredRequestHeaders.count == DiscoveredHeaderNames.maximumCount)
        #expect(store.discoveredResponseHeaders.count == DiscoveredHeaderNames.maximumCount)
        #expect(transaction.request.headers.count == headers.count)
        #expect(transaction.response?.headers.count == headers.count)
        #expect(store.discoverHeaders(from: [transaction]).request.count == DiscoveredHeaderNames.maximumCount)
        store.updateDiscoveredHeaders(from: [transaction])
        let retained = store.discoveredRequestHeaders
        transaction.request.headers = [HTTPHeader(name: "X-Outside-Suggestions", value: "still captured")]
        store.updateDiscoveredHeaders(fromBatch: [transaction])
        #expect(store.discoveredRequestHeaders == retained)
        store.addColumn(headerName: "X-Outside-Suggestions", source: .request)
        #expect(HeaderColumnStore
            .resolveValue(for: "reqHeader.X-Outside-Suggestions", transaction: transaction) == "still captured")
        #expect(store.isColumnDefined(headerName: "X-Outside-Suggestions", source: .request))
    }

    @Test("Incremental header suggestions collapse case variants across batches")
    func incrementalCasing() {
        let store = HeaderColumnStore(defaults: IsolatedDefaultsSuite.make(prefix: "Rockxy.HeaderDiscoveryCasingTests"))
        let transaction = TestFixtures.makeTransaction()
        transaction.request.headers = [HTTPHeader(name: "x-trace-id", value: "first")]
        store.updateDiscoveredHeaders(fromBatch: [transaction])
        transaction.request.headers = [HTTPHeader(name: "X-Trace-ID", value: "second")]
        store.updateDiscoveredHeaders(fromBatch: [transaction])
        #expect(store.discoveredRequestHeaders == ["X-Trace-ID"])
        store.updateDiscoveredHeaders(fromBatch: [transaction])
        #expect(store.discoveredRequestHeaders == ["X-Trace-ID"])
    }

    @Test("Legacy suggestion caches normalize and shrink on reload")
    func legacyCache() {
        let defaults = IsolatedDefaultsSuite.make(prefix: "Rockxy.HeaderDiscoveryLegacyTests")
        let requestKey = RockxyIdentity.current.defaultsKey("discoveredReqHeaders")
        let responseKey = RockxyIdentity.current.defaultsKey("discoveredResHeaders")
        let legacy = ["x-trace-id", "X-Trace-ID"] + (0 ..< 2_000).map { "X-Legacy-\($0)" }
        defaults.set(legacy, forKey: requestKey)
        defaults.set(legacy, forKey: responseKey)
        let store = HeaderColumnStore(defaults: defaults)
        #expect(store.discoveredRequestHeaders.count == DiscoveredHeaderNames.maximumCount)
        #expect(store.discoveredResponseHeaders.count == DiscoveredHeaderNames.maximumCount)
        #expect(store.discoveredRequestHeaders.contains("X-Trace-ID"))
        #expect(!store.discoveredRequestHeaders.contains("x-trace-id"))
        #expect(defaults.stringArray(forKey: requestKey) == store.discoveredRequestHeaders)
        #expect(defaults.stringArray(forKey: responseKey) == store.discoveredResponseHeaders)
        #expect(HeaderColumnStore(defaults: defaults).discoveredRequestHeaders == store.discoveredRequestHeaders)
    }
}
