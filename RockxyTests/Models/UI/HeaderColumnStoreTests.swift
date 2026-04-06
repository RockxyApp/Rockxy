import Foundation
@testable import Rockxy
import Testing

// Regression tests for `HeaderColumnStore` in the models ui layer.

@MainActor
struct HeaderColumnStoreTests {
    // MARK: Internal

    // MARK: - Initialization

    @Test("Store initializes empty")
    func defaultInit() {
        let store = makeCleanStore()
        #expect(store.columns.isEmpty)
        #expect(store.enabledColumns.isEmpty)
    }

    // MARK: - Add

    @Test("Add column creates enabled column")
    func addColumn() {
        let store = makeCleanStore()
        let col = store.addColumn(headerName: "X-Request-ID", source: .request)
        #expect(col.headerName == "X-Request-ID")
        #expect(col.source == .request)
        #expect(col.isEnabled)
        #expect(store.columns.count == 1)
    }

    @Test("Add duplicate returns existing")
    func addDuplicate() {
        let store = makeCleanStore()
        let first = store.addColumn(headerName: "Authorization", source: .request)
        let second = store.addColumn(headerName: "Authorization", source: .request)
        #expect(first.id == second.id)
        #expect(store.columns.count == 1)
    }

    @Test("Same header name different source are separate")
    func differentSource() {
        let store = makeCleanStore()
        store.addColumn(headerName: "Content-Type", source: .request)
        store.addColumn(headerName: "Content-Type", source: .response)
        #expect(store.columns.count == 2)
        #expect(store.requestColumns.count == 1)
        #expect(store.responseColumns.count == 1)
    }

    // MARK: - Remove

    @Test("Remove column by ID")
    func removeColumn() {
        let store = makeCleanStore()
        let col = store.addColumn(headerName: "X-Custom", source: .response)
        store.removeColumn(id: col.id)
        #expect(store.columns.isEmpty)
    }

    // MARK: - Toggle

    @Test("Toggle disables and re-enables")
    func toggleColumn() {
        let store = makeCleanStore()
        let col = store.addColumn(headerName: "ETag", source: .response)
        #expect(store.enabledColumns.count == 1)
        store.toggleColumn(id: col.id)
        #expect(store.enabledColumns.isEmpty)
        store.toggleColumn(id: col.id)
        #expect(store.enabledColumns.count == 1)
    }

    // MARK: - Column Identifier

    @Test("Column identifier has correct prefix")
    func columnIdentifier() {
        let req = HeaderColumn(headerName: "Authorization", source: .request)
        #expect(req.columnIdentifier == "reqHeader.Authorization")
        let res = HeaderColumn(headerName: "Cache-Control", source: .response)
        #expect(res.columnIdentifier == "resHeader.Cache-Control")
    }

    // MARK: - Value Resolution

    @Test("Resolves request header value")
    func resolveRequestHeader() {
        let transaction = TestFixtures.makeTransaction()
        let value = HeaderColumnStore.resolveValue(
            for: "reqHeader.Content-Type", transaction: transaction
        )
        #expect(value == "application/json")
    }

    @Test("Resolves response header value")
    func resolveResponseHeader() {
        let transaction = TestFixtures.makeTransaction()
        let value = HeaderColumnStore.resolveValue(
            for: "resHeader.Content-Type", transaction: transaction
        )
        #expect(value == "application/json")
    }

    @Test("Missing header returns empty string")
    func resolveMissingHeader() {
        let transaction = TestFixtures.makeTransaction()
        let value = HeaderColumnStore.resolveValue(
            for: "reqHeader.X-Nonexistent", transaction: transaction
        )
        #expect(value == "")
    }

    @Test("Case-insensitive header matching")
    func caseInsensitive() {
        let transaction = TestFixtures.makeTransaction()
        let value = HeaderColumnStore.resolveValue(
            for: "reqHeader.content-type", transaction: transaction
        )
        #expect(value == "application/json")
    }

