import Foundation
import NIOCore
import NIOEmbedded
import NIOHTTP1
@testable import Rockxy
import Testing

@Suite("MCP Server Handler Security")
struct MCPServerHandlerTests {
    // MARK: Internal

    @Test("MCPHandshakeStore constant-time validation accepts matching tokens")
    func tokenValidationMatch() {
        let token = "test-token-value-123"
        #expect(MCPHandshakeStore.validateToken(token, against: token))
    }

    @Test("MCPHandshakeStore constant-time validation rejects mismatched tokens")
    func tokenValidationMismatch() {
        #expect(!MCPHandshakeStore.validateToken("wrong", against: "correct"))
    }

    @Test("MCPHandshakeStore rejects tokens of different length")
    func tokenValidationLength() {
        #expect(!MCPHandshakeStore.validateToken("short", against: "much-longer-token"))
    }

    @Test("MCPHandshakeStore rejects validation when both tokens are empty")
    func tokenValidationBothEmpty() {
        #expect(!MCPHandshakeStore.validateToken("", against: ""))
    }

    @Test("MCPHandshakeStore rejects when candidate is empty but stored is not")
    func tokenValidationOneEmpty() {
        #expect(!MCPHandshakeStore.validateToken("", against: "non-empty"))
    }

    @Test("MCPServerConfiguration defaults to localhost")
    func configDefaultsLocalhost() {
        let config = MCPServerConfiguration.default
        #expect(config.listenAddress == "127.0.0.1")
        #expect(config.port == MCPLimits.defaultPort)
        #expect(config.allowedOrigins.contains("localhost"))
        #expect(config.allowedOrigins.contains("127.0.0.1"))
    }

    @Test("MCPServerConfiguration custom port")
    func configCustomPort() {
        let config = MCPServerConfiguration(port: 8_080)
        #expect(config.port == 8_080)
        #expect(config.listenAddress == "127.0.0.1")
    }

    @Test("MCPServerConfiguration custom allowed origins")
    func configCustomOrigins() {
        let origins: Set = ["localhost", "127.0.0.1", "custom.local"]
        let config = MCPServerConfiguration(allowedOrigins: origins)
        #expect(config.allowedOrigins.contains("custom.local"))
        #expect(config.allowedOrigins.count == 3)
    }

    @Test("MCPLimits has reasonable defaults")
    func limitsDefaults() {
        #expect(MCPLimits.maxRequestBodySize == 1_048_576)
        #expect(MCPLimits.maxResponsePayloadSize == 10_485_760)
        #expect(MCPLimits.maxFlowResults == 500)
        #expect(MCPLimits.defaultFlowResults == 50)
        #expect(MCPLimits.maxConcurrentSessions == 10)
        #expect(MCPLimits.sessionTimeout == 1_800)
        #expect(MCPLimits.defaultPort == 9_710)
    }

    @Test("MCPLimits connection idle timeout is 5 minutes")
    func limitsConnectionIdleTimeout() {
        #expect(MCPLimits.connectionIdleTimeout == 300)
    }

    @Test("MCPLimits body preview size matches request body size")
    func limitsBodyPreview() {
        #expect(MCPLimits.maxBodyPreviewSize == 1_048_576)
    }

    @Test("Origin validation - allowed origins include localhost and 127.0.0.1")
    func originValidation() {
        let config = MCPServerConfiguration.default
        #expect(config.allowedOrigins.contains("localhost"))
        #expect(config.allowedOrigins.contains("127.0.0.1"))
        #expect(!config.allowedOrigins.contains("evil.example.com"))
    }

    @Test("JSON-RPC error codes are standard")
    func standardErrorCodes() {
        #expect(JsonRpcErrorCode.parseError.rawValue == -32_700)
        #expect(JsonRpcErrorCode.invalidRequest.rawValue == -32_600)
        #expect(JsonRpcErrorCode.methodNotFound.rawValue == -32_601)
        #expect(JsonRpcErrorCode.invalidParams.rawValue == -32_602)
        #expect(JsonRpcErrorCode.internalError.rawValue == -32_603)
    }

