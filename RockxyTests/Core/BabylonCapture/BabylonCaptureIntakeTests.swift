import Foundation
@testable import Rockxy
import Testing

@Suite("Babylon capture intake")
struct BabylonCaptureIntakeTests {
    // MARK: Internal

    @Test("A gRPC call from the SDK is rebuilt as a framed HTTP/2 gRPC exchange")
    func mapsGRPCCall() throws {
        let package = makePackage(
            url: "/helloworld.Greeter/SayHello",
            method: "GRPC",
            requestHeaders: [.init(key: ":authority", value: "api.example.com")],
            requestBody: Data([0x0A, 0x03, 0x42, 0x6F, 0x62]),
            response: .init(statusCode: 200, headers: [
                .init(key: "success", value: "false"),
                .init(key: "statusCode", value: "notFound (code=5)"),
                .init(key: "statusMessage", value: "user missing"),
                .init(key: "x-request-id", value: "abc"),
            ]),
            responseBody: Data(),
            packageType: .grpc
        )

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.request.method == "POST")
        #expect(transaction.request.url.absoluteString == "https://api.example.com/helloworld.Greeter/SayHello")
        #expect(transaction.request.headers.contains { $0.name == "content-type" && $0.value == "application/grpc" })
        #expect(!transaction.request.headers.contains { $0.name.hasPrefix(":") })
        #expect(transaction.request.body == Data([0, 0, 0, 0, 5, 0x0A, 0x03, 0x42, 0x6F, 0x62]))
        let response = try #require(transaction.response)
        #expect(response.trailers?.first { $0.name == "grpc-status" }?.value == "5")
        #expect(response.trailers?.first { $0.name == "grpc-message" }?.value == "user missing")
        #expect(response.headers.contains { $0.name == "x-request-id" })
        #expect(!response.headers.contains { $0.name.lowercased() == "statuscode" })
        #expect(transaction.serverHTTPVersion == "2")
    }

    @Test("Method GRPC is treated as gRPC even when an older SDK labels it HTTP")
    func methodMarksGRPC() {
        let package = makePackage(url: "/svc.Echo/Ping", method: "grpc", packageType: .http)
        #expect(BabylonCaptureMapper.isGRPC(package))
    }

    @Test("gRPC status descriptions parse to their numeric code", arguments: [
        ("notFound (code=5)", 5),
        ("0", 0),
        ("unavailable (code=14)", 14),
    ])
    func parsesGRPCStatus(description: String, expected: Int) {
        #expect(BabylonCaptureMapper.grpcStatusCode(from: description) == expected)
    }

    @Test("An unparseable gRPC status yields no code")
    func rejectsUnparseableGRPCStatus() {
        #expect(BabylonCaptureMapper.grpcStatusCode(from: "unknown") == nil)
    }

    @Test("A body the SDK skipped is shown as omitted, not as the marker text")
    func omittedBodyIsNotShownAsContent() throws {
        let package = makePackage(responseBody: BabylonCaptureMapper.omittedBodyMarker)

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.response?.body == nil)
        #expect(transaction.response?.bodyTruncated == true)
    }

    @Test("An error the app reported is kept with its code and message")
    func appReportedErrorIsKept() throws {
        let package = makePackage(error: .init(code: -1_001, message: "The request timed out."))

        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)

        #expect(transaction.state == .failed)
        let failure = try #require(transaction.connectionLog?.failure)
        #expect(failure.message == "The app reported error -1001: The request timed out.")
        #expect(transaction.connectionLog?.host == "api.example.com")
        #expect(transaction.connectionLog?.port == 443)
    }

    @Test("A package type from a newer SDK is skipped, not mis-shown")
    func unknownPackageTypeIsRejected() throws {
        let json = Data(#""streamingRPC""#.utf8)
        let type = try JSONDecoder().decode(BabylonTrafficPackageDTO.PackageType.self, from: json)
        #expect(type == .unknown)

        #expect(throws: BabylonCaptureMappingError.unsupportedPackage) {
            try BabylonCaptureMapper.makeTransaction(from: makePackage(packageType: .unknown), identity: identity)
        }
    }

    @Test("An unknown WebSocket message type decodes instead of failing the frame")
    func unknownMessageTypeDecodes() throws {
        let json = Data(#"{"id":"m","createdAt":1,"messageType":"fragment"}"#.utf8)
        let message = try JSONDecoder().decode(BabylonTrafficPackageDTO.WebSocketMessage.self, from: json)
        #expect(message.messageType == .unknown)
        #expect(message.closeCode == nil)
    }

    @Test("Ping and pong keep their direction and control opcode")
    func mapsPingPong() throws {
        let ping = try BabylonCaptureMapper.makeWebSocketFrame(
            from: makeSocketPackage(.init(
                id: "m",
                createdAt: 1,
                messageType: .ping,
                stringValue: nil,
                dataValue: Data([1])
            ))
        )
        let pong = try BabylonCaptureMapper.makeWebSocketFrame(
            from: makeSocketPackage(.init(
                id: "m",
                createdAt: 1,
                messageType: .pong,
                stringValue: nil,
                dataValue: Data([1])
            ))
        )

        #expect(ping.direction == .sent)
        #expect(ping.opcode == .ping)
        #expect(pong.direction == .received)
        #expect(pong.opcode == .pong)
        #expect(pong.payload == Data([1]))
    }

    @Test("A received close frame carries its status code and reason as on the wire")
    func mapsReceivedClose() throws {
        let frame = try BabylonCaptureMapper.makeWebSocketFrame(
            from: makeSocketPackage(.init(
                id: "m",
                createdAt: 1,
                messageType: .receiveCloseMessage,
                stringValue: nil,
                dataValue: nil,
                closeCode: 1_001,
                closeReason: "going away"
            ))
        )

        #expect(frame.direction == .received)
        #expect(frame.opcode == .connectionClose)
        #expect(frame.payload == Data([0x03, 0xE9]) + Data("going away".utf8))
    }

    @Test("An open WebSocket stays active until the SDK reports its end")
    @MainActor
    func webSocketLifecycleUpdates() throws {
        let open = makePackage(url: "wss://example.com/socket", endAt: nil, packageType: .websocket)
        let transaction = try BabylonCaptureMapper.makeTransaction(from: open, identity: identity)
        #expect(transaction.state == .active)

        let closed = makePackage(url: "wss://example.com/socket", endAt: 105, packageType: .websocket)
        try BabylonCaptureMapper.applyUpdate(closed, to: transaction)

        #expect(transaction.state == .completed)
        #expect(transaction.measuredDuration == 5)
    }

    @Test("A finished row is not reopened or changed by a late update")
    @MainActor
    func lateUpdateDoesNotChangeFinishedRow() throws {
        let transaction = try BabylonCaptureMapper.makeTransaction(from: makePackage(), identity: identity)
        let late = makePackage(error: .init(code: 1, message: "late"))

        try BabylonCaptureMapper.applyUpdate(late, to: transaction)

        #expect(transaction.state == .completed)
        #expect(transaction.connectionLog == nil)
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
        method: String = "GET",
        requestHeaders: [BabylonTrafficPackageDTO.Header] = [],
        requestBody: Data? = nil,
        response: BabylonTrafficPackageDTO.Response? = .init(statusCode: 200, headers: []),
        responseBody: Data = Data("ok".utf8),
        error: BabylonTrafficPackageDTO.CapturedError? = nil,
        endAt: TimeInterval? = 100.5,
        packageType: BabylonTrafficPackageDTO.PackageType = .http
    )
        -> BabylonTrafficPackageDTO
    {
        BabylonTrafficPackageDTO(
            id: "request-1",
            startAt: 100,
            request: .init(url: url, method: method, headers: requestHeaders, body: requestBody),
            response: response,
            error: error,
            responseBodyData: responseBody,
            endAt: endAt,
            packageType: packageType,
            correlationContext: nil,
            websocketMessagePackage: nil,
            grpcCapture: nil
        )
    }

    private func makeSocketPackage(_ message: BabylonTrafficPackageDTO.WebSocketMessage) -> BabylonTrafficPackageDTO {
        BabylonTrafficPackageDTO(
            id: "socket",
            startAt: 1,
            request: .init(url: "wss://example.com/socket", method: "GET", headers: [], body: nil),
            response: .init(statusCode: 101, headers: []),
            error: nil,
            responseBodyData: Data(),
            endAt: nil,
            packageType: .websocket,
            correlationContext: nil,
            websocketMessagePackage: message,
            grpcCapture: nil
        )
    }
}
