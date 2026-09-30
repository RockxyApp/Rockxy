import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import os

// Defines `HTTPSProxyRelayHandler`, which handles https proxy relay flow in the proxy
// engine.

nonisolated(unsafe) private let httpsRelayLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "HTTPSProxyRelayHandler"
)

// MARK: - HTTPSProxyRelayHandler

/// Handles decrypted HTTPS traffic after TLS termination. Operates identically to
/// `HTTPProxyHandler` for plain HTTP, but reconstructs URLs with the `https://` scheme
/// and establishes a TLS client connection to the real upstream server.
final class HTTPSProxyRelayHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        host: String,
        port: Int,
        scheme: String = "https",
        ruleEngine: RuleEngine,
        scriptPluginManager: ScriptPluginManager? = nil,
        connectionLimiter: ConnectionLimiter,
        customCertificateManager: CustomCertificateManager = .shared,
        upstreamProxySnapshotProvider: @escaping @Sendable () -> UpstreamProxyResolvedConfiguration? = { nil },
        upstreamTrustProvider: @escaping @Sendable () -> Bool = { UpstreamTrustPolicy.acceptsUntrustedCertificates },
        captureContextProvider: @escaping @Sendable () -> TrafficCaptureContext? = { nil },
        clientSourcePort: UInt16? = nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? =
            nil,
        breakpointBridgeTracker: BreakpointBridgeTracker? = nil,
        connectHost: String? = nil
    ) {
        self.host = host
        self.connectHost = connectHost ?? host
        self.port = port
        self.scheme = scheme
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.connectionLimiter = connectionLimiter
        self.customCertificateManager = customCertificateManager
        self.upstreamProxySnapshotProvider = upstreamProxySnapshotProvider
        self.upstreamTrustProvider = upstreamTrustProvider
        self.captureContextProvider = captureContextProvider
        self.clientSourcePort = clientSourcePort
        // Every transaction this handler emits was decrypted inside an intercepted tunnel, so
        // stamp capture truth once at the single delivery seam. The request list then reports
        // it as intercepted regardless of how the host policy later changes. The stamp runs on
        // the event loop before the downstream callback hands the transaction off, preserving
        // the existing happens-before ordering used for other pre-delivery fields.
        let isDecryptedTunnel = scheme == "https"
        self.onTransactionComplete = { transaction in
            if transaction.sslCapture == nil, isDecryptedTunnel {
                transaction.sslCapture = .intercepted
            }
            onTransactionComplete(transaction)
        }
        self.onBreakpointHit = onBreakpointHit
        self.breakpointBridgeTracker = breakpointBridgeTracker
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !requestBodyLimitState.isRejected else {
            return
        }
        let part = unwrapInboundIn(data)
        switch part {
        case let .head(head):
            requestHead = head
            requestBody = context.channel.allocator.buffer(capacity: 0)
            requestStartTime = .now()
            requestCaptureContext = captureContextProvider()
            requestBodyLimitState.reset()

        case let .body(buffer):
            guard requestBodyLimitState.accept(buffer.readableBytes) else {
                httpsRelayLogger
                    .warning("SECURITY: HTTPS request body exceeds \(ProxyLimits.maxRequestBodySize) bytes, rejecting")
                let head = requestHead ?? HTTPRequestHead(version: .http1_1, method: .POST, uri: "/")
                sendErrorResponse(
                    context: context,
                    status: 413,
                    requestData: buildRequestData(from: head),
                    callback: onTransactionComplete
                )
                requestHead = nil
                requestBody = nil
                requestCaptureContext = nil
                return
            }
            requestBody?.writeImmutableBuffer(buffer)

        case .end:
            guard let head = requestHead else {
                return
            }
            forwardHTTPSRequest(context: context, head: head)
            requestHead = nil
            requestBody = nil
            requestCaptureContext = nil
        }
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        cancelPendingBreakpoint()
        if let sslError = error as? NIOSSLError, case .uncleanShutdown = sslError {
            context.close(promise: nil)
            return
        }
        httpsRelayLogger.error("HTTPS relay error for \(self.host): \(String(describing: error))")
        context.close(promise: nil)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        // Client disconnected while a request breakpoint may still be paused: cancel
        // the waiting Task so the queue drains and no upstream work is initiated.
        cancelPendingBreakpoint()
        context.fireChannelInactive()
    }

    nonisolated func handlerRemoved(context: ChannelHandlerContext) {
        cancelPendingBreakpoint()
    }

    // MARK: Private

    private let host: String
    /// Where the origin connection goes; differs from `host` only for emulator loopback aliases.
    private let connectHost: String
    private let port: Int
    /// `https` for a decrypted TLS tunnel, `http` when the CONNECT tunnel carried plain HTTP
    /// (a `ws://` upgrade or an http:// request sent through CONNECT).
    private let scheme: String
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let connectionLimiter: ConnectionLimiter
    private let customCertificateManager: CustomCertificateManager
    private let upstreamProxySnapshotProvider: @Sendable () -> UpstreamProxyResolvedConfiguration?
    private let upstreamTrustProvider: @Sendable () -> Bool
    private let captureContextProvider: @Sendable () -> TrafficCaptureContext?
    private let clientSourcePort: UInt16?
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?
    private let breakpointBridgeTracker: BreakpointBridgeTracker?

    private var pendingDisablesResponseCaching = false
    private var pendingBreakpointPhase: BreakpointRulePhase?
    private var pendingBreakpointRuleName: String?
    /// The unstructured Task bridging an in-flight request breakpoint to the
    /// @MainActor queue. Retained so a client disconnect / proxy stop can cancel it
    /// and drain the paused item instead of leaking the row and its continuation.
    private var pendingBreakpointTask: Task<Void, Never>?

    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?
    private var requestStartTime: DispatchTime?
    private var requestCaptureContext: TrafficCaptureContext?
    private var requestBodyLimitState = RequestBodyLimitState()

    /// Builds an `HTTPResponseData` from a resolved Map Local payload, deriving the standard
    /// reason phrase when the payload did not carry one. Shared with the single-file and
    /// directory serving paths so HTTP and HTTPS stay structurally identical.
    nonisolated private static func mapLocalResponse(
        from payload: MapLocalResponseResolver.Payload
    )
        -> HTTPResponseData
    {
        let message = payload.statusMessage ?? HTTPResponseStatus(statusCode: payload.statusCode).reasonPhrase
        return HTTPResponseData(
            statusCode: payload.statusCode,
            statusMessage: message,
            headers: payload.headers,
            body: payload.body
        )
    }

    nonisolated private func makeTransactionCallback(
        for matchedRule: ProxyRule?
    )
        -> @Sendable (HTTPTransaction) -> Void
    {
        ProxyHandlerShared.makeTransactionCallback(
            for: matchedRule,
            downstream: onTransactionComplete
        )
    }

    nonisolated private func forwardHTTPSRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead
    ) {
        pendingBreakpointPhase = nil
        pendingBreakpointRuleName = nil
        var requestData = buildRequestData(from: head)

        var head = head
        // Decided once per request so the relayed response is marked uncacheable exactly
        // when its request was made fresh; consumed by `connectToUpstream`.
        pendingDisablesResponseCaching = NoCacheHeaderMutator.isEnabled
        if pendingDisablesResponseCaching {
            requestData.headers = NoCacheHeaderMutator.apply(to: requestData.headers)
            head.headers = HTTPHeaders(requestData.headers.map { ($0.name, $0.value) })
        }

        let startTime = requestStartTime ?? .now()
        let graphQLInfo = GraphQLDetector.detect(request: requestData)
        let callback = onTransactionComplete

        let eventLoop = context.eventLoop
        let ruleEngine = self.ruleEngine

        eventLoop.makeFutureWithTask {
            await ProxyHandlerShared.evaluateRules(
                ruleEngine,
                request: requestData,
                graphQLOperationName: graphQLInfo?.operationName
            )
        }.whenComplete { [weak self] result in
            guard let self else {
                return
            }
            let evaluation = try? result.get()
            let breakpointRule = evaluation?.0
            let matchedRule = evaluation?.1
            let ruleForTransaction = ProxyHandlerShared.transactionRule(
                breakpointRule: breakpointRule,
                matchedRule: matchedRule
            )
            let matchedRuleCallback = self.makeTransactionCallback(for: ruleForTransaction)

            self.pendingBreakpointRuleName = breakpointRule?.name
            if let responsePhase = breakpointRule?.action.responseBreakpointPhase {
                self.pendingBreakpointPhase = responsePhase
            }

            if let breakpointRule,
               case let .breakpoint(phase) = breakpointRule.action,
               phase == .request || phase == .both
            {
                self.handleRuleAction(
                    breakpointRule.action,
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: self.makeTransactionCallback(for: breakpointRule),
                    matchContext: MapLocalMatchContext(matchCondition: breakpointRule.matchCondition)
                )
                return
            }

            if let matchedRule {
                self.handleRuleAction(
                    matchedRule.action,
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: matchedRuleCallback,
                    matchContext: MapLocalMatchContext(matchCondition: matchedRule.matchCondition)
                )
                return
            }

            if let scriptPluginManager = self.scriptPluginManager {
                let eventLoop = context.eventLoop
                eventLoop.makeFutureWithTask {
                    await scriptPluginManager.runRequestHook(on: requestData)
                }.whenSuccess { [weak self] outcome in
                    guard let self else {
                        return
                    }
                    switch outcome {
                    case let .forward(modifiedRequest):
                        self.connectToUpstream(
                            context: context,
                            head: head,
                            requestData: modifiedRequest,
                            graphQLInfo: graphQLInfo,
                            startTime: startTime,
                            callback: callback
                        )
                    case .blockLocally:
                        self.sendBlockResponse(
                            context: context,
                            status: 403,
                            requestData: requestData,
                            callback: callback
                        )
                    case let .mock(mockResponse):
                        self.sendMappedResponse(
                            context: context,
                            responseData: mockResponse,
                            requestData: requestData,
                            callback: callback
                        )
                    case .mockFailure:
                        self.sendBlockResponse(
                            context: context,
                            status: 502,
                            requestData: requestData,
                            callback: callback
                        )
                    }
                }
            } else {
                self.connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
            }
        }
    }

    nonisolated private func buildRequestData(from head: HTTPRequestHead) -> HTTPRequestData {
        let headers = head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }
        let body: Data? = if let buffer = requestBody, buffer.readableBytes > 0,
                             let bytes = buffer.getBytes(
                                 at: buffer.readerIndex,
                                 length: buffer.readableBytes
                             )
        {
            Data(bytes)
        } else {
            nil
        }
        // swiftlint:disable:next force_unwrapping
        let fallbackURL = URL(string: "\(scheme)://localhost/")!
        let authority = ProxyHandlerShared.authority(host: host, port: port, scheme: scheme)
        let requestTarget = head.uri.hasPrefix("/") ? head.uri : "/\(head.uri)"
        let parsedURL = URL(string: "\(scheme)://\(authority)\(requestTarget)")
            ?? URL(string: "\(scheme)://\(authority)/")
            ?? fallbackURL
        return HTTPRequestData(
            method: head.method.rawValue,
            url: parsedURL,
            httpVersion: "\(head.version.major).\(head.version.minor)",
            headers: headers,
            body: body,
            contentType: ContentTypeDetector.detect(headers: headers, body: body),
            captureContext: requestCaptureContext
        )
    }

    nonisolated private func connectToUpstream(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        responseHeaderOperations: [HeaderOperation]? = nil,
        networkConditionProfile: NetworkConditionProfile? = nil,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        let upstreamHost = self.host
        let upstreamPort = self.port

        guard connectionLimiter.acquire(host: upstreamHost, port: upstreamPort) else {
            httpsRelayLogger.warning("Connection limit reached for \(upstreamHost):\(upstreamPort)")
            sendErrorResponse(
                context: context,
                status: 503,
                requestData: requestData,
                callback: callback
            )
            return
        }

        let connectTime = DispatchTime.now()
        let limiter = connectionLimiter

        if scheme != "https" {
            UpstreamProxyConnector.connect(
                eventLoop: context.eventLoop,
                targetScheme: scheme,
                targetHost: connectHost,
                targetPort: port,
                configuration: upstreamProxySnapshotProvider()
            ) { channel in
                channel.pipeline.addHTTPClientHandlers(leftOverBytesStrategy: .forwardBytes)
            }
            .whenComplete { result in
                self.handleUpstreamConnection(
                    result: result,
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    connectTime: connectTime,
                    upstreamHost: upstreamHost,
                    upstreamPort: upstreamPort,
                    responseHeaderOperations: responseHeaderOperations,
                    networkConditionProfile: networkConditionProfile,
                    callback: callback
                )
            }
            return
        }

        do {
            var clientTLSConfig = try Self.makeClientTLSConfiguration(
                clientIdentity: customCertificateManager.clientIdentity(for: upstreamHost),
                acceptsUntrustedCertificates: upstreamTrustProvider(),
                host: upstreamHost
            )
            let offersHTTP2 = HTTP2ProxyOptions.isEnabled
            if offersHTTP2 {
                clientTLSConfig.applicationProtocols = HTTP2ProxyOptions.alpnProtocols
            }
            let sslContext = try NIOSSLContext(configuration: clientTLSConfig)
            let upstreamProxy = upstreamProxySnapshotProvider()
            UpstreamHTTPChannelConnector.connect(
                eventLoop: context.eventLoop,
                host: host,
                sslContext: sslContext,
                offersHTTP2: offersHTTP2
            ) { initializer in
                UpstreamProxyConnector.connect(
                    eventLoop: context.eventLoop,
                    targetScheme: "https",
                    targetHost: self.connectHost,
                    targetPort: upstreamPort,
                    configuration: upstreamProxy,
                    channelInitializer: initializer
                )
            }
            .whenComplete { result in
                self.handleUpstreamConnection(
                    result: result,
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    connectTime: connectTime,
                    upstreamHost: upstreamHost,
                    upstreamPort: upstreamPort,
                    responseHeaderOperations: responseHeaderOperations,
                    networkConditionProfile: networkConditionProfile,
                    offeredProtocols: clientTLSConfig.applicationProtocols,
                    callback: callback
                )
            }
        } catch {
            httpsRelayLogger.error("Client TLS setup failed: \(error.localizedDescription)")
            limiter.release(host: upstreamHost, port: upstreamPort)
            sendErrorResponse(
                context: context,
                status: 502,
                requestData: requestData,
                callback: callback
            )
        }
    }

    nonisolated private func handleUpstreamConnection(
        result: Result<Channel, Error>,
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        connectTime: DispatchTime,
        upstreamHost: String,
        upstreamPort: Int,
        responseHeaderOperations: [HeaderOperation]? = nil,
        networkConditionProfile: NetworkConditionProfile? = nil,
        offeredProtocols: [String] = [],
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        let limiter = connectionLimiter
        switch result {
        case let .success(clientChannel):
            let tcpTime = DispatchTime.now()
            let responseHandler = UpstreamResponseHandler(
                requestData: requestData,
                graphQLInfo: graphQLInfo,
                startTime: startTime,
                connectTime: connectTime,
                tcpTime: tcpTime,
                clientContext: context,
                isHTTPS: true,
                tlsIntent: requestData.url.scheme == "https"
                    ? UpstreamTLSIntent(
                        offeredProtocols: offeredProtocols,
                        acceptsUntrustedCertificates: upstreamTrustProvider()
                    )
                    : nil,
                sourcePort: self.clientSourcePort,
                breakpointPhase: self.pendingBreakpointPhase,
                breakpointRuleName: self.pendingBreakpointRuleName,
                headerResponseOperations: responseHeaderOperations,
                disablesResponseCaching: self.pendingDisablesResponseCaching,
                networkConditionProfile: networkConditionProfile,
                scriptPluginManager: self.scriptPluginManager,
                onBreakpointHit: self.onBreakpointHit,
                breakpointBridgeTracker: self.breakpointBridgeTracker,
                onTransactionComplete: callback,
                onChannelClosed: { limiter.release(host: upstreamHost, port: upstreamPort) }
            )
            self.pendingBreakpointPhase = nil
            self.pendingBreakpointRuleName = nil
            clientChannel.pipeline.addHandler(responseHandler).whenComplete { result in
                switch result {
                case .success:
                    let forwardHead = ProxyHandlerShared.buildForwardHead(
                        from: requestData,
                        originalHead: head
                    )
                    clientChannel.write(NIOAny(HTTPClientRequestPart.head(forwardHead)), promise: nil)
                    if let bodyData = requestData.body, !bodyData.isEmpty {
                        NetworkConditionIOThrottle.writeClientRequestBodyAndEnd(
                            bodyData: bodyData,
                            to: clientChannel,
                            uploadBytesPerSecond: networkConditionProfile?.uploadBytesPerSecond,
                            packetLoss: networkConditionProfile?.packetLoss
                        )
                    } else {
                        NetworkConditionIOThrottle.writeClientRequestBodyAndEnd(
                            bodyData: nil,
                            to: clientChannel,
                            uploadBytesPerSecond: networkConditionProfile?.uploadBytesPerSecond,
                            packetLoss: networkConditionProfile?.packetLoss
                        )
                    }
                case let .failure(error):
                    httpsRelayLogger.error(
                        "Failed to add response handler to upstream: \(error.localizedDescription)"
                    )
                    clientChannel.close(promise: nil)
                    limiter.release(host: upstreamHost, port: upstreamPort)
                    self.sendErrorResponse(context: context, status: 502, requestData: requestData, callback: callback)
                }
            }

        case let .failure(error):
            httpsRelayLogger.error("Upstream connection failed: \(error.localizedDescription)")
            limiter.release(host: upstreamHost, port: upstreamPort)
            self.sendErrorResponse(
                context: context,
                status: 502,
                requestData: requestData,
                callback: ConnectionLogCapture.attachingFailure(
                    error,
                    host: upstreamHost,
                    port: upstreamPort,
                    connectHost: upstreamHost == self.host
                        ? self.connectHost
                        : DNSSpoofingTable.shared.address(for: upstreamHost) ?? upstreamHost,
                    to: callback
                )
            )
        }
    }

    nonisolated private func handleRuleAction(
        _ action: RuleAction,
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        callback: @escaping @Sendable (HTTPTransaction) -> Void,
        matchContext: MapLocalMatchContext? = nil
    ) {
        switch action {
        case let .block(statusCode):
            sendBlockResponse(
                context: context,
                status: statusCode,
                requestData: requestData,
                callback: callback
            )

        case let .mapLocal(filePath, statusCode, isDirectory, delayMs, responseHeaders):
            let performMapLocal = { [weak self] in
                guard let self else {
                    return
                }
                if isDirectory {
                    self.handleMapLocalDirectory(
                        context: context,
                        head: head,
                        directoryPath: filePath,
                        statusCode: statusCode,
                        responseHeaders: responseHeaders,
                        requestData: requestData,
                        graphQLInfo: graphQLInfo,
                        startTime: startTime,
                        callback: callback,
                        matchContext: matchContext ?? MapLocalMatchContext(matchCondition: RuleMatchCondition())
                    )
                } else {
                    self.handleMapLocal(
                        context: context,
                        head: head,
                        filePath: filePath,
                        statusCode: statusCode,
                        responseHeaders: responseHeaders,
                        requestData: requestData,
                        graphQLInfo: graphQLInfo,
                        startTime: startTime,
                        callback: callback
                    )
                }
            }
            let effectiveDelayMs = delayMs < 0 ? Int.random(in: 1_000 ... 15_000) : delayMs
            if effectiveDelayMs > 0 {
                context.eventLoop.scheduleTask(in: .milliseconds(Int64(effectiveDelayMs))) {
                    performMapLocal()
                }
            } else {
                performMapLocal()
            }

        case let .mapRemote(configuration):
            handleMapRemote(
                context: context,
                configuration: configuration,
                head: head,
                requestData: requestData,
                graphQLInfo: graphQLInfo,
                startTime: startTime,
                callback: callback
            )

        case let .throttle(delayMs):
            let delay = TimeAmount.milliseconds(Int64(delayMs))
            context.eventLoop.scheduleTask(in: delay) { [weak self] in
                self?.connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
            }

        case let .networkCondition(preset, delayMs, custom):
            if preset.isOffline {
                ProxyHandlerShared.simulateOffline(
                    context: context,
                    requestData: requestData,
                    elapsed: requestElapsedDuration(),
                    sourcePort: clientSourcePort,
                    callback: callback
                )
                return
            }
            let profile = NetworkConditionProfile(preset: preset, latencyMs: delayMs, custom: custom)
            context.eventLoop.scheduleTask(in: profile.latencyDelay) { [weak self] in
                self?.connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    networkConditionProfile: profile,
                    callback: callback
                )
            }

        case let .modifyHeader(operations):
            let requestOps = HeaderOperation.requestPhase(from: operations)
            let responseOps = HeaderOperation.responsePhase(from: operations)
            var modifiedData = requestData
            HeaderMutator.apply(requestOps, to: &modifiedData.headers)
            var modifiedHead = head
            modifiedHead.headers = HTTPHeaders(modifiedData.headers.map { ($0.name, $0.value) })
            connectToUpstream(
                context: context,
                head: modifiedHead,
                requestData: modifiedData,
                graphQLInfo: graphQLInfo,
                startTime: startTime,
                responseHeaderOperations: responseOps.isEmpty ? nil : responseOps,
                callback: callback
            )

        case let .breakpoint(phase):
            pendingBreakpointPhase = phase
            if phase == .request || phase == .both {
                handleBreakpoint(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
            } else {
                connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
            }
        }
    }

    nonisolated private func sendBlockResponse(
        context: ChannelHandlerContext,
        status: Int,
        requestData: HTTPRequestData,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        guard context.channel.isActive else {
            return
        }

        if status == 0 {
            context.close(promise: nil)
            let transaction = HTTPTransaction(
                request: requestData,
                response: nil,
                state: .blocked
            )
            transaction.measuredDuration = requestElapsedDuration()
            transaction.sourcePort = clientSourcePort
            callback(transaction)
            return
        }

        let httpStatus = HTTPResponseStatus(statusCode: status)
        var responseHead = HTTPResponseHead(version: .http1_1, status: httpStatus)
        responseHead.headers.add(name: "Connection", value: "close")
        context.write(NIOAny(HTTPServerResponsePart.head(responseHead)), promise: nil)
        context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }

        let transaction = HTTPTransaction(
            request: requestData,
            response: HTTPResponseData(
                statusCode: status,
                statusMessage: httpStatus.reasonPhrase,
                headers: []
            ),
            state: status == 403 ? .blocked : .failed
        )
        transaction.measuredDuration = requestElapsedDuration()
        transaction.sourcePort = clientSourcePort
        callback(transaction)
    }

    nonisolated private func handleMapLocal(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        filePath: String,
        statusCode: Int,
        responseHeaders: [HTTPHeader],
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        guard let data = MapLocalFileValidator.loadFileData(at: filePath) else {
            // Missing / unreadable / oversized target — serve the origin instead of a
            // synthesized 404 so a broken mapping degrades to normal traffic.
            httpsRelayLogger.info("Map local file unavailable, falling back to origin")
            connectToUpstream(
                context: context,
                head: head,
                requestData: requestData,
                graphQLInfo: graphQLInfo,
                startTime: startTime,
                callback: callback
            )
            return
        }

        let outcome = MapLocalResponseResolver.resolve(
            fileData: data,
            actionStatusCode: statusCode,
            configuredHeaders: responseHeaders,
            inferredContentType: MimeTypeResolver.mimeType(for: filePath)
        )
        switch outcome {
        case let .serve(payload):
            sendMappedResponse(
                context: context,
                responseData: Self.mapLocalResponse(from: payload),
                requestData: requestData,
                callback: callback
            )
        case .fallbackToOrigin:
            // Invalid status or a malformed HTTP-message-looking file — forward the origin.
            httpsRelayLogger.info("Map local response invalid, falling back to origin")
            connectToUpstream(
                context: context,
                head: head,
                requestData: requestData,
                graphQLInfo: graphQLInfo,
                startTime: startTime,
                callback: callback
            )
        }
    }

    nonisolated private func handleMapLocalDirectory(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        directoryPath: String,
        statusCode: Int,
        responseHeaders: [HTTPHeader],
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        callback: @escaping @Sendable (HTTPTransaction) -> Void,
        matchContext: MapLocalMatchContext
    ) {
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: requestData.url.absoluteString,
            matchContext: matchContext,
            directoryPath: directoryPath
        )
        switch result {
        case let .success(file):
            let outcome = MapLocalResponseResolver.resolve(
                fileData: file.data,
                actionStatusCode: statusCode,
                configuredHeaders: responseHeaders,
                inferredContentType: file.mimeType
            )
            switch outcome {
            case let .serve(payload):
                sendMappedResponse(
                    context: context,
                    responseData: Self.mapLocalResponse(from: payload),
                    requestData: requestData,
                    callback: callback
                )
            case .fallbackToOrigin:
                httpsRelayLogger.info("Map local directory response invalid, falling back to origin")
                connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
            }
        case .failure:
            // Unresolved / invalid target — fall back to the origin request.
            httpsRelayLogger.info("Map local directory unresolved, falling back to origin")
            connectToUpstream(
                context: context,
                head: head,
                requestData: requestData,
                graphQLInfo: graphQLInfo,
                startTime: startTime,
                callback: callback
            )
        }
    }


    nonisolated private func sendMappedResponse(
        context: ChannelHandlerContext,
        responseData: HTTPResponseData,
        requestData: HTTPRequestData,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        let status = HTTPResponseStatus(statusCode: responseData.statusCode)
        var responseHead = HTTPResponseHead(version: .http1_1, status: status)
        for header in responseData.headers {
            responseHead.headers.add(name: header.name, value: header.value)
        }
        context.write(NIOAny(HTTPServerResponsePart.head(responseHead)), promise: nil)
        if let body = responseData.body {
            var buffer = context.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)

        let transaction = HTTPTransaction(
            request: requestData,
            response: responseData,
            state: .completed,
            x402Info: X402Detector.detect(request: requestData, response: responseData)
        )
        transaction.measuredDuration = requestElapsedDuration()
        transaction.sourcePort = clientSourcePort
        callback(transaction)
    }

    nonisolated private func sendErrorResponse(
        context: ChannelHandlerContext,
        status: Int,
        requestData: HTTPRequestData,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        guard context.channel.isActive else {
            return
        }
        let httpStatus = HTTPResponseStatus(statusCode: status)
        var responseHead = HTTPResponseHead(version: .http1_1, status: httpStatus)
        responseHead.headers.add(name: "Connection", value: "close")
        context.write(NIOAny(HTTPServerResponsePart.head(responseHead)), promise: nil)
        context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }

        let transaction = HTTPTransaction(
            request: requestData,
            response: HTTPResponseData(
                statusCode: status,
                statusMessage: httpStatus.reasonPhrase,
                headers: []
            ),
            state: status == 403 ? .blocked : .failed
        )
        transaction.measuredDuration = requestElapsedDuration()
        transaction.sourcePort = clientSourcePort
        callback(transaction)
    }

    nonisolated private func requestElapsedDuration() -> TimeInterval? {
        guard let requestStartTime else {
            return nil
        }
        let elapsedNanos = DispatchTime.now().uptimeNanoseconds - requestStartTime.uptimeNanoseconds
        return TimeInterval(elapsedNanos) / 1_000_000_000.0
    }

    /// Pauses the HTTPS request and presents the breakpoint UI for user decision. Bridges
    /// from the NIO event loop to @MainActor via an EventLoopPromise + async task.
    nonisolated private func handleBreakpoint(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        guard let onBreakpointHit else {
            httpsRelayLogger.warning("Breakpoint rule matched but no handler configured, forwarding HTTPS request")
            connectToUpstream(
                context: context,
                head: head,
                requestData: requestData,
                graphQLInfo: graphQLInfo,
                startTime: startTime,
                callback: callback
            )
            return
        }

        let authority = ProxyHandlerShared.authority(host: host, port: port, scheme: scheme)
        let urlString = "\(scheme)://\(authority)\(head.uri)"
        let bodyProjection = BreakpointRequestData.editableBodyProjection(from: requestData.body)
        let breakpointData = BreakpointRequestData(
            method: head.method.rawValue,
            url: urlString,
            headers: requestData.headers.map { EditableHeader(name: $0.name, value: $0.value) },
            body: bodyProjection.text,
            statusCode: 200,
            phase: .request,
            isBodyEditable: bodyProjection.isEditable,
            fixedHTTPSAuthority: authority,
            matchedRuleName: pendingBreakpointRuleName
        )

        let eventLoop = context.eventLoop
        let promise = eventLoop.makePromise(of: (BreakpointDecision, BreakpointRequestData).self)

        let bridgeLease = breakpointBridgeTracker?.begin()
        pendingBreakpointTask = promise.completeWithTask {
            await onBreakpointHit(breakpointData)
        }
        context.channel.probeBreakpointClientLiveness()

        promise.futureResult.whenComplete { [weak self] result in
            defer { bridgeLease?.finish() }
            guard let self else {
                return
            }
            self.pendingBreakpointTask = nil
            // If the downstream client is gone (disconnect / proxy stop), a resolved
            // breakpoint must not start any origin work or write a response.
            guard context.channel.isActive else {
                httpsRelayLogger.debug("HTTPS breakpoint resolved after client disconnect; dropping upstream work")
                return
            }
            switch result {
            case let .success((decision, modifiedData)):
                self.executeBreakpointDecision(
                    decision,
                    modifiedData: modifiedData,
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
            case let .failure(error):
                httpsRelayLogger.error(
                    "HTTPS breakpoint handler failed: \(error.localizedDescription), forwarding"
                )
                self.connectToUpstream(
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: callback
                )
            }
        }
    }

    nonisolated private func cancelPendingBreakpoint() {
        pendingBreakpointTask?.cancel()
        pendingBreakpointTask = nil
    }

    nonisolated private func executeBreakpointDecision(
        _ decision: BreakpointDecision,
        modifiedData: BreakpointRequestData,
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        switch decision {
        case .execute:
            if let status = modifiedData.requestLimitViolationStatusCode {
                self.sendErrorResponse(
                    context: context,
                    status: status,
                    requestData: requestData,
                    callback: callback
                )
                return
            }
            let built = BreakpointRequestBuilder.build(
                from: modifiedData,
                originalHead: head,
                originalRequestData: requestData,
                isHTTPS: true,
                originalHost: self.host,
                originalPort: self.port
            )
            if let redirect = built.upstreamRedirect {
                // The edit names another server: connect there like a Map Remote rule would.
                self.handleMapRemote(
                    context: context,
                    configuration: redirect.mapRemoteConfiguration,
                    head: built.head,
                    requestData: built.requestData,
                    graphQLInfo: GraphQLDetector.detect(request: built.requestData),
                    startTime: startTime,
                    recordsMapRemote: false,
                    callback: callback
                )
                return
            }
            self.connectToUpstream(
                context: context,
                head: built.head,
                requestData: built.requestData,
                graphQLInfo: GraphQLDetector.detect(request: built.requestData),
                startTime: startTime,
                callback: callback
            )
        case .abort:
            self.sendBlockResponse(
                context: context,
                status: 503,
                requestData: requestData,
                callback: callback
            )
        case .cancel:
            self.connectToUpstream(
                context: context,
                head: head,
                requestData: requestData,
                graphQLInfo: graphQLInfo,
                startTime: startTime,
                callback: callback
            )
        }
    }
}

