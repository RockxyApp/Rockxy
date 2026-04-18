import Foundation
@testable import Rockxy
import Testing

// MARK: - MCPProtocolMessagesTests

@Suite("MCP Protocol Messages")
struct MCPProtocolMessagesTests {
    @Test("Protocol version is 2025-11-25")
    func protocolVersion() {
        #expect(MCPProtocolVersion.current == "2025-11-25")
    }

    @Test("Protocol negotiation accepts compatible older client versions")
    func protocolNegotiation() {
        #expect(MCPProtocolVersion.negotiate(clientVersion: "2025-03-26") == MCPProtocolVersion.current)
        #expect(MCPProtocolVersion.negotiate(clientVersion: "2024-01-01") == nil)
    }

    @Test("Protocol negotiation rejects impossible calendar dates")
    func protocolNegotiationRejectsImpossibleDate() {
        #expect(MCPProtocolVersion.negotiate(clientVersion: "2025-99-99") == nil)
        #expect(MCPProtocolVersion.negotiate(clientVersion: "2025-02-30") == nil)
    }

    @Test("MCPInitializeParams round-trip")
    func initializeParams() throws {
        let params = MCPInitializeParams(
            protocolVersion: MCPProtocolVersion.current,
            capabilities: MCPClientCapabilities(),
            clientInfo: MCPClientInfo(name: "test-client", version: "1.0.0")
        )

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(MCPInitializeParams.self, from: data)

        #expect(decoded.protocolVersion == MCPProtocolVersion.current)
        #expect(decoded.clientInfo.name == "test-client")
        #expect(decoded.clientInfo.version == "1.0.0")
    }

    @Test("MCPInitializeResult round-trip")
    func initializeResult() throws {
        let result = MCPInitializeResult(
            protocolVersion: MCPProtocolVersion.current,
            capabilities: MCPServerCapabilities(
                tools: MCPToolsCapability(listChanged: true)
            ),
            serverInfo: MCPServerInfo(name: "Rockxy", version: "0.8.0"),
            instructions: "Debug proxy MCP server"
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(MCPInitializeResult.self, from: data)

        #expect(decoded.protocolVersion == MCPProtocolVersion.current)
        #expect(decoded.capabilities.tools?.listChanged == true)
        #expect(decoded.serverInfo.name == "Rockxy")
        #expect(decoded.serverInfo.version == "0.8.0")
        #expect(decoded.instructions == "Debug proxy MCP server")
    }

    @Test("MCPToolDefinition with schema")
    func toolDefinition() throws {
        let schema: MCPJSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "url": .object([
                    "type": .string("string"),
                    "description": .string("URL pattern to match"),
                ]),
            ]),
            "required": .array([.string("url")]),
        ])
        let tool = MCPToolDefinition(
            name: "get_flows",
            description: "Retrieve captured HTTP flows",
            inputSchema: schema
        )

        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(MCPToolDefinition.self, from: data)

        #expect(decoded.name == "get_flows")
        #expect(decoded.description == "Retrieve captured HTTP flows")
        #expect(decoded.inputSchema == schema)
    }

    @Test("MCPToolCallParams with arguments")
    func toolCallParams() throws {
        let params = MCPToolCallParams(
            name: "get_flows",
            arguments: [
                "url": .string("*.example.com"),
                "limit": .int(10),
            ]
        )

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(MCPToolCallParams.self, from: data)

        #expect(decoded.name == "get_flows")
        #expect(decoded.arguments?["url"] == .string("*.example.com"))
        #expect(decoded.arguments?["limit"] == .int(10))
    }

    @Test("MCPToolCallParams with nil arguments")
    func toolCallParamsNilArguments() throws {
        let params = MCPToolCallParams(name: "get_proxy_status", arguments: nil)

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(MCPToolCallParams.self, from: data)

        #expect(decoded.name == "get_proxy_status")
        #expect(decoded.arguments == nil)
    }

    @Test("MCPToolCallResult with text content")
    func toolCallResult() throws {
        let result = MCPToolCallResult(
            content: [
                MCPContent.text("Found 3 matching flows"),
                MCPContent.text("{\"flows\": []}"),
            ],
            isError: false
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(MCPToolCallResult.self, from: data)

        #expect(decoded.content.count == 2)
        #expect(decoded.content[0].type == "text")
        #expect(decoded.content[0].text == "Found 3 matching flows")
        #expect(decoded.content[1].text == "{\"flows\": []}")
        #expect(decoded.isError == false)
    }

    @Test("MCPContent text factory")
    func contentTextFactory() {
        let content = MCPContent.text("hello")
        #expect(content.type == "text")
        #expect(content.text == "hello")
    }

    @Test("MCPContent rejects unsupported content types")
    func contentRejectsUnsupportedType() throws {
        let data = Data(#"{"type":"image","text":"nope"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(MCPContent.self, from: data)
        }
    }

    @Test("MCPToolCallResult error flag")
    func toolCallResultError() throws {
        let result = MCPToolCallResult(
            content: [MCPContent.text("Tool execution failed")],
            isError: true
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(MCPToolCallResult.self, from: data)

        #expect(decoded.isError == true)
        #expect(decoded.content.count == 1)
    }
}
