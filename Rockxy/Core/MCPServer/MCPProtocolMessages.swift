import Foundation

// MARK: - MCPProtocolVersion

/// MCP protocol version constant.
enum MCPProtocolVersion {
    // MARK: Internal

    static let current = "2025-11-25"
    static let compatibilityFloor = "2025-03-26"

    static func negotiate(clientVersion: String) -> String? {
        guard isValidVersionString(clientVersion) else {
            return nil
        }
        guard clientVersion >= compatibilityFloor, clientVersion <= current else {
            return nil
        }
        return current
    }

    // MARK: Private

    private static func isValidVersionString(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: value) else {
            return false
        }
        return formatter.string(from: date) == value
    }
}

// MARK: - MCPClientInfo

/// Client identity sent during initialization.
struct MCPClientInfo: Codable {
    let name: String
    let version: String
}

// MARK: - MCPClientCapabilities

/// Client capabilities declared during initialization.
struct MCPClientCapabilities: Codable {
    // Phase 1 — no client capability fields are required.
    // Future phases may add `roots`, `sampling`, etc.
}

// MARK: - MCPInitializeParams

/// Parameters for the `initialize` request.
struct MCPInitializeParams: Codable {
    let protocolVersion: String
    let capabilities: MCPClientCapabilities
    let clientInfo: MCPClientInfo
}

// MARK: - MCPServerInfo

/// Server identity returned in the initialize result.
struct MCPServerInfo: Codable {
    let name: String
    let version: String
}

// MARK: - MCPToolsCapability

/// Advertised tools capability.
struct MCPToolsCapability: Codable {
    let listChanged: Bool?
}

// MARK: - MCPServerCapabilities

/// Server capabilities returned in the initialize result.
struct MCPServerCapabilities: Codable {
    let tools: MCPToolsCapability?
}

// MARK: - MCPInitializeResult

/// Response payload for the `initialize` request.
struct MCPInitializeResult: Codable {
    let protocolVersion: String
    let capabilities: MCPServerCapabilities
    let serverInfo: MCPServerInfo
    let instructions: String?
}

// MARK: - MCPToolDefinition

/// A single tool exposed by the MCP server.
struct MCPToolDefinition: Codable {
    let name: String
    let description: String?
    let inputSchema: MCPJSONValue
}

// MARK: - MCPToolsListResult

/// Response payload for `tools/list`.
struct MCPToolsListResult: Codable {
    let tools: [MCPToolDefinition]
}

// MARK: - MCPToolCallParams

/// Parameters for `tools/call`.
struct MCPToolCallParams: Codable {
    let name: String
    let arguments: [String: MCPJSONValue]?
}

// MARK: - MCPContent

/// A content block within a tool call result. Phase 1 only supports text.
struct MCPContent: Codable {
    // MARK: Lifecycle

    private init(type: String, text: String?) {
        self.type = type
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "text" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported MCP content type: \(type)"
            )
        }
        self.type = "text"
        text = try container.decodeIfPresent(String.self, forKey: .text)
    }

    // MARK: Internal

    let type: String
    let text: String?

    static func text(_ value: String) -> MCPContent {
        MCPContent(type: "text", text: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        assert(type == "text")
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}

// MARK: - MCPToolCallResult

/// Response payload for `tools/call`.
struct MCPToolCallResult: Codable {
    let content: [MCPContent]
    let isError: Bool?
}
