import Foundation
import NIOCore
import NIOHTTP1
import os

/// Logger must be nonisolated(unsafe) because NIO channel handlers are called
/// from event loop threads outside Swift's structured concurrency.
nonisolated(unsafe) private let mcpHandlerLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "MCPServerHandler"
)

// MARK: - MCPServerHandler

/// NIO channel handler that implements the MCP Streamable HTTP transport.
/// Processes complete HTTP requests and dispatches JSON-RPC methods to the
/// appropriate MCP protocol handler (initialize, tools/list, tools/call, etc.).
///
/// Marked `@unchecked Sendable` because NIO channel handlers are confined to a
/// single event loop thread; concurrent access does not occur in practice.
final class MCPServerHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        configuration: MCPServerConfiguration,
        sessionManager: MCPSessionManager,
        toolRegistry: MCPToolRegistry,
        storedToken: String
    ) {
        self.configuration = configuration
        self.sessionManager = sessionManager
        self.toolRegistry = toolRegistry
        self.storedToken = storedToken
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case let .head(head):
            requestMethod = head.method
            requestURI = head.uri
            requestHeaders = head.headers
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)
            accumulatedBodySize = 0
            requestAlreadyCompleted = false

        case let .body(buffer):
            guard !requestAlreadyCompleted else {
                return
            }
            accumulatedBodySize += buffer.readableBytes
            guard accumulatedBodySize <= MCPLimits.maxRequestBodySize else {
                mcpHandlerLogger.warning(
                    "SECURITY: MCP request body exceeds \(MCPLimits.maxRequestBodySize) bytes, rejecting"
                )
                requestAlreadyCompleted = true
                sendResponse(
                    context: context,
                    status: .payloadTooLarge,
                    body: errorBodyData(message: "Request body too large")
                )
                return
            }
            bodyBuffer?.writeImmutableBuffer(buffer)

        case .end:
            guard !requestAlreadyCompleted else {
                resetRequestState()
                return
            }
            requestAlreadyCompleted = true
            processCompleteRequest(context: context)
            resetRequestState()
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    // MARK: Private

    private let configuration: MCPServerConfiguration
    private let sessionManager: MCPSessionManager
    private let toolRegistry: MCPToolRegistry
    private let storedToken: String

    private var activeSessionID: String?
    private var requestMethod: HTTPMethod?
    private var requestURI: String?
    private var requestHeaders: HTTPHeaders?
    private var bodyBuffer: ByteBuffer?
    private var accumulatedBodySize = 0
    private var requestAlreadyCompleted = false

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let jsonDecoder = JSONDecoder()
}

// MARK: - Request Processing

private extension MCPServerHandler {
    func processCompleteRequest(context: ChannelHandlerContext) {
        guard let method = requestMethod,
              let uri = requestURI,
              let headers = requestHeaders else
        {
            sendResponse(
                context: context,
                status: .badRequest,
                body: errorBodyData(message: "Incomplete request")
            )
            return
        }

        if let rejection = validateSecurity(headers: headers, method: method) {
            sendResponse(context: context, status: rejection.status, body: rejection.body)
            return
        }

        switch (method, uri) {
        case (.POST, "/mcp"):
            handlePostMCP(context: context, headers: headers)
        case (.GET, "/mcp"):
            sendResponse(
                context: context,
                status: .methodNotAllowed,
                body: errorBodyData(message: "SSE transport not supported; use Streamable HTTP (POST)")
            )
        case (.DELETE, "/mcp"):
            handleDeleteMCP(context: context, headers: headers)
        default:
            sendResponse(
                context: context,
                status: .notFound,
                body: errorBodyData(message: "Not found")
            )
        }
    }

    func resetRequestState() {
        requestMethod = nil
        requestURI = nil
        requestHeaders = nil
        bodyBuffer = nil
        accumulatedBodySize = 0
        requestAlreadyCompleted = false
    }
}

// MARK: - Security Validation

private extension MCPServerHandler {
    struct SecurityRejection {
        let status: HTTPResponseStatus
        let body: Data
    }

    func validateSecurity(
        headers: HTTPHeaders,
        method: HTTPMethod
    )
        -> SecurityRejection?
    {
        // The stdio bridge does not send `Origin`, so absence is intentionally
        // permitted here. We only validate `extractHost(from:)` against
        // `configuration.allowedOrigins` when Origin is present to reduce DNS
        // rebinding risk for HTTP transports without breaking stdio clients.
        // Callers that want stricter behavior should layer it above this
        // `SecurityRejection` path.
        if let origin = headers.first(name: "Origin") {
            let originHost = extractHost(from: origin)
            if !configuration.allowedOrigins.contains(originHost) {
                mcpHandlerLogger.warning(
                    "SECURITY: Rejected request with disallowed Origin: \(origin, privacy: .public)"
                )
                return SecurityRejection(
                    status: .forbidden,
                    body: errorBodyData(message: "Origin not allowed")
                )
            }
        }

        guard let authHeader = headers.first(name: "Authorization") else {
            mcpHandlerLogger.warning("SECURITY: Missing Authorization header on MCP request")
            return SecurityRejection(
                status: .unauthorized,
                body: errorBodyData(message: "Missing Authorization header")
            )
        }

        let bearerPrefix = "Bearer "
        guard authHeader.hasPrefix(bearerPrefix) else {
            return SecurityRejection(
                status: .unauthorized,
                body: errorBodyData(message: "Invalid Authorization scheme; expected Bearer")
            )
        }

        let candidateToken = String(authHeader.dropFirst(bearerPrefix.count))
        guard MCPHandshakeStore.validateToken(candidateToken, against: storedToken) else {
            mcpHandlerLogger.warning("SECURITY: Invalid bearer token on MCP request")
            return SecurityRejection(
                status: .unauthorized,
                body: errorBodyData(message: "Invalid bearer token")
            )
        }

        return nil
    }

