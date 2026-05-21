import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ComposeViewModel` in the view models layer.

// MARK: - MockComposeExecutor

/// Mock executor for deterministic testing of ComposeViewModel.
struct MockComposeExecutor: ComposeRequestExecutor {
    let handler: @Sendable (URLRequest, Bool) async throws -> (Data, HTTPURLResponse)

    func execute(_ request: URLRequest, followsRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        try await handler(request, followsRedirects)
    }
}

// MARK: - ComposeViewModelTests

@MainActor
struct ComposeViewModelTests {
    // MARK: Internal

    // MARK: - Prefill

    @Test("Prefill correctly maps transaction fields")
    func prefillMapsFields() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/users?page=2&sort=name"
        )
        transaction.request.headers = [
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "Authorization", value: "Bearer token123"),
        ]
        transaction.request.body = Data("{\"name\":\"test\"}".utf8)

        let vm = ComposeViewModel()
        vm.prefill(from: transaction)

        #expect(vm.method == "POST")
        #expect(vm.url == "https://api.example.com/users?page=2&sort=name")
        #expect(vm.headers.count == 2)
        #expect(vm.headers[0].name == "Content-Type")
        #expect(vm.headers[0].value == "application/json")
        #expect(vm.headers[1].name == "Authorization")
        #expect(vm.body == "{\"name\":\"test\"}")
        #expect(vm.queryItems.count == 2)
        #expect(vm.queryItems[0].name == "page")
        #expect(vm.queryItems[0].value == "2")
        #expect(vm.queryItems[1].name == "sort")
        #expect(vm.queryItems[1].value == "name")
    }

    @Test("Prefill resets response state to empty")
    func prefillResetsResponse() async throws {
        let response = try makeResponse()
        let executor = MockComposeExecutor { _, _ in
            (Data("ok".utf8), response)
        }
        let vm = ComposeViewModel(executor: executor)
        vm.url = "https://example.com"
        await vm.send()

        if case .success = vm.responseState {} else {
            Issue.record("Expected success state after send")
        }

        let transaction = TestFixtures.makeTransaction()
        vm.prefill(from: transaction)

        if case .empty = vm.responseState {} else {
            Issue.record("Expected empty state after prefill")
        }
    }

    // MARK: - Send Success

    @Test("Send success updates response state")
    func sendSuccess() async throws {
        let jsonBody = Data("{\"id\":1}".utf8)
        let response = try makeResponse(
            url: "https://api.example.com/test",
            headerFields: ["Content-Type": "application/json"]
        )
        let executor = MockComposeExecutor { _, _ in
            (jsonBody, response)
        }

        let vm = ComposeViewModel(executor: executor)
        vm.url = "https://api.example.com/test"
        vm.method = "GET"

        await vm.send()

        if case let .success(result) = vm.responseState {
            #expect(result.statusCode == 200)
            #expect(result.bodyData == jsonBody)
            #expect(result.bodyText == "{\"id\":1}")
        } else {
            Issue.record("Expected success state")
        }
    }

    // MARK: - Send Failure

    @Test("Send failure updates error state")
    func sendFailure() async {
        let executor = MockComposeExecutor { _, _ in
            throw URLError(.notConnectedToInternet)
        }

        let vm = ComposeViewModel(executor: executor)
        vm.url = "https://api.example.com/test"

        await vm.send()

        if case let .error(message) = vm.responseState {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Expected error state")
        }
    }

    @Test("Send with invalid URL shows error state")
    func sendInvalidURL() async {
        let vm = ComposeViewModel()
        vm.url = ""

        await vm.send()

        if case .error = vm.responseState {} else {
            Issue.record("Expected error state for empty URL")
        }
    }

    // MARK: - Latest-Run-Wins

    @Test("Latest run wins when two sends overlap")
    func latestRunWins() async throws {
        let firstContinuation: AsyncStream<Void>.Continuation
        let firstStream: AsyncStream<Void>
        (firstStream, firstContinuation) = AsyncStream<Void>.makeStream()

        let callCount = ManagedAtomic(0)
        let firstResponse = try makeResponse(statusCode: 200)
        let secondResponse = try makeResponse(statusCode: 201)

        let executor = MockComposeExecutor { _, _ in
            let count = callCount.increment()

            if count == 1 {
                for await _ in firstStream {
                    break
                }
                return (Data("first".utf8), firstResponse)
            } else {
                return (Data("second".utf8), secondResponse)
            }
        }

        let vm = ComposeViewModel(executor: executor)
        vm.url = "https://example.com"

        let firstTask = Task { @MainActor in
            await vm.send()
        }

        try? await Task.sleep(for: .milliseconds(50))

        await vm.send()

        if case let .success(result) = vm.responseState {
            #expect(result.statusCode == 201)
            #expect(result.bodyText == "second")
        } else {
            Issue.record("Expected success state from second send")
        }

        firstContinuation.yield()
        firstContinuation.finish()
        await firstTask.value

        if case let .success(result) = vm.responseState {
            #expect(result.statusCode == 201)
        } else {
            Issue.record("Expected second send to still win after first completes")
        }
    }

    // MARK: - Binary Response Fallback

    @Test("Binary response produces fallback text")
    func binaryResponseFallback() async throws {
        let binaryData = Data([0x00, 0x01, 0xFF, 0xFE])
        let response = try makeResponse(headerFields: ["Content-Type": "application/octet-stream"])
        let executor = MockComposeExecutor { _, _ in
            (binaryData, response)
        }

        let vm = ComposeViewModel(executor: executor)
        vm.url = "https://example.com"
        await vm.send()

        if case let .success(result) = vm.responseState {
            #expect(result.bodyText == nil)
            #expect(result.bodyDisplayText.contains("4"))
            #expect(result.bodyDisplayText.contains("binary"))
        } else {
            Issue.record("Expected success state")
        }
    }

    // MARK: - Query Sync

    @Test("Editing query items updates URL")
    func queryToURLSync() {
        let vm = ComposeViewModel()
        vm.url = "https://api.example.com/users"
        vm.lastSyncedURL = vm.url
        vm.queryItems = [
            EditableQueryItem(name: "page", value: "1"),
            EditableQueryItem(name: "limit", value: "20"),
        ]
        vm.syncQueryToURL()

        #expect(vm.url.contains("page=1"))
        #expect(vm.url.contains("limit=20"))
    }

    @Test("Editing URL updates query items")
    func uRLToQuerySync() {
        let vm = ComposeViewModel()
        vm.url = "https://api.example.com/users?status=active&role=admin"
        vm.syncURLToQuery()

        #expect(vm.queryItems.count == 2)
        #expect(vm.queryItems[0].name == "status")
        #expect(vm.queryItems[0].value == "active")
        #expect(vm.queryItems[1].name == "role")
        #expect(vm.queryItems[1].value == "admin")
    }

    @Test("lastSyncedURL prevents infinite sync loop")
    func syncGuardPreventsLoop() {
        let vm = ComposeViewModel()
        vm.url = "https://example.com?a=1"
        vm.syncURLToQuery()

        let queryCountAfterFirstSync = vm.queryItems.count

        vm.syncURLToQuery()
        #expect(vm.queryItems.count == queryCountAfterFirstSync)
    }

    @Test("Empty query items are excluded from URL rebuild")
    func emptyQueryItemsExcluded() {
        let vm = ComposeViewModel()
        vm.url = "https://api.example.com/data"
        vm.lastSyncedURL = vm.url
        vm.queryItems = [
            EditableQueryItem(name: "", value: "ignored"),
            EditableQueryItem(name: "keep", value: "this"),
        ]
        vm.syncQueryToURL()

        #expect(vm.url.contains("keep=this"))
        #expect(!vm.url.contains("ignored"))
    }

    // MARK: - Header Management

    @Test("Add and remove headers")
    func headerManagement() {
        let vm = ComposeViewModel()
        #expect(vm.headers.isEmpty)

        vm.addHeader()
        #expect(vm.headers.count == 1)

        let headerId = vm.headers[0].id
        vm.removeHeader(id: headerId)
        #expect(vm.headers.isEmpty)
    }

    // MARK: - Raw Request Text

    @Test("Raw request text assembles correctly")
    func testRawRequestText() {
        let vm = ComposeViewModel()
        vm.method = "POST"
        vm.url = "https://api.example.com/users?page=1"
        vm.headers = [
            EditableReplayHeader(name: "Content-Type", value: "application/json"),
        ]
        vm.body = "{\"name\":\"test\"}"

        let raw = vm.rawRequestText
        #expect(raw.contains("POST /users?page=1 HTTP/1.1"))
        #expect(raw.contains("Host: api.example.com"))
        #expect(raw.contains("Content-Type: application/json"))
        #expect(raw.contains("{\"name\":\"test\"}"))
    }

    @Test("Raw request text excludes disabled headers")
    func rawRequestTextExcludesDisabledHeaders() {
        let vm = ComposeViewModel()
        vm.method = "GET"
        vm.url = "https://api.example.com/users"
        vm.headers = [
            EditableReplayHeader(name: "X-Enabled", value: "yes"),
            EditableReplayHeader(name: "X-Disabled", value: "no", isEnabled: false),
        ]

        let raw = vm.rawRequestText

        #expect(raw.contains("X-Enabled: yes"))
        #expect(!raw.contains("X-Disabled"))
    }

    // MARK: - Request Options

    @Test("Send applies timeout, redirect policy, enabled headers, and body")
    func sendAppliesRequestOptions() async throws {
        let capture = RequestCapture()
        let response = try makeResponse()
        let executor = MockComposeExecutor { request, followsRedirects in
            capture.record(request: request, followsRedirects: followsRedirects)
            return (Data("ok".utf8), response)
        }
        let vm = ComposeViewModel(executor: executor)
        vm.method = "POST"
        vm.url = "https://api.example.com/create"
        vm.body = "payload"
        vm.requestTimeout = .sixty
        vm.followsRedirects = false
        vm.headers = [
            EditableReplayHeader(name: "X-Enabled", value: "yes"),
            EditableReplayHeader(name: "X-Disabled", value: "no", isEnabled: false),
            EditableReplayHeader(name: "", value: "ignored"),
        ]

        await vm.send()

        let captured = try #require(capture.request)
        #expect(captured.httpMethod == "POST")
        #expect(captured.timeoutInterval == 60)
        #expect(captured.httpBody == Data("payload".utf8))
        #expect(captured.value(forHTTPHeaderField: "X-Enabled") == "yes")
        #expect(captured.value(forHTTPHeaderField: "X-Disabled") == nil)
        #expect(capture.followsRedirects == false)
    }

    @Test("No timeout maps to a non-expiring request interval")
    func noTimeoutUsesNonExpiringInterval() async throws {
        let capture = RequestCapture()
        let response = try makeResponse()
        let executor = MockComposeExecutor { request, followsRedirects in
            capture.record(request: request, followsRedirects: followsRedirects)
            return (Data("ok".utf8), response)
        }
        let vm = ComposeViewModel(executor: executor)
        vm.url = "https://api.example.com/no-timeout"
        vm.requestTimeout = .none

        await vm.send()

        let captured = try #require(capture.request)
        #expect(captured.timeoutInterval == TimeInterval.greatestFiniteMagnitude)
        #expect(capture.followsRedirects == true)
    }

    // MARK: - Templates

    @Test("Template menu applies empty request")
    func templateEmptyRequestClearsDraft() {
        let vm = ComposeViewModel()
        vm.method = "POST"
        vm.url = "https://api.example.com"
        vm.headers = [EditableReplayHeader(name: "Content-Type", value: "application/json")]
        vm.body = "{}"
        vm.queryItems = [EditableQueryItem(name: "a", value: "b")]

        vm.applyTemplate(.empty)

        #expect(vm.method == "GET")
        #expect(vm.url.isEmpty)
        #expect(vm.headers.isEmpty)
        #expect(vm.body.isEmpty)
        #expect(vm.queryItems.isEmpty)
    }

    @Test("Template menu applies GET with Query")
    func templateGetWithQuery() {
        let vm = ComposeViewModel()

        vm.applyTemplate(.getWithQuery)

        #expect(vm.method == "GET")
        #expect(vm.url.contains("?name=value"))
        #expect(vm.queryItems.count == 1)
        #expect(vm.queryItems[0].name == "name")
        #expect(vm.queryItems[0].value == "value")
        #expect(vm.headers.first?.name == "Accept")
        #expect(vm.body.isEmpty)
    }

    @Test("Template menu applies POST JSON, form, and multipart defaults")
    func templatePostDefaults() {
        let vm = ComposeViewModel()

        vm.applyTemplate(.postJSON)
        #expect(vm.method == "POST")
        #expect(vm.headers.contains { $0.name == "Content-Type" && $0.value == "application/json" })
        #expect(vm.body.contains("\"key\""))

        vm.applyTemplate(.postForm)
        #expect(vm.headers.contains { $0.name == "Content-Type" && $0.value == "application/x-www-form-urlencoded" })
        #expect(vm.body == "key=value")

        vm.applyTemplate(.postMultipart)
        #expect(vm.url == "https://example.com/upload")
        #expect(vm.headers.contains { $0.value.contains("multipart/form-data") })
        #expect(vm.body.contains("Content-Disposition: form-data"))
    }

    // MARK: - cURL Import

    @Test("Import cURL parses Rockxy exported command")
    func importCurlParsesRockxyExport() throws {
        let transaction = TestFixtures.makeTransaction(method: "PATCH", url: "https://api.example.com/users?page=1")
        transaction.request.headers = [
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "Authorization", value: "Bearer token"),
        ]
        transaction.request.body = Data("{\"name\":\"rockxy\"}".utf8)
        let curl = RequestCopyFormatter.curl(for: transaction)
        let vm = ComposeViewModel()

        try vm.importCurlCommand(curl)

        #expect(vm.method == "PATCH")
        #expect(vm.url == "https://api.example.com/users?page=1")
        #expect(vm.headers.map(\.name) == ["Content-Type", "Authorization"])
        #expect(vm.headers.map(\.value) == ["application/json", "Bearer token"])
        #expect(vm.body == "{\"name\":\"rockxy\"}")
        #expect(vm.queryItems.count == 1)
        #expect(vm.queryItems[0].name == "page")
        #expect(vm.queryItems[0].value == "1")
    }

    @Test("Import cURL supports common inline flags")
    func importCurlSupportsInlineFlags() throws {
        let vm = ComposeViewModel()

        try vm.importCurlCommand(
            #"curl --request=post "https://api.example.com/create" --header="Content-Type: application/json" --data='{"ok":true}'"#
        )

        #expect(vm.method == "POST")
        #expect(vm.url == "https://api.example.com/create")
        #expect(vm.headers.count == 1)
        #expect(vm.headers[0].name == "Content-Type")
        #expect(vm.headers[0].value == "application/json")
        #expect(vm.body == #"{"ok":true}"#)
    }

    @Test("Import cURL rejects empty, non-cURL, and URL-less commands without clearing draft")
    func importCurlRejectsInvalidCommands() {
        let vm = ComposeViewModel()
        vm.method = "POST"
        vm.url = "https://api.example.com/keep"

        #expect(throws: ComposeImportError.emptyCommand) {
            try vm.importCurlCommand("")
        }
        #expect(vm.url == "https://api.example.com/keep")

        #expect(throws: ComposeImportError.unsupportedCommand) {
            try vm.importCurlCommand("wget https://api.example.com")
        }
        #expect(vm.url == "https://api.example.com/keep")

        #expect(throws: ComposeImportError.missingURL) {
            try vm.importCurlCommand("curl -H 'Accept: application/json'")
        }
        #expect(vm.url == "https://api.example.com/keep")
    }

    // MARK: - Body Loading And Formatting

    @Test("Load body from file imports UTF-8 text")
    func loadBodyFromFile() throws {
        let vm = ComposeViewModel()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-compose-body-\(UUID().uuidString).txt")
        try Data("from file".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try vm.loadBodyFromFile(url: fileURL)

        #expect(vm.body == "from file")
        #expect(vm.lastFormattingError == nil)
    }

    @Test("JSON prettier formats valid JSON and preserves invalid body")
    func jsonPrettier() {
        let vm = ComposeViewModel()
        vm.body = "{\"b\":2,\"a\":1}"

        vm.prettifyJSONBody()

        #expect(vm.lastFormattingError == nil)
        #expect(vm.body.contains("\n"))
        #expect(vm.body.contains("\"a\""))

        let formatted = vm.body
        vm.body = "{not json"
        vm.prettifyJSONBody()

        #expect(vm.body == "{not json")
        #expect(vm.body != formatted)
        #expect(vm.lastFormattingError?.contains("JSON") == true)
    }

    @Test("XML prettifier formats valid XML and preserves invalid body")
    func xmlPrettifier() {
        let vm = ComposeViewModel()
        vm.body = "<root><child>value</child></root>"

        vm.prettifyXMLBody()

        #expect(vm.lastFormattingError == nil)
        #expect(vm.body.contains("<root>"))
        #expect(vm.body.contains("<child>value</child>"))

        let formatted = vm.body
        vm.body = "<root>"
        vm.prettifyXMLBody()

        #expect(vm.body == "<root>")
        #expect(vm.body != formatted)
        #expect(vm.lastFormattingError?.contains("XML") == true)
    }

    // MARK: - History

    @Test("Successful and failed sends are recorded in history")
    func sendsRecordHistory() async throws {
        let callCount = ManagedAtomic(0)
        let createdResponse = try makeResponse(statusCode: 201)
        let executor = MockComposeExecutor { _, _ in
            if callCount.increment() == 1 {
                return (Data("ok".utf8), createdResponse)
            }
            throw URLError(.timedOut)
        }
        let vm = ComposeViewModel(executor: executor)
        vm.method = "POST"
        vm.url = "https://api.example.com/create"

        await vm.send()
        #expect(vm.history.count == 1)
        #expect(vm.history[0].method == "POST")
        #expect(vm.history[0].statusCode == 201)

        vm.url = "https://api.example.com/fail"
        await vm.send()
        #expect(vm.history.count == 2)
        #expect(vm.history[0].statusCode == nil)
    }

    @Test("History is deduped, capped, restorable, removable, and clearable")
    func historyManagement() async throws {
        let response = try makeResponse()
        let executor = MockComposeExecutor { _, _ in
            (Data("ok".utf8), response)
        }
        let vm = ComposeViewModel(executor: executor, historyStore: makeHistoryStore(maxEntries: 20))

        for index in 0 ..< 22 {
            vm.method = index.isMultiple(of: 2) ? "GET" : "POST"
            vm.url = "https://api.example.com/\(index)"
            await vm.send()
        }

        #expect(vm.history.count == 20)
        #expect(vm.history.first?.url == "https://api.example.com/21")
        #expect(vm.history.last?.url == "https://api.example.com/2")

        vm.method = "GET"
        vm.url = "https://api.example.com/21"
        await vm.send()
        #expect(vm.history.count == 20)
        #expect(vm.history.first?.url == "https://api.example.com/21")

        let restoreID = try #require(vm.history.first(where: { $0.url == "https://api.example.com/5" })?.id)
        vm.restoreHistoryEntry(id: restoreID)
        #expect(vm.url == "https://api.example.com/5")
        #expect(vm.queryItems.isEmpty)

        let removeID = try #require(vm.history.first?.id)
        vm.removeHistoryEntry(id: removeID)
        #expect(vm.history.count == 19)

        vm.clearHistory()
        #expect(vm.history.isEmpty)
    }

    private func makeHistoryStore(maxEntries: Int = ComposeHistoryStore.defaultMaxEntries) -> ComposeHistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-compose-view-model-tests-\(UUID().uuidString)", isDirectory: true)
        return ComposeHistoryStore(
            fileURL: directory.appendingPathComponent("compose-history.json"),
            maxEntries: maxEntries
        )
    }

    @Test("Fresh Compose reset clears stale selected-row draft")
    func resetDraftClearsCapturedRequestState() async throws {
        let response = try makeResponse(statusCode: 204)
        let executor = MockComposeExecutor { _, _ in
            (Data(), response)
        }
        let vm = ComposeViewModel(executor: executor, historyStore: makeHistoryStore())
        vm.prefill(from: TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/checkout"))
        vm.headers = [EditableReplayHeader(name: "Content-Type", value: "application/json", isEnabled: false)]
        vm.body = #"{"expectedTotal":64.5}"#
        vm.queryItems = [EditableQueryItem(name: "debug", value: "1")]
        vm.requestTimeout = .sixty
        vm.followsRedirects = false
        await vm.send()

        vm.resetDraft()

        #expect(vm.method == "GET")
        #expect(vm.url.isEmpty)
        #expect(vm.headers.isEmpty)
        #expect(vm.queryItems.isEmpty)
        #expect(vm.body.isEmpty)
        #expect(vm.sourceIsWebSocket == false)
        #expect(vm.lastSyncedURL.isEmpty)
        #expect(vm.requestTimeout == .sixty)
        #expect(vm.followsRedirects == false)
        if case .empty = vm.responseState {} else {
            Issue.record("Expected fresh Compose reset to clear the response panel")
        }
    }

    // MARK: - Unsupported Request Types

    @Test("WebSocket prefill sets unsupported state")
    func webSocketPrefillUnsupported() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        let vm = ComposeViewModel()
        vm.prefill(from: transaction)

        #expect(vm.sourceIsWebSocket == true)
        #expect(vm.isUnsupportedForReplay == true)
        if case .unsupported = vm.responseState {} else {
            Issue.record("Expected unsupported state for WebSocket transaction")
        }
    }

    @Test("CONNECT prefill sets unsupported state")
    func connectPrefillUnsupported() {
        let transaction = TestFixtures.makeTransaction(method: "CONNECT", url: "https://example.com:443")
        let vm = ComposeViewModel()
        vm.prefill(from: transaction)

        #expect(vm.sourceIsWebSocket == false)
        #expect(vm.isUnsupportedForReplay == true)
        if case .unsupported = vm.responseState {} else {
            Issue.record("Expected unsupported state for CONNECT transaction")
        }
    }

    @Test("Send on unsupported draft does not invoke executor")
    func sendUnsupportedDoesNotCallExecutor() async {
        let callCount = ManagedAtomic(0)
        let executor = MockComposeExecutor { _, _ in
            _ = callCount.increment()
            throw URLError(.badURL)
        }

        let transaction = TestFixtures.makeWebSocketTransaction()
        let vm = ComposeViewModel(executor: executor)
        vm.prefill(from: transaction)

        await vm.send()

        #expect(callCount.currentValue == 0)
        if case .unsupported = vm.responseState {} else {
            Issue.record("Expected unsupported state after send attempt")
        }
    }

    @Test("Normal HTTP prefill keeps supported state")
    func normalPrefillSupported() {
        let transaction = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/test")
        let vm = ComposeViewModel()
        vm.prefill(from: transaction)

        #expect(vm.sourceIsWebSocket == false)
        #expect(vm.isUnsupportedForReplay == false)
        if case .empty = vm.responseState {} else {
            Issue.record("Expected empty state for normal HTTP transaction")
        }
    }

    @Test("Switching from unsupported to supported draft clears unsupported state")
    func switchingDraftsClearsUnsupported() {
        let vm = ComposeViewModel()

        let wsTransaction = TestFixtures.makeWebSocketTransaction()
        vm.prefill(from: wsTransaction)
        if case .unsupported = vm.responseState {} else {
            Issue.record("Expected unsupported state after WS prefill")
        }

        let normalTransaction = TestFixtures.makeTransaction()
        vm.prefill(from: normalTransaction)
        #expect(vm.sourceIsWebSocket == false)
        #expect(vm.isUnsupportedForReplay == false)
        if case .empty = vm.responseState {} else {
            Issue.record("Expected empty state after switching to normal draft")
        }
    }

    @Test("Changing method from CONNECT to GET clears unsupported response state")
    func connectToGetClearsUnsupported() {
        let transaction = TestFixtures.makeTransaction(method: "CONNECT", url: "https://example.com:443")
        let vm = ComposeViewModel()
        vm.prefill(from: transaction)

        #expect(vm.isUnsupportedForReplay == true)
        if case .unsupported = vm.responseState {} else {
            Issue.record("Expected unsupported state for CONNECT draft")
        }

        vm.method = "GET"
        vm.syncUnsupportedState()
        #expect(vm.isUnsupportedForReplay == false)
        if case .empty = vm.responseState {} else {
            Issue.record("Expected empty state after changing CONNECT to GET")
        }
    }

    @Test("Changing method from GET to CONNECT while empty transitions to unsupported")
    func getToConnectTransitionsToUnsupported() {
        let transaction = TestFixtures.makeTransaction(method: "GET", url: "https://example.com")
        let vm = ComposeViewModel()
        vm.prefill(from: transaction)

        if case .empty = vm.responseState {} else {
            Issue.record("Expected empty state for GET draft")
        }

        vm.method = "CONNECT"
        vm.syncUnsupportedState()
        #expect(vm.isUnsupportedForReplay == true)
        if case .unsupported = vm.responseState {} else {
            Issue.record("Expected unsupported state after changing GET to CONNECT")
        }
    }

    @Test("Changing method to CONNECT while response is success does not overwrite")
    func connectDoesNotOverwriteSuccess() async throws {
        let response = try makeResponse()
        let executor = MockComposeExecutor { _, _ in
            (Data("ok".utf8), response)
        }
        let vm = ComposeViewModel(executor: executor)
        vm.url = "https://example.com"
        await vm.send()

        if case .success = vm.responseState {} else {
            Issue.record("Expected success state after send")
        }

        vm.method = "CONNECT"
        vm.syncUnsupportedState()

        if case .success = vm.responseState {} else {
            Issue.record("Expected success state to be preserved when switching to CONNECT")
        }
    }

    // MARK: Private

    // MARK: - Test Helpers

    private func makeResponse(
        url: String = "https://example.com",
        statusCode: Int = 200,
        headerFields: [String: String]? = nil
    )
        throws -> HTTPURLResponse
    {
        let parsedURL = try #require(URL(string: url))
        return try #require(
            HTTPURLResponse(
                url: parsedURL,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headerFields
            )
        )
    }
}

// MARK: - ManagedAtomic

/// Simple thread-safe counter for test coordination.
private final class ManagedAtomic: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ initial: Int) {
        value = initial
    }

    // MARK: Internal

    var currentValue: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    // MARK: Private

    private var value: Int
    private let lock = NSLock()
}

// MARK: - RequestCapture

private final class RequestCapture: @unchecked Sendable {
    // MARK: Internal

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }

    var followsRedirects: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return capturedFollowsRedirects
    }

    func record(request: URLRequest, followsRedirects: Bool) {
        lock.lock()
        defer { lock.unlock() }
        capturedRequest = request
        capturedFollowsRedirects = followsRedirects
    }

    // MARK: Private

    private var capturedRequest: URLRequest?
    private var capturedFollowsRedirects: Bool?
    private let lock = NSLock()
}
