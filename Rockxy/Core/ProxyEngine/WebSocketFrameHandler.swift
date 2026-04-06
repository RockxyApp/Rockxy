import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import os

// Defines `WebSocketFrameHandler`, which handles web socket frame flow in the proxy
// engine.

private nonisolated(unsafe) let wsLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "WebSocketFrameHandler"
)

// MARK: - WebSocketDetector

/// Detects WebSocket upgrade requests by inspecting HTTP headers per RFC 6455.
nonisolated enum WebSocketDetector {
    nonisolated static func isWebSocketUpgrade(headers: HTTPHeaders) -> Bool {
        let hasUpgrade = headers.contains(name: "Upgrade") &&
            headers["Upgrade"].contains(where: { $0.lowercased() == "websocket" })
        let hasConnection = headers.contains(name: "Connection") &&
            headers["Connection"].contains(where: { $0.lowercased().contains("upgrade") })
        return hasUpgrade && hasConnection
    }
}

// MARK: - WebSocketFrameHandler

/// Captures and relays WebSocket frames in one direction (client->server or server->client).
/// Each upgraded WebSocket connection uses two instances — one per direction — sharing
/// the same `WebSocketConnection` model to collect all frames for inspection.
final class WebSocketFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        direction: FrameDirection,
        peerChannel: Channel?,
        webSocketConnection: WebSocketConnection,
        parentTransaction: HTTPTransaction,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        self.direction = direction
        self.peerChannel = peerChannel
        self.webSocketConnection = webSocketConnection
        self.parentTransaction = parentTransaction
        self.onTransactionComplete = onTransactionComplete
    }

    // MARK: Internal

    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        captureFrame(frame, context: context)
        forwardFrame(frame, context: context)
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        wsLogger.error("WebSocket error (\(self.direction.rawValue)): \(error.localizedDescription)")
        peerChannel?.close(promise: nil)
        context.close(promise: nil)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        peerChannel?.close(promise: nil)
        onTransactionComplete(parentTransaction)
    }

    // MARK: Private

    private let direction: FrameDirection
    private let peerChannel: Channel?
    private let webSocketConnection: WebSocketConnection
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let parentTransaction: HTTPTransaction

    /// Unmasks the frame payload (WebSocket client frames are always masked per RFC 6455)
    /// and records it in the shared connection model before forwarding.
    private nonisolated func captureFrame(
        _ frame: WebSocketFrame,
        context: ChannelHandlerContext
    ) {
        let opcode = mapOpcode(frame.opcode)
        var dataBuffer = frame.unmaskedData
        let payloadBytes = dataBuffer.readBytes(length: dataBuffer.readableBytes) ?? []
        let payload = Data(payloadBytes)

        guard payload.count <= ProxyLimits.maxWebSocketFrameSize else {
            wsLogger.warning("SECURITY: WebSocket frame exceeds \(ProxyLimits.maxWebSocketFrameSize) bytes, closing")
            context.close(promise: nil)
            return
        }
        guard webSocketConnection.totalPayloadSize + payload.count <= ProxyLimits.maxWebSocketConnectionSize else {
            wsLogger.warning("SECURITY: WebSocket connection exceeds total payload limit, closing")
            context.close(promise: nil)
            return
        }

        let frameData = WebSocketFrameData(
            direction: direction,
            opcode: opcode,
            payload: payload,
            isFinal: frame.fin
        )

        webSocketConnection.addFrame(frameData)

        let transaction = parentTransaction
        Task { @MainActor in
            transaction.webSocketFrameVersion += 1
        }
    }

    private nonisolated func forwardFrame(
        _ frame: WebSocketFrame,
        context: ChannelHandlerContext
    ) {
        guard let peer = peerChannel else {
            return
        }
        peer.writeAndFlush(NIOAny(frame), promise: nil)
    }

    private nonisolated func mapOpcode(_ opcode: WebSocketOpcode) -> FrameOpcode {
        switch opcode {
        case .continuation: .continuation
        case .text: .text
        case .binary: .binary
        case .connectionClose: .connectionClose
        case .ping: .ping
        case .pong: .pong
        default: .binary
        }
    }
}

// MARK: - WebSocketPipelineConfigurator

/// Reconfigures both client and server channel pipelines for WebSocket frame-level
/// proxying after an HTTP upgrade handshake completes.
nonisolated enum WebSocketPipelineConfigurator {
    nonisolated static func upgradeToWebSocket(
        clientChannel: Channel,
        serverChannel: Channel,
        requestData: HTTPRequestData,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void
    )
        -> EventLoopFuture<Void>
    {
        let wsConnection = WebSocketConnection(upgradeRequest: requestData)
        let transaction = HTTPTransaction(
            request: requestData,
            state: .active,
            webSocketConnection: wsConnection
        )

        let clientHandler = WebSocketFrameHandler(
            direction: .sent,
            peerChannel: serverChannel,
            webSocketConnection: wsConnection,
            parentTransaction: transaction,
            onTransactionComplete: onTransactionComplete
        )
        let serverHandler = WebSocketFrameHandler(
            direction: .received,
            peerChannel: clientChannel,
            webSocketConnection: wsConnection,
            parentTransaction: transaction,
            onTransactionComplete: onTransactionComplete
        )

        let clientFuture = ProxyPipeline.configureWebSocketPipeline(
            channel: clientChannel,
            handler: clientHandler
        )
        let serverFuture = ProxyPipeline.configureWebSocketPipeline(
            channel: serverChannel,
            handler: serverHandler
        )

        return clientFuture.and(serverFuture).map { _ in }
    }
}
