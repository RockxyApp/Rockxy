import Foundation
import NIOCore
import NIOHTTP1
import NIOSSL
import NIOWebSocket
import os

// Defines `UpstreamResponseHandler`, which handles upstream response flow in the proxy
// engine.

nonisolated(unsafe) private let upstreamLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "UpstreamResponseHandler"
)

// MARK: - UpstreamResponseHandler

/// Installed on the outbound (upstream) channel to collect the server's HTTP response,
/// relay it back to the client channel in real time, and assemble a complete
/// `HTTPTransaction` with timing data once the response finishes.
///
/// Timing measurements (DNS, TCP, TTFB, transfer) are captured via `DispatchTime`
/// checkpoints passed from the caller that initiated the upstream connection.
final class UpstreamResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        connectTime: DispatchTime,
        tcpTime: DispatchTime,
        clientContext: ChannelHandlerContext,
        isHTTPS: Bool = false,
        sourcePort: UInt16? = nil,
        breakpointPhase: BreakpointRulePhase? = nil,
        headerResponseOperations: [HeaderOperation]? = nil,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? =
            nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onChannelClosed: @escaping @Sendable () -> Void = {}
    ) {
        self.requestData = requestData
        self.graphQLInfo = graphQLInfo
        self.startTime = startTime
        self.connectTime = connectTime
        self.tcpTime = tcpTime
        self.clientContext = clientContext
        self.isHTTPS = isHTTPS
        self.sourcePort = sourcePort
        self.breakpointPhase = breakpointPhase
        self.headerResponseOperations = headerResponseOperations
        self.onBreakpointHit = onBreakpointHit
        self.onTransactionComplete = onTransactionComplete
        self.onChannelClosed = onChannelClosed
    }

    // MARK: Internal

    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    // MARK: - User-Agent App Identification

    nonisolated static func extractAppFromUserAgent(_ headers: [HTTPHeader]) -> String? {
        guard let ua = headers.first(where: { $0.name.lowercased() == "user-agent" })?.value else {
            return nil
        }

        // Non-browser apps typically use "AppName/version" format
        if !ua.contains("Mozilla/") {
            if let slash = ua.firstIndex(of: "/") {
                let name = String(ua[ua.startIndex ..< slash])
                if !name.isEmpty {
                    return name
                }
            }
            return ua.isEmpty ? nil : ua
        }

        // Browser detection from Mozilla-style UA strings
        if ua.contains("Edg/") {
            return "Microsoft Edge"
        }
        if ua.contains("OPR/") || ua.contains("Opera/") {
            return "Opera"
        }
        if ua.contains("Brave/") {
            return "Brave"
        }
        if ua.contains("Vivaldi/") {
            return "Vivaldi"
        }
        if ua.contains("Chrome/") {
            return "Google Chrome"
        }
        if ua.contains("Firefox/") {
            return "Firefox"
        }
        if ua.contains("Safari/"), ua.contains("Version/") {
            return "Safari"
        }

        return nil
    }

    nonisolated func handlerAdded(context: ChannelHandlerContext) {
        readTimeoutTask = context.eventLoop.scheduleTask(in: .seconds(30)) { [weak self] in
            guard let self, !self.completed else {
                return
            }
            self.completed = true
            upstreamLogger.warning("Read timeout for \(self.requestData.url)")

            if self.clientContext.channel.isActive {
                var head = HTTPResponseHead(version: .http1_1, status: .gatewayTimeout)
                head.headers.add(name: "Connection", value: "close")
                self.clientContext.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
                self.clientContext.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { _ in
                    self.clientContext.close(promise: nil)
                }
            }

            let transaction = HTTPTransaction(
                request: self.requestData,
                response: HTTPResponseData(statusCode: 504, statusMessage: "Gateway Timeout", headers: []),
                state: .failed
            )
            transaction.sourcePort = self.sourcePort
            transaction.clientApp = Self.extractAppFromUserAgent(self.requestData.headers)
            self.onTransactionComplete(transaction)
            context.close(promise: nil)
        }

        // Close upstream channel when the client disconnects to prevent FD leaks
        clientContext.channel.closeFuture.whenComplete { [weak self] _ in
            guard let self, !self.completed else {
                return
            }
            self.completed = true
            self.readTimeoutTask?.cancel()
            self.readTimeoutTask = nil
            if self.responseHead != nil {
                self.buildAndCompleteTransaction()
            }
            context.close(promise: nil)
        }
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        readTimeoutTask?.cancel()
        readTimeoutTask = nil
        callChannelClosed()
        guard !completed else {
            return
        }
        completed = true
        if responseHead != nil {
            buildAndCompleteTransaction()
        }
    }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case let .head(head):
            readTimeoutTask?.cancel()
            readTimeoutTask = nil

            var modifiedHead = head

            // WebSocket upgrade detection uses original head
            let isWebSocketUpgrade = head.status == .switchingProtocols
                && WebSocketDetector.isWebSocketUpgrade(headers: head.headers)

            // Apply response header modifications, but skip WebSocket upgrades
            if !isWebSocketUpgrade, let ops = headerResponseOperations, !ops.isEmpty {
                HeaderMutator.apply(ops, to: &modifiedHead.headers)
            }

            responseHead = modifiedHead
            firstByteTime = .now()
            responseBody = context.channel.allocator.buffer(capacity: 0)

            if isWebSocketUpgrade {
                relayResponseHead(modifiedHead)
                let serverChannel = context.channel
                let clientChannel = clientContext.channel
                WebSocketPipelineConfigurator.upgradeToWebSocket(
                    clientChannel: clientChannel,
                    serverChannel: serverChannel,
                    requestData: requestData,
                    onTransactionComplete: onTransactionComplete
                ).whenFailure { error in
                    upstreamLogger.error("WebSocket upgrade failed: \(error.localizedDescription)")
                    context.close(promise: nil)
                }
                return
            }

            if !shouldBreakOnResponse {
                relayResponseHead(modifiedHead)
            }

        case let .body(buffer):
            if !responseBodyTruncated {
                if ProxyHandlerShared.shouldTruncateCapture(
                    currentBufferSize: responseBody?.readableBytes ?? 0,
                    incomingChunkSize: buffer.readableBytes
                ) {
                    responseBodyTruncated = true
                    upstreamLogger.info(
                        "Response body exceeds capture limit for \(self.requestData.url, privacy: .private), truncating capture buffer"
                    )
                } else {
                    responseBody?.writeImmutableBuffer(buffer)
                }
            }
            if !shouldBreakOnResponse {
                relayResponseBody(buffer)
            }

        case .end:
            guard !completed else {
                return
            }
            completed = true
            readTimeoutTask?.cancel()
            readTimeoutTask = nil

            if shouldBreakOnResponse, let onBreakpointHit, let head = responseHead {
                handleResponseBreakpoint(context: context, head: head, onBreakpointHit: onBreakpointHit)
            } else {
                relayResponseEnd()
                buildAndCompleteTransaction()
                context.close(promise: nil)
            }
        }
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        readTimeoutTask?.cancel()
        readTimeoutTask = nil
        if !completed, responseHead != nil {
            completed = true
            relayResponseEnd()
            buildAndCompleteTransaction()
        }
        if Self.isUncleanTLSShutdown(error) {
            upstreamLogger.debug(
                "Upstream TLS connection closed without close_notify for \(self.requestData.url)"
            )
        } else {
            upstreamLogger.debug("Upstream closed: \(error.localizedDescription)")
        }
        context.close(promise: nil)
    }

    // MARK: Private

    private let requestData: HTTPRequestData
    private let graphQLInfo: GraphQLInfo?
    private let startTime: DispatchTime
    private let connectTime: DispatchTime
    private let tcpTime: DispatchTime
    private let clientContext: ChannelHandlerContext
    private let isHTTPS: Bool
    private let sourcePort: UInt16?
    private let breakpointPhase: BreakpointRulePhase?
    private let headerResponseOperations: [HeaderOperation]?
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onChannelClosed: @Sendable () -> Void

    private var responseHead: HTTPResponseHead?
    private var channelClosedCalled = false
    private var responseBody: ByteBuffer?
    private var responseBodyTruncated = false
    private var firstByteTime: DispatchTime?
    private var completed = false
    private var readTimeoutTask: Scheduled<Void>?

    private var shouldBreakOnResponse: Bool {
        guard let phase = breakpointPhase else {
            return false
        }
        return phase == .response || phase == .both
    }

    private static func isUncleanTLSShutdown(_ error: Error) -> Bool {
        if let sslError = error as? NIOSSLError, case .uncleanShutdown = sslError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == "NIOSSL.NIOSSLErrorDomain" && nsError.code == 12
    }

    // MARK: - Client Relay

    nonisolated private func relayResponseHead(_ head: HTTPResponseHead) {
        guard clientContext.channel.isActive else {
            return
        }
        let proxyHead = HTTPResponseHead(version: head.version, status: head.status, headers: head.headers)
        clientContext.write(
            NIOAny(HTTPServerResponsePart.head(proxyHead)),
            promise: nil
        )
    }

    nonisolated private func relayResponseBody(_ buffer: ByteBuffer) {
        guard clientContext.channel.isActive else {
            return
        }
        clientContext.write(
            NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))),
            promise: nil
        )
    }

    nonisolated private func relayResponseEnd() {
        guard clientContext.channel.isActive else {
            return
        }
        clientContext.writeAndFlush(
            NIOAny(HTTPServerResponsePart.end(nil)),
            promise: nil
        )
    }

    // MARK: - Response Breakpoint

    nonisolated private func handleResponseBreakpoint(
        context: ChannelHandlerContext,
        head: HTTPResponseHead,
        onBreakpointHit: @escaping @Sendable (BreakpointRequestData) async -> (
            BreakpointDecision,
            BreakpointRequestData
        )
    ) {
        let responseHeaders = head.headers.map { EditableHeader(name: $0.name, value: $0.value) }
        let bodyData: Data? = if let buf = responseBody, buf.readableBytes > 0,
                                 let bytes = buf.getBytes(at: buf.readerIndex, length: buf.readableBytes)
        {
            Data(bytes)
        } else {
            nil
        }
        let bodyString = bodyData.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        let breakpointData = BreakpointRequestData(
            method: requestData.method,
            url: requestData.url.absoluteString,
            headers: responseHeaders,
            body: bodyString,
            statusCode: Int(head.status.code),
            phase: .response
        )

        let eventLoop = context.eventLoop
        let promise = eventLoop.makePromise(of: (BreakpointDecision, BreakpointRequestData).self)

        promise.completeWithTask {
            await onBreakpointHit(breakpointData)
        }

        promise.futureResult.whenComplete { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .success((decision, modifiedData)):
                self.executeResponseBreakpointDecision(
                    decision,
                    modifiedData: modifiedData,
                    context: context,
                    originalHead: head
                )
            case let .failure(error):
                upstreamLogger.error(
                    "Response breakpoint handler failed: \(error.localizedDescription), forwarding original"
                )
                self.relayResponseHead(head)
                if let buf = self.responseBody, buf.readableBytes > 0 {
                    self.relayResponseBody(buf)
                }
                self.relayResponseEnd()
                self.buildAndCompleteTransaction()
                context.close(promise: nil)
            }
        }
    }

    nonisolated private func executeResponseBreakpointDecision(
        _ decision: BreakpointDecision,
        modifiedData: BreakpointRequestData,
        context: ChannelHandlerContext,
        originalHead: HTTPResponseHead
    ) {
        switch decision {
        case .execute:
            let built = BreakpointResponseBuilder.build(
                modifiedData: modifiedData,
                originalHead: originalHead
            )
            self.responseHead = built.head
            if let body = built.body {
                var buf = clientContext.channel.allocator.buffer(capacity: body.count)
                buf.writeBytes(body)
                self.responseBody = buf
            } else {
                self.responseBody = nil
            }
            relayResponseHead(built.head)
            if let body = built.body {
                var buffer = clientContext.channel.allocator.buffer(capacity: body.count)
                buffer.writeBytes(body)
                relayResponseBody(buffer)
            }
            relayResponseEnd()
            buildAndCompleteTransaction()
            context.close(promise: nil)

        case .cancel:
            relayResponseHead(originalHead)
            if let buf = responseBody, buf.readableBytes > 0 {
                relayResponseBody(buf)
            }
            relayResponseEnd()
            buildAndCompleteTransaction()
            context.close(promise: nil)

        case .abort:
            guard clientContext.channel.isActive else {
                context.close(promise: nil)
                return
            }
            var abortHead = HTTPResponseHead(version: .http1_1, status: .serviceUnavailable)
            abortHead.headers.add(name: "Connection", value: "close")
            clientContext.write(NIOAny(HTTPServerResponsePart.head(abortHead)), promise: nil)
            clientContext.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { [weak self] _ in
                self?.clientContext.close(promise: nil)
            }

            let transaction = HTTPTransaction(
                request: requestData,
                response: HTTPResponseData(statusCode: 503, statusMessage: "Service Unavailable", headers: []),
                state: .failed
            )
            transaction.sourcePort = sourcePort
            onTransactionComplete(transaction)
            context.close(promise: nil)
        }
    }

    // MARK: - Transaction Assembly

    nonisolated private func buildAndCompleteTransaction() {
        let endTime = DispatchTime.now()

        guard let head = responseHead else {
            return
        }

        let headers = head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }
        let body: Data? = if let buf = responseBody, buf.readableBytes > 0,
                             let bytes = buf.getBytes(at: buf.readerIndex, length: buf.readableBytes)
        {
            Data(bytes)
        } else {
            nil
        }
        let contentType = ContentTypeDetector.detect(headers: headers, body: body)

        var responseData = HTTPResponseData(
            statusCode: Int(head.status.code),
            statusMessage: head.status.reasonPhrase,
            headers: headers,
            body: body,
            contentType: contentType
        )
        responseData.bodyTruncated = responseBodyTruncated

        let timing = buildTimingInfo(endTime: endTime)

        let transaction = HTTPTransaction(
            request: requestData,
            response: responseData,
            state: .completed,
            timingInfo: timing,
            graphQLInfo: graphQLInfo
        )
        transaction.sourcePort = sourcePort
        transaction.clientApp = Self.extractAppFromUserAgent(requestData.headers)

        onTransactionComplete(transaction)
    }

    nonisolated private func buildTimingInfo(endTime: DispatchTime) -> TimingInfo {
        let dnsLookup = nanosecondsToSeconds(from: startTime, to: connectTime)
        let rawTcpConnection = nanosecondsToSeconds(from: connectTime, to: tcpTime)
        let ttfb = firstByteTime.map { nanosecondsToSeconds(from: tcpTime, to: $0) } ?? 0
        let transfer = firstByteTime.map { nanosecondsToSeconds(from: $0, to: endTime) } ?? 0

        let tcpConnection: TimeInterval
        let tlsHandshake: TimeInterval
        if isHTTPS {
            tcpConnection = rawTcpConnection * 0.4
            tlsHandshake = rawTcpConnection * 0.6
        } else {
            tcpConnection = rawTcpConnection
            tlsHandshake = 0
        }

        return TimingInfo(
            dnsLookup: dnsLookup,
            tcpConnection: tcpConnection,
            tlsHandshake: tlsHandshake,
            timeToFirstByte: ttfb,
            contentTransfer: transfer
        )
    }

    nonisolated private func nanosecondsToSeconds(
        from start: DispatchTime,
        to end: DispatchTime
    )
        -> TimeInterval
    {
        let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
        return TimeInterval(nanos) / 1_000_000_000.0
    }

    nonisolated private func callChannelClosed() {
        guard !channelClosedCalled else {
            return
        }
        channelClosedCalled = true
        onChannelClosed()
    }
}
