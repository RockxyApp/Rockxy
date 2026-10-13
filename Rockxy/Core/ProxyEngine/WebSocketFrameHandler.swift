import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import NIOWebSocket
import os

// Defines `WebSocketFrameHandler`, which handles web socket frame flow in the proxy
// engine.

nonisolated(unsafe) private let wsLogger = Logger(
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

// MARK: - WebSocketHandshakeRecord

/// The upstream `101 Switching Protocols` evidence captured before the pipelines are
/// swapped to frame relay, so the live WebSocket row can show handshake headers and timing.
struct WebSocketHandshakeRecord: Sendable {
    let responseHead: HTTPResponseHead?
    let timingInfo: TimingInfo?
    let sourcePort: UInt16?

    func makeResponseData() -> HTTPResponseData? {
        guard let responseHead else {
            return nil
        }
        return HTTPResponseData(
            statusCode: Int(responseHead.status.code),
            statusMessage: responseHead.status.reasonPhrase,
            headers: responseHead.headers.map { HTTPHeader(name: $0.name, value: $0.value) },
            body: nil,
            contentType: .unknown
        )
    }
}

// MARK: - WebSocketLifecycle

/// Delivers the terminal transaction and upstream-channel release exactly once even though
/// either half of a proxied WebSocket may observe channel inactivity first.
///
/// A proxied WebSocket is delivered twice through the same intake callback: once as an
/// `.active` row when the upgrade completes, and once more when the socket closes with the
/// state flipped to `.completed`. The traffic session manager treats the second delivery of
/// a live transaction as an in-place update, never as a new row.
final class WebSocketLifecycle: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onChannelClosed: @escaping @Sendable () -> Void = {}
    ) {
        self.onTransactionComplete = onTransactionComplete
        self.onChannelClosed = onChannelClosed
    }

    // MARK: Internal

    /// Publishes the upgraded connection as a live row before any frame is relayed.
    func open(_ transaction: HTTPTransaction) {
        lock.lock()
        let alreadyOpened = isOpened || isComplete
        isOpened = true
        lock.unlock()
        guard !alreadyOpened else {
            return
        }
        onTransactionComplete(transaction)
    }

    /// Records that a relay failed so the eventual completion is reported honestly as failed
    /// rather than as a clean close. Has no effect once the lifecycle reached its terminal state.
    func recordFailure() {
        lock.lock()
        // After a close frame, a dropped TCP or TLS connection is the normal end of the
        // conversation, not a failure.
        if !isComplete, !sawCloseFrame {
            didFail = true
        }
        lock.unlock()
    }

    /// Notes that either side sent a close frame, so later transport errors are not failures.
    func recordCloseFrame() {
        lock.lock()
        sawCloseFrame = true
        lock.unlock()
    }

    func complete(_ transaction: HTTPTransaction) {
        // Claim and read the open flag in one critical section: `open(_:)` checks `isComplete`
        // under the same lock, so it either delivered before this point or never will.
        lock.lock()
        let claimed = !isComplete
        isComplete = true
        let wasOpened = isOpened
        let failed = didFail
        lock.unlock()
        guard claimed else {
            return
        }
        let closedAt = Date()
        let onTransactionComplete = onTransactionComplete
        // Transaction fields are only mutated on the main actor once a row is visible.
        Task { @MainActor in
            // A socket that closed before its upgrade finished was never delivered as a live
            // row, so this single delivery is an ordinary completed row.
            if !wasOpened {
                transaction.deliversLiveRow = false
            }
            transaction.state = failed ? .failed : .completed
            transaction.measuredDuration = closedAt.timeIntervalSince(transaction.timestamp)
            transaction.webSocketFrameVersion += 1
            onTransactionComplete(transaction)
        }
        onChannelClosed()
    }

    func failSetup() {
        guard claimTerminalState() else {
            return
        }
        onChannelClosed()
    }

    // MARK: Private

    private let lock = NSLock()
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onChannelClosed: @Sendable () -> Void
    private var isOpened = false
    private var isComplete = false
    private var didFail = false
    private var sawCloseFrame = false

    private func claimTerminalState() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isComplete else {
            return false
        }
        isComplete = true
        return true
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
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        lifecycle: WebSocketLifecycle? = nil
    ) {
        self.direction = direction
        self.peerChannel = peerChannel
        self.webSocketConnection = webSocketConnection
        self.parentTransaction = parentTransaction
        self.lifecycle = lifecycle ?? WebSocketLifecycle(onTransactionComplete: onTransactionComplete)
    }

    // MARK: Internal

    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        if frame.opcode == .connectionClose {
            lifecycle.recordCloseFrame()
        }
        captureFrame(frame)
        forwardFrame(frame, context: context)
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        wsLogger.error("WebSocket error (\(self.direction.rawValue)): \(error.localizedDescription)")
        // A TLS peer that closes without close_notify is treated as a clean end everywhere else.
        let isUncleanTLSShutdown = (error as? NIOSSLError).map { if case .uncleanShutdown = $0 { true } else { false } }
            ?? false
        if !isUncleanTLSShutdown {
            lifecycle.recordFailure()
        }
        peerChannel?.close(promise: nil)
        context.close(promise: nil)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        peerChannel?.close(promise: nil)
        lifecycle.complete(parentTransaction)
    }

    // MARK: Private

    private let direction: FrameDirection
    private let peerChannel: Channel?
    private let webSocketConnection: WebSocketConnection
    private let lifecycle: WebSocketLifecycle
    private let parentTransaction: HTTPTransaction

    /// Unmasks the frame payload (WebSocket client frames are always masked per RFC 6455)
    /// and records it in the shared connection model before forwarding.
    nonisolated private func captureFrame(_ frame: WebSocketFrame) {
        guard !webSocketConnection.isCaptureLimitReached else {
            return
        }
        let opcode = mapOpcode(frame.opcode)
        var dataBuffer = frame.unmaskedData
        let payloadBytes = dataBuffer.readBytes(length: dataBuffer.readableBytes) ?? []
        let payload = Data(payloadBytes)

        guard payload.count <= ProxyLimits.maxWebSocketFrameSize else {
            webSocketConnection.stopCaptureAtLimit()
            notifyTransactionUpdate()
            wsLogger.warning(
                "WebSocket frame exceeds capture limit; capture stopped while relay remains active"
            )
            return
        }
        let frameData = WebSocketFrameData(
            direction: direction,
            opcode: opcode,
            payload: payload,
            isFinal: frame.fin
        )

        guard webSocketConnection.addFrame(
            frameData,
            maximumTotalPayloadSize: ProxyLimits.maxWebSocketConnectionSize,
            maximumFrameCount: ProxyLimits.maxWebSocketFrameCount
        ) else {
            notifyTransactionUpdate()
            wsLogger.warning(
                "WebSocket connection exceeds capture limits; capture stopped while relay remains active"
            )
            return
        }

        notifyTransactionUpdate()
    }

    nonisolated private func notifyTransactionUpdate() {
        let transaction = parentTransaction
        Task { @MainActor in
            transaction.webSocketFrameVersion += 1
        }
    }

    nonisolated private func forwardFrame(
        _ frame: WebSocketFrame,
        context: ChannelHandlerContext
    ) {
        guard let peer = peerChannel else {
            return
        }
        // NIO's decoder intentionally preserves the masked bytes and mask key. Its encoder,
        // however, expects unmasked application data and applies the key while writing. Passing
        // a decoded client frame through unchanged therefore masks the payload a second time and
        // puts plaintext on the wire. Normalize the payload before the peer encoder sees it,
        // while preserving the client's key in the client-to-server direction and never sending
        // a masked frame to a client.
        let forwardedFrame = WebSocketFrame(
            fin: frame.fin,
            rsv1: frame.rsv1,
            rsv2: frame.rsv2,
            rsv3: frame.rsv3,
            opcode: frame.opcode,
            maskKey: direction == .sent ? frame.maskKey : nil,
            data: frame.unmaskedData,
            extensionData: frame.unmaskedExtensionData
        )
        peer.writeAndFlush(NIOAny(forwardedFrame), promise: nil)
    }

    nonisolated private func mapOpcode(_ opcode: WebSocketOpcode) -> FrameOpcode {
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
        handshake: WebSocketHandshakeRecord? = nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        lifecycle: WebSocketLifecycle? = nil
    )
        -> EventLoopFuture<Void>
    {
        let wsConnection = WebSocketConnection(upgradeRequest: requestData)
        let transaction = HTTPTransaction(
            request: requestData,
            response: handshake?.makeResponseData(),
            state: .active,
            timingInfo: handshake?.timingInfo,
            webSocketConnection: wsConnection
        )
        transaction.sourcePort = handshake?.sourcePort
        transaction.clientApp = UpstreamResponseHandler.extractAppFromUserAgent(requestData.headers)
        let lifecycle = lifecycle ?? WebSocketLifecycle(onTransactionComplete: onTransactionComplete)

        let clientHandler = WebSocketFrameHandler(
            direction: .sent,
            peerChannel: serverChannel,
            webSocketConnection: wsConnection,
            parentTransaction: transaction,
            onTransactionComplete: onTransactionComplete,
            lifecycle: lifecycle
        )
        let serverHandler = WebSocketFrameHandler(
            direction: .received,
            peerChannel: clientChannel,
            webSocketConnection: wsConnection,
            parentTransaction: transaction,
            onTransactionComplete: onTransactionComplete,
            lifecycle: lifecycle
        )

        let clientFuture = ProxyPipeline.configureClientWebSocketPipeline(
            channel: clientChannel,
            handler: clientHandler
        )
        let serverFuture = ProxyPipeline.configureUpstreamWebSocketPipeline(
            channel: serverChannel,
            handler: serverHandler
        )

        // The accepted and upstream channels may live on different event loops.
        // Complete the combined transition on the client loop so callers can safely
        // chain this future from the flushed 101 response promise.
        return clientFuture.and(serverFuture.hop(to: clientChannel.eventLoop)).map { _ in
            lifecycle.open(transaction)
        }
    }
}
