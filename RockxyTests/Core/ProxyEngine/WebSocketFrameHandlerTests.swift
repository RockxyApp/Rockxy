import Foundation
import NIOCore
import NIOEmbedded
import NIOHTTP1
import NIOSSL
import NIOWebSocket
@testable import Rockxy
import Testing

// MARK: - WebSocketFrameHandlerTests

struct WebSocketFrameHandlerTests {
    @Test("WebSocket lifecycle completes and releases exactly once")
    func lifecycleIsIdempotent() async {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let transaction = HTTPTransaction(request: request, state: .active)
        let completions = WebSocketEventCount()
        let releases = WebSocketEventCount()
        let lifecycle = WebSocketLifecycle(
            onTransactionComplete: { _ in completions.record() },
            onChannelClosed: { releases.record() }
        )

        lifecycle.complete(transaction)
        lifecycle.complete(transaction)
        lifecycle.failSetup()
        await Task.yield()
        await MainActor.run {}

        #expect(completions.value == 1)
        #expect(releases.value == 1)
        #expect(transaction.state == .completed)
        #expect(transaction.measuredDuration != nil)
    }

    @Test("WebSocket lifecycle publishes the live row once at open and marks it closed on completion")
    func lifecyclePublishesOpenThenClosed() async {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let transaction = HTTPTransaction(request: request, state: .active)
        let states = WebSocketStateRecorder()
        let lifecycle = WebSocketLifecycle(
            onTransactionComplete: { states.record($0.state) },
            onChannelClosed: {}
        )

        lifecycle.open(transaction)
        lifecycle.open(transaction)
        #expect(states.value == [.active])

        lifecycle.complete(transaction)
        await Task.yield()
        await MainActor.run {}

        #expect(states.value == [.active, .completed])
        // A late open after completion must not resurrect an active row.
        lifecycle.open(transaction)
        #expect(states.value == [.active, .completed])
    }

    @Test("A socket that closes before it opens is delivered once as an ordinary row")
    func lifecycleCloseBeforeOpenIsNotLive() async {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let transaction = HTTPTransaction(request: request, state: .active)
        #expect(transaction.deliversLiveRow)
        let completions = WebSocketEventCount()
        let lifecycle = WebSocketLifecycle(
            onTransactionComplete: { _ in completions.record() },
            onChannelClosed: {}
        )

        lifecycle.complete(transaction)
        lifecycle.open(transaction)
        await Task.yield()
        await MainActor.run {}

        #expect(completions.value == 1)
        // No second delivery will follow, so the session must not wait for one.
        #expect(!transaction.deliversLiveRow)
    }

    @Test("Upgrade records the 101 handshake and publishes the live row")
    func upgradeRecordsHandshakeAndPublishesLiveRow() throws {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let eventLoop = EmbeddedEventLoop()
        let client = EmbeddedChannel(loop: eventLoop)
        let server = EmbeddedChannel(loop: eventLoop)
        let published = WebSocketTransactionRecorder()
        var head = HTTPResponseHead(version: .http1_1, status: .switchingProtocols)
        head.headers.add(name: "Upgrade", value: "websocket")
        head.headers.add(name: "Sec-WebSocket-Accept", value: "fixture")

        let future = WebSocketPipelineConfigurator.upgradeToWebSocket(
            clientChannel: client,
            serverChannel: server,
            requestData: request,
            handshake: WebSocketHandshakeRecord(
                responseHead: head,
                timingInfo: TimingInfo(
                    dnsLookup: 0,
                    tcpConnection: 0.001,
                    tlsHandshake: 0,
                    timeToFirstByte: 0.002,
                    contentTransfer: 0
                ),
                sourcePort: 4_242
            ),
            onTransactionComplete: { published.record($0) }
        )
        eventLoop.run()
        try future.wait()

        let transaction = try #require(published.value.first)
        #expect(published.value.count == 1)
        #expect(transaction.state == .active)
        #expect(transaction.webSocketConnection != nil)
        #expect(transaction.response?.statusCode == 101)
        #expect(transaction.response?.headers.contains { $0.name == "Sec-WebSocket-Accept" } == true)
        #expect(transaction.sourcePort == 4_242)
        #expect(transaction.displayDuration == nil)

        _ = try? client.finish(acceptAlreadyClosed: true)
        _ = try? server.finish(acceptAlreadyClosed: true)
    }

