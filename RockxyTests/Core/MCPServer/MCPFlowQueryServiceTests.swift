import Foundation
@testable import Rockxy
import Testing

// MARK: - MockFlowProvider

@MainActor
final class MockFlowProvider: MCPLiveFlowProvider {
    var transactions: [HTTPTransaction] = []

    var liveTransactions: [HTTPTransaction] {
        transactions
    }

    var liveTransactionCount: Int {
        transactions.count
    }

    func liveTransaction(for id: UUID) -> HTTPTransaction? {
        transactions.first { $0.id == id }
    }
}

// MARK: - MCPFlowQueryServiceTests

@MainActor
@Suite("MCP Flow Query Service")
struct MCPFlowQueryServiceTests {
    // MARK: Internal

    // MARK: - Provider Unavailable

    @Test("Returns empty flows when no provider attached")
    func nilProvider() async {
        let coordinator = MCPServerCoordinator()
        let service = MCPFlowQueryService(
            serverCoordinator: coordinator,
            redactionPolicy: MCPRedactionPolicy(isEnabled: false)
        )

        let result = await service.getRecentFlows(
            limit: 50,
            filterHost: nil,
            filterMethod: nil,
            filterStatusCode: nil
        )

        #expect(result.isError == nil || result.isError == false)
    }

    // MARK: - Get Recent Flows