    @Test("MCPServerError provides descriptive messages")
    func serverErrorDescriptions() throws {
        let portError = MCPServerError.portInUse(9_710)
        #expect(portError.errorDescription != nil)
        #expect(try #require(portError.errorDescription?.contains("9710")))

        let tokenError = MCPServerError.tokenGenerationFailed
        #expect(tokenError.errorDescription != nil)
    }

    @Test("MCPServerError port in use includes port number")
    func serverErrorPortInUse() throws {
        let error = MCPServerError.portInUse(8_080)
        #expect(try #require(error.errorDescription?.contains("8080")))
    }

    @Test("MCPProtocolVersion current is set")
    func protocolVersion() {
        #expect(!MCPProtocolVersion.current.isEmpty)
    }

    @Test("MCPSessionManager starts with zero sessions")
    func sessionManagerInitialState() {
        let manager = MCPSessionManager()
        #expect(manager.activeSessions == 0)
    }

    @Test("MCPSessionManager creates sessions with unique IDs")
    func sessionManagerCreateUnique() {
        let manager = MCPSessionManager()
        let id1 = manager.createSession()
        let id2 = manager.createSession()
        #expect(id1 != nil)
        #expect(id2 != nil)
        #expect(id1 != id2)
        #expect(manager.activeSessions == 2)
    }

    @Test("MCPSessionManager validates existing sessions")
    func sessionManagerValidate() throws {
        let manager = MCPSessionManager()
        let id = try #require(manager.createSession())
        #expect(manager.validateSession(id))
        #expect(!manager.validateSession("nonexistent-session-id"))
    }

    @Test("MCPSessionManager removes sessions")
    func sessionManagerRemove() throws {
        let manager = MCPSessionManager()
        let id = try #require(manager.createSession())
        #expect(manager.activeSessions == 1)
        manager.removeSession(id)
        #expect(manager.activeSessions == 0)
        #expect(!manager.validateSession(id))
    }

    @Test("MCPSessionManager enforces concurrent session limit")
    func sessionManagerLimit() {
        let manager = MCPSessionManager()
        for _ in 0 ..< MCPLimits.maxConcurrentSessions {
            #expect(manager.createSession() != nil)
        }
        #expect(manager.activeSessions == MCPLimits.maxConcurrentSessions)
        #expect(manager.createSession() == nil)
    }

    @Test("MCPSessionManager remove nonexistent session is safe")
    func sessionManagerRemoveNonexistent() {
        let manager = MCPSessionManager()
        manager.removeSession("does-not-exist")
        #expect(manager.activeSessions == 0)
    }

    @Test("MCPSessionManager removeExpiredSessions cleans up")
    func sessionManagerEviction() throws {
        let manager = MCPSessionManager()
        let sessionID = try #require(manager.createSession())
        #expect(manager.activeSessions == 1)

        manager.setSessionTimestamp(
            Date().addingTimeInterval(-(MCPLimits.sessionTimeout + 5)),
            for: sessionID
        )
        manager.removeExpiredSessions()
        #expect(manager.activeSessions == 0)
    }

