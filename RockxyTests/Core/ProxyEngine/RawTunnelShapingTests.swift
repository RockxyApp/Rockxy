import NIOCore
import NIOEmbedded
@testable import Rockxy
import Testing

// An undecrypted CONNECT tunnel is shaped as a byte stream: bandwidth-capped, delayed, and
// never reordered.

struct RawTunnelShapingTests {
    @Test("A bandwidth-capped tunnel delivers every byte in order, paced over time")
    func cappedTunnelPacesAndKeepsOrder() throws {
        let peer = EmbeddedChannel()
        let source = EmbeddedChannel(handler: RawTunnelHandler(peerChannel: peer, bytesPerSecond: 10_000))
        defer { _ = try? source.finish(); _ = try? peer.finish() }

        let payload = (0 ..< 20_000).map { UInt8($0 % 251) }
        try source.writeInbound(ByteBuffer(bytes: payload))
        source.embeddedEventLoop.advanceTime(by: .milliseconds(100))
        peer.embeddedEventLoop.advanceTime(by: .milliseconds(100))

        var received: [UInt8] = []
        func drain() throws {
            while let chunk = try peer.readOutbound(as: ByteBuffer.self) {
                received.append(contentsOf: chunk.readableBytesView)
            }
        }
        try drain()
        #expect(received.count < payload.count)

        source.embeddedEventLoop.advanceTime(by: .seconds(4))
        try drain()
        #expect(received == payload)
    }

    @Test("An unshaped tunnel relays immediately")
    func unshapedTunnelRelaysImmediately() throws {
        let peer = EmbeddedChannel()
        let source = EmbeddedChannel(handler: RawTunnelHandler(peerChannel: peer))
        defer { _ = try? source.finish(); _ = try? peer.finish() }

        try source.writeInbound(ByteBuffer(bytes: [1, 2, 3]))
        let out = try peer.readOutbound(as: ByteBuffer.self)
        #expect(out?.readableBytes == 3)
    }

    @Test("Latency delays the first forwarded bytes")
    func latencyDelaysForwarding() throws {
        let peer = EmbeddedChannel()
        let source = EmbeddedChannel(handler: RawTunnelHandler(peerChannel: peer, latencyMs: 300))
        defer { _ = try? source.finish(); _ = try? peer.finish() }

        try source.writeInbound(ByteBuffer(bytes: [9]))
        #expect(try peer.readOutbound(as: ByteBuffer.self) == nil)
        source.embeddedEventLoop.advanceTime(by: .milliseconds(400))
        #expect(try peer.readOutbound(as: ByteBuffer.self)?.readableBytes == 1)
    }
}
