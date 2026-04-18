import Foundation
import os

nonisolated(unsafe) private let mcpToolRegistryLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "MCPToolRegistry"
)

// MARK: - MCPToolRegistry

struct MCPToolRegistry {
    // MARK: Internal

    let flowService: MCPFlowQueryService
    let statusService: MCPStatusService
    let ruleService: MCPRuleQueryService

    func listTools() -> MCPToolsListResult {
        MCPToolsListResult(tools: MCPToolDefinitions.allTools)
    }

    func callTool(params: MCPToolCallParams) async -> MCPToolCallResult {
        let args = params.arguments ?? [:]
        mcpToolRegistryLogger.debug("Tool call: \(params.name, privacy: .public)")

        switch params.name {
        case "get_version":
            return statusService.getVersion()

        case "get_proxy_status":
            return await statusService.getProxyStatus()

        case "get_certificate_status":
            return await statusService.getCertificateStatus()

        case "get_recent_flows":
            let limit = extractInt("limit", from: args) ?? MCPLimits.defaultFlowResults
            let filterHost = extractString("filter_host", from: args)
            let filterMethod = extractString("filter_method", from: args)
            let filterStatusCode = extractInt("filter_status_code", from: args)
            return await flowService.getRecentFlows(
                limit: limit,
                filterHost: filterHost,
                filterMethod: filterMethod,
                filterStatusCode: filterStatusCode
            )

        case "get_flow_detail":
            guard let flowId = extractUUID("flow_id", from: args) else {
                return missingParamResult("flow_id")
            }
            return await flowService.getFlowDetail(flowId: flowId)

        case "search_flows":
            let query = extractString("query", from: args)
            let method = extractString("method", from: args)
            let statusMin = extractInt("status_min", from: args)
            let statusMax = extractInt("status_max", from: args)
            let limit = extractInt("limit", from: args) ?? MCPLimits.defaultFlowResults
            return await flowService.searchFlows(
                query: query,
                method: method,
                statusMin: statusMin,
                statusMax: statusMax,
                limit: limit
            )

        case "filter_flows":
            guard let filters = extractArray("filters", from: args) else {
                return missingParamResult("filters")
            }
            var filterDicts: [[String: MCPJSONValue]] = []
            for value in filters {
                guard case let .object(dict) = value else {
                    return invalidParamResult("filters", message: "Each filter entry must be an object")
                }
                filterDicts.append(dict)
            }
            let combination = extractString("combination", from: args) ?? "and"
            guard ["and", "or"].contains(combination.lowercased()) else {
                return invalidParamResult("combination", message: "combination must be 'and' or 'or'")
            }
            return await flowService.filterFlows(filters: filterDicts, combination: combination)

        case "export_flow_curl":
            guard let flowId = extractUUID("flow_id", from: args) else {
                return missingParamResult("flow_id")
            }
            return await flowService.exportFlowAsCurl(flowId: flowId)

        case "list_rules":
            return await ruleService.listRules()

        case "get_ssl_proxying_list":
            return await statusService.getSSLProxyingList()

        default:
            mcpToolRegistryLogger.warning("Unknown tool called: \(params.name, privacy: .public)")
            return unknownToolResult(name: params.name)
        }
    }

    // MARK: Private

    private func extractString(_ key: String, from args: [String: MCPJSONValue]) -> String? {
        guard case let .string(value) = args[key] else {
            return nil
        }
        return value
    }

    private func extractInt(_ key: String, from args: [String: MCPJSONValue]) -> Int? {
        switch args[key] {
        case let .int(value):
            return value
        case let .double(value):
            guard value.isFinite,
                  value.rounded(.towardZero) == value,
                  value >= Double(Int.min),
                  value <= Double(Int.max) else
            {
                return nil
            }
            return Int(value)
        default:
            return nil
        }
    }

    private func extractUUID(_ key: String, from args: [String: MCPJSONValue]) -> UUID? {
        guard let string = extractString(key, from: args) else {
            return nil
        }
        return UUID(uuidString: string)
    }

    private func extractArray(_ key: String, from args: [String: MCPJSONValue]) -> [MCPJSONValue]? {
        guard case let .array(value) = args[key] else {
            return nil
        }
        return value
    }

    private func missingParamResult(_ paramName: String) -> MCPToolCallResult {
        mcpToolRegistryLogger.warning("Missing required parameter: \(paramName, privacy: .public)")
        return invalidParamResult(paramName, message: "Missing required parameter: \(paramName)")
    }

    private func invalidParamResult(_ paramName: String, message: String) -> MCPToolCallResult {
        MCPToolCallResult(
            content: [.text(encodeErrorJSON(["error": message, "param": paramName]))],
            isError: true
        )
    }

    private func unknownToolResult(name: String) -> MCPToolCallResult {
        MCPToolCallResult(
            content: [.text(encodeErrorJSON(["error": "Unknown tool: \(name)"]))],
            isError: true
        )
    }

    private func encodeErrorJSON(_ payload: [String: String]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            return String(data: data, encoding: .utf8) ?? #"{"error":"Internal encoding error"}"#
        } catch {
            mcpToolRegistryLogger.warning("Failed to encode error JSON: \(error.localizedDescription)")
            return #"{"error":"Internal encoding error"}"#
        }
    }
}