    func extractHost(from origin: String) -> String {
        guard let url = URL(string: origin), let host = url.host else {
            return origin
        }
        return host
    }
}

// MARK: - POST /mcp (JSON-RPC Dispatch)

private extension MCPServerHandler {
    func handlePostMCP(context: ChannelHandlerContext, headers: HTTPHeaders) {
        guard let body = bodyBuffer, body.readableBytes > 0 else {
            sendJsonRpcError(
                context: context,
                id: nil,
                code: .invalidRequest,
                message: "Empty request body"
            )
            return
        }

        let bodyData = Data(body.readableBytesView)

        let request: JsonRpcRequest
        do {
            request = try jsonDecoder.decode(JsonRpcRequest.self, from: bodyData)
        } catch {
            sendJsonRpcError(
                context: context,
                id: nil,
                code: .parseError,
                message: "Invalid JSON: \(error.localizedDescription)"
            )
            return
        }

        guard request.jsonrpc == "2.0" else {
            sendJsonRpcError(
                context: context,
                id: request.id,
                code: .invalidRequest,
                message: "Unsupported JSON-RPC version"
            )
            return
        }

        if request.method != "initialize" {
            if let sessionID = headers.first(name: "Mcp-Session-Id") {
                guard sessionManager.validateSession(sessionID) else {
                    sendResponse(
                        context: context,
                        status: .notFound,
                        body: errorBodyData(message: "Invalid or expired session")
                    )
                    return
                }
            } else {
                sendResponse(
                    context: context,
                    status: .badRequest,
                    body: errorBodyData(message: "Missing Mcp-Session-Id header")
                )
                return
            }
        }

        dispatchMethod(context: context, request: request)
    }

    func dispatchMethod(context: ChannelHandlerContext, request: JsonRpcRequest) {
        switch request.method {
        case "initialize":
            handleInitialize(context: context, request: request)
        case "notifications/initialized":
            sendResponse(context: context, status: .accepted, body: nil)
        case "tools/list":
            handleToolsList(context: context, request: request)
        case "tools/call":
            handleToolsCall(context: context, request: request)
        case "ping":
            handlePing(context: context, request: request)
        default:
            sendJsonRpcError(
                context: context,
                id: request.id,
                code: .methodNotFound,
                message: "Method not found: \(request.method)"
            )
        }
    }
}

// MARK: - Method Handlers

private extension MCPServerHandler {
    func handleInitialize(context: ChannelHandlerContext, request: JsonRpcRequest) {
        guard let params = request.params else {
            sendJsonRpcError(
                context: context,
                id: request.id,
                code: .invalidParams,
                message: "Missing initialize params"
            )
            return
        }

        let initParams: MCPInitializeParams
        do {
            let paramsData = try params.encodeToData()
            initParams = try jsonDecoder.decode(MCPInitializeParams.self, from: paramsData)
        } catch {
            sendJsonRpcError(
                context: context,
                id: request.id,
                code: .invalidParams,
                message: "Invalid initialize params: \(error.localizedDescription)"
            )
            return
        }

        guard let negotiatedVersion = MCPProtocolVersion.negotiate(clientVersion: initParams.protocolVersion) else {
            sendJsonRpcError(
                context: context,
                id: request.id,
                code: .invalidParams,
                message: "Unsupported MCP protocol version: \(initParams.protocolVersion). Compatible range: \(MCPProtocolVersion.compatibilityFloor) ... \(MCPProtocolVersion.current)"
            )
            return
        }

        if let existingSessionID = requestHeaders?.first(name: "Mcp-Session-Id") {
            sessionManager.removeSession(existingSessionID)
            if activeSessionID == existingSessionID {
                activeSessionID = nil
            }
        }
        if let activeSessionID {
            sessionManager.removeSession(activeSessionID)
            self.activeSessionID = nil
        }

        guard let sessionID = sessionManager.createSession() else {
            sendJsonRpcError(
                context: context,
                id: request.id,
                code: .internalError,
                message: "Session limit reached"
            )
            return
        }
        activeSessionID = sessionID

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let result = MCPInitializeResult(
            protocolVersion: negotiatedVersion,
            capabilities: MCPServerCapabilities(
                tools: MCPToolsCapability(listChanged: false)
            ),
            serverInfo: MCPServerInfo(name: "Rockxy", version: appVersion),
            instructions: "Rockxy MCP server — debug HTTP/HTTPS traffic, inspect requests/responses, and manage proxy rules."
        )

        mcpHandlerLogger.info(
            "MCP initialized for client \(initParams.clientInfo.name, privacy: .public) v\(initParams.clientInfo.version, privacy: .public), session \(sessionID, privacy: .public)"
        )

        sendJsonRpcResult(
            context: context,
            id: request.id,
            result: result,
            extraHeaders: [("Mcp-Session-Id", sessionID)]
        )
    }

