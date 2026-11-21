import Foundation
@testable import Rockxy
import Testing

// MARK: - CustomColumnValueTests

@MainActor
struct CustomColumnValueTests {
    @Test("Every custom column kind has its own identifier prefix")
    func identifiers() {
        for source in HeaderColumnSource.allCases {
            let column = HeaderColumn(headerName: "Name", source: source)
            let parsed = HeaderColumn.parse(columnID: column.columnIdentifier)
            #expect(parsed?.source == source)
            #expect(parsed?.name == "Name")
            #expect(HeaderColumn.isCustomColumnID(column.columnIdentifier))
        }
        #expect(!HeaderColumn.isCustomColumnID("url"))
        #expect(HeaderColumn.parse(columnID: "resBody.$.data[0].id")?.name == "$.data[0].id")
    }

    @Test("Query columns show a parameter's first value")
    func queryValue() {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/search?q=swift&page=2&page=3")
        #expect(HeaderColumnStore.resolveValue(for: "reqQuery.page", transaction: transaction) == "2")
        #expect(HeaderColumnStore.resolveValue(for: "reqQuery.q", transaction: transaction) == "swift")
        #expect(HeaderColumnStore.resolveValue(for: "reqQuery.missing", transaction: transaction).isEmpty)
        let row = RequestListRow(from: transaction)
        #expect(RequestListRow.resolveHeaderValue(for: "reqQuery.page", row: row) == "2")
    }

    @Test("Body columns evaluate JSONPath or jq, and ignore bodies that are not JSON")
    func bodyValue() {
        let body = Data(#"{"data":{"user":{"name":"ana","roles":["admin","dev"]}},"count":2}"#.utf8)
        #expect(CustomColumnValueResolver.evaluate("$.data.user.name", on: body) == "ana")
        #expect(CustomColumnValueResolver.evaluate("$.data.user.roles[*]", on: body) == "admin, dev")
        #expect(CustomColumnValueResolver.evaluate(".data.user.roles | length", on: body) == "2")
        #expect(CustomColumnValueResolver
            .evaluate(".data.user", on: body) == #"{"name":"ana","roles":["admin","dev"]}"#)
        #expect(CustomColumnValueResolver.evaluate(".count + 1", on: body) == "3")
        #expect(CustomColumnValueResolver.evaluate(".nope(", on: body).isEmpty)
        #expect(CustomColumnValueResolver.evaluate(".a", on: Data("plain text".utf8)).isEmpty)
        let long = Data("[\"\(String(repeating: "x", count: 400))\"]".utf8)
        #expect(CustomColumnValueResolver.evaluate(".[0]", on: long).count == CustomColumnValueResolver
            .maxDisplayLength + 1)
    }