    @Test("HTTP-to-WebSocket transition removes codecs and relays the first frame")
    func transitionRemovesHTTPCodecsAndRelaysFirstFrame() throws {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let connection = WebSocketConnection(upgradeRequest: request)
        let transaction = HTTPTransaction(
            request: request,
            state: .active,
            webSocketConnection: connection
        )
        let peer = EmbeddedChannel()
        let eventLoop = EmbeddedEventLoop()
        let channel = EmbeddedChannel(loop: eventLoop)
        let httpConfiguration = ProxyPipeline.configureHTTPPipeline(
            channel: channel,
            handler: WebSocketTransitionPassThroughHandler()
        )
        eventLoop.run()
        try httpConfiguration.wait()

        let relay = WebSocketFrameHandler(
            direction: .sent,
            peerChannel: peer,
            webSocketConnection: connection,
            parentTransaction: transaction,
            onTransactionComplete: { _ in }
        )
        let webSocketConfiguration = ProxyPipeline.configureClientWebSocketPipeline(
            channel: channel,
            handler: relay
        )
        eventLoop.run()
        try webSocketConfiguration.wait()

        #expect((try? channel.pipeline.context(
            handlerType: ByteToMessageHandler<HTTPRequestDecoder>.self
        ).wait()) == nil)
        #expect((try? channel.pipeline.context(handlerType: HTTPResponseEncoder.self).wait()) == nil)

        var bytes = channel.allocator.buffer(capacity: 4)
        bytes.writeBytes([0x81, 0x02, 0x6F, 0x6B])
        try channel.writeInbound(bytes)

        let forwarded = try #require(try peer.readOutbound(as: WebSocketFrame.self))
        var payload = forwarded.unmaskedData
        #expect(payload.readString(length: 2) == "ok")
        #expect(connection.frames.count == 1)

        _ = try? channel.finish(acceptAlreadyClosed: true)
        _ = try? peer.finish(acceptAlreadyClosed: true)
    }

    @Test("Upstream WebSocket transition removes HTTP codecs and relays the first server frame")
    func upstreamTransitionRemovesHTTPCodecsAndRelaysFirstFrame() throws {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let connection = WebSocketConnection(upgradeRequest: request)
        let transaction = HTTPTransaction(
            request: request,
            state: .active,
            webSocketConnection: connection
        )
        let peer = EmbeddedChannel()
        let eventLoop = EmbeddedEventLoop()
        let channel = EmbeddedChannel(loop: eventLoop)
        let httpConfiguration = channel.pipeline.addHTTPClientHandlers(leftOverBytesStrategy: .forwardBytes)
        eventLoop.run()
        try httpConfiguration.wait()

        let relay = WebSocketFrameHandler(
            direction: .received,
            peerChannel: peer,
            webSocketConnection: connection,
            parentTransaction: transaction,
            onTransactionComplete: { _ in }
        )
        let webSocketConfiguration = ProxyPipeline.configureUpstreamWebSocketPipeline(
            channel: channel,
            handler: relay
        )
        eventLoop.run()
        try webSocketConfiguration.wait()

        #expect((try? channel.pipeline.context(
            handlerType: ByteToMessageHandler<HTTPResponseDecoder>.self
        ).wait()) == nil)
        #expect((try? channel.pipeline.context(handlerType: HTTPRequestEncoder.self).wait()) == nil)

        var bytes = channel.allocator.buffer(capacity: 4)
        bytes.writeBytes([0x81, 0x02, 0x6F, 0x6B])
        try channel.writeInbound(bytes)

        let forwarded = try #require(try peer.readOutbound(as: WebSocketFrame.self))
        var payload = forwarded.unmaskedData
        #expect(payload.readString(length: 2) == "ok")
        #expect(connection.frames.count == 1)

        _ = try? channel.finish(acceptAlreadyClosed: true)
        _ = try? peer.finish(acceptAlreadyClosed: true)
    }

    @Test("Capture limit never interrupts the proxied WebSocket")
    func captureLimitKeepsRelayActive() throws {
        let request = TestFixtures.makeRequest(url: "wss://example.com/ws")
        let connection = WebSocketConnection(upgradeRequest: request)
        connection.stopCaptureAtLimit()
        let transaction = HTTPTransaction(
            request: request,
            state: .active,
            webSocketConnection: connection
        )
        let peer = EmbeddedChannel()
        let handler = WebSocketFrameHandler(
            direction: .received,
            peerChannel: peer,
            webSocketConnection: connection,
            parentTransaction: transaction,
            onTransactionComplete: { _ in }
        )
        let channel = EmbeddedChannel(handler: handler)
        try peer.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 8_081)).wait()
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 8_082)).wait()
        var payload = channel.allocator.buffer(capacity: 5)
        payload.writeString("hello")

        try channel.writeInbound(WebSocketFrame(fin: true, opcode: .text, data: payload))

        let forwarded = try #require(try peer.readOutbound(as: WebSocketFrame.self))
        var forwardedPayload = forwarded.unmaskedData
        #expect(forwardedPayload.readString(length: 5) == "hello")
        #expect(channel.isActive)
        #expect(peer.isActive)
        #expect(connection.frames.isEmpty)

        _ = try? channel.finish(acceptAlreadyClosed: true)
        _ = try? peer.finish(acceptAlreadyClosed: true)
    }

    @Test("Client relay hands unmasked payload to the encoder exactly once")
    func clientRelayDoesNotDoubleMaskDecodedFrames() throws {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let connection = WebSocketConnection(upgradeRequest: request)
        let transaction = HTTPTransaction(
            request: request,
            state: .active,
            webSocketConnection: connection
        )
        let peer = EmbeddedChannel(handler: WebSocketFrameEncoder())
        let handler = WebSocketFrameHandler(
            direction: .sent,
            peerChannel: peer,
            webSocketConnection: connection,
            parentTransaction: transaction,
            onTransactionComplete: { _ in }
        )
        let channel = EmbeddedChannel(handler: handler)
        let maskingKey: WebSocketMaskingKey = [0x11, 0x22, 0x33, 0x44]
        let plaintext = Array("client-text".utf8)
        var maskedPayload = channel.allocator.buffer(capacity: plaintext.count)
        maskedPayload.writeBytes(plaintext)
        maskedPayload.webSocketMask(maskingKey)

        try channel.writeInbound(WebSocketFrame(
            fin: true,
            opcode: .text,
            maskKey: maskingKey,
            data: maskedPayload
        ))

        var wire = peer.allocator.buffer(capacity: plaintext.count + 6)
        while var part = try peer.readOutbound(as: ByteBuffer.self) {
            wire.writeBuffer(&part)
        }
        #expect(wire.readInteger(as: UInt8.self) == 0x81)
        #expect(wire.readInteger(as: UInt8.self) == 0x80 | UInt8(plaintext.count))
        #expect(wire.readBytes(length: 4) == Array(maskingKey))
        let encodedSlice = wire.readSlice(length: plaintext.count)
        var encodedPayload = try #require(encodedSlice)
        encodedPayload.webSocketUnmask(maskingKey)
        #expect(encodedPayload.readBytes(length: plaintext.count) == plaintext)

        _ = try? channel.finish(acceptAlreadyClosed: true)
        _ = try? peer.finish(acceptAlreadyClosed: true)
    }

    @Test("Server relay never emits a masked frame to the client")
    func serverRelayStripsUnexpectedMasking() throws {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let connection = WebSocketConnection(upgradeRequest: request)
        let transaction = HTTPTransaction(
            request: request,
            state: .active,
            webSocketConnection: connection
        )
        let peer = EmbeddedChannel(handler: WebSocketFrameEncoder())
        let handler = WebSocketFrameHandler(
            direction: .received,
            peerChannel: peer,
            webSocketConnection: connection,
            parentTransaction: transaction,
            onTransactionComplete: { _ in }
        )
        let channel = EmbeddedChannel(handler: handler)
        let maskingKey: WebSocketMaskingKey = [0xAA, 0xBB, 0xCC, 0xDD]
        let plaintext = Array("server-text".utf8)
        var maskedPayload = channel.allocator.buffer(capacity: plaintext.count)
        maskedPayload.writeBytes(plaintext)
        maskedPayload.webSocketMask(maskingKey)

        try channel.writeInbound(WebSocketFrame(
            fin: true,
            opcode: .text,
            maskKey: maskingKey,
            data: maskedPayload
        ))

        var wire = peer.allocator.buffer(capacity: plaintext.count + 2)
        while var part = try peer.readOutbound(as: ByteBuffer.self) {
            wire.writeBuffer(&part)
        }
        #expect(wire.readInteger(as: UInt8.self) == 0x81)
        #expect(wire.readInteger(as: UInt8.self) == UInt8(plaintext.count))
        #expect(wire.readBytes(length: plaintext.count) == plaintext)

        _ = try? channel.finish(acceptAlreadyClosed: true)
        _ = try? peer.finish(acceptAlreadyClosed: true)
    }

    @Test("Client-first close completes the shared lifecycle exactly once")
    func clientFirstCloseCompletesOnce() async throws {
        let pair = try WebSocketRelayPair()
        pair.lifecycle.open(pair.transaction)
        var payload = pair.client.allocator.buffer(capacity: 2)
        payload.writeInteger(UInt16(1_000))
        try pair.client.writeInbound(WebSocketFrame(fin: true, opcode: .connectionClose, data: payload))

        pair.client.pipeline.fireChannelInactive()
        pair.server.pipeline.fireChannelInactive()
        await pair.settle()

        #expect(pair.states.value == [.active, .completed])
        #expect(pair.releases.value == 1)
        #expect(pair.transaction.webSocketConnection?.frames.count == 1)
        pair.finish()
    }

    @Test("Server-first close completes the shared lifecycle exactly once")
    func serverFirstCloseCompletesOnce() async throws {
        let pair = try WebSocketRelayPair()
        pair.lifecycle.open(pair.transaction)
        var text = pair.server.allocator.buffer(capacity: 3)
        text.writeString("bye")
        try pair.server.writeInbound(WebSocketFrame(fin: true, opcode: .text, data: text))
        var close = pair.server.allocator.buffer(capacity: 2)
        close.writeInteger(UInt16(1_000))
        try pair.server.writeInbound(WebSocketFrame(fin: true, opcode: .connectionClose, data: close))

        pair.server.pipeline.fireChannelInactive()
        pair.client.pipeline.fireChannelInactive()
        await pair.settle()

        #expect(pair.states.value == [.active, .completed])
        #expect(pair.releases.value == 1)
        #expect(pair.transaction.webSocketConnection?.frames.count == 2)
        pair.finish()
    }

    @Test("Abrupt disconnect without a close frame still completes exactly once")
    func abruptDisconnectCompletesOnce() async throws {
        let pair = try WebSocketRelayPair()
        pair.lifecycle.open(pair.transaction)

        pair.server.pipeline.fireChannelInactive()
        pair.server.pipeline.fireChannelInactive()
        pair.client.pipeline.fireChannelInactive()
        await pair.settle()

        #expect(pair.states.value == [.active, .completed])
        #expect(pair.releases.value == 1)
        pair.finish()
    }

    @Test("A forwarding error marks the WebSocket failed and completes it exactly once")
    func forwardingErrorMarksFailed() async throws {
        let pair = try WebSocketRelayPair()
        pair.lifecycle.open(pair.transaction)

        pair.client.pipeline.fireErrorCaught(ChannelError.ioOnClosedChannel)
        pair.client.pipeline.fireChannelInactive()
        pair.server.pipeline.fireErrorCaught(ChannelError.ioOnClosedChannel)
        pair.server.pipeline.fireChannelInactive()
        await pair.settle()

        #expect(pair.states.value == [.active, .failed])
        #expect(pair.transaction.state == .failed)
        #expect(pair.releases.value == 1)
        pair.finish()
    }

    @Test("A transport error after a close frame is still a clean close")
    func errorAfterCloseFrameIsClean() async throws {
        let pair = try WebSocketRelayPair()
        pair.lifecycle.open(pair.transaction)
        var payload = pair.client.allocator.buffer(capacity: 2)
        payload.writeInteger(UInt16(1_000))
        try pair.client.writeInbound(WebSocketFrame(fin: true, opcode: .connectionClose, data: payload))

        pair.server.pipeline.fireErrorCaught(ChannelError.ioOnClosedChannel)
        pair.server.pipeline.fireChannelInactive()
        await pair.settle()

        #expect(pair.states.value == [.active, .completed])
        pair.finish()
    }

    @Test("A TLS peer closing without close_notify is not a failure")
    func uncleanTLSShutdownIsClean() async throws {
        let pair = try WebSocketRelayPair()
        pair.lifecycle.open(pair.transaction)

        pair.server.pipeline.fireErrorCaught(NIOSSLError.uncleanShutdown)
        pair.server.pipeline.fireChannelInactive()
        await pair.settle()

        #expect(pair.states.value == [.active, .completed])
        pair.finish()
    }

    @Test("A failure reported after completion does not rewrite the final state")
    func lateFailureIsIgnored() async {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let transaction = HTTPTransaction(request: request, state: .active)
        let lifecycle = WebSocketLifecycle(onTransactionComplete: { _ in }, onChannelClosed: {})

        lifecycle.complete(transaction)
        lifecycle.recordFailure()
        lifecycle.complete(transaction)
        await Task.yield()
        await MainActor.run {}

        #expect(transaction.state == .completed)
    }
}

