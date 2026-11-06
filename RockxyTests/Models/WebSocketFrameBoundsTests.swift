import Foundation
@testable import Rockxy
import Testing

// Regression tests for the frame-count bound and the per-direction running totals.

@Suite("WebSocket capture bounds")
struct WebSocketFrameBoundsTests {
    // MARK: Internal

    @Test("A flood of tiny frames stops at the frame cap long before the byte cap")
    func frameFloodStopsAtFrameCap() {
        let connection = WebSocketConnection(upgradeRequest: Self.upgradeRequest())
        let tick = WebSocketFrameData(direction: .received, opcode: .text, payload: Data(repeating: 0x2A, count: 20))
        var accepted = 0
        // One more than the cap: the aggregate payload here is 20 bytes x 64, nowhere near
        // `maxWebSocketConnectionSize`, so only the count bound can stop this.
        for _ in 0 ... 64 {
            if connection.addFrame(tick, maximumTotalPayloadSize: 100 * 1_024 * 1_024, maximumFrameCount: 64) {
                accepted += 1
            }
        }

        #expect(accepted == 64)
        #expect(connection.frameCount == 64)
        #expect(connection.isCaptureLimitReached)
    }

    @Test("The product frame cap is the proxy's cap, so the Babylon path cannot outgrow it")
    func productFrameCapIsShared() {
        #expect(ProxyLimits.maxWebSocketFrameCount == 100_000)
    }

    @Test("Per-direction frame counts are running totals that match the captured frames")
    func perDirectionCountsMatchFrames() {
        let connection = WebSocketConnection(upgradeRequest: Self.upgradeRequest())
        for index in 0 ..< 7 {
            connection.addFrame(WebSocketFrameData(
                direction: index.isMultiple(of: 2) ? .sent : .received,
                opcode: .text,
                payload: Data(repeating: 0x01, count: 4)
            ))
        }

        #expect(connection.sentFrameCount == 4)
        #expect(connection.receivedFrameCount == 3)
        #expect(connection.sentFrameCount == connection.sentFrames.count)
        #expect(connection.receivedFrameCount == connection.receivedFrames.count)
        #expect(connection.sentPayloadSize == 16)
        #expect(connection.receivedPayloadSize == 12)
    }

    @Test("Seeded frames are counted by direction")
    func seededFramesAreCounted() {
        let connection = WebSocketConnection(
            upgradeRequest: Self.upgradeRequest(),
            frames: [
                WebSocketFrameData(direction: .sent, opcode: .text, payload: Data()),
                WebSocketFrameData(direction: .received, opcode: .text, payload: Data()),
                WebSocketFrameData(direction: .received, opcode: .text, payload: Data()),
            ]
        )

        #expect(connection.sentFrameCount == 1)
        #expect(connection.receivedFrameCount == 2)
    }

    @Test("A rejected frame leaves the per-direction counts untouched")
    func rejectedFramesDoNotCount() {
        let connection = WebSocketConnection(upgradeRequest: Self.upgradeRequest())
        let frame = WebSocketFrameData(direction: .sent, opcode: .text, payload: Data(repeating: 0x01, count: 4))

        #expect(connection.addFrame(frame, maximumTotalPayloadSize: 8, maximumFrameCount: 1))
        // Rejected by the count bound, then by the limit flag the first rejection set.
        #expect(!connection.addFrame(frame, maximumTotalPayloadSize: 8, maximumFrameCount: 1))
        #expect(!connection.addFrame(frame, maximumTotalPayloadSize: 8, maximumFrameCount: 10))

        #expect(connection.sentFrameCount == 1)
        #expect(connection.receivedFrameCount == 0)
        #expect(connection.frameCount == 1)
        #expect(connection.sentPayloadSize == 4)
    }

    // MARK: Private

    private static func upgradeRequest() -> HTTPRequestData {
        guard let url = URL(string: "wss://example.com/socket") else {
            preconditionFailure("Expected valid fixture URL")
        }
        return HTTPRequestData(
            method: "GET",
            url: url,
            httpVersion: "HTTP/1.1",
            headers: [],
            body: nil,
            contentType: nil
        )
    }
}
