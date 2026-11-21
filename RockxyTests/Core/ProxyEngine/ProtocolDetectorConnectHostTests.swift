import Foundation
import NIOCore
import NIOEmbedded
import NIOSSL
@testable import Rockxy
import Testing

// MARK: - DialledHostBox

private final class DialledHostBox: @unchecked Sendable {
    // MARK: Internal

    private(set) var host: String?

    func record(_ host: String) {
        lock.lock()
        self.host = host
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
}

// MARK: - ProtocolDetectorConnectHostTests

/// The protocol detector's raw-tunnel fallback used to dial the request's own host while every
/// other upstream connection went through `UpstreamConnectHost.resolve`, so an Android emulator's
/// `10.0.2.2` was mapped back to loopback everywhere except this one path.
///
/// `@MainActor` because `SSLProxyingManager` is a main-actor type, which is how the other
/// suites that build one are written.
@MainActor
struct ProtocolDetectorConnectHostTests {
    // MARK: Internal

    @Test("raw tunnel fallback dials the resolved connect host rather than the request host")
    func rawFallbackDialsResolvedConnectHost() throws {
        let dialled = DialledHostBox()
        let channel = try makeDetectorChannel(
            host: "10.0.2.2",
            connectHost: "127.0.0.1",
            dialled: dialled
        )

        try writeUnknownProtocolPreface(to: channel.channel)
        channel.loop.run()

        #expect(dialled.host == "127.0.0.1")
        _ = try? channel.channel.finish()
    }

    @Test("raw tunnel fallback keeps the request host when no connect host is resolved")
    func rawFallbackDefaultsToRequestHost() throws {
        let dialled = DialledHostBox()
        let channel = try makeDetectorChannel(
            host: "example.com",
            connectHost: nil,
            dialled: dialled
        )

        try writeUnknownProtocolPreface(to: channel.channel)
        channel.loop.run()

        #expect(dialled.host == "example.com")
        _ = try? channel.channel.finish()
    }

    // MARK: Private

    private func makeDetectorChannel(
        host: String,
        connectHost: String?,
        dialled: DialledHostBox
    )
        throws -> (channel: EmbeddedChannel, loop: EmbeddedEventLoop)
    {
        let loop = EmbeddedEventLoop()
        let channel = EmbeddedChannel(handlers: [], loop: loop)
        let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
        let sslHandler = NIOSSLServerHandler(context: sslContext)
        let postHandshake = PostHandshakeHandler(
            host: host,
            port: 443,
            ruleEngine: RuleEngine(),
            scriptPluginManager: nil,
            connectionLimiter: ConnectionLimiter(),
            sslProxyingManager: makeSSLProxyingManager(),
            onTransactionComplete: { _ in }
        )
        let detector = ProtocolDetectorHandler(
            sslHandler: sslHandler,
            host: host,
            port: 443,
            postHandshake: postHandshake,
            connectionLimiter: ConnectionLimiter(),
            rawTunnelConnector: { eventLoop, dialledHost, _, _ in
                dialled.record(dialledHost)
                // The connect itself is irrelevant here: the assertion is which address the
                // detector asked for.
                return eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel)
            },
            connectHost: connectHost
        )
        try channel.pipeline.syncOperations.addHandlers(detector, sslHandler, postHandshake)
        return (channel, loop)
    }

    /// Neither a TLS record content type nor an HTTP/1.x request line, so the detector takes its
    /// raw-tunnel fallback.
    private func writeUnknownProtocolPreface(to channel: EmbeddedChannel) throws {
        var preface = channel.allocator.buffer(capacity: 4)
        preface.writeBytes([0x00, 0x01, 0x02, 0x03])
        try channel.writeInbound(preface)
    }

    private func makeSSLProxyingManager() -> SSLProxyingManager {
        SSLProxyingManager(
            storageURL: makeTempURL(prefix: "rockxy-detector-connect-host-ssl"),
            passthroughStorageURL: makeTempURL(prefix: "rockxy-detector-connect-host-passthrough")
        )
    }

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }
}