    func handleToolsList(context: ChannelHandlerContext, request: JsonRpcRequest) {
        let result = toolRegistry.listTools()
        sendJsonRpcResult(context: context, id: request.id, result: result)
    }

    func handleToolsCall(context: ChannelHandlerContext, request: JsonRpcRequest) {
        guard let params = request.params else {
            sendJsonRpcError(
                context: context,
                id: request.id,
                code: .invalidParams,
                message: "Missing tool call params"
            )
            return
        }

        let callParams: MCPToolCallParams
        do {
            let paramsData = try params.encodeToData()
            callParams = try jsonDecoder.decode(MCPToolCallParams.self, from: paramsData)
        } catch {
            sendJsonRpcError(
                context: context,
                id: request.id,
                code: .invalidParams,
                message: "Invalid tool call params: \(error.localizedDescription)"
            )
            return
        }

        let requestID = request.id
        context.eventLoop.makeFutureWithTask { [toolRegistry] in
            await toolRegistry.callTool(params: callParams)
        }.whenComplete { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .success(toolResult):
                sendJsonRpcResult(context: context, id: requestID, result: toolResult)
            case let .failure(error):
                sendJsonRpcError(
                    context: context,
                    id: requestID,
                    code: .internalError,
                    message: "Tool execution failed: \(error.localizedDescription)"
                )
            }
        }
    }

    func handlePing(context: ChannelHandlerContext, request: JsonRpcRequest) {
        sendJsonRpcResult(context: context, id: request.id, result: EmptyResult())
    }
}

// MARK: - DELETE /mcp (Session Teardown)

private extension MCPServerHandler {
    func handleDeleteMCP(context: ChannelHandlerContext, headers: HTTPHeaders) {
        guard let sessionID = headers.first(name: "Mcp-Session-Id") else {
            sendResponse(
                context: context,
                status: .badRequest,
                body: errorBodyData(message: "Missing Mcp-Session-Id header")
            )
            return
        }

        sessionManager.removeSession(sessionID)
        if activeSessionID == sessionID {
            activeSessionID = nil
        }
        mcpHandlerLogger.info("MCP session teardown: \(sessionID, privacy: .public)")
        sendResponse(context: context, status: .ok, body: nil)
    }
}

// MARK: - Response Helpers

private extension MCPServerHandler {
    func sendJsonRpcResult(
        context: ChannelHandlerContext,
        id: JsonRpcId?,
        result: some Encodable,
        extraHeaders: [(String, String)] = []
    ) {
        do {
            let resultData = try jsonEncoder.encode(result)
            let resultValue = try jsonDecoder.decode(MCPJSONValue.self, from: resultData)
            let response = JsonRpcResponse(id: id, result: resultValue)
            let responseData = try jsonEncoder.encode(response)
            sendResponse(
                context: context,
                status: .ok,
                body: responseData,
                extraHeaders: extraHeaders
            )
        } catch {
            mcpHandlerLogger.error("Failed to encode JSON-RPC result: \(error.localizedDescription)")
            sendJsonRpcError(
                context: context,
                id: id,
                code: .internalError,
                message: "Internal encoding error"
            )
        }
    }

    func sendJsonRpcError(
        context: ChannelHandlerContext,
        id: JsonRpcId?,
        code: JsonRpcErrorCode,
        message: String
    ) {
        let response = JsonRpcResponse(
            id: id,
            error: JsonRpcError(code: code, message: message)
        )
        do {
            let responseData = try jsonEncoder.encode(response)
            sendResponse(context: context, status: .ok, body: responseData)
        } catch {
            mcpHandlerLogger.error("Failed to encode JSON-RPC error: \(error.localizedDescription)")
            sendResponse(
                context: context,
                status: .internalServerError,
                body: errorBodyData(message: "Internal server error")
            )
        }
    }

    func sendResponse(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        body: Data?,
        extraHeaders: [(String, String)] = []
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")

        let bodyLength = body?.count ?? 0
        headers.add(name: "Content-Length", value: "\(bodyLength)")

        for (name, value) in extraHeaders {
            headers.add(name: name, value: value)
        }

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        if let body, !body.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func errorBodyData(message: String) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: ["error": message], options: [])
        } catch {
            mcpHandlerLogger.warning("Failed to encode MCP HTTP error body: \(error.localizedDescription)")
            return Data("{\"error\":\"Internal server error\"}".utf8)
        }
    }
}

// MARK: - EmptyResult

/// Empty JSON-RPC result for methods like `ping` that return `{}`.
private struct EmptyResult: Encodable {}
