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
final class UpstreamResponseHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
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
        breakpointRuleName: String? = nil,
        headerResponseOperations: [HeaderOperation]? = nil,
        disablesResponseCaching: Bool = false,
        networkConditionProfile: NetworkConditionProfile? = nil,
        scriptPluginManager: ScriptPluginManager? = nil,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? =
            nil,
        breakpointBridgeTracker: BreakpointBridgeTracker? = nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onChannelClosed: @escaping @Sendable () -> Void = {}
    ) {
        self.requestData = requestData
        self.disablesResponseCaching = disablesResponseCaching
        self.graphQLInfo = graphQLInfo
        self.startTime = startTime
        self.connectTime = connectTime
        self.tcpTime = tcpTime
        self.clientContext = clientContext
        self.isHTTPS = isHTTPS
        self.sourcePort = sourcePort
        self.breakpointPhase = breakpointPhase
        self.breakpointRuleName = breakpointRuleName
        self.headerResponseOperations = headerResponseOperations
        self.networkConditionProfile = networkConditionProfile
        self.scriptPluginManager = scriptPluginManager
        self.onBreakpointHit = onBreakpointHit
        self.breakpointBridgeTracker = breakpointBridgeTracker
        self.onTransactionComplete = onTransactionComplete
        self.onChannelClosed = onChannelClosed
        if let scriptPluginManager {
            self.hasResponseScript = scriptPluginManager.hasResponseHookForSnapshot(request: requestData)
        } else {
            self.hasResponseScript = false
        }
        self.deferRelayForScript = self.hasResponseScript
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
        // An HTTP/2 origin is reached through a stream channel whose parent is the connection.
        serverHTTPVersion = context.channel.parent == nil ? "1.1" : "2"
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
            guard let self else {
                return
            }
            // A response breakpoint sets `completed` at `.end` before pausing, so the
            // guard below would otherwise skip a paused item. Cancel it here first so
            // the queue drains; its resolution gate then suppresses relay/build because
            // the client channel is already inactive.
            self.cancelPendingResponseBreakpoint()
            guard !self.completed else {
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
        } else {
            failClientBeforeResponse(reason: "Upstream closed the connection before responding")
        }
    }

    /// The upstream went away (TLS handshake rejected, connection reset, server closed early)
    /// before a single response byte arrived. Without this the client would sit on an open
    /// socket until its own timeout and the request would never appear in the list.
    nonisolated private func failClientBeforeResponse(reason: String) {
        upstreamLogger.warning("Upstream failed before responding for \(self.requestData.url): \(reason)")
        if clientContext.channel.isActive {
            var head = HTTPResponseHead(version: .http1_1, status: .badGateway)
            head.headers.add(name: "Connection", value: "close")
            head.headers.add(name: "Content-Length", value: "0")
            clientContext.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
            clientContext.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { [clientContext] _ in
                clientContext.close(promise: nil)
            }
        }

        let transaction = HTTPTransaction(
            request: requestData,
            response: HTTPResponseData(statusCode: 502, statusMessage: reason, headers: []),
            state: .failed
        )
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds &- startTime.uptimeNanoseconds
        transaction.measuredDuration = Double(elapsedNanoseconds) / 1_000_000_000
        transaction.sourcePort = sourcePort
        transaction.clientApp = Self.extractAppFromUserAgent(requestData.headers)
        onTransactionComplete(transaction)
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
            // No Caching was decided when the request was forwarded, so the response is
            // marked uncacheable for the client exactly when its request was made fresh.
            if !isWebSocketUpgrade, disablesResponseCaching {
                NoCacheHeaderMutator.applyToResponse(&modifiedHead.headers)
            }

            responseHead = modifiedHead
            firstByteTime = .now()
            responseBody = context.channel.allocator.buffer(capacity: 0)

            if isWebSocketUpgrade {
                relayResponseHead(modifiedHead)
                pendingWebSocketUpgrade = true
                return
            }

            if !shouldBreakOnResponse, !deferRelayForScript {
                relayResponseHead(modifiedHead)
                if Self.isStreamingResponse(modifiedHead.headers) {
                    publishLiveStream(head: modifiedHead)
                }
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
                    let decision = ProxyHandlerShared.oversizeRelayDecision(
                        deferRelayForScript: deferRelayForScript,
                        shouldBreakOnResponse: shouldBreakOnResponse
                    )
                    switch decision {
                    case .suppressBreakpointAndResumeStreaming:
                        // The complete original body is no longer available, so allowing
                        // the breakpoint to Execute or Cancel would relay only a prefix.
                        // Suppress it, flush the captured prefix, and preserve the live
                        // response by streaming this and all subsequent chunks.
                        responseBreakpointSuppressed = true
                        deferRelayForScript = false
                        if let head = responseHead {
                            relayResponseHead(head)
                        }
                        if let buffered = responseBody, buffered.readableBytes > 0 {
                            relayResponseBody(buffered)
                        }
                        upstreamLogger.warning(
                            "Response exceeded capture cap; skipping response breakpoint and script mutation for \(self.requestData.url, privacy: .private)"
                        )
                    case .flushBufferedAndResumeStreaming:
                        // No breakpoint in play; abandon deferral, flush prefix, resume streaming.
                        deferRelayForScript = false
                        if let head = responseHead {
                            relayResponseHead(head)
                        }
                        if let buffered = responseBody, buffered.readableBytes > 0 {
                            relayResponseBody(buffered)
                        }
                        upstreamLogger.warning(
                            "Response exceeded capture cap; skipping script mutation for \(self.requestData.url, privacy: .private)"
                        )
                    case .alreadyStreaming:
                        break
                    }
                } else {
                    responseBody?.writeImmutableBuffer(buffer)
                }
            }
            if !shouldBreakOnResponse, !deferRelayForScript {
                relayResponseBody(buffer)
            }

        case let .end(trailers):
            guard !completed else {
                return
            }
            responseTrailers = trailers
            if pendingWebSocketUpgrade {
                completed = true
                readTimeoutTask?.cancel()
                readTimeoutTask = nil

                let handshakePromise = clientContext.eventLoop.makePromise(of: Void.self)
                clientContext.writeAndFlush(
                    NIOAny(HTTPServerResponsePart.end(nil)),
                    promise: handshakePromise
                )
                let webSocketLifecycle = WebSocketLifecycle(
                    onTransactionComplete: onTransactionComplete,
                    onChannelClosed: onChannelClosed
                )
                let handshake = WebSocketHandshakeRecord(
                    responseHead: responseHead,
                    timingInfo: buildTimingInfo(endTime: .now()),
                    sourcePort: sourcePort
                )
                handshakePromise.futureResult.flatMap { [clientContext, requestData, onTransactionComplete] in
                    WebSocketPipelineConfigurator.upgradeToWebSocket(
                        clientChannel: clientContext.channel,
                        serverChannel: context.channel,
                        requestData: requestData,
                        handshake: handshake,
                        onTransactionComplete: onTransactionComplete,
                        lifecycle: webSocketLifecycle
                    )
                }.whenFailure { error in
                    upstreamLogger.error("WebSocket upgrade failed: \(error.localizedDescription)")
                    webSocketLifecycle.failSetup()
                    self.clientContext.close(promise: nil)
                    context.close(promise: nil)
                }
                return
            }
            completed = true
            readTimeoutTask?.cancel()
            readTimeoutTask = nil

            if deferRelayForScript {
                runResponseScriptThenContinue(context: context)
            } else if shouldBreakOnResponse, let onBreakpointHit, let head = responseHead {
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
        } else if !completed, !Self.isUncleanTLSShutdown(error) {
            completed = true
            failClientBeforeResponse(reason: Self.upstreamFailureReason(for: error))
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

    /// A short, user-facing reason for the failed row. Certificate problems are the case a
    /// developer most needs to recognise, so they get a dedicated message.
    nonisolated static func upstreamFailureReason(for error: Error) -> String {
        if let sslError = error as? NIOSSLError {
            switch sslError {
            case .handshakeFailed:
                return "Upstream TLS handshake failed (certificate rejected)"
            default:
                return "Upstream TLS error"
            }
        }
        if error is NIOSSLExtraError {
            return "Upstream TLS handshake failed (certificate rejected)"
        }
        return "Upstream connection failed before responding"
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
    private let breakpointRuleName: String?
    private let headerResponseOperations: [HeaderOperation]?
    private let disablesResponseCaching: Bool
    private let networkConditionProfile: NetworkConditionProfile?
    private let scriptPluginManager: ScriptPluginManager?
    private let hasResponseScript: Bool
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?
    private let breakpointBridgeTracker: BreakpointBridgeTracker?
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onChannelClosed: @Sendable () -> Void

    private var responseHead: HTTPResponseHead?
    /// Trailers sent after the body (HTTP/2, or chunked HTTP/1.1), e.g. `grpc-status`.
    private var responseTrailers: HTTPHeaders?
    private var serverHTTPVersion: String?
    private var pendingWebSocketUpgrade = false
    private var channelClosedCalled = false
    private var responseBody: ByteBuffer?
    private var responseBodyTruncated = false
    private var responseBreakpointSuppressed = false
    private var firstByteTime: DispatchTime?
    private var completed = false
    private var readTimeoutTask: Scheduled<Void>?
    /// The unstructured Task bridging an in-flight response breakpoint to the
    /// @MainActor queue. Retained so a downstream-client disconnect can cancel it and
    /// drain the paused item instead of leaking the row and its continuation. Only the
    /// client `closeFuture` cancels it — an upstream close after a full response is a
    /// normal end-of-stream and must not disturb a legitimately paused breakpoint.
    private var pendingResponseBreakpointTask: Task<Void, Never>?
    private var downloadReadyAtNanos: UInt64?
    private var downloadTailFuture: EventLoopFuture<Void>?
    /// The row published when a streaming response's head arrived, completed in place at `.end`.
    private var liveStreamTransaction: HTTPTransaction?

    /// True while we are buffering the response before relaying, because a
    /// matching response-side script is expected to mutate it. Flipped to false
    /// if the body exceeds the capture cap (in which case we flush what we have
    /// and resume streaming — see Truncated-Response Policy).
    private var deferRelayForScript: Bool = false

    private var shouldBreakOnResponse: Bool {
        guard !responseBreakpointSuppressed,
              onBreakpointHit != nil,
              let phase = breakpointPhase else
        {
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

    nonisolated private func cancelPendingResponseBreakpoint() {
        pendingResponseBreakpointTask?.cancel()
        pendingResponseBreakpointTask = nil
    }

    // MARK: - Client Relay

    nonisolated private func relayResponseHead(_ head: HTTPResponseHead) {
        guard clientContext.channel.isActive else {
            return
        }
        let proxyHead = HTTPResponseHead(version: head.version, status: head.status, headers: head.headers)
        let part = NIOAny(HTTPServerResponsePart.head(proxyHead))
        if networkConditionProfile?.downloadBytesPerSecond != nil {
            clientContext.writeAndFlush(part, promise: nil)
        } else {
            clientContext.write(part, promise: nil)
        }
    }

    nonisolated private func relayResponseBody(_ buffer: ByteBuffer) {
        guard clientContext.channel.isActive else {
            return
        }
        guard let plan = NetworkThrottlePlanner.makePlan(
            byteCount: buffer.readableBytes,
            bytesPerSecond: networkConditionProfile?.downloadBytesPerSecond,
            earliestReadyAtNanos: downloadReadyAtNanos
        ) else {
            clientContext.write(
                NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))),
                promise: nil
            )
            return
        }

        downloadReadyAtNanos = plan.readyAtNanos
        for chunk in plan.chunks {
            let isLastChunk = chunk == plan.chunks.last
            let tailPromise = isLastChunk ? clientContext.eventLoop.makePromise(of: Void.self) : nil
            if let tailPromise {
                downloadTailFuture = tailPromise.futureResult
            }
            clientContext.eventLoop.scheduleTask(in: .milliseconds(chunk.delayMs)) { [clientContext] in
                guard clientContext.channel.isActive else {
                    tailPromise?.fail(ChannelError.ioOnClosedChannel)
                    return
                }
                var chunkBuffer = buffer
                chunkBuffer.moveReaderIndex(forwardBy: chunk.offset)
                let slice = chunkBuffer.readSlice(length: chunk.length) ?? chunkBuffer
                let bodyPromise = clientContext.eventLoop.makePromise(of: Void.self)
                clientContext.writeAndFlush(
                    NIOAny(HTTPServerResponsePart.body(.byteBuffer(slice))),
                    promise: bodyPromise
                )
                if let tailPromise {
                    bodyPromise.futureResult.whenComplete { result in
                        tailPromise.completeWith(result)
                    }
                }
            }
        }
    }

    nonisolated private func relayResponseEnd() {
        guard clientContext.channel.isActive else {
            return
        }
        let trailers = responseTrailers
        if let downloadTailFuture {
            self.downloadTailFuture = nil
            downloadTailFuture.whenComplete { [clientContext] _ in
                guard clientContext.channel.isActive else {
                    return
                }
                clientContext.writeAndFlush(
                    NIOAny(HTTPServerResponsePart.end(trailers)),
                    promise: nil
                )
            }
            return
        }
        let delayMs = NetworkThrottlePlanner.millisecondsUntil(readyAtNanos: downloadReadyAtNanos)
        clientContext.eventLoop.scheduleTask(in: .milliseconds(delayMs)) { [clientContext] in
            guard clientContext.channel.isActive else {
                return
            }
            clientContext.writeAndFlush(
                NIOAny(HTTPServerResponsePart.end(trailers)),
                promise: nil
            )
        }
    }

    // MARK: - Response Script

    nonisolated private func runResponseScriptThenContinue(context: ChannelHandlerContext) {
        guard let head = responseHead, let scriptPluginManager else {
            relayResponseEnd()
            buildAndCompleteTransaction()
            context.close(promise: nil)
            return
        }

        let headers = head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }
        let bodyData: Data? = if let buf = responseBody, buf.readableBytes > 0,
                                 let bytes = buf.getBytes(at: buf.readerIndex, length: buf.readableBytes)
        {
            Data(bytes)
        } else {
            nil
        }
        let contentType = ContentTypeDetector.detect(headers: headers, body: bodyData)
        let originalResponse = HTTPResponseData(
            statusCode: Int(head.status.code),
            statusMessage: head.status.reasonPhrase,
            headers: headers,
            body: bodyData,
            bodyTruncated: false,
            contentType: contentType
        )

        let request = requestData
        let eventLoop = context.eventLoop

        eventLoop.makeFutureWithTask {
            await scriptPluginManager.runResponseHook(request: request, response: originalResponse)
        }.whenComplete { [weak self] result in
            guard let self else {
                return
            }
            let mutated: HTTPResponseData = (try? result.get()) ?? originalResponse
            self.applyMutatedResponseAndRelay(mutated: mutated, context: context)
        }
    }

    nonisolated private func applyMutatedResponseAndRelay(
        mutated: HTTPResponseData,
        context: ChannelHandlerContext
    ) {
        let mutatedHead = ProxyHandlerShared.buildRelayResponseHead(
            from: mutated,
            originalHead: responseHead
        )
        responseHead = mutatedHead
        if let body = mutated.body {
            var buffer = clientContext.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            responseBody = buffer
        } else {
            responseBody = nil
        }

        // Hand off to the breakpoint path if one is armed — it now operates on the
        // script-mutated buffers.
        if shouldBreakOnResponse, let onBreakpointHit {
            handleResponseBreakpoint(context: context, head: mutatedHead, onBreakpointHit: onBreakpointHit)
            return
        }

        relayResponseHead(mutatedHead)
        if let buf = responseBody, buf.readableBytes > 0 {
            relayResponseBody(buf)
        }
        relayResponseEnd()
        buildAndCompleteTransaction()
        context.close(promise: nil)
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
        // Compressed origin bodies are decoded for the editor; the editable headers then
        // describe the plain body so an executed edit is relayed with consistent framing.
        let projection = BreakpointRequestData.editableResponseProjection(
            body: bodyData,
            headers: responseHeaders
        )

        let breakpointData = BreakpointRequestData(
            method: requestData.method,
            url: requestData.url.absoluteString,
            headers: projection.headers,
            body: projection.text,
            statusCode: Int(head.status.code),
            phase: .response,
            isBodyEditable: projection.isEditable,
            matchedRuleName: breakpointRuleName
        )

        let eventLoop = context.eventLoop
        let promise = eventLoop.makePromise(of: (BreakpointDecision, BreakpointRequestData).self)

        let bridgeLease = breakpointBridgeTracker?.begin()
        pendingResponseBreakpointTask = promise.completeWithTask {
            await onBreakpointHit(breakpointData)
        }
        clientContext.channel.probeBreakpointClientLiveness()

        promise.futureResult.whenComplete { [weak self] result in
            defer { bridgeLease?.finish() }
            guard let self else {
                return
            }
            self.pendingResponseBreakpointTask = nil
            // If the downstream client disconnected during the pause, do not relay the
            // response or build a (duplicate) completed transaction — just release the
            // upstream channel.
            guard self.clientContext.channel.isActive else {
                upstreamLogger.debug("Response breakpoint resolved after client disconnect; dropping relay")
                context.close(promise: nil)
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
            let originalBody = responseBody.flatMap { buffer -> Data? in
                guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else {
                    return nil
                }
                return Data(bytes)
            }
            let built = BreakpointResponseBuilder.build(
                modifiedData: modifiedData,
                originalHead: originalHead,
                originalBody: originalBody
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

            let responseData = HTTPResponseData(
                statusCode: 503,
                statusMessage: "Service Unavailable",
                headers: [HTTPHeader(name: "Connection", value: "close")]
            )
            let transaction = HTTPTransaction(
                request: requestData,
                response: responseData,
                state: .failed,
                timingInfo: buildTimingInfo(endTime: .now()),
                graphQLInfo: graphQLInfo,
                web3RPCInfo: Web3RPCDetector.detect(request: requestData, response: responseData),
                x402Info: X402Detector.detect(request: requestData, response: responseData)
            )
            transaction.sourcePort = sourcePort
            transaction.clientApp = Self.extractAppFromUserAgent(requestData.headers)
            onTransactionComplete(transaction)
            context.close(promise: nil)
        }
    }

    // MARK: - Transaction Assembly

    /// Server-sent events and newline-delimited JSON stay open for as long as the server keeps
    /// producing — an LLM completion commonly streams for 30 s or more. Only these content
    /// types get a live row, so ordinary responses keep their single delivery.
    nonisolated static func isStreamingResponse(_ headers: HTTPHeaders) -> Bool {
        guard let contentType = headers.first(name: "Content-Type")?.lowercased() else {
            return false
        }
        let mediaType = contentType.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return [
            "text/event-stream",
            "application/x-ndjson",
            "application/ndjson",
            "application/jsonl",
            "application/x-jsonlines",
        ].contains(mediaType)
    }

    /// Delivers a streaming response as an `.active` row the moment its head arrives, so a
    /// long stream is visible while it runs instead of appearing only once it ends. The same
    /// transaction is completed in place by `buildAndCompleteTransaction()`.
    nonisolated private func publishLiveStream(head: HTTPResponseHead) {
        guard liveStreamTransaction == nil else {
            return
        }
        let headers = head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }
        let transaction = HTTPTransaction(
            request: requestData,
            response: HTTPResponseData(
                statusCode: Int(head.status.code),
                statusMessage: head.status.reasonPhrase,
                headers: headers,
                body: nil,
                contentType: ContentTypeDetector.detect(headers: headers, body: nil)
            ),
            state: .active,
            graphQLInfo: graphQLInfo
        )
        transaction.sourcePort = sourcePort
        transaction.clientApp = Self.extractAppFromUserAgent(requestData.headers)
        liveStreamTransaction = transaction
        onTransactionComplete(transaction)
    }

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
        responseData.trailers = responseTrailers.map { $0.map { HTTPHeader(name: $0.name, value: $0.value) } }

        let timing = buildTimingInfo(endTime: endTime)

        let transaction = HTTPTransaction(
            request: requestData,
            response: responseData,
            state: .completed,
            timingInfo: timing,
            graphQLInfo: graphQLInfo,
            web3RPCInfo: Web3RPCDetector.detect(request: requestData, response: responseData),
            x402Info: X402Detector.detect(request: requestData, response: responseData)
        )
        transaction.sourcePort = sourcePort
        transaction.clientApp = Self.extractAppFromUserAgent(requestData.headers)
        transaction.noCachingApplied = disablesResponseCaching
        transaction.serverHTTPVersion = serverHTTPVersion

        guard let live = liveStreamTransaction else {
            onTransactionComplete(transaction)
            return
        }
        // The live row has been observed by the UI since its head arrived, so its fields are
        // written on the main actor before the closing delivery updates the existing row.
        liveStreamTransaction = nil
        let onTransactionComplete = onTransactionComplete
        Task { @MainActor in
            live.response = transaction.response
            live.timingInfo = transaction.timingInfo
            live.web3RPCInfo = transaction.web3RPCInfo
            live.x402Info = transaction.x402Info
            live.noCachingApplied = transaction.noCachingApplied
            live.serverHTTPVersion = transaction.serverHTTPVersion
            live.state = .completed
            onTransactionComplete(live)
        }
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