    @Test("JsonRpcRequest encodes with 2.0 version")
    func jsonRpcRequestVersion() throws {
        let request = JsonRpcRequest(
            id: .int(1),
            method: "test"
        )
        #expect(request.jsonrpc == "2.0")

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JsonRpcRequest.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.method == "test")
        #expect(decoded.id == .int(1))
    }

    @Test("JsonRpcRequest with string ID round-trips")
    func jsonRpcRequestStringId() throws {
        let request = JsonRpcRequest(
            id: .string("abc-123"),
            method: "tools/list"
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JsonRpcRequest.self, from: data)
        #expect(decoded.id == .string("abc-123"))
    }

    @Test("JsonRpcRequest notification has nil ID")
    func jsonRpcRequestNotification() {
        let notification = JsonRpcRequest(method: "notifications/initialized")
        #expect(notification.id == nil)
    }

    @Test("JsonRpcResponse success round-trips")
    func jsonRpcResponseSuccess() throws {
        let response = JsonRpcResponse(id: .int(1), result: .string("ok"))
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JsonRpcResponse.self, from: data)
        #expect(decoded.result == .string("ok"))
        #expect(decoded.error == nil)
    }

    @Test("JsonRpcResponse error round-trips")
    func jsonRpcResponseError() throws {
        let error = JsonRpcError(
            code: .methodNotFound,
            message: "Method not found"
        )
        let response = JsonRpcResponse(id: .int(1), error: error)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JsonRpcResponse.self, from: data)
        #expect(decoded.result == nil)
        #expect(decoded.error?.code == JsonRpcErrorCode.methodNotFound.rawValue)
        #expect(decoded.error?.message == "Method not found")
    }

    @Test("MCPJSONValue encodes and decodes all types")
    func jsonValueRoundTrip() throws {
        let values: [MCPJSONValue] = [
            .null,
            .bool(true),
            .int(42),
            .double(3.14),
            .string("hello"),
            .array([.int(1), .string("two")]),
            .object(["key": .bool(false)]),
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(MCPJSONValue.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("MCPJSONValue literal initialization")
    func jsonValueLiterals() {
        let null: MCPJSONValue = nil
        #expect(null == .null)

        let bool: MCPJSONValue = true
        #expect(bool == .bool(true))

        let int: MCPJSONValue = 42
        #expect(int == .int(42))

        let double: MCPJSONValue = 3.14
        #expect(double == .double(3.14))

        let string: MCPJSONValue = "hello"
        #expect(string == .string("hello"))

        let array: MCPJSONValue = [1, 2, 3]
        #expect(array == .array([.int(1), .int(2), .int(3)]))

        let object: MCPJSONValue = ["key": "value"]
        #expect(object == .object(["key": .string("value")]))
    }

    @Test("MCPJSONValue encodeToData produces valid JSON")
    func jsonValueEncodeToData() throws {
        let value: MCPJSONValue = .object(["name": .string("test")])
        let data = try value.encodeToData()
        #expect(!data.isEmpty)
        let decoded = try JSONDecoder().decode(MCPJSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("MCPRedactionPolicy redacts sensitive headers when enabled")
    func redactionPolicyHeaders() {
        let policy = MCPRedactionPolicy(isEnabled: true)
        let headers: [(name: String, value: String)] = [
            (name: "Authorization", value: "Bearer secret-token"),
            (name: "Content-Type", value: "application/json"),
            (name: "Cookie", value: "session=abc123"),
        ]
        let redacted = policy.redactHeaders(headers)
        #expect(redacted[0].value == "[REDACTED]")
        #expect(redacted[1].value == "application/json")
        #expect(redacted[2].value == "[REDACTED]")
    }

    @Test("MCPRedactionPolicy passes headers through when disabled")
    func redactionPolicyDisabled() {
        let policy = MCPRedactionPolicy(isEnabled: false)
        let headers: [(name: String, value: String)] = [
            (name: "Authorization", value: "Bearer secret-token"),
        ]
        let result = policy.redactHeaders(headers)
        #expect(result[0].value == "Bearer secret-token")
    }

    @Test("MCPRedactionPolicy redacts sensitive URL query params")
    func redactionPolicyURL() {
        let policy = MCPRedactionPolicy(isEnabled: true)
        let url = "https://api.example.com/data?api_key=secret123&page=1"
        let redacted = policy.redactURL(url)
        #expect(redacted.contains("%5BREDACTED%5D") || redacted.contains("[REDACTED]"))
        #expect(redacted.contains("page=1"))
        #expect(!redacted.contains("secret123"))
    }

    @Test("MCPRedactionPolicy redacts JSON body tokens")
    func redactionPolicyBody() {
        let policy = MCPRedactionPolicy(isEnabled: true)
        let body = """
        {"access_token": "FAKE.TOKEN.FORTEST", "username": "john"}
        """
        let redacted = policy.redactJSONBody(body)
        #expect(redacted.contains("[REDACTED]"))
        #expect(redacted.contains("john"))
    }

    @Test("MCPRedactionPolicy lists expected sensitive headers")
    func redactionPolicySensitiveHeaderList() {
        let expected = ["authorization", "cookie", "set-cookie", "x-api-key"]
        for header in expected {
            #expect(MCPRedactionPolicy.sensitiveHeaders.contains(header))
        }
    }

    @Test("MCPRedactionPolicy lists expected sensitive query params")
    func redactionPolicySensitiveQueryList() {
        let expected = ["api_key", "token", "password", "secret", "client_secret"]
        for param in expected {
            #expect(MCPRedactionPolicy.sensitiveQueryParams.contains(param))
        }
    }

    @Test("Direct handler rejects missing session header after initialize")
    @MainActor
    func directHandlerRejectsMissingSessionHeader() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let initialize = try performRequest(
            through: channel,
            method: .POST,
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Tests","version":"1.0"}}}
            """,
            includeAuthorization: true
        )

        #expect(initialize.status == .ok)
        #expect(initialize.headers.contains(name: "Mcp-Session-Id"))

        let tools = try performRequest(
            through: channel,
            method: .POST,
            body: """
            {"jsonrpc":"2.0","id":2,"method":"tools/list"}
            """,
            includeAuthorization: true
        )

        #expect(tools.status == .badRequest)
        #expect(tools.body.contains("Missing Mcp-Session-Id header"))
    }

    @Test("Direct handler rejects invalid session header after initialize")
    @MainActor
    func directHandlerRejectsInvalidSessionHeader() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let initialize = try performRequest(
            through: channel,
            method: .POST,
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Tests","version":"1.0"}}}
            """,
            includeAuthorization: true
        )

        #expect(initialize.status == .ok)

        let tools = try performRequest(
            through: channel,
            method: .POST,
            body: """
            {"jsonrpc":"2.0","id":2,"method":"tools/list"}
            """,
            sessionId: "expired-session",
            includeAuthorization: true
        )

        #expect(tools.status == .notFound)
        #expect(tools.body.contains("Invalid or expired session"))
    }

    @Test("Direct handler rejects unsupported initialize protocol version")
    @MainActor
    func directHandlerRejectsUnsupportedProtocolVersion() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let response = try performRequest(
            through: channel,
            method: .POST,
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-01-01","capabilities":{},"clientInfo":{"name":"Tests","version":"1.0"}}}
            """,
            includeAuthorization: true
        )

        #expect(response.status == .ok)
        #expect(response.body.contains("Unsupported MCP protocol version"))
    }

    @Test("Direct handler rejects disallowed origin")
    @MainActor
    func directHandlerRejectsOrigin() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let response = try performRequest(
            through: channel,
            method: .POST,
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Tests","version":"1.0"}}}
            """,
            origin: "https://evil.example.com",
            includeAuthorization: true
        )

        #expect(response.status == .forbidden)
        #expect(response.body.contains("Origin not allowed"))
    }

    @Test("Direct handler rejects GET transport")
    @MainActor
    func directHandlerRejectsGet() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let response = try performRequest(
            through: channel,
            method: .GET,
            body: nil,
            includeAuthorization: true
        )

        #expect(response.status == .methodNotAllowed)
        #expect(response.body.contains("SSE transport not supported"))
    }

    @Test("Direct handler tears down session on delete")
    @MainActor
    func directHandlerDeleteRemovesSession() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let initialize = try performRequest(
            through: channel,
            method: .POST,
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Tests","version":"1.0"}}}
            """,
            includeAuthorization: true
        )
        let sessionId = try #require(initialize.headers.first(name: "Mcp-Session-Id"))

        let deleteResponse = try performRequest(
            through: channel,
            method: .DELETE,
            body: nil,
            sessionId: sessionId,
            includeAuthorization: true
        )
        #expect(deleteResponse.status == .ok)

        let tools = try performRequest(
            through: channel,
            method: .POST,
            body: """
            {"jsonrpc":"2.0","id":2,"method":"tools/list"}
            """,
            sessionId: sessionId,
            includeAuthorization: true
        )
        #expect(tools.status == .notFound)
        #expect(tools.body.contains("Invalid or expired session"))
    }

    @Test("Direct handler rejects oversized fragmented request")
    @MainActor
    func directHandlerRejectsOversizedFragmentedBody() throws {
        let channel = try makeChannel()
        defer { _ = try? channel.finish() }

        let head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/mcp")
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Authorization", value: "Bearer test-token")

        var requestHead = head
        requestHead.headers = headers
        try channel.writeInbound(HTTPServerRequestPart.head(requestHead))

        let firstChunk = String(repeating: "a", count: MCPLimits.maxRequestBodySize / 2)
        let secondChunk = String(repeating: "b", count: (MCPLimits.maxRequestBodySize / 2) + 32)
        var firstBuffer = channel.allocator.buffer(capacity: firstChunk.count)
        firstBuffer.writeString(firstChunk)
        var secondBuffer = channel.allocator.buffer(capacity: secondChunk.count)
        secondBuffer.writeString(secondChunk)

        try channel.writeInbound(HTTPServerRequestPart.body(firstBuffer))
        try channel.writeInbound(HTTPServerRequestPart.body(secondBuffer))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let response = try readResponse(from: channel)
        #expect(response.status == .payloadTooLarge)
        #expect(response.body.contains("Request body too large"))
    }

    // MARK: Private

    @MainActor
    private func makeChannel() throws -> EmbeddedChannel {
        let coordinator = MCPServerCoordinator()
        let flowService = MCPFlowQueryService(
            serverCoordinator: coordinator,
            redactionPolicy: MCPRedactionPolicy(isEnabled: false)
        )
        let statusService = MCPStatusService(serverCoordinator: coordinator)
        let ruleService = MCPRuleQueryService(ruleEngine: RuleEngine())
        let registry = MCPToolRegistry(
            flowService: flowService,
            statusService: statusService,
            ruleService: ruleService
        )
        let handler = MCPServerHandler(
            configuration: .default,
            sessionManager: MCPSessionManager(),
            toolRegistry: registry,
            storedToken: "test-token"
        )
        return EmbeddedChannel(handler: handler)
    }

    private func performRequest(
        through channel: EmbeddedChannel,
        method: HTTPMethod,
        body: String?,
        origin: String? = nil,
        sessionId: String? = nil,
        includeAuthorization: Bool = false
    )
        throws -> (status: HTTPResponseStatus, headers: HTTPHeaders, body: String)
    {
        var headers = HTTPHeaders()
        if let body {
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        } else {
            headers.add(name: "Content-Length", value: "0")
        }
        if includeAuthorization {
            headers.add(name: "Authorization", value: "Bearer test-token")
        }
        if let origin {
            headers.add(name: "Origin", value: origin)
        }
        if let sessionId {
            headers.add(name: "Mcp-Session-Id", value: sessionId)
        }

        let head = HTTPRequestHead(
            version: .http1_1,
            method: method,
            uri: "/mcp",
            headers: headers
        )
        try channel.writeInbound(HTTPServerRequestPart.head(head))

        if let body {
            var buffer = channel.allocator.buffer(capacity: body.utf8.count)
            buffer.writeString(body)
            try channel.writeInbound(HTTPServerRequestPart.body(buffer))
        }

        try channel.writeInbound(HTTPServerRequestPart.end(nil))
        return try readResponse(from: channel)
    }

    private func readResponse(from channel: EmbeddedChannel) throws
        -> (status: HTTPResponseStatus, headers: HTTPHeaders, body: String)
    {
        let headPart = try #require(try channel.readOutbound(as: HTTPServerResponsePart.self))
        guard case let .head(head) = headPart else {
            Issue.record("Expected HTTP response head")
            throw CocoaError(.coderInvalidValue)
        }

        var bodyText = ""
        while let part = try channel.readOutbound(as: HTTPServerResponsePart.self) {
            switch part {
            case let .body(bodyPart):
                switch bodyPart {
                case let .byteBuffer(buffer):
                    bodyText += String(bytes: buffer.readableBytesView, encoding: .utf8) ?? ""
                case .fileRegion:
                    Issue.record("Unexpected file region in HTTP response body")
                    throw CocoaError(.coderInvalidValue)
                }
            case .end:
                return (head.status, head.headers, bodyText)
            case .head:
                Issue.record("Unexpected extra response head")
                throw CocoaError(.coderInvalidValue)
            }
        }

        Issue.record("Expected response end")
        throw CocoaError(.coderInvalidValue)
    }
}