// MARK: - WebSocketTransitionPassThroughHandler

private final class WebSocketTransitionPassThroughHandler:
    ChannelInboundHandler,
    RemovableChannelHandler,
    @unchecked Sendable
{
    typealias InboundIn = HTTPServerRequestPart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }
}

// MARK: - WebSocketEventCount

private final class WebSocketEventCount: @unchecked Sendable {
    // MARK: Internal

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func record() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var count = 0
}

// MARK: - WebSocketStateRecorder

private final class WebSocketStateRecorder: @unchecked Sendable {
    // MARK: Internal

    var value: [TransactionState] {
        lock.lock()
        defer { lock.unlock() }
        return states
    }

    func record(_ state: TransactionState) {
        lock.lock()
        states.append(state)
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var states: [TransactionState] = []
}

// MARK: - WebSocketTransactionRecorder

private final class WebSocketTransactionRecorder: @unchecked Sendable {
    // MARK: Internal

    var value: [HTTPTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return transactions
    }

    func record(_ transaction: HTTPTransaction) {
        lock.lock()
        transactions.append(transaction)
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var transactions: [HTTPTransaction] = []
}

// MARK: - WebSocketRelayPair

/// Client-facing and upstream relays wired to each other through a shared lifecycle,
/// mirroring how an upgraded proxied WebSocket is assembled.
private struct WebSocketRelayPair {
    // MARK: Lifecycle

