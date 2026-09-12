import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import os

/// Logger must be nonisolated(unsafe) because NIO channel handlers are called
/// from event loop threads outside Swift's structured concurrency.
nonisolated(unsafe) private let proxyHandlerLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "HTTPProxyHandler"
)

// MARK: - HTTPProxyHandler

/// Primary channel handler for all inbound proxy connections. Handles the initial
/// HTTP request from the client and decides how to process it:
///
/// - **CONNECT**: HTTPS tunnel — responds with 200, removes itself from the pipeline,
///   and hands off to `TLSInterceptHandler` for TLS man-in-the-middle decryption.
/// - **Plain HTTP**: Evaluates rules, then forwards to the upstream server via
///   `ClientBootstrap` and collects the response through `UpstreamResponseHandler`.
///
/// Marked `@unchecked Sendable` because NIO channel handlers are confined to a single
/// event loop thread; concurrent access does not occur in practice.
final class HTTPProxyHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        certificateManager: CertificateManager,
        ruleEngine: RuleEngine,
        scriptPluginManager: ScriptPluginManager? = nil,
        connectionLimiter: ConnectionLimiter,
        sslProxyingManager: SSLProxyingManager,
        bypassProxyManager: BypassProxyManager,
        customCertificateManager: CustomCertificateManager = .shared,
        upstreamProxySnapshotProvider: @escaping @Sendable () -> UpstreamProxyResolvedConfiguration? = { nil },
        captureContextProvider: @escaping @Sendable () -> TrafficCaptureContext? = { nil },
        shouldBypassUserModifications: @escaping @Sendable (HTTPRequestData) -> Bool = { _ in false },
        clientIdentityHandle: ClientIdentityHandle? = nil,
        clientConnectionDescriptor: ProxyConnectionDescriptor? = nil,
        liveTunnelRegistry: LiveTunnelRegistry? = nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? =
            nil,
        breakpointBridgeTracker: BreakpointBridgeTracker? = nil
    ) {
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.connectionLimiter = connectionLimiter
        self.sslProxyingManager = sslProxyingManager
        self.bypassProxyManager = bypassProxyManager
        self.customCertificateManager = customCertificateManager
        self.upstreamProxySnapshotProvider = upstreamProxySnapshotProvider
        self.captureContextProvider = captureContextProvider
        self.shouldBypassUserModifications = shouldBypassUserModifications
        self.clientIdentityHandle = clientIdentityHandle
        self.clientConnectionDescriptor = clientConnectionDescriptor
        self.liveTunnelRegistry = liveTunnelRegistry
        self.onTransactionComplete = onTransactionComplete
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
            if clientSourcePort == nil, let port = context.channel.remoteAddress?.port {
                clientSourcePort = UInt16(port)
            }

        case let .body(buffer):
            guard requestBodyLimitState.accept(buffer.readableBytes) else {
                proxyHandlerLogger
                    .warning("SECURITY: Request body exceeds \(ProxyLimits.maxRequestBodySize) bytes, rejecting")
                let head = requestHead ?? HTTPRequestHead(version: .http1_1, method: .POST, uri: "/")
                sendErrorResponse(context: context, status: 413, requestData: buildRequestData(from: head))
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
            processRequest(context: context, head: head)
            requestHead = nil
            requestBody = nil
            requestCaptureContext = nil
        }
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        proxyHandlerLogger.error("Channel error: \(error.localizedDescription)")
        cancelPendingBreakpoint()
        context.close(promise: nil)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        // Client disconnected while a request breakpoint may still be paused: cancel
        // the waiting Task so the queue drains and no upstream work is initiated.
        cancelPendingBreakpoint()
        context.fireChannelInactive()
    }

    nonisolated func handlerRemoved(context: ChannelHandlerContext) {
        pendingThrottleTask?.cancel()
        pendingThrottleTask = nil
        cancelPendingBreakpoint()
    }

    // MARK: Private

    private let certificateManager: CertificateManager
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let connectionLimiter: ConnectionLimiter
    private let sslProxyingManager: SSLProxyingManager
    private let bypassProxyManager: BypassProxyManager
    private let customCertificateManager: CustomCertificateManager
    private let upstreamProxySnapshotProvider: @Sendable () -> UpstreamProxyResolvedConfiguration?
    private let captureContextProvider: @Sendable () -> TrafficCaptureContext?
    private let shouldBypassUserModifications: @Sendable (HTTPRequestData) -> Bool
    private let clientIdentityHandle: ClientIdentityHandle?
    private let clientConnectionDescriptor: ProxyConnectionDescriptor?
    private let liveTunnelRegistry: LiveTunnelRegistry?
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?
    private let breakpointBridgeTracker: BreakpointBridgeTracker?
    private var pendingThrottleTask: Scheduled<Void>?
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
    private var clientSourcePort: UInt16?
    private var requestBodyLimitState = RequestBodyLimitState()

    /// Builds an `HTTPResponseData` from a resolved Map Local payload, deriving the standard
    /// reason phrase when the payload did not carry one.
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

    nonisolated private func processRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead
    ) {
        pendingBreakpointPhase = nil
        pendingBreakpointRuleName = nil

        if head.uri.count > ProxyLimits.maxURILength {
            proxyHandlerLogger.warning("SECURITY: URI exceeds \(ProxyLimits.maxURILength) chars, rejecting with 414")
            sendErrorResponse(context: context, status: 414, requestData: buildRequestData(from: head))
            return
        }

        proxyHandlerLogger.info("Processing \(head.method.rawValue) \(head.uri)")

        let requestData = buildRequestData(from: head)
        let headers = requestData.headers
        let method = requestData.method
        let url = requestData.url

        // Internal health probes must measure the listener and upstream relay itself, not
        // user-authored breakpoints, throttles, scripts, cache mutation, or External Proxy.
        // The injected predicate accepts only the currently registered random probe token.
        if shouldBypassUserModifications(requestData) {
            forwardRequest(
                context: context,
                head: head,
                requestData: requestData,
                bypassUserModifications: true,
                callback: onTransactionComplete
            )
            return
        }

        // Rule evaluation is async (actor-isolated), so bridge to NIO's EventLoopFuture world
        let eventLoop = context.eventLoop
        let ruleEngine = self.ruleEngine

        eventLoop.makeFutureWithTask {
            let breakpointRule = await ruleEngine.evaluateBreakpointRule(method: method, url: url, headers: headers)
            let matchedRule = await ruleEngine.evaluateRule(method: method, url: url, headers: headers)
            return (breakpointRule, matchedRule)
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
            let callback = self.makeTransactionCallback(for: ruleForTransaction)

            // CONNECT policy: only .block is meaningful on tunnel establishment (sends
            // rejection). All other actions either break the TLS handshake or produce
            // nonsensical results. The actual HTTP traffic inside the tunnel gets rules
            // applied by HTTPSProxyRelayHandler after decryption.
            if head.method == .CONNECT {
                if let matchedRule {
                    switch matchedRule.action {
                    case .block:
                        self.handleRuleAction(
                            matchedRule.action,
                            context: context,
                            head: head,
                            requestData: requestData,
                            callback: callback,
                            matchContext: MapLocalMatchContext(matchCondition: matchedRule.matchCondition)
                        )
                        return
                    case .throttle,
                         .networkCondition,
                         .mapLocal,
                         .mapRemote,
                         .modifyHeader,
                         .breakpoint:
                        break
                    }
                }
                self.handleConnect(
                    context: context,
                    head: head,
                    requestData: requestData
                )
                return
            }

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
                    callback: callback,
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
                        self.forwardRequest(
                            context: context,
                            head: head,
                            requestData: modifiedRequest,
                            callback: self.onTransactionComplete
                        )
                    case .blockLocally:
                        self.sendErrorResponse(
                            context: context,
                            status: 403,
                            requestData: requestData,
                            callback: self.onTransactionComplete
                        )
                    case let .mock(mockResponse):
                        self.sendResponse(
                            context: context,
                            responseData: mockResponse,
                            requestData: requestData,
                            callback: self.onTransactionComplete
                        )
                    case .mockFailure:
                        self.sendErrorResponse(
                            context: context,
                            status: 502,
                            requestData: requestData,
                            callback: self.onTransactionComplete
                        )
                    }
                }
            } else {
                self.forwardRequest(
                    context: context,
                    head: head,
                    requestData: requestData,
                    callback: self.onTransactionComplete
                )
            }
        }
    }

    nonisolated private func buildRequestData(from head: HTTPRequestHead) -> HTTPRequestData {
        let headers = head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }
        let host = head.headers["Host"].first ?? ""
        let uri = head.uri
        let url: String = if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
            uri
        } else {
            "http://\(host)\(uri)"
        }
        let body = requestBody.flatMap { buffer -> Data? in
            guard buffer.readableBytes > 0 else {
                return nil
            }
            guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else {
                return nil
            }
            return Data(bytes)
        }
        let contentType = ContentTypeDetector.detect(headers: headers, body: body)

        let fallbackURL = URL(string: "http://localhost/")!
        let parsedURL = URL(string: url) ?? URL(string: "http://\(host)/") ?? fallbackURL
        return HTTPRequestData(
            method: head.method.rawValue,
            url: parsedURL,
            httpVersion: "\(head.version.major).\(head.version.minor)",
            headers: headers,
            body: body,
            contentType: contentType,
            captureContext: requestCaptureContext
        )
    }

    nonisolated private func handleRuleAction(
        _ action: RuleAction,
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        callback: @escaping @Sendable (HTTPTransaction) -> Void,
        matchContext: MapLocalMatchContext? = nil
    ) {
        switch action {
        case let .block(statusCode):
            sendErrorResponse(context: context, status: statusCode, requestData: requestData, callback: callback)

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
                        callback: callback
                    )
                }
            }
            let effectiveDelayMs = delayMs < 0 ? Int.random(in: 1_000 ... 15_000) : delayMs
            if effectiveDelayMs > 0 {
                pendingThrottleTask = context.eventLoop.scheduleTask(in: .milliseconds(Int64(effectiveDelayMs))) {
                    performMapLocal()
                }
            } else {
                performMapLocal()
            }

        case let .modifyHeader(operations):
            let requestOps = HeaderOperation.requestPhase(from: operations)
            let responseOps = HeaderOperation.responsePhase(from: operations)
            var modifiedData = requestData
            HeaderMutator.apply(requestOps, to: &modifiedData.headers)
            var modifiedHead = head
            modifiedHead.headers = HTTPHeaders(modifiedData.headers.map { ($0.name, $0.value) })
            forwardRequest(
                context: context,
                head: modifiedHead,
                requestData: modifiedData,
                responseHeaderOperations: responseOps.isEmpty ? nil : responseOps,
                callback: callback
            )

        case let .mapRemote(configuration):
            handleMapRemote(
                context: context,
                head: head,
                requestData: requestData,
                configuration: configuration,
                callback: callback
            )

        case let .throttle(delayMs):
            let delay = TimeAmount.milliseconds(Int64(delayMs))
            pendingThrottleTask = context.eventLoop.scheduleTask(in: delay) { [weak self] in
                guard let self else {
                    return
                }
                self.forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
            }

        case let .networkCondition(preset, delayMs):
            let profile = NetworkConditionProfile(preset: preset, latencyMs: delayMs)
            pendingThrottleTask = context.eventLoop.scheduleTask(in: profile.latencyDelay) { [weak self] in
                guard let self else {
                    return
                }
                self.forwardRequest(
                    context: context,
                    head: head,
                    requestData: requestData,
                    networkConditionProfile: profile,
                    callback: callback
                )
            }

        case let .breakpoint(phase):
            pendingBreakpointPhase = phase
            if phase == .request || phase == .both {
                handleBreakpoint(context: context, head: head, requestData: requestData, callback: callback)
            } else {
                forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
            }
        }
    }

    nonisolated private func handleMapRemote(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        configuration: MapRemoteConfiguration,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        guard configuration.hasOverride else {
            forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
            return
        }

        let rewrite = ProxyHandlerShared.buildMapRemoteRewrite(
            configuration: configuration,
            originalHead: head,
            requestData: requestData,
            fallbackScheme: "http",
            fallbackHost: "localhost"
        )

        forwardRequest(context: context, head: rewrite.head, requestData: rewrite.requestData, callback: callback)
    }

    nonisolated private func handleMapLocal(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        filePath: String,
        statusCode: Int,
        responseHeaders: [HTTPHeader],
        requestData: HTTPRequestData,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        guard let data = MapLocalFileValidator.loadFileData(at: filePath) else {
            // Missing / unreadable / oversized target — serve the origin instead of a
            // synthesized 404 so a broken mapping degrades to normal traffic.
            proxyHandlerLogger.info("Map local file unavailable, falling back to origin")
            forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
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
            sendResponse(
                context: context,
                responseData: Self.mapLocalResponse(from: payload),
                requestData: requestData,
                callback: callback
            )
        case .fallbackToOrigin:
            // Invalid status or a malformed HTTP-message-looking file — forward the origin.
            proxyHandlerLogger.info("Map local response invalid, falling back to origin")
            forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
        }
    }

    nonisolated private func handleMapLocalDirectory(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        directoryPath: String,
        statusCode: Int,
        responseHeaders: [HTTPHeader],
        requestData: HTTPRequestData,
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
                sendResponse(
                    context: context,
                    responseData: Self.mapLocalResponse(from: payload),
                    requestData: requestData,
                    callback: callback
                )
            case .fallbackToOrigin:
                proxyHandlerLogger.info("Map local directory response invalid, falling back to origin")
                forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
            }
        case .failure:
            // Unresolved / invalid target — fall back to the origin request.
            proxyHandlerLogger.info("Map local directory unresolved, falling back to origin")
            forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
        }
    }

    /// Pauses the request and presents the breakpoint UI for user decision. The NIO
    /// event loop is freed via an EventLoopPromise that completes when the @MainActor
    /// breakpoint view model returns the user's choice.
    nonisolated private func handleBreakpoint(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        guard let onBreakpointHit else {
            proxyHandlerLogger.warning("Breakpoint rule matched but no handler configured, forwarding")
            forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
            return
        }

        let bodyProjection = BreakpointRequestData.editableBodyProjection(from: requestData.body)
        let breakpointData = BreakpointRequestData(
            method: head.method.rawValue,
            url: requestData.url.absoluteString,
            headers: requestData.headers.map { EditableHeader(name: $0.name, value: $0.value) },
            body: bodyProjection.text,
            statusCode: 200,
            phase: .request,
            isBodyEditable: bodyProjection.isEditable,
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
                proxyHandlerLogger.debug("Breakpoint resolved after client disconnect; dropping without upstream work")
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
                    callback: callback
                )
            case let .failure(error):
                proxyHandlerLogger.error("Breakpoint handler failed: \(error.localizedDescription), forwarding")
                self.forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
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
                originalRequestData: requestData
            )
            self.forwardRequest(context: context, head: built.head, requestData: built.requestData, callback: callback)
        case .abort:
            self.sendErrorResponse(context: context, status: 503, requestData: requestData, callback: callback)
        case .cancel:
            self.forwardRequest(context: context, head: head, requestData: requestData, callback: callback)
        }
    }
}