    @Test("No response returns empty for response header")
    func noResponse() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        let value = HeaderColumnStore.resolveValue(
            for: "resHeader.Content-Type", transaction: transaction
        )
        #expect(value == "")
    }

    // MARK: - Discovery

    @Test("Discover headers from transactions")
    func discoverHeaders() {
        let store = makeCleanStore()
        let transactions = [TestFixtures.makeTransaction()]
        let discovered = store.discoverHeaders(from: transactions)
        #expect(discovered.request.contains("Content-Type"))
        #expect(discovered.response.contains("Content-Type"))
    }

    @Test("Discovery excludes already-defined headers")
    func discoveryExcludesExisting() {
        let store = makeCleanStore()
        store.addColumn(headerName: "Content-Type", source: .request)
        let transactions = [TestFixtures.makeTransaction()]
        let discovered = store.discoverHeaders(from: transactions)
        #expect(!discovered.request.contains("Content-Type"))
        #expect(discovered.response.contains("Content-Type"))
    }

    // MARK: - isDefined

    @Test("isColumnDefined checks name and source")
    func isColumnDefined() {
        let store = makeCleanStore()
        store.addColumn(headerName: "Authorization", source: .request)
        #expect(store.isColumnDefined(headerName: "Authorization", source: .request))
        #expect(!store.isColumnDefined(headerName: "Authorization", source: .response))
    }

    // MARK: - Discovery Updates

    @Test("updateDiscoveredHeaders populates arrays")
    func updateDiscoveredHeaders() {
        let store = makeCleanStore()
        let transactions = [TestFixtures.makeTransaction()]
        store.updateDiscoveredHeaders(from: transactions)
        #expect(!store.discoveredRequestHeaders.isEmpty)
        #expect(!store.discoveredResponseHeaders.isEmpty)
        #expect(store.discoveredRequestHeaders.contains("Content-Type"))
    }

    @Test("Discovered headers persist to UserDefaults")
    func discoveredHeadersPersist() {
        let store = makeCleanStore()
        let transactions = [TestFixtures.makeTransaction()]
        store.updateDiscoveredHeaders(from: transactions)

        let store2 = HeaderColumnStore()
        #expect(store2.discoveredRequestHeaders.contains("Content-Type"))
        #expect(store2.discoveredResponseHeaders.contains("Content-Type"))
    }

    // MARK: - Built-in Column Visibility

    @Test("Toggle built-in column visibility")
    func toggleBuiltInColumn() {
        let store = makeCleanStore()
        #expect(store.isBuiltInColumnVisible("url"))
        store.toggleBuiltInColumn("url")
        #expect(!store.isBuiltInColumnVisible("url"))
        store.toggleBuiltInColumn("url")
        #expect(store.isBuiltInColumnVisible("url"))
    }

    @Test("Hidden built-in columns persist")
    func hiddenBuiltInPersist() {
        let store = makeCleanStore()
        store.toggleBuiltInColumn("method")
        store.toggleBuiltInColumn("size")

        let store2 = HeaderColumnStore()
        #expect(!store2.isBuiltInColumnVisible("method"))
        #expect(!store2.isBuiltInColumnVisible("size"))
        #expect(store2.isBuiltInColumnVisible("url"))
    }

    // MARK: - Incremental Discovery

    @Test("Incremental discovery from batch discovers new headers")
    func incrementalDiscovery() {
        let store = makeCleanStore()
        let batch = [TestFixtures.makeTransaction()]
        store.updateDiscoveredHeaders(fromBatch: batch)
        #expect(!store.discoveredRequestHeaders.isEmpty)
        #expect(!store.discoveredResponseHeaders.isEmpty)
        #expect(store.discoveredRequestHeaders.contains("Content-Type"))
    }

    @Test("Late-arriving headers in second batch are discovered")
    func lateArrivingHeaders() throws {
        let store = makeCleanStore()
        let firstBatch = [TestFixtures.makeTransaction()]
        store.updateDiscoveredHeaders(fromBatch: firstBatch)

        let customTransaction = TestFixtures.makeTransaction()
        customTransaction.request = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "https://example.com/test")),
            httpVersion: "HTTP/1.1",
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "X-Custom-Late", value: "value"),
            ],
            body: nil,
            contentType: .json
        )
        let secondBatch = [customTransaction]
        store.updateDiscoveredHeaders(fromBatch: secondBatch)

        #expect(store.discoveredRequestHeaders.contains("X-Custom-Late"))
    }

    @Test("Incremental discovery does not lose previously discovered headers")
    func incrementalPreserves() {
        let store = makeCleanStore()
        let firstBatch = [TestFixtures.makeTransaction()]
        store.updateDiscoveredHeaders(fromBatch: firstBatch)
        let firstCount = store.discoveredRequestHeaders.count

        let emptyBatch: [HTTPTransaction] = []
        store.updateDiscoveredHeaders(fromBatch: emptyBatch)

        #expect(store.discoveredRequestHeaders.count == firstCount)
    }

    @Test("Full-scan discovery followed by incremental preserves all headers")
    func fullScanThenIncrementalPreserves() throws {
        let store = makeCleanStore()
        let transactions = [TestFixtures.makeTransaction()]
        store.updateDiscoveredHeaders(from: transactions)
        let afterFullScan = store.discoveredRequestHeaders

        let customTransaction = TestFixtures.makeTransaction()
        customTransaction.request = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "https://example.com/test")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "X-New-Header", value: "value")],
            body: nil,
            contentType: nil
        )
        store.updateDiscoveredHeaders(fromBatch: [customTransaction])

        // Full-scan headers must still be present after incremental batch
        for header in afterFullScan {
            #expect(store.discoveredRequestHeaders.contains(header))
        }
        // New header from batch must also be present
        #expect(store.discoveredRequestHeaders.contains("X-New-Header"))
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeCleanStore() -> HeaderColumnStore {
        UserDefaults.standard.removeObject(forKey: TestIdentity.headerColumnStorageKey)
        UserDefaults.standard.removeObject(forKey: TestIdentity.discoveredRequestHeadersKey)
        UserDefaults.standard.removeObject(forKey: TestIdentity.discoveredResponseHeadersKey)
        UserDefaults.standard.removeObject(forKey: TestIdentity.hiddenBuiltInColumnsKey)
        return HeaderColumnStore()
    }
}
