import Foundation
@testable import Rockxy
import Testing

// MARK: - GistPublishPayloadBuilderTests

struct GistPublishPayloadBuilderTests {
    @Test("Builds default secret Gist payload with README, HAR, and transaction text")
    func buildsDefaultPayload() throws {
        let transaction = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/users?token=secret",
            statusCode: 200
        )

        let payload = try GistPublishPayloadBuilder().build(
            transactions: [transaction],
            options: GistPublishOptions()
        )

        #expect(payload.isPublic == false)
        #expect(payload.files["README.md"]?.contains("Request count: 1") == true)
        #expect(payload.files["rockxy-selected.har"] != nil)
        #expect(payload.files.keys.contains { $0.hasSuffix(".txt") })
    }

    @Test("Redacts sensitive headers, query, and body without mutating original transaction")
    func redactsSensitiveDataWithoutMutation() throws {
        var request = TestFixtures.makeRequest(
            method: "POST",
            url: "https://api.example.com/login?api_key=secret&mode=json",
            headers: [
                HTTPHeader(name: "Authorization", value: "Bearer secret"),
                HTTPHeader(name: "Content-Type", value: "application/json"),
            ]
        )
        request.body = Data(#"{"password":"secret","name":"Ada"}"#.utf8)
        request.contentType = .json
        let transaction = HTTPTransaction(request: request, state: .completed)
        transaction.response = TestFixtures.makeResponse(statusCode: 200)

        let payload = try GistPublishPayloadBuilder().build(
            transactions: [transaction],
            options: GistPublishOptions(redactSensitiveData: true)
        )
        let serialized = payload.files.values.joined(separator: "\n")

        #expect(!serialized.contains("Bearer secret"))
        #expect(!serialized.contains("api_key=secret"))
        #expect(!serialized.contains(#""password":"secret""#))
        #expect(transaction.request.headers.first?.value == "Bearer secret")
        #expect(transaction.request.url.absoluteString.contains("api_key=secret"))
    }

    @Test("Redacts Web3 RPC wallet secrets before publishing")
    func redactsWeb3RPCSecrets() throws {
        let requestBody = Data(
            #"{"jsonrpc":"2.0","id":1,"method":"eth_sendRawTransaction","params":[{"privateKey":"0xsecret","seedPhrase":"twelve words","signature":"0xsig"}]}"#.utf8
        )
        let responseBody = Data(#"{"jsonrpc":"2.0","id":1,"result":"0xhash","signature":"0xresponsesig"}"#.utf8)
        let transaction = TestFixtures.makeWeb3RPCTransaction(
            method: "eth_sendRawTransaction",
            requestBody: requestBody,
            responseBody: responseBody
        )

        let payload = try GistPublishPayloadBuilder().build(
            transactions: [transaction],
            options: GistPublishOptions(redactSensitiveData: true)
        )
        let serialized = payload.files.values.joined(separator: "\n")

        #expect(!serialized.contains("0xsecret"))
        #expect(!serialized.contains("twelve words"))
        #expect(!serialized.contains("0xsig"))
        #expect(!serialized.contains("0xresponsesig"))
        #expect(serialized.contains("[REDACTED]"))
    }

    @Test("Includes WebSocket frames only when selected transactions contain frames")
    func includesWebSocketFramesWhenPresent() throws {
        let http = TestFixtures.makeTransaction()
        let noWebSocket = try GistPublishPayloadBuilder().build(
            transactions: [http],
            options: GistPublishOptions()
        )
        let webSocket = try GistPublishPayloadBuilder().build(
            transactions: [TestFixtures.makeWebSocketTransaction()],
            options: GistPublishOptions()
        )

        #expect(noWebSocket.files["websocket-frames.json"] == nil)
        #expect(webSocket.files["websocket-frames.json"]?.contains("Frame 0") == true)
    }
}
