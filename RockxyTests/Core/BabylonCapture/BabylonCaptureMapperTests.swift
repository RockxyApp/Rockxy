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
            websocketMessagePackage: .init(
                id: "socket",
                createdAt: 3,
                messageType: .receive,
                stringValue: nil,
                dataValue: Data([0x01, 0x02])
            )
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

    private func makePackage(url: String = "https://api.example.com/items") -> BabylonTrafficPackageDTO {
        BabylonTrafficPackageDTO(
            id: "request-1",
            startAt: 100,
            request: .init(
                url: url,
                method: "POST",
                headers: [.init(key: "Content-Type", value: "text/plain")],
                body: Data("request".utf8)
            ),
            response: .init(statusCode: 201, headers: [.init(key: "Content-Type", value: "text/plain")]),
            error: nil,
            responseBodyData: Data("response".utf8),
            endAt: 100.75,
            packageType: url.hasPrefix("ws") ? .websocket : .http,
            correlationContext: nil,
            websocketMessagePackage: nil
        )
    }
}
