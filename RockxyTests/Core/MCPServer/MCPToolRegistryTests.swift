import Foundation
@testable import Rockxy
import Testing

// MARK: - MCPToolRegistryTests

@MainActor
@Suite("MCP Tool Registry")
struct MCPToolRegistryTests {
    // MARK: Internal

    // MARK: - Tool Definitions

    @Test("Lists all Phase 1 tools")
    func listAllTools() {
        let tools = MCPToolDefinitions.allTools
        #expect(tools.count == 10)

        let names = Set(tools.map(\.name))
        #expect(names.contains("get_version"))
        #expect(names.contains("get_proxy_status"))
        #expect(names.contains("get_certificate_status"))
        #expect(names.contains("get_recent_flows"))
        #expect(names.contains("get_flow_detail"))
        #expect(names.contains("search_flows"))
        #expect(names.contains("filter_flows"))
        #expect(names.contains("export_flow_curl"))
        #expect(names.contains("list_rules"))
        #expect(names.contains("get_ssl_proxying_list"))
    }

    @Test("Tool definitions have valid schemas")
    func toolSchemasValid() {
        for tool in MCPToolDefinitions.allTools {
            if case let .object(obj) = tool.inputSchema {
                #expect(obj["type"] == .string("object"))
            } else {
                Issue.record("Tool \(tool.name) schema is not an object")
            }
        }
    }

    @Test("Tool names are unique")
    func toolNamesUnique() {
        let names = MCPToolDefinitions.allTools.map(\.name)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }

    @Test("All tool definitions have descriptions")
    func allToolsHaveDescriptions() {
        for tool in MCPToolDefinitions.allTools {
            #expect(tool.description != nil)
            #expect(tool.description?.isEmpty == false)
        }
    }

    // MARK: - Registry List

    @Test("Registry listTools returns all definitions")
    func registryListTools() {
        let registry = makeTestRegistry()
        let result = registry.listTools()
        #expect(result.tools.count == MCPToolDefinitions.allTools.count)
    }

    // MARK: - Unknown Tool

    @Test("Unknown tool returns error result")
    func unknownTool() async {
        let registry = makeTestRegistry()
        let result = await registry.callTool(
            params: MCPToolCallParams(name: "nonexistent_tool", arguments: nil)
        )
        #expect(result.isError == true)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("Unknown tool"))
        #expect(text.contains("nonexistent_tool"))
    }

    // MARK: - get_version Tool

    @Test("get_version returns version info")
    func getVersionTool() async {
        let registry = makeTestRegistry()
        let result = await registry.callTool(
            params: MCPToolCallParams(name: "get_version", arguments: nil)
        )
        #expect(result.isError == nil || result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("mcp_protocol_version"))
        #expect(text.contains("app_name"))
    }

    @Test("get_recent_flows dispatches to flow service")
    func recentFlowsTool() async throws {
        let flowProvider = MockFlowProvider()
        flowProvider.transactions = [
            TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/users", statusCode: 200),
            TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/orders", statusCode: 201),
        ]
        let registry = makeTestRegistry(flowProvider: flowProvider)

        let result = await registry.callTool(
            params: MCPToolCallParams(
                name: "get_recent_flows",
                arguments: ["limit": .int(5), "filter_host": .string("api.example.com")]
            )
        )

        let json = try decodeJSONObject(from: result)
        let flows = try #require(json["flows"] as? [[String: Any]])
        #expect(flows.count == 2)
        #expect(json["total_count"] as? Int == 2)
    }

    @Test("export_flow_curl dispatches to flow service")
    func exportCurlTool() async throws {
        let flowProvider = MockFlowProvider()
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/orders?token=secret"
        )
        flowProvider.transactions = [transaction]
        let registry = makeTestRegistry(flowProvider: flowProvider)

        let result = await registry.callTool(
            params: MCPToolCallParams(
                name: "export_flow_curl",
                arguments: ["flow_id": .string(transaction.id.uuidString)]
            )
        )

