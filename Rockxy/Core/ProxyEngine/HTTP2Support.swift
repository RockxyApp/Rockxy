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

    static var isEnabled: Bool {
        if let forced = override.withLockedValue({ $0 }) {
            return forced
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Test seam so loopback tests never write the app's shared defaults.
    static func setOverride(_ value: Bool?) {
        override.withLockedValue { $0 = value }
    }

    // MARK: Private

    private static let override = NIOLockedValueBox<Bool?>(nil)
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
                    let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                    return channel.pipeline.addHandler(sslHandler).flatMap {
                        channel.pipeline.addHTTPClientHandlers(leftOverBytesStrategy: .forwardBytes)
                    }
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
        }

        let ready = NIOLockedValueBox<EventLoopPromise<Connection>?>(nil)
        return connect { channel in
            let promise = channel.eventLoop.makePromise(of: Connection.self)
            ready.withLockedValue { $0 = promise }
            // A failed handshake closes the connection before ALPN completes.
            channel.closeFuture.whenComplete { _ in
                promise.fail(ChannelError.alreadyClosed)
            }
            do {
                let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                let alpn = ApplicationProtocolNegotiationHandler { result, channel in
                    configure(channel: channel, result: result, promise: promise)
                }
                return channel.pipeline.addHandlers([sslHandler, alpn])
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

    private static func configure(
        channel: Channel,
        result: ALPNResult,
        promise: EventLoopPromise<Connection>
    )
        -> EventLoopFuture<Void>
    {
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
