import Foundation

// MARK: - MCPToolDefinitions

enum MCPToolDefinitions {
    static let allTools: [MCPToolDefinition] = [
        getVersion,
        getProxyStatus,
        getCertificateStatus,
        getRecentFlows,
        getFlowDetail,
        searchFlows,
        filterFlows,
        exportFlowCurl,
        listRules,
        getSSLProxyingList,
    ]

    // MARK: - Status Tools

    static let getVersion = MCPToolDefinition(
        name: "get_version",
        description: "Get the Rockxy app version and MCP protocol version",
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
        ])
    )

    static let getProxyStatus = MCPToolDefinition(
        name: "get_proxy_status",
        description: "Get the current proxy server status including port, recording state, and transaction count",
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
        ])
    )

    static let getCertificateStatus = MCPToolDefinition(
        name: "get_certificate_status",
        description: "Get the root CA certificate status for HTTPS interception",
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
        ])
    )

    // MARK: - Flow Tools

    static let getRecentFlows = MCPToolDefinition(
        name: "get_recent_flows",
        description: "Get recent HTTP/HTTPS flows captured by the proxy, ordered newest-first",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "limit": .object([
                    "type": "integer",
                    "description": "Maximum number of flows to return (default 50, max 500)",
                    "default": .int(50),
                    "minimum": .int(1),
                    "maximum": .int(500),
                ]),
                "filter_host": .object([
                    "type": "string",
                    "description": "Filter flows by host (substring match)",
                ]),
                "filter_method": .object([
                    "type": "string",
                    "description": "Filter flows by HTTP method (exact match, e.g. GET, POST)",
                ]),
                "filter_status_code": .object([
                    "type": "integer",
                    "description": "Filter flows by exact HTTP status code",
                ]),
            ]),
        ])
    )

    static let getFlowDetail = MCPToolDefinition(
        name: "get_flow_detail",
        description: "Get full details for a specific flow including headers, body preview, and timing",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "flow_id": .object([
                    "type": "string",
                    "description": "The UUID of the flow to retrieve",
                ]),
            ]),
            "required": .array([.string("flow_id")]),
        ])
    )

    static let searchFlows = MCPToolDefinition(
        name: "search_flows",
        description: "Search flows by URL query string, HTTP method, and/or status code range",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "query": .object([
                    "type": "string",
                    "description": "Search query matched against the request URL (substring match)",
                ]),
                "method": .object([
                    "type": "string",
                    "description": "Filter by HTTP method (exact match)",
                ]),
                "status_min": .object([
                    "type": "integer",
                    "description": "Minimum HTTP status code (inclusive)",
                ]),
                "status_max": .object([
                    "type": "integer",
                    "description": "Maximum HTTP status code (inclusive)",
                ]),
                "limit": .object([
                    "type": "integer",
                    "description": "Maximum number of results (default 50, max 500)",
                    "default": .int(50),
                    "minimum": .int(1),
                    "maximum": .int(500),
                ]),
            ]),
        ])
    )

    static let filterFlows = MCPToolDefinition(
        name: "filter_flows",
        description: "Filter flows using structured filter expressions with field/operator/value triples",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "filters": .object([
                    "type": "array",
                    "description": "Array of filter objects",
                    "items": .object([
                        "type": "object",
                        "properties": .object([
                            "field": .object([
                                "type": "string",
                                "description":
                                    "Field to filter on: host, method, status_code, path, client_app, state",
                            ]),
                            "operator": .object([
                                "type": "string",
                                "description":
                                    "Comparison operator: equals, not_equals, contains, starts_with, gt, lt",
                            ]),
                            "value": .object([
                                "type": "string",
                                "description": "Value to compare against (pass as string, e.g. '404' for numeric fields like status_code)",
                            ]),
                        ]),
                        "required": .array([.string("field"), .string("operator"), .string("value")]),
                    ]),
                ]),
                "combination": .object([
                    "type": "string",
                    "description": "How to combine multiple filters: 'and' (default) or 'or'",
                    "default": "and",
                    "enum": .array([.string("and"), .string("or")]),
                ]),
            ]),
            "required": .array([.string("filters")]),
        ])
    )

    static let exportFlowCurl = MCPToolDefinition(
        name: "export_flow_curl",
        description: "Export a specific flow as a cURL command",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "flow_id": .object([
                    "type": "string",
                    "description": "The UUID of the flow to export",
                ]),
            ]),
            "required": .array([.string("flow_id")]),
        ])
    )

    // MARK: - Rule Tools

    static let listRules = MCPToolDefinition(
        name: "list_rules",
        description: "List all proxy rules including their match conditions and actions",
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
        ])
    )

    // MARK: - SSL Tools

    static let getSSLProxyingList = MCPToolDefinition(
        name: "get_ssl_proxying_list",
        description: "Get the SSL proxying domain list including include/exclude rules and bypass domains",
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
        ])
    )
}
