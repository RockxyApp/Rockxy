import Foundation

// MARK: - MCPChangeToolDefinitions

/// Tools that change Rockxy. They are always listed so an agent can explain how to enable them,
/// but each call is refused until the user turns on Settings > MCP > Allow Changes.
enum MCPChangeToolDefinitions {
    static let allTools: [MCPToolDefinition] = [
        createBreakpoint,
        createMapLocal,
        createMapRemote,
        createBlockRule,
        setRuleEnabled,
        enableSSLProxying,
        setNoCaching,
        setRecording,
        clearSession,
    ]

    static let createBreakpoint = MCPToolDefinition(
        name: "create_breakpoint",
        description: requiresPermission(
            "Create an enabled Breakpoint rule that pauses matching requests and/or responses in Rockxy "
                + "for the user to inspect and edit"
        ),
        inputSchema: schema(
            matchProperties(patternKey: "url").merging([
                "phase": .object([
                    "type": "string",
                    "description": "When to pause: request, response, or both (default both)",
                    "enum": .array([.string("request"), .string("response"), .string("both")]),
                ]),
            ]) { current, _ in current },
            required: ["url"]
        )
    )

    static let createMapLocal = MCPToolDefinition(
        name: "create_map_local",
        description: requiresPermission(
            "Create an enabled Map Local rule that answers matching requests with a local response "
                + "(status, headers, body) instead of contacting the server"
        ),
        inputSchema: schema(
            matchProperties(patternKey: "url").merging([
                "status_code": .object([
                    "type": "integer",
                    "description": "Response status code (default 200)",
                    "minimum": .int(100),
                    "maximum": .int(599),
                ]),
                "headers": .object([
                    "type": "object",
                    "description": "Response headers as name: value pairs, e.g. {\"Content-Type\": \"application/json\"}",
                    "additionalProperties": .object(["type": "string"]),
                ]),
                "body": .object([
                    "type": "string",
                    "description": "Response body text (at most 512 KB)",
                ]),
                "delay_ms": .object([
                    "type": "integer",
                    "description": "Delay before responding, in milliseconds (0-60000)",
                    "minimum": .int(0),
                    "maximum": .int(60_000),
                ]),
            ]) { current, _ in current },
            required: ["url"]
        )
    )

    static let createMapRemote = MCPToolDefinition(
        name: "create_map_remote",
        description: requiresPermission(
            "Create an enabled Map Remote rule that sends matching requests to another server, "
                + "for example production to localhost"
        ),
        inputSchema: schema(
            matchProperties(patternKey: "from_url").merging([
                "to_url": .object([
                    "type": "string",
                    "description": "Destination URL, e.g. http://localhost:3000. A path or query replaces the original one",
                ]),
                "preserve_host_header": .object([
                    "type": "boolean",
                    "description": "Keep the original Host header (default false)",
                ]),
            ]) { current, _ in current },
            required: ["from_url", "to_url"]
        )
    )

    static let createBlockRule = MCPToolDefinition(
        name: "create_block_rule",
        description: requiresPermission("Create an enabled Block rule for matching requests"),
        inputSchema: schema(
            matchProperties(patternKey: "url").merging([
                "action": .object([
                    "type": "string",
                    "description": "forbidden returns 403 (default); drop closes the connection",
                    "enum": .array([.string("forbidden"), .string("drop")]),
                ]),
            ]) { current, _ in current },
            required: ["url"]
        )
    )

    static let setRuleEnabled = MCPToolDefinition(
        name: "set_rule_enabled",
        description: requiresPermission("Enable or disable an existing rule by the id returned from list_rules"),
        inputSchema: schema(
            [
                "rule_id": .object(["type": "string", "description": "Rule UUID from list_rules"]),
                "enabled": .object(["type": "boolean", "description": "true to enable, false to disable"]),
            ],
            required: ["rule_id", "enabled"]
        )
    )

    static let enableSSLProxying = MCPToolDefinition(
        name: "enable_ssl_proxying",
        description: requiresPermission(
            "Turn on HTTPS decryption for a domain, like the Enable HTTPS Decryption menu item. "
                + "Decryption also needs the Rockxy root certificate to be trusted"
        ),
        inputSchema: schema(
            [
                "domain": .object([
                    "type": "string",
                    "description": "Host name such as api.example.com, or *.example.com for subdomains",
                ]),
            ],
            required: ["domain"]
        )
    )

    static let setNoCaching = MCPToolDefinition(
        name: "set_no_caching",
        description: requiresPermission("Turn No Caching on or off so clients always fetch fresh responses"),
        inputSchema: schema(
            ["enabled": .object(["type": "boolean", "description": "true to strip caching headers"])],
            required: ["enabled"]
        )
    )

    static let setRecording = MCPToolDefinition(
        name: "set_recording",
        description: requiresPermission(
            "Pause or resume recording traffic into the session while the proxy keeps running"
        ),
        inputSchema: schema(
            ["recording": .object(["type": "boolean", "description": "true to record, false to pause"])],
            required: ["recording"]
        )
    )

    static let clearSession = MCPToolDefinition(
        name: "clear_session",
        description: requiresPermission("Remove every captured flow from the current session"),
        inputSchema: schema([:], required: [])
    )

    // MARK: Private

    private static func requiresPermission(_ text: String) -> String {
        text + ". Requires the user to allow changes in Rockxy Settings > MCP."
    }

    private static func matchProperties(patternKey: String) -> [String: MCPJSONValue] {
        [
            patternKey: .object([
                "type": "string",
                "description": .string(
                    "URL to match. Wildcards: * matches any text, ? one character, "
                        + "e.g. https://api.example.com/v1/users*"
                ),
            ]),
            "match_type": .object([
                "type": "string",
                "description": "wildcard (default) or regex",
                "enum": .array([.string("wildcard"), .string("regex")]),
            ]),
            "include_subpaths": .object([
                "type": "boolean",
                "description": "For wildcard patterns, also match longer paths (default true)",
            ]),
            "method": .object([
                "type": "string",
                "description": "HTTP method to match, e.g. GET or POST (default any)",
            ]),
            "graphql_operation": .object([
                "type": "string",
                "description": "Only match GraphQL requests with this operation name",
            ]),
            "name": .object(["type": "string", "description": "Rule name shown in Rockxy"]),
        ]
    }

    private static func schema(_ properties: [String: MCPJSONValue], required: [String]) -> MCPJSONValue {
        var fields: [String: MCPJSONValue] = [
            "type": "object",
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            fields["required"] = .array(required.map { .string($0) })
        }
        return .object(fields)
    }
}
