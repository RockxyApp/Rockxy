import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ProtocolFilter` in the models ui layer.

// MARK: - ProtocolFilterTests

struct ProtocolFilterTests {
    // MARK: - Protocol Matching

    @Test("HTTP filter matches http scheme")
    func httpMatches() {
        let transaction = TestFixtures.makeTransaction(url: "http://example.com/test")
        #expect(ProtocolFilter.http.matches(transaction))
        #expect(!ProtocolFilter.https.matches(transaction))
    }

    @Test("HTTPS filter matches https scheme")
    func httpsMatches() {
        let transaction = TestFixtures.makeTransaction(url: "https://example.com/test")
        #expect(ProtocolFilter.https.matches(transaction))
        #expect(!ProtocolFilter.http.matches(transaction))
    }

    @Test("WebSocket filter matches transaction with WebSocket connection")
    func websocketMatches() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        #expect(ProtocolFilter.websocket.matches(transaction))
    }

    @Test("AI filter matches likely AI traffic")
    func aiMatches() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.openai.com/v1/responses"
        )
        #expect(ProtocolFilter.ai.matches(transaction))
        #expect(!ProtocolFilter.ai.matches(TestFixtures.makeTransaction()))
    }

    @Test("AI Session filter matches known app session hosts")
    func aiSessionMatches() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://chatgpt.com/",
            statusCode: nil
        )

        #expect(ProtocolFilter.aiSession.matches(transaction))
        #expect(!ProtocolFilter.ai.matches(transaction))
        #expect(!ProtocolFilter.aiSession.matches(TestFixtures.makeTransaction()))
    }

    @Test("Web3 RPC filter matches transaction with Web3 metadata")
    func web3RPCMatches() {
        let transaction = TestFixtures.makeWeb3RPCTransaction()
        #expect(ProtocolFilter.web3RPC.matches(transaction))
        #expect(!ProtocolFilter.graphql.matches(transaction))
    }

    @Test("RPC error filter matches Web3 transactions with provider errors")
    func rpcErrorMatches() {
        let transaction = TestFixtures.makeWeb3RPCTransaction(
            error: Web3RPCError(code: -32_000, message: "rate limited")
        )
        #expect(ProtocolFilter.rpcError.matches(transaction))
        #expect(!ProtocolFilter.rpcError.matches(TestFixtures.makeWeb3RPCTransaction()))
    }

    @Test("gRPC filter matches transaction with gRPC metadata")
    func grpcMatches() {
        let transaction = TestFixtures.makeGRPCTransaction()
        #expect(ProtocolFilter.grpc.matches(transaction))
        #expect(!ProtocolFilter.other.matches(transaction))
    }

    // MARK: - Content Type Matching

    @Test("JSON filter matches JSON content type")
    func jsonMatches() {
        let transaction = TestFixtures.makeTransactionWithBody(
            statusCode: 200,
            responseJSON: ["key": "value"]
        )
        #expect(ProtocolFilter.json.matches(transaction))
    }

    @Test("Document filter matches HTML content type")
    func documentMatches() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "text/html")]
        )
        transaction.response?.contentType = .html
        #expect(ProtocolFilter.document.matches(transaction))
    }

    @Test("Media filter matches image content type")
    func mediaMatches() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "image/png")]
        )
        transaction.response?.contentType = .image
        #expect(ProtocolFilter.media.matches(transaction))
    }

    // MARK: - Form Filter

    @Test("Form filter matches form content types")
    func formMatches() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://example.com/submit"
        )
        transaction.request.contentType = .form
        #expect(ProtocolFilter.form.matches(transaction))
    }

    @Test("Form filter matches multipart form")
    func formMatchesMultipart() {
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://example.com/upload"
        )
        transaction.request.contentType = .multipartForm
        #expect(ProtocolFilter.form.matches(transaction))
    }

    // MARK: - Font Filter

    @Test("Font filter matches font content types")
    func fontMatches() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "font/woff2")]
        )
        #expect(ProtocolFilter.font.matches(transaction))
    }

    @Test("Font filter matches legacy font MIME types")
    func fontMatchesLegacy() {
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "application/x-font-ttf")]
        )
        #expect(ProtocolFilter.font.matches(transaction))
    }

    // MARK: - Other Filter

    @Test("Other filter excludes known content types")
    func otherExcludesKnown() {
        let jsonTransaction = TestFixtures.makeTransactionWithBody(
            statusCode: 200,
            responseJSON: ["key": "value"]
        )
        #expect(!ProtocolFilter.other.matches(jsonTransaction))
    }

    // MARK: - Status Filters

    @Test("Status filters match correct ranges")
    func statusRanges() {
        let ok = TestFixtures.makeTransaction(statusCode: 200)
        let redirect = TestFixtures.makeTransaction(statusCode: 301)
        let clientError = TestFixtures.makeTransaction(statusCode: 404)
        let serverError = TestFixtures.makeErrorTransaction(statusCode: 500)

        #expect(ProtocolFilter.status2xx.matches(ok))
        #expect(!ProtocolFilter.status3xx.matches(ok))
        #expect(ProtocolFilter.status3xx.matches(redirect))
        #expect(ProtocolFilter.status4xx.matches(clientError))
        #expect(ProtocolFilter.status5xx.matches(serverError))
    }

    @Test("Status filter rejects transaction without response")
    func statusRejectsNoResponse() {
        let transaction = TestFixtures.makeTransaction(statusCode: nil, state: .pending)
        #expect(!ProtocolFilter.status2xx.matches(transaction))
    }

    // MARK: - All Filter

    @Test("All filter matches everything")
    func allMatchesEverything() {
        let transaction = TestFixtures.makeTransaction()
        #expect(ProtocolFilter.all.matches(transaction))
    }
}