    @Test("Response body values are cached once the transaction finishes and refreshed when the response changes")
    func bodyCache() {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/user")
        transaction.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"id":1}"#.utf8)
        )
        #expect(HeaderColumnStore.resolveValue(for: "resBody..id", transaction: transaction) == "1")
        #expect(transaction.customColumnValueCache.value(for: "res:.id") == "1")

        transaction.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [],
            body: Data(#"{"id":2}"#.utf8)
        )
        #expect(transaction.customColumnValueCache.value(for: "res:.id") == nil)
        #expect(HeaderColumnStore.resolveValue(for: "resBody..id", transaction: transaction) == "2")

        let request = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/login")
        request.request.body = Data(#"{"user":"bo"}"#.utf8)
        #expect(HeaderColumnStore.resolveValue(for: "reqBody.$.user", transaction: request) == "bo")
    }

    @Test("Live body columns cache unchanged evidence and invalidate on nested body mutations")
    func liveBodyCache() {
        let transaction = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/live")
        transaction.state = .active
        transaction.request.body = Data(#"{"id":1}"#.utf8)
        #expect(CustomColumnValueResolver
            .bodyValue(expression: ".id", response: false, transaction: transaction) == "1")
        #expect(transaction.customColumnValueCache.value(for: "req:.id") == "1")
        #expect(CustomColumnValueResolver.bodyValue(expression: ".id", response: true, transaction: transaction)
            .isEmpty)
        #expect(transaction.customColumnValueCache.value(for: "res:.id") == "")

        transaction.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [],
            body: Data(#"{"id":2}"#.utf8)
        )
        #expect(transaction.customColumnValueCache.value(for: "res:.id") == nil)
        #expect(CustomColumnValueResolver.bodyValue(expression: ".id", response: true, transaction: transaction) == "2")
        transaction.response?.body = Data(#"{"id":3}"#.utf8)
        #expect(transaction.customColumnValueCache.value(for: "res:.id") == nil)
        #expect(CustomColumnValueResolver.bodyValue(expression: ".id", response: true, transaction: transaction) == "3")
        transaction.request.body = Data(#"{"id":4}"#.utf8)
        #expect(transaction.customColumnValueCache.value(for: "req:.id") == nil)
        #expect(CustomColumnValueResolver
            .bodyValue(expression: ".id", response: false, transaction: transaction) == "4")
        transaction.state = .completed
        #expect(CustomColumnValueResolver.bodyValue(expression: ".id", response: true, transaction: transaction) == "3")
    }

    @Test("Query columns cache per transaction and invalidate when the request changes")
    func queryColumnCache() {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/search?q=rockxy&page=2"
        )

        #expect(HeaderColumnStore.resolveValue(for: "reqQuery.q", transaction: transaction) == "rockxy")
        // Cached, so a redraw no longer re-parses the URL for every visible row.
        #expect(transaction.customColumnValueCache.value(for: "qry:q") == "rockxy")

        // A name that is absent caches its empty result too, or a column of misses would
        // keep paying full URL parsing on every pass.
        #expect(HeaderColumnStore.resolveValue(for: "reqQuery.missing", transaction: transaction).isEmpty)
        #expect(transaction.customColumnValueCache.value(for: "qry:missing") == "")

        // Replaying or editing a request must not leave the old value on screen. `url` is a
        // `let` on `HTTPRequestData`, so a changed URL arrives as a whole replaced request --
        // which is what bumps the revision and drops the cache, the same invalidation
        // `bodyValue` relies on.
        transaction.request = TestFixtures.makeRequest(
            url: "https://api.example.com/search?q=proxy&page=2"
        )
        #expect(transaction.customColumnValueCache.value(for: "qry:q") == nil)
        #expect(HeaderColumnStore.resolveValue(for: "reqQuery.q", transaction: transaction) == "proxy")
    }

    @Test("Body column previews preserve truncation and separators for multiple matches")
    func boundedBodyPreview() throws {
        for expression in ["$[*]", ".[]"] {
            for values in [
                [],
                [""],
                ["", ""],
                ["a", "b"],
                [String(repeating: "x", count: 100), "\u{301}" + String(repeating: "y", count: 1_000)],
                [String(repeating: "x", count: 300)],
                [String(repeating: "x", count: 299), ""],
                Array(repeating: String(repeating: "👩🏽‍💻", count: 200), count: 50)
            ] {
                let data = try JSONEncoder().encode(values)
                let joined = values.joined(separator: ", ")
                let expected = joined.count > CustomColumnValueResolver.maxDisplayLength
                    ? String(joined.prefix(CustomColumnValueResolver.maxDisplayLength)) + "…"
                    : joined
                #expect(CustomColumnValueResolver.evaluate(expression, on: data) == expected)
            }
        }
    }

    @Test("Body previews bound UTF-8 storage and never show partial Unicode clusters")
    func byteBoundedBodyPreview() throws {
        let hugeGrapheme = "e" + String(repeating: "\u{301}", count: 20_000)
        let cluster = "e" + String(repeating: "\u{301}", count: 30)
        for expression in ["$[*]", ".[]"] {
            let exact = "e" + String(repeating: "\u{301}", count: 4_095) + "x"
            #expect(exact.utf8.count == CustomColumnValueResolver.maxDisplayBytes)
            let boundary = try JSONEncoder().encode([exact + "y"])
            #expect(CustomColumnValueResolver.evaluate(expression, on: boundary) == exact + "…")
            let huge = try JSONEncoder().encode([hugeGrapheme])
            #expect(CustomColumnValueResolver.evaluate(expression, on: huge) == "…")
            let data = try JSONEncoder().encode(["prefix", hugeGrapheme, "suffix"])
            let result = CustomColumnValueResolver.evaluate(expression, on: data)
            #expect(result == "prefix, …")
            let groups = try JSONEncoder().encode([String(repeating: cluster, count: 300)])
            let preview = CustomColumnValueResolver.evaluate(expression, on: groups)
            #expect(preview.hasSuffix("…"))
            #expect(preview.utf8.count <= CustomColumnValueResolver.maxDisplayBytes + "…".utf8.count)
            #expect(preview.count < CustomColumnValueResolver.maxDisplayLength)
            #expect(preview.dropLast().allSatisfy { String($0) == cluster })
        }
    }

    @Test("Adding query and body columns validates the name and keeps expressions case-sensitive")
    func addColumns() {
        let store = HeaderColumnStore(defaults: IsolatedDefaultsSuite.make(prefix: "Rockxy.CustomColumnValueTests"))
        let model = CustomHeaderColumnsViewModel(store: store, source: .query)

        #expect(model.addHeader("a=b") != .added("query:a=b"))
        if case .added = model.addHeader("page") {} else {
            Issue.record("query column was not added")
        }

        model.source = .responseBody
        #expect(CustomHeaderColumnsViewModel.validationMessage(for: ".data[", source: .responseBody) != nil)
        #expect(CustomHeaderColumnsViewModel.validationMessage(for: "$.data[", source: .responseBody) != nil)
        #expect(CustomHeaderColumnsViewModel.validationMessage(for: "$.data.id", source: .responseBody) == nil)
        #expect(model.addHeader(".Data") == .added("responseBody:.Data"))
        #expect(model.addHeader(".data") == .added("responseBody:.data"))
        #expect(store.columns.count(where: { $0.source == .responseBody }) == 2)
        #expect(model.addHeader(".data") == .alreadyEnabled)
    }
}
