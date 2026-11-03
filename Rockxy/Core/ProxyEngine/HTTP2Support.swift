import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOHTTP2
import NIOSSL
import NIOTLS
import os

nonisolated(unsafe) private let http2Logger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "HTTP2"
)

// MARK: - HTTP2ProxyOptions

/// Whether decrypted HTTPS connections may negotiate HTTP/2. Off by default; read for each new
/// connection, so changing it affects the next connection without restarting the proxy.
/// Each side negotiates on its own: a client can speak HTTP/2 to Rockxy while the server
/// answers over HTTP/1.1, and the other way around.
nonisolated enum HTTP2ProxyOptions {
    // MARK: Internal

    static let defaultsKey = RockxyIdentity.current.defaultsKey("proxy.useHTTP2")
    static let h2 = "h2"
    static let alpnProtocols = ["h2", "http/1.1"]

    /// Answered from a cached snapshot. `TLSInterceptHandler` reaches this through a default
    /// argument and `HTTPSProxyRelayHandler` through `offersHTTP2Upstream(for:)`, both once
    /// per intercepted connection on a NIO event-loop thread. `UserDefaults` serves from the
    /// in-process CFPreferences cache, so this was never a disk read, but it is a lock
    /// acquisition plus a keyed lookup taken concurrently from several event loops.
    ///
    /// The snapshot is invalidated on `UserDefaults.didChangeNotification` so the setting
    /// still applies to the next connection without restarting the proxy, as the type
    /// comment promises. Residual: a connection whose ALPN offer is already being built
    /// negotiates under the old value, and a write from another process is seen when that
    /// change is noticed rather than at the write. The worst case is one connection speaking
    /// the protocol the user just turned off (or staying on HTTP/1.1 just after turning
    /// HTTP/2 on); both are protocols Rockxy intercepts either way, so nothing is dropped.
    static var isEnabled: Bool {
        if let forced = override.withLockedValue({ $0 }) {
            return forced
        }
        if let cached = enabledCache.withLockedValue({ $0 }) {
            return cached
        }
        let value = UserDefaults.standard.bool(forKey: defaultsKey)
        enabledCache.withLockedValue { $0 = value }
        return value
    }

    /// Whether the origin connection for `head` may offer HTTP/2. A request that asks to
    /// switch protocols (a WebSocket handshake) only works over HTTP/1.1, so offering h2
    /// for it would let the origin pick a protocol that cannot upgrade and answer 200.
    static func offersHTTP2Upstream(for head: HTTPRequestHead) -> Bool {
        isEnabled && !head.headers.contains(name: "Upgrade")
    }

    /// Test seam so loopback tests never write the app's shared defaults.
    static func setOverride(_ value: Bool?) {
        override.withLockedValue { $0 = value }
    }

    // MARK: Private

    private static let override = NIOLockedValueBox<Bool?>(nil)

    /// The toggle as the connection path last read it; `nil` means it has to be read again.
    /// The box and its observer live for the process, so the observer is never removed --
    /// unlike `ScriptPluginManager`, which has one observer per instance and has to.
    private static let enabledCache: NIOLockedValueBox<Bool?> = {
        let cache = NIOLockedValueBox<Bool?>(nil)
        _ = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            cache.withLockedValue { $0 = nil }
        }
        return cache
    }()
}

// MARK: - UpstreamHTTPChannelConnector

