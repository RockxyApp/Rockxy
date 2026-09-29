import Foundation
import NIOCore
import NIOHTTP1
import NIOSSL
import NIOWebSocket

/// Factory methods for assembling NIO channel pipelines used throughout the proxy.
/// Centralizes pipeline construction so that handler ordering (TLS -> HTTP codecs ->
/// application handler) stays consistent across plain HTTP, HTTPS intercept, and
/// WebSocket upgrade paths.
nonisolated enum ProxyPipeline {
    // MARK: Internal

    // MARK: - HTTP

    nonisolated static func configureHTTPPipeline(
        channel: Channel,
        handler: some ChannelHandler & Sendable
    )
        -> EventLoopFuture<Void>
    {
        configureHTTPServerHandlers(channel: channel).flatMap {
            channel.pipeline.addHandler(handler)
        }
    }

    // MARK: - TLS

    /// Installs NIOSSLServerHandler first so that all subsequent HTTP codec
    /// operations happen on the decrypted byte stream.
    nonisolated static func configureTLSPipeline(
        channel: Channel,
        sslContext: NIOSSLContext,
        handler: some ChannelHandler & Sendable
    )
        -> EventLoopFuture<Void>
    {
        let sslHandler = NIOSSLServerHandler(context: sslContext)
        return channel.pipeline.addHandler(sslHandler).flatMap {
            configureHTTPServerHandlers(channel: channel)
        }.flatMap {
            channel.pipeline.addHandler(handler)
        }
    }

    // MARK: - Pipeline Teardown

    /// Removes all handlers added by `configureHTTPServerPipeline()`.
    /// Must be called before transitioning a channel from HTTP mode to raw
    /// byte mode (e.g., for CONNECT tunnels and TLS interception).
    nonisolated static func removeHTTPServerPipeline(
        from pipeline: ChannelPipeline,
        on eventLoop: EventLoop
    )
        -> EventLoopFuture<Void>
    {
        func removeIfPresent(_ type: (some RemovableChannelHandler).Type) -> EventLoopFuture<Void> {
            pipeline.context(handlerType: type).flatMap {
                pipeline.removeHandler(context: $0)
            }.flatMapError { _ in
                eventLoop.makeSucceededVoidFuture()
            }
        }

        return removeIfPresent(ReverseProxyRequestRewriter.self)
            .flatMap { removeIfPresent(HTTPServerProtocolErrorHandler.self) }
            .flatMap { removeIfPresent(NIOHTTPResponseHeadersValidator.self) }
            .flatMap { removeIfPresent(HTTPServerPipelineHandler.self) }
            .flatMap { removeIfPresent(ByteToMessageHandler<HTTPRequestDecoder>.self) }
            .flatMap { removeIfPresent(HTTPResponseEncoder.self) }
    }

    // MARK: - WebSocket

    /// Replaces HTTP codecs with WebSocket frame decoder/encoder for upgraded connections.
    nonisolated static func configureClientWebSocketPipeline(
        channel: Channel,
        handler: some ChannelHandler & Sendable
    )
        -> EventLoopFuture<Void>
    {
        configureWebSocketPipeline(channel: channel, handler: handler).flatMap {
            removeClientHTTPHandlers(from: channel.pipeline, on: channel.eventLoop)
        }
    }

    nonisolated static func configureUpstreamWebSocketPipeline(
        channel: Channel,
        handler: some ChannelHandler & Sendable
    )
        -> EventLoopFuture<Void>
    {
        configureWebSocketPipeline(channel: channel, handler: handler).flatMap {
            removeUpstreamHTTPHandlers(from: channel.pipeline, on: channel.eventLoop)
        }
    }

    // MARK: Private

    nonisolated private static func configureHTTPServerHandlers(
        channel: Channel
    )
        -> EventLoopFuture<Void>
    {
        let responseEncoder = HTTPResponseEncoder()
        let requestDecoder = ByteToMessageHandler(
            HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)
        )
        return channel.pipeline.addHandler(responseEncoder).flatMap {
            channel.pipeline.addHandler(requestDecoder)
        }.flatMap {
            channel.pipeline.addHandler(HTTPServerPipelineHandler())
        }.flatMap {
            channel.pipeline.addHandler(NIOHTTPResponseHeadersValidator())
        }.flatMap {
            channel.pipeline.addHandler(HTTPServerProtocolErrorHandler())
        }
    }

    nonisolated private static func configureWebSocketPipeline(
        channel: Channel,
        handler: some ChannelHandler & Sendable
    )
        -> EventLoopFuture<Void>
    {
        let decoder = ByteToMessageHandler(WebSocketFrameDecoder())
        let encoder = WebSocketFrameEncoder()
        return channel.pipeline.addHandler(decoder).flatMap {
            channel.pipeline.addHandler(encoder)
        }.flatMap {
            channel.pipeline.addHandler(handler)
        }
    }

    nonisolated private static func removeClientHTTPHandlers(
        from pipeline: ChannelPipeline,
        on eventLoop: EventLoop
    )
        -> EventLoopFuture<Void>
    {
        func removeIfPresent(_ type: (some RemovableChannelHandler).Type) -> EventLoopFuture<Void> {
            pipeline.context(handlerType: type).flatMap {
                pipeline.removeHandler(context: $0)
            }.flatMapError { _ in
                eventLoop.makeSucceededVoidFuture()
            }
        }

        // The reverse/SOCKS request rewriter only understands HTTP request parts; it must
        // leave with the HTTP layer or raw WebSocket bytes would reach it after an upgrade.
        return removeIfPresent(ReverseProxyRequestRewriter.self)
            .flatMap { removeIfPresent(HTTPProxyHandler.self) }
            .flatMap { removeIfPresent(HTTPSProxyRelayHandler.self) }
            .flatMap { removeIfPresent(HTTPServerProtocolErrorHandler.self) }
            .flatMap { removeIfPresent(NIOHTTPResponseHeadersValidator.self) }
            .flatMap { removeIfPresent(HTTPServerPipelineHandler.self) }
            .flatMap { removeIfPresent(HTTPResponseEncoder.self) }
            .flatMap { removeIfPresent(ByteToMessageHandler<HTTPRequestDecoder>.self) }
    }

    nonisolated private static func removeUpstreamHTTPHandlers(
        from pipeline: ChannelPipeline,
        on eventLoop: EventLoop
    )
        -> EventLoopFuture<Void>
    {
        func removeIfPresent(_ type: (some RemovableChannelHandler).Type) -> EventLoopFuture<Void> {
            pipeline.context(handlerType: type).flatMap {
                pipeline.removeHandler(context: $0)
            }.flatMapError { _ in
                eventLoop.makeSucceededVoidFuture()
            }
        }

        return removeIfPresent(UpstreamResponseHandler.self)
            .flatMap { removeIfPresent(NIOHTTPRequestHeadersValidator.self) }
            .flatMap { removeIfPresent(HTTPRequestEncoder.self) }
            .flatMap { removeIfPresent(ByteToMessageHandler<HTTPResponseDecoder>.self) }
    }
}