// MARK: - Connection Handling

extension HTTPProxyHandler {
    /// Handles HTTP CONNECT for HTTPS tunneling. Responds with 200 to establish the
    /// tunnel, then swaps this handler out for TLSInterceptHandler which will perform
    /// TLS termination with a per-host certificate.
    nonisolated func handleConnect(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData
    ) {
        guard let parsed = try? HostPortParser.parse(head.uri) else {
            proxyHandlerLogger.warning("SECURITY: Malformed CONNECT URI")
            sendErrorResponse(context: context, status: 400, requestData: requestData)
            return
        }
        let host = parsed.host
        let port = parsed.port

        var responseHead = HTTPResponseHead(version: head.version, status: .ok)
        responseHead.headers.add(name: "content-length", value: "0")
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).flatMap {
            proxyHandlerLogger.info("CONNECT tunnel for \(host):\(port)")
            return context.channel.setOption(ChannelOptions.autoRead, value: false)
        }.flatMap {
            context.pipeline.removeHandler(context: context)
        }.flatMap {
            ProxyPipeline.removeHTTPServerPipeline(from: context.pipeline, on: context.eventLoop)
        }.flatMap { () -> EventLoopFuture<ClientApplicationIdentity?> in
            let identityCanAffectDecision = self.sslProxyingManager.hasEnabledApplicationRules()
                || self.sslProxyingManager.shouldIntercept(host: host, application: nil)
            guard identityCanAffectDecision else {
                return context.eventLoop.makeSucceededFuture(nil)
            }
            // Start and await bounded resolution only when host or application policy can lead
            // to interception. autoRead is already false so no client bytes are lost; an
            // unresolved identity fails closed for application-only rules.
            return context.eventLoop.makeFutureWithTask {
                await self.clientIdentityHandle?.awaitIdentity()
            }
        }.flatMap { clientApplicationIdentity in
            let tlsHandler = TLSInterceptHandler(
                host: host,
                port: port,
                certificateManager: self.certificateManager,
                ruleEngine: self.ruleEngine,
                scriptPluginManager: self.scriptPluginManager,
                connectionLimiter: self.connectionLimiter,
                sslProxyingManager: self.sslProxyingManager,
                bypassProxyManager: self.bypassProxyManager,
                customCertificateManager: self.customCertificateManager,
                upstreamProxySnapshotProvider: self.upstreamProxySnapshotProvider,
                captureContextProvider: self.captureContextProvider,
                tunnelCaptureContext: requestData.captureContext,
                clientSourcePort: self.clientSourcePort,
                clientApplicationIdentity: clientApplicationIdentity,
                clientConnectionDescriptor: self.clientConnectionDescriptor,
                liveTunnelRegistry: self.liveTunnelRegistry,
                onTransactionComplete: self.onTransactionComplete,
                onBreakpointHit: self.onBreakpointHit,
                breakpointBridgeTracker: self.breakpointBridgeTracker
            )
            return context.pipeline.addHandler(tlsHandler)
        }.whenFailure { error in
            proxyHandlerLogger.error(
                "Failed to set up TLS handler for \(host): \(String(describing: error))"
            )
            self.onTransactionComplete(
                TLSInterceptHandler.makeTunnelTransaction(
                    host: host,
                    port: port,
                    statusCode: 500,
                    statusMessage: "TLS Handler Setup Failed",
                    state: .failed,
                    sourcePort: self.clientSourcePort,
                    captureContext: requestData.captureContext,
                    clientIdentifier: TLSInterceptHandler.clientScopeIdentifier(
                        application: nil,
                        connectionDescriptor: self.clientConnectionDescriptor
                    )
                )
            )
            context.close(promise: nil)
        }
    }

    nonisolated func forwardRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        responseHeaderOperations: [HeaderOperation]? = nil,
        networkConditionProfile: NetworkConditionProfile? = nil
    ) {
        forwardRequest(
            context: context,
            head: head,
            requestData: requestData,
            responseHeaderOperations: responseHeaderOperations,
            networkConditionProfile: networkConditionProfile,
            callback: onTransactionComplete
        )
    }

    nonisolated func forwardRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        responseHeaderOperations: [HeaderOperation]? = nil,
        networkConditionProfile: NetworkConditionProfile? = nil,
        bypassUserModifications: Bool = false,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        var head = head
        var requestData = requestData

        if !bypassUserModifications, NoCacheHeaderMutator.isEnabled {
            requestData.headers = NoCacheHeaderMutator.apply(to: requestData.headers)
            head.headers = HTTPHeaders(requestData.headers.map { ($0.name, $0.value) })
        }

        let host = requestData.host
        let startTime = requestStartTime ?? .now()
        let graphQLInfo = GraphQLDetector.detect(request: requestData)
        guard !host.isEmpty else {
            sendErrorResponse(context: context, status: 400, requestData: requestData, callback: callback)
            return
        }

        let port: Int = requestData.url.port ?? (requestData.url.scheme == "https" ? 443 : 80)

        let connectTime = DispatchTime.now()

        guard connectionLimiter.acquire(host: host, port: port) else {
            proxyHandlerLogger.warning("Connection limit reached for \(host):\(port)")
            sendErrorResponse(context: context, status: 503, requestData: requestData, callback: callback)
            return
        }

        let limiter = connectionLimiter
        let useTLS = requestData.url.scheme == "https"
        UpstreamProxyConnector.connect(
            eventLoop: context.eventLoop,
            targetScheme: requestData.url.scheme ?? "http",
            targetHost: host,
            targetPort: port,
            configuration: bypassUserModifications ? nil : upstreamProxySnapshotProvider()
        ) { channel in
            if useTLS {
                do {
                    let tlsConfig = try HTTPSProxyRelayHandler.makeClientTLSConfiguration(
                        clientIdentity: self.customCertificateManager.clientIdentity(for: host)
                    )
                    let sslContext = try NIOSSLContext(configuration: tlsConfig)
                    let sslHandler = try NIOSSLClientHandler(
                        context: sslContext,
                        serverHostname: host
                    )
                    return channel.pipeline.addHandler(sslHandler).flatMap {
                        channel.pipeline.addHTTPClientHandlers()
                    }
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            return channel.pipeline.addHTTPClientHandlers()
        }
        .whenComplete { [weak self] result in
            guard let self else {
                if case let .success(channel) = result {
                    channel.close(promise: nil)
                }
                limiter.release(host: host, port: port)
                return
            }
            switch result {
            case let .success(clientChannel):
                let tcpTime = DispatchTime.now()
                self.relayRequest(
                    context: context,
                    clientChannel: clientChannel,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    connectTime: connectTime,
                    tcpTime: tcpTime,
                    responseHeaderOperations: responseHeaderOperations,
                    networkConditionProfile: networkConditionProfile,
                    bypassUserModifications: bypassUserModifications,
                    onUpstreamClosed: { limiter.release(host: host, port: port) },
                    callback: callback
                )
            case let .failure(error):
                proxyHandlerLogger.error("Connection failed: \(error.localizedDescription)")
                limiter.release(host: host, port: port)
                self.sendErrorResponse(context: context, status: 502, requestData: requestData, callback: callback)
            }
        }
    }

    nonisolated private func relayRequest(
        context: ChannelHandlerContext,
        clientChannel: Channel,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        connectTime: DispatchTime,
        tcpTime: DispatchTime,
        responseHeaderOperations: [HeaderOperation]? = nil,
        networkConditionProfile: NetworkConditionProfile? = nil,
        bypassUserModifications: Bool = false,
        onUpstreamClosed: @escaping @Sendable () -> Void,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        let responseHandler = UpstreamResponseHandler(
            requestData: requestData,
            graphQLInfo: graphQLInfo,
            startTime: startTime,
            connectTime: connectTime,
            tcpTime: tcpTime,
            clientContext: context,
            sourcePort: clientSourcePort,
            breakpointPhase: pendingBreakpointPhase,
            breakpointRuleName: pendingBreakpointRuleName,
            headerResponseOperations: responseHeaderOperations,
            networkConditionProfile: networkConditionProfile,
            scriptPluginManager: bypassUserModifications ? nil : scriptPluginManager,
            onBreakpointHit: bypassUserModifications ? nil : onBreakpointHit,
            breakpointBridgeTracker: breakpointBridgeTracker,
            onTransactionComplete: callback,
            onChannelClosed: onUpstreamClosed
        )
        pendingBreakpointPhase = nil
        pendingBreakpointRuleName = nil

        clientChannel.pipeline.addHandler(responseHandler).whenComplete { result in
            switch result {
            case .success:
                // Rebuild the outbound head from (possibly script-mutated) requestData so
                // allowed mutations (method, path/query, headers, body-derived Content-Length)
                // actually reach upstream. Host/port/scheme mutations are dropped earlier in
                // ScriptRequestContext.apply(to:pluginID:).
                let forwardHead = ProxyHandlerShared.buildForwardHead(
                    from: requestData,
                    originalHead: head
                )
                clientChannel.write(NIOAny(HTTPClientRequestPart.head(forwardHead)), promise: nil)
                if let bodyData = requestData.body, !bodyData.isEmpty {
                    NetworkConditionIOThrottle.writeClientRequestBodyAndEnd(
                        bodyData: bodyData,
                        to: clientChannel,
                        uploadBytesPerSecond: networkConditionProfile?.uploadBytesPerSecond
                    )
                } else {
                    NetworkConditionIOThrottle.writeClientRequestBodyAndEnd(
                        bodyData: nil,
                        to: clientChannel,
                        uploadBytesPerSecond: networkConditionProfile?.uploadBytesPerSecond
                    )
                }
            case let .failure(error):
                proxyHandlerLogger.error(
                    "Failed to add response handler to upstream: \(error.localizedDescription)"
                )
                clientChannel.close(promise: nil)
                onUpstreamClosed()
                self.sendErrorResponse(context: context, status: 502, requestData: requestData, callback: callback)
            }
        }
    }

    nonisolated func sendErrorResponse(
        context: ChannelHandlerContext,
        status: Int,
        requestData: HTTPRequestData
    ) {
        sendErrorResponse(context: context, status: status, requestData: requestData, callback: onTransactionComplete)
    }

    nonisolated func sendErrorResponse(
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
        var responseHead = HTTPResponseHead(
            version: .http1_1,
            status: httpStatus
        )
        responseHead.headers.add(name: "Connection", value: "close")
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
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

    nonisolated private func sendResponse(
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
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        if let body = responseData.body {
            var buffer = context.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)

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

    nonisolated private func completeTransaction(
        context: ChannelHandlerContext,
        requestData: HTTPRequestData,
        state: TransactionState,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        let transaction = HTTPTransaction(request: requestData, state: state)
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
}