        let text = try #require(result.content.first?.text)
        #expect(text.contains("curl"))
        #expect(text.contains("api.example.com"))
    }

    @Test("get_proxy_status dispatches to status service")
    func proxyStatusTool() async throws {
        let stateProvider = MockProxyStateProvider()
        stateProvider.isProxyRunning = true
        stateProvider.activeProxyPort = 9_991
        stateProvider.transactionCount = 8
        let registry = makeTestRegistry(stateProvider: stateProvider)

        let result = await registry.callTool(
            params: MCPToolCallParams(name: "get_proxy_status", arguments: nil)
        )

        let json = try decodeJSONObject(from: result)
        #expect(json["is_running"] as? Bool == true)
        #expect(json["port"] as? Int == 9_991)
        #expect(json["transaction_count"] as? Int == 8)
    }

    // MARK: - get_flow_detail Missing Param

    @Test("get_flow_detail without flow_id returns error")
    func flowDetailMissingParam() async {
        let registry = makeTestRegistry()
        let result = await registry.callTool(
            params: MCPToolCallParams(name: "get_flow_detail", arguments: [:])
        )
        #expect(result.isError == true)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("flow_id"))
    }

    // MARK: - export_flow_curl Missing Param

    @Test("export_flow_curl without flow_id returns error")
    func exportCurlMissingParam() async {
        let registry = makeTestRegistry()
        let result = await registry.callTool(
            params: MCPToolCallParams(name: "export_flow_curl", arguments: [:])
        )
        #expect(result.isError == true)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("flow_id"))
    }

    // MARK: - filter_flows Missing Param

    @Test("filter_flows without filters returns error")
    func filterFlowsMissingParam() async {
        let registry = makeTestRegistry()
        let result = await registry.callTool(
            params: MCPToolCallParams(name: "filter_flows", arguments: [:])
        )
        #expect(result.isError == true)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("filters"))
    }

    @Test("filter_flows rejects malformed filter entries")
    func filterFlowsRejectsMalformedEntries() async {
        let registry = makeTestRegistry()
        let result = await registry.callTool(
            params: MCPToolCallParams(
                name: "filter_flows",
                arguments: ["filters": .array([.string("bad-filter")])]
            )
        )

        #expect(result.isError == true)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("must be an object"))
    }

    @Test("filter_flows rejects invalid combination")
    func filterFlowsRejectsInvalidCombination() async {
        let registry = makeTestRegistry()
        let result = await registry.callTool(
            params: MCPToolCallParams(
                name: "filter_flows",
                arguments: [
                    "filters": .array([.object([
                        "field": .string("host"),
                        "operator": .string("contains"),
                        "value": .string("example.com"),
                    ])]),
                    "combination": .string("xor"),
                ]
            )
        )

        #expect(result.isError == true)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("combination"))
    }

    // MARK: Private

    // MARK: - Private Helpers

    private func makeTestRegistry(
        flowProvider: MockFlowProvider? = nil,
        stateProvider: MockProxyStateProvider? = nil
    )
        -> MCPToolRegistry
    {
        let coordinator = MCPServerCoordinator()
        if let flowProvider, let stateProvider {
            coordinator.attachProviders(flow: flowProvider, state: stateProvider)
        } else if let flowProvider {
            coordinator.attachProviders(flow: flowProvider, state: MockProxyStateProvider())
        } else if let stateProvider {
            coordinator.attachProviders(flow: MockFlowProvider(), state: stateProvider)
        }
        let flowService = MCPFlowQueryService(
            serverCoordinator: coordinator,
            redactionPolicy: MCPRedactionPolicy(isEnabled: false)
        )
        let statusService = MCPStatusService(serverCoordinator: coordinator)
        let ruleService = MCPRuleQueryService(ruleEngine: RuleEngine())
        return MCPToolRegistry(
            flowService: flowService,
            statusService: statusService,
            ruleService: ruleService
        )
    }

    private func decodeJSONObject(from result: MCPToolCallResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
