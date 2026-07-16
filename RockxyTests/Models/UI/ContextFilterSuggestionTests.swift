import Foundation
@testable import Rockxy
import Testing

struct ContextFilterSuggestionTests {
    @Test("Header suggestions target the correct side and preserve header identity")
    func headerSuggestion() throws {
        let header = HTTPHeader(name: "X-Request-ID", value: "abc-123")

        let request = try #require(ContextFilterSuggestion.header(header, source: .request))
        let response = try #require(ContextFilterSuggestion.header(header, source: .response))

        #expect(request.field == .requestHeader)
        #expect(response.field == .responseHeader)
        #expect(request.value == "X-Request-ID: abc-123")
        #expect(request.includeOperator == .contains)
        #expect(request.excludeOperator == .doesNotContain)
    }

    @Test("Table suggestions only promote stable semantic values")
    func tableCellSuggestion() throws {
        let transaction = TestFixtures.makeTransaction(method: "POST", statusCode: 201)
        transaction.clientApp = "Safari"
        transaction.request.headers.append(HTTPHeader(name: "X-Trace", value: "trace-42"))

        let method = try #require(ContextFilterSuggestion.tableCell(columnID: "method", transaction: transaction))
        let status = try #require(ContextFilterSuggestion.tableCell(columnID: "code", transaction: transaction))
        let header = try #require(ContextFilterSuggestion.tableCell(
            columnID: "reqHeader.X-Trace",
            transaction: transaction
        ))

        #expect(method == ContextFilterSuggestion(
            field: .method,
            value: "POST",
            includeOperator: .is,
            excludeOperator: .notEqual
        ))
        #expect(status.value == "201")
        #expect(header.field == .requestHeader)
        #expect(header.value == "X-Trace: trace-42")
        #expect(ContextFilterSuggestion.tableCell(columnID: "duration", transaction: transaction) == nil)
    }

    @Test("Context actions use the visible advanced-filter rule state")
    @MainActor
    func coordinatorAppliesContextFilter() throws {
        let coordinator = MainContentCoordinator()
        let get = TestFixtures.makeTransaction(method: "GET")
        let post = TestFixtures.makeTransaction(method: "POST")
        coordinator.transactions = [get, post]
        var placeholder = FilterRule()
        placeholder.connector = .or
        coordinator.filterRules = [placeholder]

        let suggestion = try #require(ContextFilterSuggestion.tableCell(columnID: "method", transaction: post))
        coordinator.applyContextFilter(suggestion)

        #expect(coordinator.isFilterBarVisible)
        #expect(coordinator.filterRules.count == 1)
        #expect(coordinator.filterRules.first?.field == .method)
        #expect(coordinator.filterRules.first?.filterOperator == .is)
        #expect(coordinator.filterRules.first?.id == placeholder.id)
        #expect(coordinator.filterRules.first?.connector == .or)
        #expect(coordinator.filteredTransactions.map(\.id) == [post.id])
    }
}