    @Test("Get recent flows returns transactions")
    func getRecentFlows() async {
        let provider = MockFlowProvider()
        provider.transactions = [
            TestFixtures.makeTransaction(
                method: "GET",
                url: "https://api.example.com/users",
                statusCode: 200
            ),
            TestFixtures.makeTransaction(
                method: "POST",
                url: "https://api.example.com/data",
                statusCode: 201
            ),
        ]

        let service = makeService(provider: provider)
        let result = await service.getRecentFlows(
            limit: 50,
            filterHost: nil,
            filterMethod: nil,
            filterStatusCode: nil
        )

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("api.example.com"))
        #expect(text.contains("total_count"))
    }

    @Test("Get recent flows falls back to SessionStore when live provider is unavailable")
    func getRecentFlowsFallsBackToSessionStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SessionStore(directory: directory)
        let storedTransactions = [
            TestFixtures.makeTransaction(method: "POST", url: "https://other.example.com/orders", statusCode: 202),
            TestFixtures.makeTransaction(method: "GET", url: "https://store.example.com/orders/1", statusCode: 200),
        ]
        for transaction in storedTransactions {
            try await store.saveTransaction(transaction)
        }

        let coordinator = MCPServerCoordinator(sessionStoreFactory: { store })
        let service = MCPFlowQueryService(
            serverCoordinator: coordinator,
            redactionPolicy: MCPRedactionPolicy(isEnabled: false)
        )

        let result = await service.getRecentFlows(
            limit: 1,
            filterHost: "store.example.com",
            filterMethod: nil,
            filterStatusCode: nil
        )

        let json = try decodeJSONObject(from: result)
        let flows = try #require(json["flows"] as? [[String: Any]])
        #expect(flows.count == 1)
        #expect(flows.allSatisfy { ($0["host"] as? String) == "store.example.com" })
        #expect(json["total_count"] as? Int == 1)
    }

    @Test("Filters flows by host")
    func filterByHost() async {
        let provider = MockFlowProvider()
        provider.transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/users"),
            TestFixtures.makeTransaction(url: "https://other.host.com/data"),
            TestFixtures.makeTransaction(url: "https://api.example.com/posts"),
        ]

        let service = makeService(provider: provider)
        let result = await service.getRecentFlows(
            limit: 50,
            filterHost: "api.example.com",
            filterMethod: nil,
            filterStatusCode: nil
        )

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("api.example.com"))
        #expect(!text.contains("other.host.com"))
    }

    @Test("Filters flows by method")
    func filterByMethod() async {
        let provider = MockFlowProvider()
        provider.transactions = [
            TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/a"),
            TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/b"),
            TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/c"),
        ]

        let service = makeService(provider: provider)
        let result = await service.getRecentFlows(
            limit: 50,
            filterHost: nil,
            filterMethod: "POST",
            filterStatusCode: nil
        )

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("\"total_count\":1") || text.contains("\"total_count\": 1"))
    }

    @Test("Respects limit")
    func respectsLimit() async throws {
        let provider = MockFlowProvider()
        provider.transactions = (0 ..< 20).map { i in
            TestFixtures.makeTransaction(url: "https://api.example.com/item/\(i)")
        }

        let service = makeService(provider: provider)
        let result = await service.getRecentFlows(
            limit: 5,
            filterHost: nil,
            filterMethod: nil,
            filterStatusCode: nil
        )

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        let data = Data(text.utf8)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let flows = try #require(json["flows"] as? [[String: Any]])
        #expect(flows.count == 5)
    }

    @Test("Filters flows by status code")
    func filterByStatusCode() async {
        let provider = MockFlowProvider()
        provider.transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/a", statusCode: 200),
            TestFixtures.makeTransaction(url: "https://api.example.com/b", statusCode: 404),
            TestFixtures.makeTransaction(url: "https://api.example.com/c", statusCode: 200),
        ]

        let service = makeService(provider: provider)
        let result = await service.getRecentFlows(
            limit: 50,
            filterHost: nil,
            filterMethod: nil,
            filterStatusCode: 404
        )

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("\"total_count\":1") || text.contains("\"total_count\": 1"))
    }

    // MARK: - Get Flow Detail

    @Test("Get flow detail returns full info")
    func getFlowDetail() async {
        let provider = MockFlowProvider()
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/submit",
            statusCode: 201
        )
        provider.transactions = [transaction]

        let service = makeService(provider: provider)
        let result = await service.getFlowDetail(flowId: transaction.id)

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains(transaction.id.uuidString))
        #expect(text.contains("request"))
        #expect(text.contains("response"))
        #expect(text.contains("201"))
    }

    @Test("Get flow detail falls back to SessionStore lookup")
    func getFlowDetailFallsBackToSessionStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SessionStore(directory: directory)
        let transaction = TestFixtures.makeTransaction(
            method: "PATCH",
            url: "https://store.example.com/profile",
            statusCode: 204
        )
        transaction.comment = "persisted"
        try await store.saveTransaction(transaction)

        let coordinator = MCPServerCoordinator(sessionStoreFactory: { store })
        let service = MCPFlowQueryService(
            serverCoordinator: coordinator,
            redactionPolicy: MCPRedactionPolicy(isEnabled: false)
        )

        let result = await service.getFlowDetail(flowId: transaction.id)

        let json = try decodeJSONObject(from: result)
        #expect(json["id"] as? String == transaction.id.uuidString)
        let request = try #require(json["request"] as? [String: Any])
        #expect(request["method"] as? String == "PATCH")
    }

    @Test("Get flow detail for unknown ID returns error")
    func unknownFlowId() async {
        let provider = MockFlowProvider()
        provider.transactions = [TestFixtures.makeTransaction()]

        let service = makeService(provider: provider)
        let unknownId = UUID()
        let result = await service.getFlowDetail(flowId: unknownId)

        #expect(result.isError == true)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("not found") || text.contains("Flow not found"))
    }

    @Test("Get flow detail with no provider returns error")
    func flowDetailNilProvider() async {
        let coordinator = MCPServerCoordinator()
        let service = MCPFlowQueryService(
            serverCoordinator: coordinator,
            redactionPolicy: MCPRedactionPolicy(isEnabled: false)
        )

        let result = await service.getFlowDetail(flowId: UUID())

        #expect(result.isError == true)
    }

    // MARK: - Export cURL

    @Test("Export flow as cURL")
    func exportCurl() async {
        let provider = MockFlowProvider()
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/data"
        )
        provider.transactions = [transaction]

        let service = makeService(provider: provider)
        let result = await service.exportFlowAsCurl(flowId: transaction.id)

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("curl"))
        #expect(text.contains("api.example.com"))
    }

    @Test("Export cURL for unknown flow returns error")
    func exportCurlUnknownFlow() async {
        let provider = MockFlowProvider()
        let service = makeService(provider: provider)
        let result = await service.exportFlowAsCurl(flowId: UUID())

        #expect(result.isError == true)
    }

    @Test("Export cURL redacts sensitive headers when enabled")
    func exportCurlRedacted() async throws {
        let provider = MockFlowProvider()
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/data"
        )
        transaction.request = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "https://api.example.com/data")),
            httpVersion: "HTTP/1.1",
            headers: [
                HTTPHeader(name: "Authorization", value: "Bearer secret-token-123"),
                HTTPHeader(name: "Content-Type", value: "application/json"),
            ],
            body: nil
        )
        provider.transactions = [transaction]

        let service = makeService(provider: provider, redactionEnabled: true)
        let result = await service.exportFlowAsCurl(flowId: transaction.id)

        let text = result.content.first?.text ?? ""
        #expect(!text.contains("secret-token-123"))
        #expect(text.contains("-H '"))
        #expect(text.contains("Authorization: [REDACTED]"))
    }

    // MARK: - Search Flows

    @Test("Search flows by URL query")
    func searchByQuery() async {
        let provider = MockFlowProvider()
        provider.transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/users"),
            TestFixtures.makeTransaction(url: "https://api.example.com/posts"),
            TestFixtures.makeTransaction(url: "https://other.example.com/users"),
        ]

        let service = makeService(provider: provider)
        let result = await service.searchFlows(
            query: "posts",
            method: nil,
            statusMin: nil,
            statusMax: nil,
            limit: 50
        )

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("posts"))
        #expect(text.contains("\"total_count\":1") || text.contains("\"total_count\": 1"))
    }

    @Test("Search flows with status range")
    func searchByStatusRange() async {
        let provider = MockFlowProvider()
        provider.transactions = [
            TestFixtures.makeTransaction(statusCode: 200),
            TestFixtures.makeTransaction(statusCode: 404),
            TestFixtures.makeTransaction(statusCode: 500),
        ]

        let service = makeService(provider: provider)
        let result = await service.searchFlows(
            query: nil,
            method: nil,
            statusMin: 400,
            statusMax: 499,
            limit: 50
        )

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("404"))
    }

    // MARK: - Filter Flows

    @Test("Filter flows with structured filter")
    func filterWithStructuredFilter() async {
        let provider = MockFlowProvider()
        provider.transactions = [
            TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/a", statusCode: 200),
            TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/b", statusCode: 201),
            TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/c", statusCode: 404),
        ]

        let service = makeService(provider: provider)
        let filters: [[String: MCPJSONValue]] = [
            [
                "field": .string("method"),
                "operator": .string("equals"),
                "value": .string("GET"),
            ],
        ]
        let result = await service.filterFlows(filters: filters, combination: "and")

        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("\"total_count\":2") || text.contains("\"total_count\": 2"))
    }

    @Test("Filter flows with no valid filters returns error")
    func filterNoValidFilters() async {
        let provider = MockFlowProvider()
        provider.transactions = [TestFixtures.makeTransaction()]

        let service = makeService(provider: provider)
        let result = await service.filterFlows(filters: [], combination: "and")

        #expect(result.isError == true)
    }

    // MARK: Private

    // MARK: - Private Helpers

    private func makeService(
        provider: MockFlowProvider,
        redactionEnabled: Bool = false
    )
        -> MCPFlowQueryService
    {
        let coordinator = MCPServerCoordinator()
        coordinator.attachProviders(
            flow: provider,
            state: MockProxyStateProvider()
        )
        return MCPFlowQueryService(
            serverCoordinator: coordinator,
            redactionPolicy: MCPRedactionPolicy(isEnabled: redactionEnabled)
        )
    }

    private func decodeJSONObject(from result: MCPToolCallResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
