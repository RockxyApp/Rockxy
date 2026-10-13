import Compression
import Foundation
@testable import Rockxy
import Testing

/// Tests for the extracted protocol-routing/defaulting logic used by ResponseInspectorView.
/// These cover ProtocolTabKind.defaultFor(...) and state transition sequences.
/// Actual SwiftUI lifecycle behavior (.task(id:) firing, tab-button interaction) is not
/// covered by this suite. Those behaviors remain manual verification scope for now.
struct InspectorRoutingTests {
    // MARK: - Model Facts

    @Test("HTTP transaction has no WebSocket connection")
    func httpTransactionNoWebSocket() {
        let transaction = TestFixtures.makeTransaction()
        #expect(transaction.webSocketConnection == nil)
        #expect(transaction.graphQLInfo == nil)
    }

    @Test("WebSocket transaction has WebSocket connection")
    func webSocketTransactionHasConnection() throws {
        let transaction = TestFixtures.makeWebSocketTransaction()
        #expect(transaction.webSocketConnection != nil)
        #expect(try #require(transaction.webSocketConnection?.frameCount) > 0)
    }

    @Test("GraphQL transaction has GraphQL info")
    func graphQLTransactionHasInfo() {
        let transaction = TestFixtures.makeGraphQLTransaction()
        #expect(transaction.graphQLInfo != nil)
        #expect(transaction.graphQLInfo?.operationType == .query)
    }

    @Test("gRPC transaction is detected from HTTP metadata")
    func grpcTransactionHasInspectionMetadata() {
        let transaction = TestFixtures.makeGRPCTransaction()
        #expect(GRPCDetector.isGRPC(transaction: transaction))
    }

