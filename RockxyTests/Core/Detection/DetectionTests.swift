import Foundation
@testable import Rockxy
import Testing

// Tests for content detection: `GraphQLDetector` (operation type parsing, operationName/variables
// extraction, negative cases) and `ContentTypeDetector` (JSON, XML, HTML, image, form, unknown).

// MARK: - DetectionTests

struct DetectionTests {
    // MARK: - GraphQLDetector Tests

    @Test("GraphQLDetector detects query operation")
    func detectGraphQLQuery() throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["query": "{ users { id } }"]
        )
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/graphql")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: body
        )

        let info = try #require(GraphQLDetector.detect(request: request))

        #expect(info.operationType == .query)
        #expect(info.query == "{ users { id } }")
    }

    @Test("GraphQLDetector detects mutation operation")
    func detectGraphQLMutation() throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["query": "mutation { createUser(name: \"test\") { id } }"]
        )
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/graphql")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: body
        )

        let info = try #require(GraphQLDetector.detect(request: request))

        #expect(info.operationType == .mutation)
    }

    @Test("GraphQLDetector returns nil for non-POST requests")
    func detectGraphQLNonPost() throws {
        let request = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "https://api.example.com/graphql")),
            httpVersion: "HTTP/1.1",
            headers: []
        )

        let info = GraphQLDetector.detect(request: request)

        #expect(info == nil)
    }

    @Test("GraphQLDetector returns nil for non-graphql path")
    func detectGraphQLWrongPath() throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["query": "{ users { id } }"]
        )
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/api/v1/data")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: body
        )

        let info = GraphQLDetector.detect(request: request)

        #expect(info == nil)
    }

    @Test("GraphQLDetector returns nil for missing query in body")
    func detectGraphQLMissingQuery() throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["variables": ["id": 1]]
        )
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/graphql")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: body
        )

        let info = GraphQLDetector.detect(request: request)

        #expect(info == nil)
    }

    @Test("GraphQLDetector extracts operationName and variables")
    func detectGraphQLOperationNameAndVariables() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "query": "query GetUser($id: ID!) { user(id: $id) { name } }",
            "operationName": "GetUser",
            "variables": ["id": "123"]
        ])
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://api.example.com/graphql")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: body
        )

        let info = try #require(GraphQLDetector.detect(request: request))

        #expect(info.operationName == "GetUser")
        #expect(info.variables != nil)
        #expect(try #require(info.variables?.contains("123")))
    }

    // MARK: - ContentTypeDetector Tests

    @Test("ContentTypeDetector detects JSON")
    func detectJSON() {
        let headers = [HTTPHeader(name: "Content-Type", value: "application/json")]
        let result = ContentTypeDetector.detect(headers: headers, body: nil)
        #expect(result == .json)
    }

    @Test("ContentTypeDetector detects vendor JSON media types")
    func detectVendorJSON() {
        let headers = [HTTPHeader(name: "Content-Type", value: "application/problem+json; charset=utf-8")]
        let result = ContentTypeDetector.detect(headers: headers, body: nil)
        #expect(result == .json)
    }

    @Test("ContentTypeDetector sniffs JSON body when header is missing")
    func sniffJSONBodyWithoutHeader() {
        let body = Data(#"{"token":"secret","ok":true}"#.utf8)
        let result = ContentTypeDetector.detect(headers: [], body: body)
        #expect(result == .json)
    }

    @Test("ContentTypeDetector detects XML")
    func detectXML() {
        let headers = [HTTPHeader(name: "Content-Type", value: "application/xml")]
        let result = ContentTypeDetector.detect(headers: headers, body: nil)
        #expect(result == .xml)
    }

    @Test("ContentTypeDetector detects HTML")
    func detectHTML() {
        let headers = [HTTPHeader(name: "Content-Type", value: "text/html; charset=utf-8")]
        let result = ContentTypeDetector.detect(headers: headers, body: nil)
        #expect(result == .html)
    }

    @Test("ContentTypeDetector detects image")
    func detectImage() {
        let headers = [HTTPHeader(name: "Content-Type", value: "image/png")]
        let result = ContentTypeDetector.detect(headers: headers, body: nil)
        #expect(result == .image)
    }

    @Test("ContentTypeDetector detects form data")
    func detectForm() {
        let headers = [
            HTTPHeader(name: "Content-Type", value: "application/x-www-form-urlencoded")
        ]
        let result = ContentTypeDetector.detect(headers: headers, body: nil)
        #expect(result == .form)
    }

    @Test("ContentTypeDetector detects gRPC and Protobuf media types")
    func detectGRPCAndProtobuf() {
        let grpc = [HTTPHeader(name: "Content-Type", value: "application/grpc+proto; charset=utf-8")]
        let grpcWeb = [HTTPHeader(name: "Content-Type", value: "application/grpc-web+proto")]
        let protobuf = [HTTPHeader(name: "Content-Type", value: "application/x-protobuf")]

        #expect(ContentTypeDetector.detect(headers: grpc, body: nil) == .protobuf)
        #expect(ContentTypeDetector.detect(headers: grpcWeb, body: nil) == .protobuf)
        #expect(ContentTypeDetector.detect(headers: protobuf, body: nil) == .protobuf)
    }

    @Test("ContentTypeDetector returns unknown for unrecognized type")
    func detectUnknown() {
        let headers = [HTTPHeader(name: "Content-Type", value: "application/octet-stream")]
        let result = ContentTypeDetector.detect(headers: headers, body: nil)
        #expect(result == .unknown)
    }

    // MARK: - GRPCDetector Tests

    @Test("GRPCDetector detects method metadata and unary frames")
    func detectGRPCUnaryFrames() throws {
        let transaction = TestFixtures.makeGRPCTransaction()

        let inspection = try #require(GRPCDetector.detect(
            request: transaction.request,
            response: transaction.response,
            timingInfo: transaction.timingInfo,
            measuredDuration: transaction.measuredDuration
        ))

        #expect(inspection.serviceName == "user.v1.UserService")
        #expect(inspection.methodName == "GetProfile")
        #expect(inspection.grpcStatus == "0")
        #expect(inspection.requestFrames.count == 1)
        #expect(inspection.responseFrames.count == 1)
        #expect(inspection.requestFrames.first?.heuristicTree != nil)
    }

    @Test("GRPCDetector preserves streaming frame boundaries")
    func detectGRPCStreamingFrames() throws {
        let first = TestFixtures.grpcFrame(payload: Data([0x08, 0x01]))
        let second = TestFixtures.grpcFrame(payload: Data([0x08, 0x02]))
        let transaction = TestFixtures.makeGRPCTransaction(responseBody: first + second)

        let inspection = try #require(GRPCDetector.detect(
            request: transaction.request,
            response: transaction.response,
            timingInfo: nil,
            measuredDuration: nil
        ))

        #expect(inspection.responseFrames.count == 2)
        #expect(inspection.responseFrames.map(\.index) == [1, 2])
        #expect(inspection.responseFrames.map(\.payload.count) == [2, 2])
    }

    @Test("GRPCDetector reports truncated payloads honestly")
    func detectGRPCTruncatedPayload() throws {
        let truncated = Data([0x00, 0x00, 0x00, 0x00, 0x04, 0x08])
        let frames = GRPCDetector.parseFrames(truncated, direction: .response)
        let frame = try #require(frames.first)

        #expect(frames.count == 1)
        #expect(frame.status == .truncatedPayload(expectedBytes: 4, actualBytes: 1))
        #expect(frame.heuristicTree == nil)
    }

    // MARK: - Web3RPCDetector Tests

    @Test("Web3RPCDetector detects eth_call metadata")
    func detectWeb3EthCall() throws {
        let request = try web3Request(
            body: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "eth_call",
                "params": [
                    ["to": "0x1111111111111111111111111111111111111111", "data": "0x70a08231"],
                    "latest",
                ],
            ]
        )
        let response = try web3Response(body: ["jsonrpc": "2.0", "id": 1, "result": "0x0"])

        let info = try #require(Web3RPCDetector.detect(request: request, response: response))

        #expect(info.family == .evm)
        #expect(info.providerHost == "mainnet.infura.io")
        #expect(info.method == "eth_call")
        #expect(info.requestID == "1")
        #expect(info.blockIdentifier == "latest")
        #expect(info.requestPayloadSize == request.body?.count)
        #expect(info.responsePayloadSize == response.body?.count)
    }

    @Test("Web3RPCDetector detects eth_estimateGas")
    func detectWeb3EthEstimateGas() throws {
        let request = try web3Request(
            body: [
                "jsonrpc": "2.0",
                "id": "gas-1",
                "method": "eth_estimateGas",
                "params": [
                    ["from": "0x2222222222222222222222222222222222222222", "to": "0x3333333333333333333333333333333333333333"],
                    "pending",
                ],
            ]
        )

        let info = try #require(Web3RPCDetector.detect(request: request))

        #expect(info.method == "eth_estimateGas")
        #expect(info.requestID == "gas-1")
        #expect(info.blockIdentifier == "pending")
    }

    @Test("Web3RPCDetector extracts eth_sendRawTransaction hash")
    func detectWeb3EthSendRawTransaction() throws {
        let txHash = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let request = try web3Request(
            body: [
                "jsonrpc": "2.0",
                "id": 7,
                "method": "eth_sendRawTransaction",
                "params": ["0xf86c808504a817c80082520894"],
            ]
        )
        let response = try web3Response(body: ["jsonrpc": "2.0", "id": 7, "result": txHash])

        let info = try #require(Web3RPCDetector.detect(request: request, response: response))

        #expect(info.method == "eth_sendRawTransaction")
        #expect(info.transactionHash == txHash)
    }

    @Test("Web3RPCDetector extracts eth_getLogs block and transaction hash")
    func detectWeb3EthGetLogs() throws {
        let txHash = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let request = try web3Request(
            body: [
                "jsonrpc": "2.0",
                "id": 12,
                "method": "eth_getLogs",
                "params": [
                    [
                        "address": "0x4444444444444444444444444444444444444444",
                        "fromBlock": "0x10",
                        "toBlock": "0x20",
                    ],
                ],
            ]
        )
        let response = try web3Response(
            body: [
                "jsonrpc": "2.0",
                "id": 12,
                "result": [
                    ["blockNumber": "0x12", "transactionHash": txHash],
                ],
            ]
        )

        let info = try #require(Web3RPCDetector.detect(request: request, response: response))

        #expect(info.method == "eth_getLogs")
        #expect(info.blockIdentifier == "0x10...0x20")
        #expect(info.transactionHash == txHash)
    }

    @Test("Web3RPCDetector extracts eth_chainId result")
    func detectWeb3EthChainID() throws {
        let request = try web3Request(body: ["jsonrpc": "2.0", "id": 4, "method": "eth_chainId", "params": []])
        let response = try web3Response(body: ["jsonrpc": "2.0", "id": 4, "result": "0x1"])

        let info = try #require(Web3RPCDetector.detect(request: request, response: response))

        #expect(info.method == "eth_chainId")
        #expect(info.chainHint?.chainID == "0x1")
    }

    @Test("Web3RPCDetector summarizes batches")
    func detectWeb3BatchSummary() throws {
        let request = try web3Request(
            body: [
                ["jsonrpc": "2.0", "id": 1, "method": "eth_chainId", "params": []],
                ["jsonrpc": "2.0", "id": 2, "method": "eth_blockNumber", "params": []],
            ]
        )
        let response = try web3Response(
            body: [
                ["jsonrpc": "2.0", "id": 1, "result": "0x1"],
                ["jsonrpc": "2.0", "id": 2, "error": ["code": -32_000, "message": "rate limited"]],
            ]
        )

        let info = try #require(Web3RPCDetector.detect(request: request, response: response))
        let batch = try #require(info.batch)

        #expect(info.method == nil)
        #expect(info.requestID == nil)
        #expect(batch.requestCount == 2)
        #expect(batch.web3RequestCount == 2)
        #expect(batch.responseCount == 2)
        #expect(batch.errorCount == 1)
        #expect(batch.methods == ["eth_chainId", "eth_blockNumber"])
    }

    @Test("Web3RPCDetector extracts provider error")
    func detectWeb3ProviderError() throws {
        let request = try web3Request(body: ["jsonrpc": "2.0", "id": 9, "method": "eth_call", "params": []])
        let response = try web3Response(
            body: [
                "jsonrpc": "2.0",
                "id": 9,
                "error": ["code": -32_602, "message": "invalid argument 0"],
            ]
        )

        let info = try #require(Web3RPCDetector.detect(request: request, response: response))

        #expect(info.error?.code == -32_602)
        #expect(info.error?.message == "invalid argument 0")
    }

    @Test("Web3RPCDetector ignores malformed JSON")
    func detectWeb3MalformedPayload() throws {
        let request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://mainnet.infura.io/v3/test")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"jsonrpc":"2.0","method":"eth_call""#.utf8),
            contentType: .json
        )

        #expect(Web3RPCDetector.detect(request: request) == nil)
    }

    @Test("Web3RPCDetector ignores non-RPC JSON")
    func detectWeb3NonRPCJSON() throws {
        let request = try web3Request(
            body: [
                "method": "search",
                "query": "eth_call examples",
                "filters": ["chain": "mainnet"],
            ]
        )

        #expect(Web3RPCDetector.detect(request: request) == nil)
    }

    @Test("Web3RPCDetector detects Solana JSON-RPC")
    func detectWeb3SolanaRPC() throws {
        let request = try web3Request(
            url: "https://api.mainnet-beta.solana.com",
            body: ["jsonrpc": "2.0", "id": 1, "method": "getLatestBlockhash", "params": []]
        )

        let info = try #require(Web3RPCDetector.detect(request: request))

        #expect(info.family == .solana)
        #expect(info.method == "getLatestBlockhash")
        #expect(info.providerHost == "api.mainnet-beta.solana.com")
    }

    private func web3Request(url: String = "https://mainnet.infura.io/v3/test", body: Any) throws -> HTTPRequestData {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: url)),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: data,
            contentType: .json
        )
    }

    private func web3Response(body: Any) throws -> HTTPResponseData {
        let data = try JSONSerialization.data(withJSONObject: body)
        return HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: data,
            contentType: .json
        )
    }
}