/// Opens a TLS connection to the origin offering `h2` and `http/1.1`, then hands back the
/// channel that carries `HTTPClientRequestPart`/`HTTPClientResponsePart`: the connection
/// itself for HTTP/1.1, or a single HTTP/2 stream that closes its connection when it ends.
nonisolated enum UpstreamHTTPChannelConnector {
    // MARK: Internal

    struct Connection {
        let channel: Channel
        let negotiatedProtocol: String?
    }

    /// Returns the channel carrying HTTP/1-style client parts. Without HTTP/2 the TLS handshake
    /// runs behind HTTP/1.1 codecs as before, so handshake failures still reach the response
    /// handler that reports them; with HTTP/2 the channel is handed back once ALPN settles.
    static func connect(
        eventLoop: EventLoop,
        host: String,
        sslContext: NIOSSLContext,
        offersHTTP2: Bool,
        connect: (@escaping @Sendable (Channel) -> EventLoopFuture<Void>) -> EventLoopFuture<Channel>
    )
        -> EventLoopFuture<Channel>
    {
        guard offersHTTP2 else {
            return connect { channel in
                do {
                    let sslHandler = try NIOSSLClientHandler(
                        context: sslContext,
                        serverHostname: TLSServerName.sni(for: host)
                    )
                    return channel.pipeline.addHandler(sslHandler).flatMap {
                        channel.pipeline.addHTTPClientHandlers(leftOverBytesStrategy: .forwardBytes)
                    }
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
        }

        let ready = NIOLockedValueBox<EventLoopPromise<Connection>?>(nil)
        let handshakeError = UpstreamTLSHandshakeErrorStorage()
        return connect { channel in
            let promise = channel.eventLoop.makePromise(of: Connection.self)
            ready.withLockedValue { $0 = promise }
            // A failed handshake closes the connection before ALPN completes. Keep the
            // original TLS error so the caller can distinguish trust failures from a close.
            channel.closeFuture.whenComplete { _ in
                promise.fail(handshakeError.error ?? ChannelError.alreadyClosed)
            }
            do {
                let sslHandler = try NIOSSLClientHandler(
                    context: sslContext,
                    serverHostname: TLSServerName.sni(for: host)
                )
                let handshakeCapture = UpstreamTLSHandshakeErrorCaptureHandler(storage: handshakeError)
                let alpn = ApplicationProtocolNegotiationHandler { result, channel in
                    configure(channel: channel, result: result, promise: promise)
                }
                return channel.pipeline.addHandlers([sslHandler, handshakeCapture, alpn])
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }.flatMap { _ in
            guard let promise = ready.withLockedValue({ $0 }) else {
                return eventLoop.makeFailedFuture(ChannelError.inappropriateOperationForState)
            }
            return promise.futureResult.map(\.channel)
        }
    }

    // MARK: Private

    private static func configure(
        channel: Channel,
        result: ALPNResult,
        promise: EventLoopPromise<Connection>
    )
        -> EventLoopFuture<Void>
    {
        if let probe = UpstreamConnectionProbe.find(on: channel) {
            probe.tlsHandshakeCompletedAt = .now()
            if case let .negotiated(name) = result {
                probe.negotiatedProtocol = name
            }
        }
        guard case .negotiated(HTTP2ProxyOptions.h2) = result else {
            return channel.pipeline.addHTTPClientHandlers(leftOverBytesStrategy: .forwardBytes).map {
                promise.succeed(Connection(channel: channel, negotiatedProtocol: nil))
            }
        }
        return channel.configureHTTP2Pipeline(mode: .client, inboundStreamInitializer: nil).flatMap { multiplexer in
            multiplexer.createStreamChannel { stream in
                stream.pipeline.addHandler(HTTP2FramePayloadToHTTP1ClientCodec(httpProtocol: .https))
            }
        }.map { stream in
            // One request per upstream connection: closing the stream retires the connection.
            stream.closeFuture.whenComplete { _ in
                channel.close(promise: nil)
            }
            http2Logger.debug("Upstream negotiated HTTP/2")
            promise.succeed(Connection(channel: stream, negotiatedProtocol: HTTP2ProxyOptions.h2))
        }
    }
}

// MARK: - UpstreamTLSHandshakeErrorStorage

private final class UpstreamTLSHandshakeErrorStorage: @unchecked Sendable {
    // MARK: Internal

    var error: Error? {
        value.withLockedValue { $0 }
    }

    func record(_ error: Error) {
        value.withLockedValue { storedError in
            if storedError == nil {
                storedError = error
            }
        }
    }

    // MARK: Private

    private let value = NIOLockedValueBox<Error?>(nil)
}

// MARK: - UpstreamTLSHandshakeErrorCaptureHandler

private final class UpstreamTLSHandshakeErrorCaptureHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(storage: UpstreamTLSHandshakeErrorStorage) {
        self.storage = storage
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        storage.record(error)
        context.fireErrorCaught(error)
    }

    // MARK: Private

    private let storage: UpstreamTLSHandshakeErrorStorage
}

// MARK: - HTTP2ServerPipeline

nonisolated enum HTTP2ServerPipeline {
    /// Replaces HTTP/1 handling on a decrypted client connection with an HTTP/2 connection whose
    /// streams each get an HTTP/1-style codec and their own relay, so every stream is one row.
    static func configure(
        channel: Channel,
        makeRelay: @escaping @Sendable () -> ChannelHandler
    )
        -> EventLoopFuture<Void>
    {
        channel.configureHTTP2Pipeline(mode: .server, inboundStreamInitializer: { stream in
            stream.pipeline.addHandlers([HTTP2FramePayloadToHTTP1ServerCodec(), makeRelay()])
        }).map { _ in }
    }
}