    @Test("WebSocket transaction preserves HTTP response for handshake inspection")
    func webSocketPreservesHTTPResponse() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        #expect(transaction.response != nil)
        #expect(transaction.response?.statusCode == 101)
    }

    @Test("Inspector response snapshot decodes Brotli display body without mutating original bytes")
    func inspectorResponseSnapshotDecodesBrotliDisplayBody() throws {
        let html = "<html><body>Example Domain</body></html>"
        let compressed = try #require(compress(Data(html.utf8), algorithm: COMPRESSION_BROTLI))
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [
                HTTPHeader(name: "Content-Type", value: "text/html"),
                HTTPHeader(name: "Content-Encoding", value: "br"),
            ],
            body: compressed,
            contentType: .html
        )

        let snapshot = InspectorResponseSnapshot(response: response)

        #expect(snapshot.body == compressed)
        #expect(String(data: try #require(snapshot.displayBody), encoding: .utf8) == html)
        #expect(InspectorPayloadFormatter.responseDisplayText(body: try #require(snapshot.displayBody), sortedKeys: false) == html)
    }

    @Test("Raw response text uses decoded gzip body while preserving headers")
    func rawResponseTextUsesDecodedGzipBody() throws {
        let text = "compressed response text"
        let originalData = Data(text.utf8)
        let compressed = try #require(compress(originalData, algorithm: COMPRESSION_ZLIB))
        let gzipData = wrapInGzip(compressed, originalData: originalData)
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [
                HTTPHeader(name: "Content-Type", value: "text/plain"),
                HTTPHeader(name: "Content-Encoding", value: "gzip"),
            ],
            body: gzipData,
            contentType: .text
        )

        let raw = try #require(InspectorPayloadFormatter.rawResponse(InspectorResponseSnapshot(response: response)))

        #expect(raw.contains("Content-Encoding: gzip"))
        #expect(raw.contains(text))
        #expect(InspectorResponseSnapshot(response: response).body == gzipData)
    }

    @Test("Decoded JSON display body feeds JSON preview rendering")
    func decodedJSONDisplayBodyFeedsPreviewRendering() throws {
        let json = #"{"name":"Rockxy","ok":true}"#
        let compressed = try #require(compress(Data(json.utf8), algorithm: COMPRESSION_BROTLI))
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Content-Encoding", value: "br"),
            ],
            body: compressed,
            contentType: .json
        )
        let body = try #require(InspectorResponseSnapshot(response: response).displayBody)

        if case let .text(text) = PreviewRenderer.render(body: body, mode: .json) {
            #expect(text.contains(#""name" : "Rockxy""#))
        } else {
            Issue.record("Expected decoded JSON text preview")
        }

        if case let .json(object) = PreviewRenderer.render(body: body, mode: .jsonTree),
           let dict = object as? [String: Any] {
            #expect(dict["name"] as? String == "Rockxy")
        } else {
            Issue.record("Expected decoded JSON tree preview")
        }
    }

    @Test("Invalid and unsupported response encodings fall back to original body")
    func unsupportedResponseEncodingsFallBackToOriginalBody() throws {
        let invalidCompressedBody = Data([0x00, 0x01, 0x02, 0x03])
        let invalidResponse = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Encoding", value: "br")],
            body: invalidCompressedBody
        )
        let unsupportedBody = Data("zstd bytes stay opaque".utf8)
        let unsupportedResponse = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Encoding", value: "zstd")],
            body: unsupportedBody
        )

        #expect(InspectorResponseSnapshot(response: invalidResponse).displayBody == invalidCompressedBody)
        #expect(InspectorResponseSnapshot(response: unsupportedResponse).displayBody == unsupportedBody)
    }

    @Test("Inspector snapshot preserves original bytes for wire-fidelity renderers")
    func inspectorSnapshotPreservesOriginalBytesForWireFidelityRenderers() throws {
        let text = "wire bytes should stay compressed"
        let compressed = try #require(compress(Data(text.utf8), algorithm: COMPRESSION_BROTLI))
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Encoding", value: "br")],
            body: compressed
        )
        let snapshot = InspectorResponseSnapshot(response: response)

        #expect(snapshot.body == compressed)
        #expect(snapshot.displayBody != compressed)
        #expect(PreviewRenderer.formatHexDump(try #require(snapshot.body)) == PreviewRenderer.formatHexDump(compressed))
    }

    @Test("WebSocket transaction preserves HTTP request for upgrade headers")
    func webSocketPreservesHTTPRequest() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        #expect(transaction.request.method == "GET")
        #expect(transaction.request.url.scheme == "wss")
    }

    // MARK: - Protocol Tab Selection Behavior (via ProtocolTabKind.defaultFor)

    @Test("WebSocket transaction defaults to .websocket protocol tab")
    func wsDefaultsToWebSocketTab() {
        let tx = TestFixtures.makeWebSocketTransaction()
        let tab = ProtocolTabKind.defaultFor(tx)
        #expect(tab == .websocket)
    }

    @Test("GraphQL transaction defaults to .graphql protocol tab")
    func gqlDefaultsToGraphQLTab() {
        let tx = TestFixtures.makeGraphQLTransaction()
        let tab = ProtocolTabKind.defaultFor(tx)
        #expect(tab == .graphql)
    }

    @Test("gRPC transaction defaults to .grpc protocol tab")
    func grpcDefaultsToGRPCTab() {
        let tx = TestFixtures.makeGRPCTransaction()
        let tab = ProtocolTabKind.defaultFor(tx)
        #expect(tab == .grpc)
        #expect(ProtocolTabKind.isSupported(.grpc, by: tx))
    }

    @Test("Web3 RPC metadata defaults to .web3 protocol tab")
    func web3RPCMetadataDefaultsToWeb3Tab() {
        let tx = makeWeb3RPCTransaction()
        let tab = ProtocolTabKind.defaultFor(tx)

        #expect(tab == .web3)
        #expect(ProtocolTabKind.isSupported(.web3, by: tx))
    }

    @Test("Plain HTTP transaction defaults to nil protocol tab")
    func httpDefaultsToNilTab() {
        let tx = TestFixtures.makeTransaction()
        let tab = ProtocolTabKind.defaultFor(tx)
        #expect(tab == nil)
    }

    @Test("JSON-RPC shaped HTTP without Web3 metadata defaults to nil protocol tab")
    func jsonRPCWithoutWeb3MetadataDefaultsToNilTab() {
        let tx = makeJSONRPCTransaction(
            body: #"{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}"#
        )

        #expect(ProtocolTabKind.defaultFor(tx) == nil)
    }

    @Test("Malformed JSON-RPC HTTP without Web3 metadata falls back to nil protocol tab")
    func malformedJSONRPCWithoutWeb3MetadataDefaultsToNilTab() {
        let tx = makeJSONRPCTransaction(body: #"{"jsonrpc":"2.0","method":"eth_sendRawTransaction""#)

        #expect(ProtocolTabKind.defaultFor(tx) == nil)
    }

    @Test("Plain HTTP transaction still supports empty gRPC tab")
    func httpSupportsEmptyGRPCTab() {
        let tx = TestFixtures.makeTransaction()
        #expect(ProtocolTabKind.isSupported(.grpc, by: tx))
    }

    @Test("Plain HTTP transaction exposes empty AI and Web3 tabs")
    func httpExposesEmptyAIAndWeb3Tabs() {
        let tx = TestFixtures.makeTransaction()
        let tabs = ProtocolTabKind.availableTabs(for: tx)

        #expect(tabs == [.ai, .web3, .grpc])
        #expect(!tabs.contains(.websocket))
        #expect(!tabs.contains(.graphql))
        #expect(ProtocolTabKind.defaultFor(tx) == nil)
        #expect(ProtocolTabKind.isSupported(.ai, by: tx))
        #expect(ProtocolTabKind.isSupported(.web3, by: tx))
        #expect(!ProtocolTabKind.hasDetectedSignal(.ai, in: tx))
        #expect(!ProtocolTabKind.hasDetectedSignal(.web3, in: tx))
    }

    @Test("AI and Web3 tabs coexist when both signals are present")
    func aiAndWeb3TabsCoexist() {
        let tx = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.openai.com/v1/responses"
        )
        tx.web3RPCInfo = makeWeb3RPCTransaction().web3RPCInfo

        let tabs = ProtocolTabKind.availableTabs(for: tx)

        #expect(tabs.contains(.ai))
        #expect(tabs.contains(.web3))
        #expect(ProtocolTabKind.defaultFor(tx) == .ai)
    }

    @Test("Detected dynamic tabs stay before always-visible AI Web3 gRPC tail")
    func protocolTabOrderKeepsAlwaysVisibleTabsAtEnd() {
        let tx = TestFixtures.makeWebSocketTransaction()
        tx.graphQLInfo = GraphQLInfo(
            operationName: "SubscribeBlocks",
            operationType: .subscription,
            query: "subscription SubscribeBlocks { block { number } }",
            variables: nil
        )

        #expect(ProtocolTabKind.availableTabs(for: tx) == [.websocket, .graphql, .ai, .web3, .grpc])
    }

    @Test("Switching WS → HTTP clears protocol tab")
    func wsToHttpClearsProtocol() {
        let wsTx = TestFixtures.makeWebSocketTransaction()
        let httpTx = TestFixtures.makeTransaction()

        // Simulate: first select WS
        var protocolTab = ProtocolTabKind.defaultFor(wsTx)
        #expect(protocolTab == .websocket)

        // Then select HTTP
        protocolTab = ProtocolTabKind.defaultFor(httpTx)
        #expect(protocolTab == nil)
    }

    @Test("Switching GraphQL → HTTP clears protocol tab")
    func graphQLToHttpClearsProtocol() {
        let gqlTx = TestFixtures.makeGraphQLTransaction()
        let httpTx = TestFixtures.makeTransaction()

        var protocolTab = ProtocolTabKind.defaultFor(gqlTx)
        #expect(protocolTab == .graphql)

        protocolTab = ProtocolTabKind.defaultFor(httpTx)
        #expect(protocolTab == nil)
    }

    @Test("Switching gRPC → HTTP clears protocol tab")
    func grpcToHttpClearsProtocol() {
        let grpcTx = TestFixtures.makeGRPCTransaction()
        let httpTx = TestFixtures.makeTransaction()

        var protocolTab = ProtocolTabKind.defaultFor(grpcTx)
        #expect(protocolTab == .grpc)

        protocolTab = ProtocolTabKind.defaultFor(httpTx)
        #expect(protocolTab == nil)
    }

    @Test("Switching Web3 RPC → HTTP clears protocol tab")
    func web3RPCToHttpClearsProtocol() {
        let web3Tx = makeWeb3RPCTransaction()
        let httpTx = TestFixtures.makeTransaction()

        var protocolTab = ProtocolTabKind.defaultFor(web3Tx)
        #expect(protocolTab == .web3)

        protocolTab = ProtocolTabKind.defaultFor(httpTx)
        #expect(protocolTab == nil)
    }

    @Test("Switching HTTP → WS re-enables protocol tab")
    func httpToWsReEnablesProtocol() {
        let httpTx = TestFixtures.makeTransaction()
        let wsTx = TestFixtures.makeWebSocketTransaction()

        var protocolTab = ProtocolTabKind.defaultFor(httpTx)
        #expect(protocolTab == nil)

        protocolTab = ProtocolTabKind.defaultFor(wsTx)
        #expect(protocolTab == .websocket)
    }

    @Test("Switching WS → HTTP → WS resets and re-enables correctly")
    func wsHttpWsTransition() {
        let ws1 = TestFixtures.makeWebSocketTransaction()
        let http = TestFixtures.makeTransaction()
        let ws2 = TestFixtures.makeWebSocketTransaction()

        var tab = ProtocolTabKind.defaultFor(ws1)
        #expect(tab == .websocket)

        tab = ProtocolTabKind.defaultFor(http)
        #expect(tab == nil)

        tab = ProtocolTabKind.defaultFor(ws2)
        #expect(tab == .websocket)
    }

    @Test("Switching WS → GraphQL transitions protocol tab correctly")
    func wsToGraphQLTransition() {
        let ws = TestFixtures.makeWebSocketTransaction()
        let gql = TestFixtures.makeGraphQLTransaction()

        var tab = ProtocolTabKind.defaultFor(ws)
        #expect(tab == .websocket)

        tab = ProtocolTabKind.defaultFor(gql)
        #expect(tab == .graphql)
    }

    @Test("Switching WebSocket → Web3 RPC transitions protocol tab correctly")
    func wsToWeb3RPCTransition() {
        let ws = TestFixtures.makeWebSocketTransaction()
        let web3 = makeWeb3RPCTransaction()

        var tab = ProtocolTabKind.defaultFor(ws)
        #expect(tab == .websocket)

        tab = ProtocolTabKind.defaultFor(web3)
        #expect(tab == .web3)
    }

    @Test("Web3 RPC metadata is preferred before GraphQL metadata")
    func web3RPCPreferredBeforeGraphQL() {
        let tx = makeWeb3RPCTransaction(graphQLInfo: GraphQLInfo(
            operationName: "Example",
            operationType: .query,
            query: "query Example { blockNumber }",
            variables: nil
        ))

        #expect(ProtocolTabKind.defaultFor(tx) == .web3)
    }

    @Test("Switching GraphQL → gRPC transitions protocol tab correctly")
    func graphQLToGRPCTransition() {
        let gql = TestFixtures.makeGraphQLTransaction()
        let grpc = TestFixtures.makeGRPCTransaction()

        var tab = ProtocolTabKind.defaultFor(gql)
        #expect(tab == .graphql)

        tab = ProtocolTabKind.defaultFor(grpc)
        #expect(tab == .grpc)
    }

    @Test("Manual switch to nil preserves until next transaction change")
    func manualSwitchPreserved() {
        let ws = TestFixtures.makeWebSocketTransaction()

        // Auto-select on first appearance
        var protocolTab = ProtocolTabKind.defaultFor(ws)
        #expect(protocolTab == .websocket)

        // User manually clicks Headers tab — clears protocol tab
        protocolTab = nil
        #expect(protocolTab == nil)

        // Same transaction — manual choice should be preserved
        // (autoSelectProtocolTab only fires on transaction CHANGE, not same transaction)
        // The nil state remains until the transaction id changes
        #expect(protocolTab == nil)

        // Different transaction triggers auto-select again
        let ws2 = TestFixtures.makeWebSocketTransaction()
        protocolTab = ProtocolTabKind.defaultFor(ws2)
        #expect(protocolTab == .websocket)
    }

    @Test("CONNECT tunnel shows domain and app SSL prompt actions")
    func connectTunnelShowsSSLPromptActions() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )
        transaction.clientApp = "Brave Browser Helper"

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: false,
            appScope: HTTPSInspectionAppScope(
                name: "Brave Browser Helper",
                knownHostCount: 3,
                enabledHostCount: 0
            )
        )

        #expect(prompt?.host == "api.example.com")
        #expect(prompt?.hostScope?.control == .button)
        #expect(prompt?.hostScope?.controlTitle == "Decrypt Host")
        #expect(prompt?.hostScope?.action == .enableDomain("api.example.com"))
        #expect(prompt?.appScope?.control == .button)
        #expect(prompt?.appScope?.controlTitle == "Decrypt Observed Hosts")
        #expect(prompt?.appScope?.action == .enableApp("Brave Browser Helper", fallbackDomain: "api.example.com"))
        #expect(prompt?.appScope?.actionDescription.contains("apply to every application") == true)
        #expect(prompt?.requiresCertificateSetup == false)
        #expect(prompt?.insight == .tunnelEstablished(statusCode: 200))
        #expect(prompt?.insight?.title == "Content Not Inspected")
        #expect(prompt?.insight?.summary == "HTTPS content was not inspected.")
    }

    @Test("A CONNECT row explains its tunnel with the reason recorded at capture")
    func connectTunnelUsesCaptureReason() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )
        transaction.tunnelReason = .noDecryptionRule

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: true,
            appScope: nil
        )

        #expect(prompt?.captureReason == .noDecryptionRule)
        #expect(prompt?.insight == .tunnelEstablished(statusCode: 200))
        #expect(TunnelReason.noDecryptionRule.captureNote.contains("no HTTPS Decryption rule"))
    }

    @Test("A row tunneled by auto-passthrough keeps its rejection evidence after the passthrough expires")
    func autoPassthroughReasonIsRejectionEvidence() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://pinned.example.com:443",
            statusCode: 200
        )
        transaction.tunnelReason = .autoPassthrough

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: true,
            hasRecentTLSRejection: false,
            appScope: nil
        )

        #expect(prompt?.insight == .tlsInterceptionRejected)
        #expect(prompt?.captureReason == .autoPassthrough)
    }

    @Test("Every raw tunnel decision maps to a recorded reason")
    func rawTunnelReasonsMap() {
        #expect(TLSInterceptHandler.RawTunnelReason.bypassProxyList.tunnelReason == .bypassList)
        #expect(TLSInterceptHandler.RawTunnelReason.noSSLProxyingRule.tunnelReason == .noDecryptionRule)
        #expect(TLSInterceptHandler.RawTunnelReason.unresolvedApplicationIdentity.tunnelReason == .unresolvedApplication)
        #expect(TLSInterceptHandler.RawTunnelReason.autoPassthrough.tunnelReason == .autoPassthrough)
    }

    @Test("CONNECT tunnel hides duplicate app action when only the current host is known")
    func connectTunnelHidesDuplicateAppAction() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )
        transaction.clientApp = "Google Chrome"

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: false,
            appScope: HTTPSInspectionAppScope(
                name: "Google Chrome",
                knownHostCount: 1,
                enabledHostCount: 0
            )
        )

        #expect(prompt?.hostScope?.action == .enableDomain("api.example.com"))
        #expect(prompt?.appScope == nil)
    }

    @Test("CONNECT tunnel hides app action when it only adds the current disabled host")
    func connectTunnelHidesEquivalentPartialAppAction() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://client.crisp.chat:443",
            statusCode: 200
        )
        transaction.clientApp = "ChatGPT"

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: false,
            appScope: HTTPSInspectionAppScope(
                name: "ChatGPT",
                knownHostCount: 2,
                enabledHostCount: 1
            )
        )

        #expect(prompt?.hostScope?.action == .enableDomain("client.crisp.chat"))
        #expect(prompt?.appScope == nil)
    }

    @Test("CONNECT tunnel prefers certificate guidance when HTTPS interception is unavailable")
    func connectTunnelShowsCertificateGuidance() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: false,
            domainRuleEnabled: false,
            appScope: HTTPSInspectionAppScope(
                name: "Secure Client",
                knownHostCount: 3,
                enabledHostCount: 1
            )
        )

        #expect(prompt?.host == "api.example.com")
        #expect(prompt?.certificateAction == .installCertificate)
        #expect(prompt?.hostScope == nil)
        #expect(prompt?.appScope == nil)
        #expect(prompt?.requiresCertificateSetup == true)
        #expect(prompt?.insight == nil)
    }

    @Test("CONNECT tunnel reports TLS rejection evidence without claiming pinning as fact")
    func connectTunnelShowsTLSRejectionInsight() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: true,
            hasRecentTLSRejection: true,
            appScope: HTTPSInspectionAppScope(
                name: "Secure Client",
                knownHostCount: 3,
                enabledHostCount: 1
            )
        )

        #expect(prompt?.insight == .tlsInterceptionRejected)
        #expect(prompt?.insight?.evidence.contains("Certificate pinning is possible") == true)
        #expect(prompt?.hostScope?.control == .button)
        #expect(prompt?.hostScope?.action == .retryDomain("api.example.com"))
        #expect(prompt?.hostScope?.controlTitle == "Retry")
        #expect(prompt?.appScope == nil)
    }

    @Test("TLS failure transaction exposes the rejection insight directly")
    func tlsFailureShowsRejectionInsight() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://secure.example.com:443",
            statusCode: 0
        )
        transaction.isTLSFailure = true

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: true,
            appScope: nil
        )

        #expect(prompt?.insight == .tlsInterceptionRejected)
        #expect(prompt?.hostScope?.action == .retryDomain("secure.example.com"))
    }

    // MARK: - Compression Helpers

    private func compress(_ input: Data, algorithm: compression_algorithm) -> Data? {
        let capacity = max(input.count * 4, 1_024)
        let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destBuffer.deallocate() }
        let compressedSize = input.withUnsafeBytes { srcPtr -> Int in
            guard let base = srcPtr.baseAddress else {
                return 0
            }
            return compression_encode_buffer(
                destBuffer,
                capacity,
                base.assumingMemoryBound(to: UInt8.self),
                input.count,
                nil,
                algorithm
            )
        }
        guard compressedSize > 0 else {
            return nil
        }
        return Data(bytes: destBuffer, count: compressedSize)
    }

    private func wrapInGzip(_ deflatedData: Data, originalData: Data) -> Data {
        var gzip = Data()
        gzip.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00])
        gzip.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        gzip.append(contentsOf: [0x00, 0x03])
        gzip.append(deflatedData)

        var crc: UInt32 = 0
        originalData.withUnsafeBytes { ptr in
            crc = Self.crc32(ptr)
        }
        withUnsafeBytes(of: crc.littleEndian) { gzip.append(contentsOf: $0) }

        let size = UInt32(originalData.count & 0xFFFF_FFFF)
        withUnsafeBytes(of: size.littleEndian) { gzip.append(contentsOf: $0) }
        return gzip
    }

    private static func crc32(_ buffer: UnsafeRawBufferPointer) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in buffer {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private func makeWeb3RPCTransaction(graphQLInfo: GraphQLInfo? = nil) -> HTTPTransaction {
        guard let url = URL(string: "https://rpc.example.com") else {
            preconditionFailure("Expected valid Web3 RPC fixture URL")
        }
        let request = HTTPRequestData(
            method: "POST",
            url: url,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}"#.utf8),
            contentType: .json
        )
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"jsonrpc":"2.0","id":1,"result":"0x1"}"#.utf8),
            contentType: .json
        )
        return HTTPTransaction(
            request: request,
            response: response,
            state: .completed,
            graphQLInfo: graphQLInfo,
            web3RPCInfo: Web3RPCInfo(
                family: .evm,
                providerHost: "rpc.example.com",
                method: "eth_blockNumber",
                requestID: "1",
                batch: nil,
                error: nil,
                chainHint: Web3RPCChainHint(chainID: "0x1"),
                transactionHash: nil,
                blockIdentifier: nil,
                requestPayloadSize: request.body?.count,
                responsePayloadSize: response.body?.count
            )
        )
    }

    private func makeJSONRPCTransaction(body: String?) -> HTTPTransaction {
        guard let url = URL(string: "https://rpc.example.com") else {
            preconditionFailure("Expected valid JSON-RPC fixture URL")
        }
        let request = HTTPRequestData(
            method: "POST",
            url: url,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: body.map { Data($0.utf8) },
            contentType: .json
        )
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"jsonrpc":"2.0","id":1,"result":"0x1"}"#.utf8),
            contentType: .json
        )
        return HTTPTransaction(request: request, response: response, state: .completed)
    }

    @Test("CONNECT tunnel with an existing host rule exposes ready status")
    func connectTunnelWithExistingRuleShowsReadyStatus() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: true,
            appScope: nil
        )

        #expect(prompt?.hostScope?.state == .ready)
        #expect(prompt?.hostScope?.control == .status)
        #expect(prompt?.hostScope?.action == nil)
        #expect(prompt?.hostScope?.controlTitle == nil)
        #expect(prompt?.appScope == nil)
    }

    @Test("CONNECT tunnel distinguishes partial app-host coverage from the current host")
    func connectTunnelShowsPartialAppHostCoverage() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )
        transaction.clientApp = "Google Chrome"

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: true,
            appScope: HTTPSInspectionAppScope(
                name: "Google Chrome",
                knownHostCount: 4,
                enabledHostCount: 1
            )
        )

        #expect(prompt?.hostScope?.state == .ready)
        #expect(prompt?.hostScope?.control == .status)
        #expect(prompt?.hostScope?.action == nil)
        #expect(prompt?.appScope?.state == .partial)
        #expect(prompt?.appScope?.control == .button)
        #expect(prompt?.appScope?.controlTitle == "Decrypt Observed Hosts")
        #expect(prompt?.appScope?.action == .enableApp("Google Chrome", fallbackDomain: "api.example.com"))
    }

    @Test("HTTPS prompt scope presentation exposes host and app-host state")
    func httpsPromptScopePresentation() {
        let host = HTTPSInspectionScopePresentation.host(value: "api.example.com", isReady: false)
        let appHosts = HTTPSInspectionScopePresentation.appHosts(
            name: "Brave Browser Helper",
            enabledHostCount: 1,
            knownHostCount: 3,
            currentHostEnabled: true,
            fallbackDomain: "api.example.com"
        )

        #expect(host.kind == .host)
        #expect(host.control == .button)
        #expect(host.controlTitle == "Decrypt Host")
        #expect(host.actionDescription == "Turn on HTTPS decryption for new connections to api.example.com")

        #expect(appHosts?.kind == .appHosts)
        #expect(appHosts?.state == .partial)
        #expect(appHosts?.control == .button)
        #expect(appHosts?.action == .enableApp("Brave Browser Helper", fallbackDomain: "api.example.com"))
        #expect(appHosts?.controlTitle == "Decrypt Observed Hosts")

        let duplicateScope = HTTPSInspectionScopePresentation.appHosts(
            name: "curl",
            enabledHostCount: 0,
            knownHostCount: 1,
            currentHostEnabled: false,
            fallbackDomain: "api.example.com"
        )
        #expect(duplicateScope == nil)

        let equivalentScope = HTTPSInspectionScopePresentation.appHosts(
            name: "ChatGPT",
            enabledHostCount: 1,
            knownHostCount: 2,
            currentHostEnabled: false,
            fallbackDomain: "client.crisp.chat"
        )
        #expect(equivalentScope == nil)
    }

    @Test("blocked host Decrypt opens rule review instead of claiming it can enable")
    func blockedHostDecryptOpensRuleReview() {
        let blocked = HTTPSInspectionScopePresentation.host(
            value: "api.example.com",
            isReady: false,
            decryptBlockedReason: "Tunnel rule *.example.com takes priority."
        )

        #expect(blocked.controlTitle == "Review Rules")
        #expect(blocked.action == .openSSLProxyingList)
        #expect(blocked.actionDescription == "Tunnel rule *.example.com takes priority.")
        #expect(blocked.state == .available)
    }

    @Test("Plain HTTP response does not show HTTPS prompt")
    func plainHTTPDoesNotShowHTTPSPrompt() {
        let transaction = TestFixtures.makeTransaction()

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: true,
            domainRuleEnabled: false,
            appScope: nil
        )

        #expect(prompt == nil)
    }

    // MARK: - Frame Version

    @Test("webSocketFrameVersion starts at zero")
    func frameVersionStartsAtZero() {
        let transaction = TestFixtures.makeTransaction()
        #expect(transaction.webSocketFrameVersion == 0)
    }

    @Test("webSocketFrameVersion is writable")
    func frameVersionWritable() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        #expect(transaction.webSocketFrameVersion == 0)
        transaction.webSocketFrameVersion += 1
        #expect(transaction.webSocketFrameVersion == 1)
    }
}
