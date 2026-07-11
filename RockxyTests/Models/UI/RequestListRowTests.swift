import Foundation
@testable import Rockxy
import Testing

@MainActor
struct RequestListRowTests {
    // MARK: Internal

    // MARK: - Basic Extraction

    @Test("Extracts all fields from completed HTTP transaction")
    func extractsAllFields() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/users/1",
            statusCode: 201
        )
        transaction.sequenceNumber = 42
        transaction.clientApp = "Safari"
        transaction.sourcePort = 54_321
        transaction.isPinned = true
        transaction.isSaved = false
        transaction.comment = "Test comment"
        transaction.highlightColor = .blue

        let row = RequestListRow(from: transaction)

        #expect(row.id == transaction.id)
        #expect(row.timestamp == transaction.timestamp)
        #expect(row.method == "POST")
        #expect(row.scheme == "https")
        #expect(row.host == "api.example.com")
        #expect(row.path == "/users/1")
        #expect(row.statusCode == 201)
        #expect(row.state == .completed)
        #expect(row.clientApp == "Safari")
        #expect(row.sourcePort == 54_321)
        #expect(row.isPinned == true)
        #expect(row.isSaved == false)
        #expect(row.comment == "Test comment")
        #expect(row.highlightColor == .blue)
        #expect(row.sequenceNumber == 42)
        #expect(row.isTLSFailure == false)
    }

    @Test("Nil response produces nil status and response fields")
    func nilResponse() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil)
        let row = RequestListRow(from: transaction)

        #expect(row.statusCode == nil)
        #expect(row.statusMessage == nil)
        #expect(row.responseSize == nil)
        #expect(row.responseContentType == nil)
        #expect(row.responseHeaders == nil)
    }

    @Test("Extracts GraphQL fields correctly")
    func graphQLFields() {
        let transaction = TestFixtures.makeGraphQLTransaction(
            operationName: "GetUsers",
            operationType: .query
        )
        let row = RequestListRow(from: transaction)

        #expect(row.graphQLOpName == "GetUsers")
        #expect(row.graphQLOpType == "query")
        #expect(row.isWebSocket == false)
        #expect(row.webSocketFrameCount == 0)
    }

    @Test("Extracts Web3 RPC fields correctly")
    func web3RPCFields() {
        let transaction = TestFixtures.makeWeb3RPCTransaction(
            method: nil,
            batch: Web3RPCBatchSummary(
                requestCount: 2,
                web3RequestCount: 2,
                responseCount: 2,
                errorCount: 1,
                methods: ["eth_chainId", "eth_blockNumber"]
            ),
            error: Web3RPCError(code: -32_000, message: "rate limited")
        )

        let row = RequestListRow(from: transaction)

        #expect(row.isWeb3RPC == true)
        #expect(row.web3RPCMethod == "eth_chainId + 1")
        #expect(row.web3RPCProviderHost == "rpc.example.com")
        #expect(row.web3RPCErrorCode == -32_000)
    }

    @Test("Extracts WebSocket fields correctly")
    func webSocketFields() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        let row = RequestListRow(from: transaction)

        #expect(row.isWebSocket == true)
        #expect(row.webSocketFrameCount == 5)
        #expect(row.graphQLOpName == nil)
    }

    @Test("Extracts headers for custom column resolution")
    func headersExtracted() {
        let transaction = TestFixtures.makeTransaction()
        let row = RequestListRow(from: transaction)

        #expect(!row.requestHeaders.isEmpty)
        #expect(row.requestHeaders.contains { $0.name == "Content-Type" })
        #expect(row.responseHeaders != nil)
        #expect(row.responseHeaders?.contains { $0.name == "Content-Type" } == true)
    }

    @Test("TLS failure field extracted")
    func tlsFailure() {
        let transaction = TestFixtures.makeTransaction()
        transaction.isTLSFailure = true
        let row = RequestListRow(from: transaction)

        #expect(row.isTLSFailure == true)
    }

    @Test("AI traffic signal is extracted from model-provider requests")
    func aiTrafficSignal() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.openai.com/v1/responses",
            statusCode: 200
        )

        let row = RequestListRow(from: transaction)

        #expect(row.aiTrafficSignal.isLikelyAI)
        #expect(row.aiTrafficSignal.provider == .openAICompatible)
        #expect(row.aiTrafficSignal.kind == .api)
        #expect(row.aiTrafficSignal.tableLabel == "AI API")
        #expect(row.smartBadgeText == "AI API")
        #expect(row.smartBadgeTooltip?.contains("OpenAI-compatible") == true)
    }

    @Test("AI session signal is extracted from known native app hosts")
    func aiSessionTrafficSignal() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://chatgpt.com/",
            statusCode: nil
        )
        transaction.clientApp = "ChatGPT"

        let row = RequestListRow(from: transaction)

        #expect(row.aiTrafficSignal.isLikelyAI)
        #expect(row.aiTrafficSignal.provider == .chatGPT)
        #expect(row.aiTrafficSignal.kind == .session)
        #expect(row.smartBadgeText == "AI Session")
        #expect(row.smartBadgeTooltip?.contains("body hidden") == true)
    }

    @Test("Smart badge text summarizes Web3 RPC metadata")
    func web3SmartBadgeText() {
        let normal = RequestListRow(from: TestFixtures.makeWeb3RPCTransaction())
        let error = RequestListRow(from: TestFixtures.makeWeb3RPCTransaction(
            error: Web3RPCError(code: -32_000, message: "rate limited")
        ))

        #expect(normal.smartBadgeText == "Web3")
        #expect(normal.smartBadgeTooltip?.contains("rpc.example.com") == true)
        #expect(error.smartBadgeText == "RPC ERR")
        #expect(error.smartBadgeTooltip?.contains("-32000") == true)
    }

    @Test("Protocol column labels ordinary and structured traffic")
    func protocolColumnFallbackLabels() {
        let http = RequestListRow(from: TestFixtures.makeTransaction(url: "http://example.com/test"))
        let https = RequestListRow(from: TestFixtures.makeTransaction(url: "https://example.com/test"))
        let webSocket = RequestListRow(from: TestFixtures.makeWebSocketTransaction())
        let graphQL = RequestListRow(from: TestFixtures.makeGraphQLTransaction())
        let grpc = RequestListRow(from: TestFixtures.makeGRPCTransaction())

        #expect(http.smartBadgeText == "HTTP")
        #expect(https.smartBadgeText == "HTTPS")
        #expect(webSocket.smartBadgeText == "WS")
        #expect(graphQL.smartBadgeText == "GraphQL")
        #expect(grpc.smartBadgeText == "gRPC")
    }

    @Test("Body sizes extracted from request and response")
    func bodySizes() {
        let transaction = TestFixtures.makeTransactionWithBody(
            responseJSON: ["key": "value"]
        )
        let row = RequestListRow(from: transaction)

        #expect(row.responseSize != nil)
        #expect(row.responseSize ?? 0 > 0)
    }

    // MARK: - Sorting

    @Test("Sort by URL ascending")
    func sortByURL() {
        let a = makeRow(host: "alpha.com", path: "/test")
        let b = makeRow(host: "beta.com", path: "/test")
        let descriptors = [NSSortDescriptor(key: "url", ascending: true)]

        #expect(RequestListRow.compare(a, b, using: descriptors) == true)
        #expect(RequestListRow.compare(b, a, using: descriptors) == false)
    }

    @Test("Sort by status code with nil sorting last")
    func sortByStatusCode() {
        let ok = makeRow(statusCode: 200)
        let error = makeRow(statusCode: 500)
        let pending = makeRow(statusCode: nil)
        let descriptors = [NSSortDescriptor(key: "code", ascending: true)]

        #expect(RequestListRow.compare(ok, error, using: descriptors) == true)
        #expect(RequestListRow.compare(ok, pending, using: descriptors) == true)
        #expect(RequestListRow.compare(pending, ok, using: descriptors) == false)
    }

    @Test("Sort by status text")
    func sortByStatusText() {
        let active = makeRow(state: .active)
        let completed = makeRow(state: .completed)
        let descriptors = [NSSortDescriptor(key: "state", ascending: true)]

        #expect(RequestListRow.compare(active, completed, using: descriptors) == true)
        #expect(RequestListRow.compare(completed, active, using: descriptors) == false)
    }

    @Test("Sort by sequence number (row column)")
    func sortBySequenceNumber() {
        let first = makeRow(sequenceNumber: 1)
        let second = makeRow(sequenceNumber: 2)
        let descriptors = [NSSortDescriptor(key: "row", ascending: true)]

        #expect(RequestListRow.compare(first, second, using: descriptors) == true)
        #expect(RequestListRow.compare(second, first, using: descriptors) == false)
    }

    @Test("Sort descending reverses order")
    func sortDescending() {
        let a = makeRow(host: "alpha.com", path: "/test")
        let b = makeRow(host: "beta.com", path: "/test")
        let descriptors = [NSSortDescriptor(key: "url", ascending: false)]

        #expect(RequestListRow.compare(a, b, using: descriptors) == false)
        #expect(RequestListRow.compare(b, a, using: descriptors) == true)
    }

    @Test("Unknown sort key preserves order")
    func unknownSortKey() {
        let a = makeRow(host: "alpha.com", path: "/test")
        let b = makeRow(host: "beta.com", path: "/test")
        let descriptors = [NSSortDescriptor(key: "nonexistent", ascending: true)]

        #expect(RequestListRow.compare(a, b, using: descriptors) == false)
        #expect(RequestListRow.compare(b, a, using: descriptors) == false)
    }

    @Test("Sort by request size uses request body bytes")
    func sortByRequestSize() {
        let small = makeRow(requestBodySize: 12)
        let large = makeRow(requestBodySize: 120)
        let descriptors = [NSSortDescriptor(key: "requestSize", ascending: true)]

        #expect(RequestListRow.compare(small, large, using: descriptors) == true)
        #expect(RequestListRow.compare(large, small, using: descriptors) == false)
    }

    @Test("Sort by response size uses response body bytes")
    func sortByResponseSize() {
        let small = makeRow(responseBodySize: 24)
        let large = makeRow(responseBodySize: 240)
        let descriptors = [NSSortDescriptor(key: "responseSize", ascending: true)]

        #expect(RequestListRow.compare(small, large, using: descriptors) == true)
        #expect(RequestListRow.compare(large, small, using: descriptors) == false)
    }

    @Test("Sort by ssl groups insecure before secure")
    func sortBySSL() {
        let http = makeRow(scheme: "http")
        let https = makeRow(scheme: "https")
        let descriptors = [NSSortDescriptor(key: "ssl", ascending: true)]

        #expect(RequestListRow.compare(http, https, using: descriptors) == true)
        #expect(RequestListRow.compare(https, http, using: descriptors) == false)
    }

    @Test("Sort by protocol label")
    func sortByAI() {
        let ai = makeRow(host: "api.openai.com", path: "/v1/responses")
        let ordinary = makeRow(host: "example.com")
        let descriptors = [NSSortDescriptor(key: "ai", ascending: true)]

        #expect(ai.smartBadgeText == "AI API")
        #expect(ordinary.smartBadgeText == "HTTPS")
        #expect(RequestListRow.compare(ai, ordinary, using: descriptors) == true)
        #expect(RequestListRow.compare(ordinary, ai, using: descriptors) == false)
    }

    @Test("SSL state can represent intercepted HTTPS separately from tunneled HTTPS")
    func interceptedSSLState() {
        let tunneled = makeRow(scheme: "https")
        let intercepted = makeRow(scheme: "https", sslState: .secureIntercepted)
        let descriptors = [NSSortDescriptor(key: "ssl", ascending: true)]

        #expect(RequestListRow.compare(tunneled, intercepted, using: descriptors) == true)
        #expect(intercepted.sslState == .secureIntercepted)
    }

    @Test("Request size includes start line and headers even without body")
    func requestSizeIncludesHeaders() {
        let row = makeRow(
            requestHeaders: [HTTPHeader(name: "Host", value: "example.com")]
        )

        #expect((row.requestSize ?? 0) > 0)
    }

    @Test("Duration falls back to measured runtime when timing breakdown is missing")
    func durationFallsBackToMeasuredRuntime() {
        let transaction = TestFixtures.makeTransaction()
        transaction.timingInfo = nil
        transaction.measuredDuration = 0.245

        let row = RequestListRow(from: transaction)

        #expect(row.totalDuration == 0.245)
    }

    @Test("CONNECT tunnel rows do not expose synthetic byte sizes")
    func connectTunnelHidesSyntheticByteSizes() {
        let transaction = TLSInterceptHandler.makeTunnelTransaction(
            host: "example.com",
            port: 443,
            statusCode: 200,
            statusMessage: "Connection Established",
            state: .completed,
            sourcePort: 54_321,
            measuredDuration: 0.120
        )

        let row = RequestListRow(from: transaction)

        #expect(row.isConnectTunnel == true)
        #expect(row.requestSize == nil)
        #expect(row.responseSize == nil)
        #expect(row.totalDuration == 0.120)
    }

    @Test("Custom header column sort resolved from row headers")
    func customHeaderSort() {
        let a = makeRow(requestHeaders: [HTTPHeader(name: "X-Request-ID", value: "aaa")])
        let b = makeRow(requestHeaders: [HTTPHeader(name: "X-Request-ID", value: "zzz")])
        let descriptors = [NSSortDescriptor(key: "reqHeader.X-Request-ID", ascending: true)]

        #expect(RequestListRow.compare(a, b, using: descriptors) == true)
    }

    // MARK: - Header Value Resolution

    @Test("Resolve request header value")
    func resolveRequestHeader() {
        let row = makeRow(requestHeaders: [HTTPHeader(name: "Authorization", value: "Bearer token")])
        let value = RequestListRow.resolveHeaderValue(for: "reqHeader.Authorization", row: row)
        #expect(value == "Bearer token")
    }

    @Test("Resolve response header value")
    func resolveResponseHeader() {
        let row = makeRow(responseHeaders: [HTTPHeader(name: "Cache-Control", value: "no-cache")])
        let value = RequestListRow.resolveHeaderValue(for: "resHeader.Cache-Control", row: row)
        #expect(value == "no-cache")
    }

    @Test("Missing header returns empty string")
    func missingHeader() {
        let row = makeRow()
        let value = RequestListRow.resolveHeaderValue(for: "reqHeader.X-Nonexistent", row: row)
        #expect(value == "")
    }

    // MARK: - WebSocket Numeric Sort

    @Test("WebSocket frame count sorts numerically not lexicographically")
    func webSocketNumericSort() {
        let ws2 = makeWebSocketRow(frameCount: 2)
        let ws10 = makeWebSocketRow(frameCount: 10)
        let descriptors = [NSSortDescriptor(key: "queryName", ascending: true)]

        // Numeric: 2 < 10 (lexicographic would put "10" before "2")
        #expect(RequestListRow.compare(ws2, ws10, using: descriptors) == true)
        #expect(RequestListRow.compare(ws10, ws2, using: descriptors) == false)
    }

    @Test("Web3 RPC method participates in operation sort")
    func web3RPCOperationSort() {
        let call = RequestListRow(from: TestFixtures.makeWeb3RPCTransaction(method: "eth_call"))
        let logs = RequestListRow(from: TestFixtures.makeWeb3RPCTransaction(method: "eth_getLogs"))
        let descriptors = [NSSortDescriptor(key: "queryName", ascending: true)]

        #expect(RequestListRow.compare(call, logs, using: descriptors) == true)
        #expect(RequestListRow.compare(logs, call, using: descriptors) == false)
    }

    // MARK: - Sequence Number Display

    @Test("sequenceNumber is correctly set from transaction")
    func sequenceNumberFromTransaction() {
        let transaction = TestFixtures.makeTransaction()
        transaction.sequenceNumber = 42
        let row = RequestListRow(from: transaction)
        #expect(row.sequenceNumber == 42)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeRow(
        host: String = "example.com",
        path: String = "/test",
        statusCode: Int? = 200,
        state: TransactionState = .completed,
        scheme: String = "https",
        sslState: RequestListRow.SSLState? = nil,
        sequenceNumber: Int = 0,
        requestBodySize: Int? = nil,
        responseBodySize: Int? = nil,
        requestHeaders: [HTTPHeader] = [],
        responseHeaders: [HTTPHeader]? = nil
    )
        -> RequestListRow
    {
        let url = "\(scheme)://\(host)\(path)"
        let transaction = TestFixtures.makeTransaction(
            url: url,
            statusCode: statusCode
        )
        transaction.state = state
        transaction.sequenceNumber = sequenceNumber
        if !requestHeaders.isEmpty {
            guard let requestURL = URL(string: url) else {
                Issue.record("Expected test URL to be valid: \(url)")
                return RequestListRow(from: transaction)
            }
            transaction.request = HTTPRequestData(
                method: "GET",
                url: requestURL,
                httpVersion: "HTTP/1.1",
                headers: requestHeaders,
                body: nil,
                contentType: nil
            )
        }
        if let requestBodySize {
            transaction.request = HTTPRequestData(
                method: transaction.request.method,
                url: transaction.request.url,
                httpVersion: transaction.request.httpVersion,
                headers: transaction.request.headers,
                body: Data(repeating: 0x61, count: requestBodySize),
                contentType: transaction.request.contentType
            )
        }
        if let resHeaders = responseHeaders, let response = transaction.response {
            transaction.response = HTTPResponseData(
                statusCode: response.statusCode,
                statusMessage: response.statusMessage,
                headers: resHeaders,
                body: response.body,
                contentType: response.contentType
            )
        }
        if let responseBodySize, let response = transaction.response {
            transaction.response = HTTPResponseData(
                statusCode: response.statusCode,
                statusMessage: response.statusMessage,
                headers: response.headers,
                body: Data(repeating: 0x62, count: responseBodySize),
                contentType: response.contentType
            )
        }
        return RequestListRow(from: transaction, sslState: sslState)
    }

    private func makeWebSocketRow(frameCount: Int) -> RequestListRow {
        let request = TestFixtures.makeRequest(url: "wss://ws.example.com/stream")
        let frames = (0 ..< frameCount).map { i in
            WebSocketFrameData(
                direction: i % 2 == 0 ? .sent : .received,
                opcode: .text,
                payload: Data("Frame \(i)".utf8)
            )
        }
        let connection = WebSocketConnection(upgradeRequest: request, frames: frames)
        let transaction = HTTPTransaction(
            request: request, state: .completed, webSocketConnection: connection
        )
        transaction.response = HTTPResponseData(
            statusCode: 101, statusMessage: "Switching Protocols",
            headers: [], body: nil, contentType: nil
        )
        return RequestListRow(from: transaction)
    }
}