// MARK: - Client TLS

extension HTTPSProxyRelayHandler {
    nonisolated static func makeClientTLSConfiguration(
        clientIdentity: CustomTLSIdentity?,
        acceptsUntrustedCertificates: Bool = UpstreamTrustPolicy.acceptsUntrustedCertificates,
        host: String? = nil
    )
        throws -> TLSConfiguration
    {
        var clientTLSConfig = TLSConfiguration.makeClientConfiguration()
        clientTLSConfig.certificateVerification = UpstreamTrustPolicy.certificateVerification(
            acceptingUntrusted: acceptsUntrustedCertificates
        )
        // NIOSSL matches hostnames only through SNI, which an IP address cannot carry. For IP
        // origins the chain is still verified; the name check has nothing to compare against.
        if let host, TLSServerName.sni(for: host) == nil,
           clientTLSConfig.certificateVerification == .fullVerification
        {
            clientTLSConfig.certificateVerification = .noHostnameVerification
        }
        if let clientIdentity {
            clientTLSConfig.certificateChain = try clientIdentity.certificateSources
            clientTLSConfig.privateKey = try clientIdentity.privateKeySource
        }
        TLSKeyLogWriter.apply(to: &clientTLSConfig)
        return clientTLSConfig
    }
}

// MARK: - Map Remote

