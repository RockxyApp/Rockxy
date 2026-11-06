import Foundation
@testable import Rockxy
import Testing

// MARK: - HeaderColumnStoreTests

// Regression tests for `HeaderColumnStore` in the models ui layer.

@Suite(.serialized)
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

    @Test("Header names are deduplicated case-insensitively")
    func addDuplicateWithDifferentCasing() {
        let store = makeCleanStore()
        let first = store.addColumn(headerName: "x-request-id", source: .request)
        let second = store.addColumn(headerName: "X-Request-ID", source: .request)

        #expect(first.id == second.id)
        #expect(store.columns.count == 1)
        #expect(store.isColumnDefined(headerName: "X-REQUEST-ID", source: .request))
    }

    /// Query parameter names, unlike HTTP field names, are case-sensitive: `?Token=`
    /// and `?token=` are two parameters, and the resolver reads one by exact name. When
    /// the duplicate check folded case, the second column could not be created at all
    /// and the first one's value was shown under the name the user had asked for.
    @Test("Query parameter names differing only in case are separate columns")
    func queryNamesAreCaseSensitive() {
        let store = makeCleanStore()
        let lower = store.addColumn(headerName: "token", source: .query)
        let upper = store.addColumn(headerName: "Token", source: .query)

        #expect(lower.id != upper.id)
        #expect(store.columns.count == 2)
        #expect(store.isColumnDefined(headerName: "Token", source: .query))
        #expect(!store.isColumnDefined(headerName: "TOKEN", source: .query))

        let transaction = TestFixtures.makeTransaction(
            url: "https://api.example.com/items?token=lower&Token=upper"
        )
        #expect(
            HeaderColumnStore.resolveValue(for: "reqQuery.token", transaction: transaction) == "lower"
        )
        #expect(
            HeaderColumnStore.resolveValue(for: "reqQuery.Token", transaction: transaction) == "upper"
        )
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

    @Test("Saved column state persists across store instances")
    func savedColumnStatePersistsAcrossStoreInstances() {
        let environment = TestFixtures.makeNamedIsolatedDefaults()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = HeaderColumnStore(defaults: environment.defaults)
        let request = store.addColumn(headerName: "X-Request-ID", source: .request)
        _ = store.addColumn(headerName: "X-Request-ID", source: .response)
        store.toggleColumn(id: request.id)

        let freshStore = HeaderColumnStore(defaults: environment.defaults)

        #expect(freshStore.requestColumns.count == 1)
        #expect(freshStore.responseColumns.count == 1)
        #expect(freshStore.requestColumns.first?.isEnabled == false)
        #expect(freshStore.responseColumns.first?.isEnabled == true)

        if let responseID = freshStore.responseColumns.first?.id {
            freshStore.removeColumn(id: responseID)
        }

        let afterRemoval = HeaderColumnStore(defaults: environment.defaults)
        #expect(afterRemoval.requestColumns.count == 1)
        #expect(afterRemoval.responseColumns.isEmpty)
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

    @Test("Discovery excludes saved headers regardless of casing")
    func discoveryExcludesExistingHeaderCasing() {
        let store = makeCleanStore()
        store.addColumn(headerName: "content-type", source: .request)

        let discovered = store.discoverHeaders(from: [TestFixtures.makeTransaction()])

        #expect(!discovered.request.contains("Content-Type"))
        #expect(discovered.response.contains("Content-Type"))
    }

    @Test("Discovery collapses captured header casing variants")
    func discoveryCollapsesCapturedHeaderCasing() {
        let store = makeCleanStore()
        let transaction = TestFixtures.makeTransaction()
        transaction.request.headers.append(contentsOf: [
            HTTPHeader(name: "x-trace-id", value: "lower"),
            HTTPHeader(name: "X-Trace-ID", value: "upper"),
        ])

        let discovered = store.discoverHeaders(from: [transaction])
        let traceHeaders = discovered.request.filter {
            $0.caseInsensitiveCompare("X-Trace-ID") == .orderedSame
        }

        #expect(traceHeaders == ["X-Trace-ID"])
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
        let environment = TestFixtures.makeNamedIsolatedDefaults()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = HeaderColumnStore(defaults: environment.defaults)
        let transactions = [TestFixtures.makeTransaction()]
        store.updateDiscoveredHeaders(from: transactions)

        let store2 = HeaderColumnStore(defaults: environment.defaults)
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

    @Test("Protocol built-in column is visible by default and can be hidden")
    func protocolBuiltInColumnDefaultVisibility() {
        let environment = TestFixtures.makeNamedIsolatedDefaults()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = HeaderColumnStore(defaults: environment.defaults)

        #expect(store.isBuiltInColumnVisible("ai"))
        store.toggleBuiltInColumn("ai")
        #expect(!store.isBuiltInColumnVisible("ai"))

        let store2 = HeaderColumnStore(defaults: environment.defaults)
        #expect(!store2.isBuiltInColumnVisible("ai"))
        store2.toggleBuiltInColumn("ai")
        #expect(store2.isBuiltInColumnVisible("ai"))
    }

    @Test("Hidden built-in columns persist")
    func hiddenBuiltInPersist() {
        let environment = TestFixtures.makeNamedIsolatedDefaults()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = HeaderColumnStore(defaults: environment.defaults)
        store.toggleBuiltInColumn("method")
        store.toggleBuiltInColumn("responseSize")

        let store2 = HeaderColumnStore(defaults: environment.defaults)
        #expect(!store2.isBuiltInColumnVisible("method"))
        #expect(!store2.isBuiltInColumnVisible("responseSize"))
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
        HeaderColumnStore(defaults: TestFixtures.makeIsolatedDefaults())
    }
}

// MARK: - CustomHeaderColumnsViewModelTests

@Suite(.serialized)
@MainActor
struct CustomHeaderColumnsViewModelTests {
    // MARK: Internal

    @Test("Saved spelling wins when captured casing differs")
    func savedSpellingWins() {
        let environment = makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = environment.store
        store.addColumn(headerName: "x-request-id", source: .request)
        store.discoveredRequestHeaders = ["X-Request-ID"]
        let model = CustomHeaderColumnsViewModel(store: store)

        #expect(model.allRowsForSource.count == 1)
        #expect(model.allRowsForSource.first?.displayName == "x-request-id")
        #expect(model.allRowsForSource.first?.isAlsoDiscovered == true)
        #expect(model.allRowsForSource.first?.state == .savedEnabled)
    }

    @Test("Showing a discovered header creates one saved column")
    func discoveredToggleCreatesOneColumn() throws {
        let environment = makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = environment.store
        store.discoveredRequestHeaders = ["X-Correlation-ID"]
        let model = CustomHeaderColumnsViewModel(store: store)
        let rowID = try #require(model.visibleRows.first?.id)

        model.toggle(rowID: rowID)
        model.toggle(rowID: rowID)

        #expect(store.requestColumns.count == 1)
        #expect(store.requestColumns.first?.headerName == "X-Correlation-ID")
        #expect(store.requestColumns.first?.isEnabled == false)
    }

    @Test("Adding an existing hidden column enables it without duplicating")
    func addHiddenExistingColumn() {
        let environment = makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = environment.store
        let column = store.addColumn(headerName: "ETag", source: .response)
        store.toggleColumn(id: column.id)
        let model = CustomHeaderColumnsViewModel(store: store, source: .response)

        let result = model.addHeader("etag")

        #expect(result == .enabledExisting("response:etag"))
        #expect(store.responseColumns.count == 1)
        #expect(store.responseColumns.first?.isEnabled == true)
    }

    @Test("Request and response columns remain independent")
    func sourceIndependence() {
        let environment = makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = environment.store
        let model = CustomHeaderColumnsViewModel(store: store)

        #expect(model.addHeader("Content-Type") == .added("request:content-type"))
        model.source = .response
        #expect(model.addHeader("Content-Type") == .added("response:content-type"))

        #expect(store.requestColumns.count == 1)
        #expect(store.responseColumns.count == 1)
    }

    @Test("Filtering removes selection that is no longer visible")
    func searchReconcilesSelection() throws {
        let environment = makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = environment.store
        store.addColumn(headerName: "Authorization", source: .request)
        store.addColumn(headerName: "X-Request-ID", source: .request)
        let model = CustomHeaderColumnsViewModel(store: store)
        model.selection = try [#require(model.visibleRows.first?.id)]

        model.searchText = "request"
        model.reconcileSelection()

        #expect(model.selection.isEmpty)
        #expect(model.visibleRows.map(\.displayName) == ["X-Request-ID"])
    }

    @Test("Manual header names enforce bounded HTTP token syntax")
    func headerNameValidation() {
        #expect(CustomHeaderColumnsViewModel.validationMessage(for: "") != nil)
        #expect(CustomHeaderColumnsViewModel.validationMessage(for: "Bad Header") != nil)
        #expect(CustomHeaderColumnsViewModel.validationMessage(for: "Bad:Header") != nil)
        #expect(CustomHeaderColumnsViewModel.validationMessage(for: "X-Héader") != nil)
        #expect(
            CustomHeaderColumnsViewModel.validationMessage(
                for: String(repeating: "a", count: CustomHeaderColumnsViewModel.maxHeaderNameLength + 1)
            ) != nil
        )
        #expect(CustomHeaderColumnsViewModel.validationMessage(for: "X-Request-ID") == nil)
    }

    @Test("Removing a captured saved column keeps its discovered suggestion selected")
    func removalKeepsDiscoveredSuggestion() throws {
        let environment = makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let store = environment.store
        store.addColumn(headerName: "X-Trace-ID", source: .request)
        store.discoveredRequestHeaders = ["X-Trace-ID"]
        let model = CustomHeaderColumnsViewModel(store: store)
        let rowID = try #require(model.visibleRows.first?.id)
        model.selection = [rowID]

        model.removeSelected()

        #expect(store.requestColumns.isEmpty)
        #expect(model.visibleRows.first?.state == .discovered)
        #expect(model.selection == [rowID])
    }

    // MARK: Private

    private func makeEnvironment() -> (
        store: HeaderColumnStore,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let environment = TestFixtures.makeNamedIsolatedDefaults()
        return (
            HeaderColumnStore(defaults: environment.defaults),
            environment.defaults,
            environment.suiteName
        )
    }
}
