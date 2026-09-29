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