extension HTTPSProxyRelayHandler {
    nonisolated private func handleMapRemote(
        context: ChannelHandlerContext,
        configuration: MapRemoteConfiguration,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        recordsMapRemote: Bool = true,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        let rewrite = ProxyHandlerShared.buildMapRemoteRewrite(
            configuration: configuration,
            originalHead: head,
            requestData: requestData,
            fallbackScheme: scheme,
            fallbackHost: host,
            fallbackPort: port
        )
        let callback = recordsMapRemote
            ? ProxyHandlerShared.makeMapRemoteProvenanceCallback(originalURL: requestData.url, downstream: callback)
            : callback
        let remoteHost = rewrite.upstreamHost
        let remotePort = rewrite.upstreamPort
        let scheme = rewrite.scheme

        guard connectionLimiter.acquire(host: remoteHost, port: remotePort) else {
            httpsRelayLogger.warning("Connection limit reached for \(remoteHost):\(remotePort)")
            sendErrorResponse(context: context, status: 503, requestData: rewrite.requestData, callback: callback)
            return
        }
        let limiter = connectionLimiter

        if scheme == "https" {
            let connectTime = DispatchTime.now()
            do {
                let clientTLSConfig = try Self.makeClientTLSConfiguration(
                    clientIdentity: customCertificateManager.clientIdentity(for: remoteHost),
                    acceptsUntrustedCertificates: upstreamTrustProvider(),
                    host: remoteHost
                )
                let sslContext = try NIOSSLContext(configuration: clientTLSConfig)

                UpstreamProxyConnector.connect(
                    eventLoop: context.eventLoop,
                    targetScheme: "https",
                    targetHost: DNSSpoofingTable.shared.address(for: remoteHost) ?? remoteHost,
                    targetPort: remotePort,
                    configuration: upstreamProxySnapshotProvider()
                ) { channel in
                    do {
                        let sslHandler = try NIOSSLClientHandler(
                            context: sslContext,
                            serverHostname: TLSServerName.sni(for: remoteHost)
                        )
                        return channel.pipeline.addHandler(sslHandler).flatMap {
                            channel.pipeline.addHTTPClientHandlers(leftOverBytesStrategy: .forwardBytes)
                        }
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
                .whenComplete { [weak self] result in
                    guard let self else {
                        if case let .success(channel) = result {
                            channel.close(promise: nil)
                        }
                        limiter.release(host: remoteHost, port: remotePort)
                        return
                    }
                    self.handleUpstreamConnection(
                        result: result,
                        context: context,
                        head: rewrite.head,
                        requestData: rewrite.requestData,
                        graphQLInfo: graphQLInfo,
                        startTime: startTime,
                        connectTime: connectTime,
                        upstreamHost: remoteHost,
                        upstreamPort: remotePort,
                        callback: callback
                    )
                }
            } catch {
                httpsRelayLogger.error("Map remote TLS setup failed: \(error.localizedDescription)")
                limiter.release(host: remoteHost, port: remotePort)
                sendErrorResponse(context: context, status: 502, requestData: rewrite.requestData, callback: callback)
            }
        } else {
            let connectTime = DispatchTime.now()
            UpstreamProxyConnector.connect(
                eventLoop: context.eventLoop,
                targetScheme: scheme,
                targetHost: DNSSpoofingTable.shared.address(for: remoteHost) ?? remoteHost,
                targetPort: remotePort,
                configuration: upstreamProxySnapshotProvider()
            ) { channel in
                channel.pipeline.addHTTPClientHandlers(leftOverBytesStrategy: .forwardBytes)
            }
            .whenComplete { [weak self] result in
                guard let self else {
                    if case let .success(channel) = result {
                        channel.close(promise: nil)
                    }
                    limiter.release(host: remoteHost, port: remotePort)
                    return
                }
                self.handleUpstreamConnection(
                    result: result,
                    context: context,
                    head: rewrite.head,
                    requestData: rewrite.requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    connectTime: connectTime,
                    upstreamHost: remoteHost,
                    upstreamPort: remotePort,
                    callback: callback
                )
            }
        }
    }
}
