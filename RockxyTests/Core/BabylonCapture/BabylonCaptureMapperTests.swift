import Foundation
@testable import Rockxy
import Testing

@Suite("Babylon capture mapper")
struct BabylonCaptureMapperTests {
    // MARK: Internal

    @Test("HTTP package maps to Rockxy transaction")
    func mapsHTTPPackage() throws {
        let package = makePackage()
        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.request.method == "POST")
        #expect(transaction.request.url.absoluteString == "https://api.example.com/items")
        #expect(transaction.request.body == Data("request".utf8))
        #expect(transaction.response?.statusCode == 201)
        #expect(transaction.response?.body == Data("response".utf8))
        #expect(transaction.timingInfo?.contentTransfer == 0.75)
        #expect(transaction.clientApp == "Example • iPhone")
        #expect(transaction.state == .completed)
    }

    @Test("SDK omission metadata marks request and response bodies truncated")
    func mapsBodyOmissionMetadata() throws {
        var package = makePackage()
        package.requestBodyOmission = .init(reason: "sizeLimit", observedBytes: 20, originalBytes: 80)
        package.responseBodyOmission = .init(reason: "policy", observedBytes: 0, originalBytes: 12)

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.request.bodyTruncated)
        #expect(transaction.response?.bodyTruncated == true)
        #expect(transaction.request.bodyOmission?.reason == "sizeLimit")
        #expect(transaction.request.bodyOmission?.originalBytes == 80)
        #expect(transaction.response?.bodyOmission?.reason == "policy")
        #expect(transaction.response?.bodyOmission?.observedBytes == 0)
    }

    @Test("Invalid captured header names and values are skipped")
    func skipsInvalidCapturedHeaders() throws {
        let package = makePackage(extraHeaders: [
            .init(key: "Bad\rName", value: "ignored"),
            .init(key: "x-injected", value: "first\r\nSecond: injected"),
        ])

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.request.headers.map(\.name) == ["Content-Type"])
    }

    @Test("Session coding preserves Babylon request truncation")
    func persistsRequestTruncation() throws {
        var package = makePackage(requestBody: nil)
        package.requestBodyOmission = .init(reason: "sizeLimit", observedBytes: 0, originalBytes: 80)
        package.responseBodyOmission = .init(reason: "policy", observedBytes: 0, originalBytes: 12)
        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        let decoded = try JSONDecoder().decode(
            CodableTransaction.self,
            from: JSONEncoder().encode(CodableTransaction(from: transaction))
        ).toLiveModel()

        #expect(decoded.request.body == nil)
        #expect(decoded.request.bodyTruncated)
        #expect(decoded.request.bodyOmission == .init(reason: "sizeLimit", observedBytes: 0, originalBytes: 80))
        #expect(decoded.response?.bodyOmission == .init(reason: "policy", observedBytes: 0, originalBytes: 12))
    }

    @Test("Babylon source, correlation, capabilities, and error survive session coding")
    func persistsBabylonCaptureMetadata() throws {
        let correlation = BabylonTrafficPackageDTO.CorrelationContext(
            sessionID: "runtime-session",
            traceID: "trace",
            stepID: "step",
            createdAt: 1
        )
        let error = BabylonTrafficPackageDTO.CapturedError(
            code: -1_001,
            message: "timed out",
            domain: "NSURLErrorDomain",
            phase: "response"
        )
        let timing = BabylonTrafficPackageDTO.URLSessionTiming(
            schemaVersion: 1,
            taskDuration: 1.25,
            redirectCount: 1,
            reportedTransactionCount: 1,
            omittedTransactionCount: 0,
            transactions: [
                .init(
                    index: 0,
                    fetchDuration: 1.25,
                    dnsDuration: 0.01,
                    connectDuration: 0.02,
                    secureConnectDuration: nil,
                    requestDuration: 0.03,
                    serverWaitDuration: 0.8,
                    responseTransferDuration: 0.39,
                    networkProtocolName: "h2",
                    reusedConnection: true,
                    proxyConnection: false,
                    resourceFetchType: "networkLoad"
                ),
            ]
        )
        let package = makePackage(correlation: correlation, error: error, urlSessionTiming: timing)
        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        transaction.babylonGRPCCallType = "bidirectionalStreaming"
        let capabilities = BabylonConnectionPackageDTO.Capabilities(
            sdkVersion: "1.2.3",
            platform: "iOS",
            payloadSchemaVersions: ["traffic": 1],
            supportedMessageTypes: ["connection", "traffic"],
            supportedTrafficTypes: ["http"],
            maximumBodyBytes: 50_000,
            maximumWebSocketFrameBytes: 10_000,
            maximumCaptureMemoryBytes: 500_000
        )
        transaction.babylonCaptureMetadata = BabylonCaptureMetadata(
            identity: identity,
            capabilities: capabilities,
            correlation: package.correlationContext,
            urlSessionTiming: package.urlSessionTiming,
            error: package.error,
            compatibilityDiagnostics: ["Update Rockxy"]
        )

        let encoded = try JSONEncoder().encode(CodableTransaction(from: transaction))
        let decoded = try JSONDecoder().decode(CodableTransaction.self, from: encoded).toLiveModel()
        #expect(decoded.babylonCaptureMetadata?.clientID == "client")
        #expect(decoded.babylonCaptureMetadata?.bundleIdentifier == "com.example.app")
        #expect(decoded.babylonCaptureMetadata?.deviceModel == "iPhone 17")
        #expect(decoded.babylonCaptureMetadata?.transportSessionID == "session")
        #expect(decoded.babylonCaptureMetadata?.runtimeSessionID == "runtime-session")
        #expect(decoded.babylonCaptureMetadata?.traceID == "trace")
        #expect(decoded.babylonCaptureMetadata?.stepID == "step")
        #expect(decoded.babylonCaptureMetadata?.urlSessionTiming?.taskDuration == 1.25)
        #expect(decoded.babylonCaptureMetadata?.urlSessionTiming?.redirectCount == 1)
        #expect(decoded.babylonCaptureMetadata?.urlSessionTiming?.transactions.first?.dnsDuration == 0.01)
        #expect(decoded.babylonCaptureMetadata?.urlSessionTiming?.transactions.first?.secureConnectDuration == nil)
        #expect(decoded.babylonCaptureMetadata?.urlSessionTiming?.transactions.first?.networkProtocolName == "h2")
        #expect(decoded.babylonCaptureMetadata?.sdkVersion == "1.2.3")
        #expect(decoded.babylonCaptureMetadata?.errorDomain == "NSURLErrorDomain")
        #expect(decoded.babylonCaptureMetadata?.errorCode == -1_001)
        #expect(decoded.babylonCaptureMetadata?.failurePhase == "response")
        #expect(decoded.babylonCaptureMetadata?.errorMessage == "timed out")
        #expect(decoded.babylonGRPCCallType == "bidirectionalStreaming")
        #expect(transaction.connectionLog?.failure?.message.contains("NSURLErrorDomain; response") == true)

        var oversizedMetadata = try #require(
            JSONSerialization
                .jsonObject(with: JSONEncoder().encode(transaction.babylonCaptureMetadata)) as? [String: Any]
        )
        oversizedMetadata["packageName"] = String(repeating: "é", count: 200)
        oversizedMetadata["supportedTrafficTypes"] = Array(repeating: String(repeating: "x", count: 100), count: 50)
        oversizedMetadata["compatibilityDiagnostics"] = Array(repeating: String(repeating: "y", count: 600), count: 20)
        let boundedMetadataData = try JSONSerialization.data(withJSONObject: oversizedMetadata)
        let boundedMetadata = try JSONDecoder().decode(BabylonCaptureMetadata.self, from: boundedMetadataData)
        #expect(boundedMetadata.packageName.utf8.count == 120)
        #expect(boundedMetadata.supportedTrafficTypes.count == 16)
        #expect(boundedMetadata.supportedTrafficTypes.allSatisfy { $0.count == 64 })
        #expect(boundedMetadata.compatibilityDiagnostics.count == 16)
        #expect(boundedMetadata.compatibilityDiagnostics.allSatisfy { $0.count == 512 })

        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "babylonCaptureMetadata")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        #expect(try JSONDecoder().decode(CodableTransaction.self, from: legacyData).toLiveModel()
            .babylonCaptureMetadata == nil)
    }

    @Test("Producer schema and traffic mismatches yield actionable diagnostics")
    func diagnosesUnsupportedProducerCapabilities() {
        let capabilities = BabylonConnectionPackageDTO.Capabilities(
            sdkVersion: "2.0.0",
            platform: "macOS",
            payloadSchemaVersions: ["futureEvent": 1, "traffic": 2, "urlSessionTiming": 1],
            supportedMessageTypes: ["connection", "futureEvent"],
            supportedTrafficTypes: ["http", "webtransport"],
            maximumBodyBytes: 60 * 1_024 * 1_024,
            maximumWebSocketFrameBytes: 1_024,
            maximumCaptureMemoryBytes: 1_024
        )
        let diagnostics = BabylonCaptureReceiver.compatibilityDiagnostics(for: capabilities)

        #expect(diagnostics.count == 6)
        #expect(diagnostics.contains { $0.contains("major version") })
        #expect(diagnostics.contains { $0.contains("incompatible schema version") })
        #expect(diagnostics.contains { $0.contains("does not consume") })
        #expect(diagnostics.contains { $0.contains("unsupported traffic type") })
        #expect(diagnostics.contains { $0.contains("unsupported optional message type") })
        #expect(diagnostics.contains { $0.contains("safe capture limit") })
    }

    @Test("Typed gRPC status fields fill missing status trailers")
    func mapsTypedGRPCStatus() throws {
        let package = BabylonTrafficPackageDTO(
            id: "grpc-status",
            startAt: 1,
            request: .init(url: "/example.Service/Call", method: "POST", headers: [], body: nil),
            response: .init(statusCode: 200, headers: []),
            error: nil,
            responseBodyData: Data(),
            endAt: 2,
            packageType: .grpc,
            correlationContext: nil,
            urlSessionTiming: nil,
            websocketMessagePackage: nil,
            grpcCapture: .init(
                schemaVersion: 1,
                endpoint: "/example.Service/Call",
                authority: "grpc.example.com",
                service: "example.Service",
                method: "Call",
                callType: .unary,
                requestMetadata: [],
                responseMetadata: [],
                trailers: [],
                statusCode: 14,
                statusMessage: "unavailable",
                requestCompression: "gzip",
                responseCompression: "gzip",
                messages: [
                    .init(
                        sequence: 0,
                        direction: .request,
                        data: Data("hello".utf8),
                        observedBytes: 5,
                        omitted: false,
                        compressed: true,
                        timestamp: 1
                    ),
                ]
            )
        )

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        let trailers = try #require(transaction.response?.trailers)

        #expect(trailers.contains { $0.name == "grpc-status" && $0.value == "14" })
        #expect(trailers.contains { $0.name == "grpc-message" && $0.value == "unavailable" })
        #expect(transaction.request.headers.contains { $0.name == "grpc-encoding" && $0.value == "gzip" })
        #expect(transaction.request.body?.first == 1)
        let responseHeaders = transaction.response?.headers ?? []
        #expect(responseHeaders.contains { $0.name == "grpc-encoding" && $0.value == "gzip" })
    }

    @Test("Typed gRPC directions share the producer body budget")
    func rejectsOversizedTypedGRPCAggregateAcrossDirections() {
        let messageSize = 26_214_401
        let package = makeTypedGRPCPackage(messages: [
            .init(
                sequence: 0,
                direction: .request,
                data: Data(repeating: 0, count: messageSize),
                observedBytes: messageSize,
                omitted: false,
                compressed: false,
                timestamp: 1
            ),
            .init(
                sequence: 1,
                direction: .response,
                data: Data(repeating: 0, count: messageSize),
                observedBytes: messageSize,
                omitted: false,
                compressed: false,
                timestamp: 2
            ),
        ])

        #expect(throws: BabylonCaptureMappingError.oversizedBody) {
            try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        }
    }

    @Test("HTTP request and response share the producer body budget")
    func rejectsOversizedHTTPAggregateBody() {
        let bodySize = 26_214_401
        let package = makePackage(
            requestBody: Data(repeating: 0, count: bodySize),
            responseBody: Data(repeating: 0, count: bodySize)
        )

        #expect(throws: BabylonCaptureMappingError.oversizedBody) {
            try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        }
    }

    @Test("WebSocket frame bytes share the producer transaction body budget")
    func rejectsOversizedWebSocketAggregateBody() {
        let frame = BabylonTrafficPackageDTO.WebSocketMessage(
            id: "large-frame",
            createdAt: 1,
            messageType: .send,
            stringValue: nil,
            dataValue: Data(repeating: 1, count: 6 * 1_024 * 1_024)
        )
        let package = makePackage(
            url: "wss://api.example.com/socket",
            requestBody: Data(repeating: 0, count: 45 * 1_024 * 1_024),
            websocketMessage: frame
        )

        #expect(throws: BabylonCaptureMappingError.oversizedBody) {
            try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        }
    }

    @Test("Typed gRPC authority cannot inject credentials or a URL path")
    func rejectsUnsafeTypedGRPCAuthority() {
        let package = makeTypedGRPCPackage(authority: "user:secret@grpc.example.com/path")

        #expect(throws: BabylonCaptureMappingError.invalidURL) {
            try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        }
    }

    @Test("Omitted typed gRPC messages retain aggregate observed and original byte counts")
    func mapsOmittedTypedGRPCMessages() throws {
        let package = makeTypedGRPCPackage(messages: [
            .init(
                sequence: 0,
                direction: .request,
                data: nil,
                observedBytes: 4_096,
                omitted: true,
                compressed: false,
                timestamp: 1
            ),
            .init(
                sequence: 1,
                direction: .request,
                data: nil,
                observedBytes: 3_072,
                omitted: true,
                compressed: false,
                timestamp: 2
            ),
        ])

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.request.body == nil)
        #expect(transaction.request.bodyTruncated)
        #expect(transaction.request.bodyOmission?.reason == "grpcMessageOmitted")
        #expect(transaction.request.bodyOmission?.observedBytes == 7_168)
        #expect(transaction.request.bodyOmission?.originalBytes == 7_168)

        let restored = try JSONDecoder().decode(
            CodableTransaction.self,
            from: JSONEncoder().encode(CodableTransaction(from: transaction))
        ).toLiveModel()
        #expect(restored.request.bodyOmission == .init(
            reason: "grpcMessageOmitted",
            observedBytes: 7_168,
            originalBytes: 7_168
        ))
    }

    @Test("Omitted typed gRPC message sizes stay within the metadata limit")
    func clampsOmittedTypedGRPCMessageSizes() throws {
        let package = makeTypedGRPCPackage(messages: [
            .init(
                sequence: 0,
                direction: .request,
                data: nil,
                observedBytes: 800_000_000,
                omitted: true,
                compressed: false,
                timestamp: 1
            ),
            .init(
                sequence: 1,
                direction: .request,
                data: nil,
                observedBytes: 800_000_000,
                omitted: true,
                compressed: false,
                timestamp: 2
            ),
        ])

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.request.bodyOmission?.observedBytes == 1_000_000_000)
        #expect(transaction.request.bodyOmission?.originalBytes == 1_000_000_000)
    }

    @Test("Typed gRPC maps the absolute endpoint URL accepted by the Babylon SDK")
    func mapsTypedGRPCAbsoluteEndpointURL() throws {
        let endpoint = "https://grpc.example.com:8443/example.Service/Call"
        let package = makeTypedGRPCPackage(authority: "grpc.example.com:8443", endpoint: endpoint)

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.request.url.absoluteString == endpoint)
        #expect(transaction.request.url.path == "/example.Service/Call")
        #expect(transaction.babylonGRPCCallType == "unary")
    }

    @Test("Typed gRPC absolute endpoint URLs may omit a separate authority")
    func mapsTypedGRPCAbsoluteEndpointWithoutAuthority() throws {
        let endpoint = "http://grpc.example.com/example.Service/Call"
        let package = makeTypedGRPCPackage(authority: nil, endpoint: endpoint)

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.request.url.absoluteString == endpoint)
    }

    @Test("Typed gRPC path endpoints keep their legacy default authority")
    func mapsTypedGRPCPathWithoutAuthority() throws {
        let package = makeTypedGRPCPackage(authority: nil)

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.request.url.absoluteString == "https://grpc.babylon/example.Service/Call")
    }

    @Test("Typed gRPC rejects an authority that conflicts with its absolute endpoint URL")
    func rejectsConflictingTypedGRPCAuthority() {
        let package = makeTypedGRPCPackage(
            authority: "other.example.com",
            endpoint: "https://grpc.example.com/example.Service/Call"
        )

        #expect(throws: BabylonCaptureMappingError.invalidURL) {
            try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        }
    }

    @Test("Typed gRPC rejects an authority port that conflicts with its absolute endpoint URL")
    func rejectsConflictingTypedGRPCAuthorityPort() {
        let package = makeTypedGRPCPackage(
            authority: "grpc.example.com:8444",
            endpoint: "https://grpc.example.com:8443/example.Service/Call"
        )

        #expect(throws: BabylonCaptureMappingError.invalidURL) {
            try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        }
    }

    @Test("Typed gRPC absolute endpoint URLs reject credentials and URL parameters")
    func rejectsUnsafeTypedGRPCAbsoluteEndpointURL() {
        for endpoint in [
            "https://user:secret@grpc.example.com/example.Service/Call",
            "https://grpc.example.com/example.Service/Call?debug=true",
            "https://grpc.example.com/example.Service/Call#fragment",
            "ftp://grpc.example.com/example.Service/Call",
            "https://grpc.example.com:invalid/example.Service/Call",
        ] {
            let package = makeTypedGRPCPackage(authority: nil, endpoint: endpoint)

            #expect(throws: BabylonCaptureMappingError.invalidURL) {
                try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
            }
        }
    }

    @Test("A GraphQL request from the SDK keeps its operation name")
    func labelsGraphQLOperation() throws {
        let package = BabylonTrafficPackageDTO(
            id: "graphql",
            startAt: 1,
            request: .init(
                url: "https://api.example.com/graphql",
                method: "POST",
                headers: [.init(key: "Content-Type", value: "application/json")],
                body: Data(#"{"operationName":"GetUser","query":"query GetUser { user { id } }"}"#.utf8)
            ),
            response: .init(statusCode: 200, headers: []),
            error: nil,
            responseBodyData: Data(#"{"data":{}}"#.utf8),
            endAt: 2,
            packageType: .http,
            correlationContext: nil,
            urlSessionTiming: nil,
            websocketMessagePackage: nil,
            grpcCapture: nil
        )

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.graphQLInfo?.operationName == "GetUser")
    }

    @Test("WebSocket package maps binary receive frame")
    func mapsWebSocketFrame() throws {
        let package = BabylonTrafficPackageDTO(
            id: "socket",
            startAt: 1,
            request: .init(url: "wss://example.com/socket", method: "GET", headers: [], body: nil),
            response: .init(statusCode: 101, headers: []),
            error: nil,
            responseBodyData: Data(),
            endAt: 2,
            packageType: .websocket,
            correlationContext: nil,
            urlSessionTiming: nil,
            websocketMessagePackage: .init(
                id: "socket",
                createdAt: 3,
                messageType: .receive,
                stringValue: nil,
                dataValue: Data([0x01, 0x02])
            ),
            grpcCapture: nil
        )

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        let frame = try BabylonCaptureMapper.makeWebSocketFrame(from: package)

        #expect(transaction.webSocketConnection != nil)
        #expect(frame.direction == .received)
        #expect(frame.opcode == .binary)
        #expect(frame.payload == Data([0x01, 0x02]))
    }

    @Test("Unsupported URL schemes are rejected")
    func rejectsUnsupportedScheme() {
        let package = makePackage(url: "file:///tmp/private")

        #expect(throws: BabylonCaptureMappingError.unsupportedScheme) {
            try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        }
    }

    @Test("WebSocket connection applies its payload limit atomically")
    func boundedWebSocketAppend() throws {
        let transaction = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(url: "wss://example.com/socket"),
            identity: identity
        )
        let connection = try #require(transaction.webSocketConnection)
        let first = WebSocketFrameData(direction: .received, opcode: .binary, payload: Data(repeating: 1, count: 3))
        let second = WebSocketFrameData(direction: .received, opcode: .binary, payload: Data(repeating: 2, count: 3))

        #expect(connection.addFrame(first, maximumTotalPayloadSize: 5))
        #expect(!connection.addFrame(second, maximumTotalPayloadSize: 5))
        #expect(connection.frameCount == 1)
        #expect(connection.totalPayloadSize == 3)
    }

    // MARK: Private

    private let identity = BabylonCaptureIdentity(
        clientID: "client",
        sessionID: "session",
        projectName: "Example",
        bundleIdentifier: "com.example.app",
        deviceName: "iPhone",
        deviceModel: "iPhone 17"
    )

    private func makePackage(
        url: String = "https://api.example.com/items",
        requestBody: Data? = Data("request".utf8),
        responseBody: Data = Data("response".utf8),
        websocketMessage: BabylonTrafficPackageDTO.WebSocketMessage? = nil,
        extraHeaders: [BabylonTrafficPackageDTO.Header] = [],
        correlation: BabylonTrafficPackageDTO.CorrelationContext? = nil,
        error: BabylonTrafficPackageDTO.CapturedError? = nil,
        urlSessionTiming: BabylonTrafficPackageDTO.URLSessionTiming? = nil
    )
        -> BabylonTrafficPackageDTO
    {
        BabylonTrafficPackageDTO(
            id: "request-1",
            startAt: 100,
            request: .init(
                url: url,
                method: "POST",
                headers: [.init(key: "Content-Type", value: "text/plain")] + extraHeaders,
                body: requestBody
            ),
            response: .init(statusCode: 201, headers: [.init(key: "Content-Type", value: "text/plain")]),
            error: error,
            responseBodyData: responseBody,
            endAt: 100.75,
            packageType: url.hasPrefix("ws") ? .websocket : .http,
            correlationContext: correlation,
            urlSessionTiming: urlSessionTiming,
            websocketMessagePackage: websocketMessage,
            grpcCapture: nil
        )
    }

    private func makeTypedGRPCPackage(
        authority: String? = "grpc.example.com",
        endpoint: String = "/example.Service/Call",
        messages: [BabylonTrafficPackageDTO.GRPCCapture.Message] = []
    )
        -> BabylonTrafficPackageDTO
    {
        BabylonTrafficPackageDTO(
            id: "grpc-test",
            startAt: 1,
            request: .init(url: endpoint, method: "POST", headers: [], body: nil),
            response: nil,
            error: nil,
            responseBodyData: Data(),
            endAt: 2,
            packageType: .grpc,
            correlationContext: nil,
            urlSessionTiming: nil,
            websocketMessagePackage: nil,
            grpcCapture: .init(
                schemaVersion: 1,
                endpoint: endpoint,
                authority: authority,
                service: "example.Service",
                method: "Call",
                callType: .unary,
                requestMetadata: [],
                responseMetadata: [],
                trailers: [],
                statusCode: nil,
                statusMessage: nil,
                requestCompression: nil,
                responseCompression: nil,
                messages: messages
            )
        )
    }
}