    init() throws {
        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let connection = WebSocketConnection(upgradeRequest: request)
        let transaction = HTTPTransaction(request: request, state: .active, webSocketConnection: connection)
        let states = WebSocketStateRecorder()
        let releases = WebSocketEventCount()
        let lifecycle = WebSocketLifecycle(
            onTransactionComplete: { states.record($0.state) },
            onChannelClosed: { releases.record() }
        )
        let client = EmbeddedChannel()
        let server = EmbeddedChannel()
        try client.pipeline.syncOperations.addHandler(WebSocketFrameHandler(
            direction: .sent,
            peerChannel: server,
            webSocketConnection: connection,
            parentTransaction: transaction,
            onTransactionComplete: { _ in },
            lifecycle: lifecycle
        ))
        try server.pipeline.syncOperations.addHandler(WebSocketFrameHandler(
            direction: .received,
            peerChannel: client,
            webSocketConnection: connection,
            parentTransaction: transaction,
            onTransactionComplete: { _ in },
            lifecycle: lifecycle
        ))
        self.transaction = transaction
        self.states = states
        self.releases = releases
        self.lifecycle = lifecycle
        self.client = client
        self.server = server
    }

    // MARK: Internal

    let transaction: HTTPTransaction
    let states: WebSocketStateRecorder
    let releases: WebSocketEventCount
    let lifecycle: WebSocketLifecycle
    let client: EmbeddedChannel
    let server: EmbeddedChannel

    func settle() async {
        await Task.yield()
        await MainActor.run {}
    }

    func finish() {
        _ = try? client.finish(acceptAlreadyClosed: true)
        _ = try? server.finish(acceptAlreadyClosed: true)
    }
}
