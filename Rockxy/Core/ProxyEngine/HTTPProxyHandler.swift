import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import os

/// Logger must be nonisolated(unsafe) because NIO channel handlers are called
/// from event loop threads outside Swift's structured concurrency.
private nonisolated(unsafe) let proxyHandlerLogger = Logger(
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
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? = nil
    ) {
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.connectionLimiter = connectionLimiter
        self.onTransactionComplete = onTransactionComplete
        self.onBreakpointHit = onBreakpointHit
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case let .head(head):
            requestHead = head
            requestBody = context.channel.allocator.buffer(capacity: 0)
            requestStartTime = .now()
            accumulatedBodySize = 0
            if clientSourcePort == nil, let port = context.channel.remoteAddress?.port {
                clientSourcePort = UInt16(port)
            }

        case let .body(buffer):
            accumulatedBodySize += buffer.readableBytes
            guard accumulatedBodySize <= ProxyLimits.maxRequestBodySize else {
                proxyHandlerLogger
                    .warning("SECURITY: Request body exceeds \(ProxyLimits.maxRequestBodySize) bytes, rejecting")
                let head = requestHead ?? HTTPRequestHead(version: .http1_1, method: .POST, uri: "/")
                sendErrorResponse(context: context, status: 413, requestData: buildRequestData(from: head))
                requestHead = nil
                requestBody = nil
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
        }
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        proxyHandlerLogger.error("Channel error: \(error.localizedDescription)")
        context.close(promise: nil)
    }

    nonisolated func handlerRemoved(context: ChannelHandlerContext) {
        pendingThrottleTask?.cancel()
        pendingThrottleTask = nil
    }

    // MARK: Private

    private let certificateManager: CertificateManager
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let connectionLimiter: ConnectionLimiter
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?
    private var pendingThrottleTask: Scheduled<Void>?
    private var pendingBreakpointPhase: BreakpointRulePhase?

    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?
    private var requestStartTime: DispatchTime?
    private var clientSourcePort: UInt16?
    private var accumulatedBodySize: Int = 0

    private nonisolated func processRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead
    ) {
        pendingBreakpointPhase = nil

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

        // Rule evaluation is async (actor-isolated), so bridge to NIO's EventLoopFuture world
        let eventLoop = context.eventLoop
        let ruleEngine = self.ruleEngine

        eventLoop.makeFutureWithTask {
            await ruleEngine.evaluateRule(method: method, url: url, headers: headers)
        }.whenComplete { [weak self] result in
            guard let self else {
                return
            }
            let matchedRule: ProxyRule? = (try? result.get()) ?? nil

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
                            urlPattern: matchedRule.matchCondition.urlPattern
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
                self.handleConnect(context: context, head: head)
                return
            }

            if let matchedRule {
                self.handleRuleAction(
                    matchedRule.action,
                    context: context,
                    head: head,
                    requestData: requestData,
                    urlPattern: matchedRule.matchCondition.urlPattern
                )
                return
            }

            if let scriptPluginManager = self.scriptPluginManager {
                let eventLoop = context.eventLoop
                eventLoop.makeFutureWithTask {
                    await scriptPluginManager.runRequestHooks(on: requestData)
                }.whenSuccess { [weak self] modifiedRequest in
                    guard let self else {
                        return
                    }
                    self.forwardRequest(context: context, head: head, requestData: modifiedRequest)
                }
            } else {
                self.forwardRequest(context: context, head: head, requestData: requestData)
            }
        }
    }

    private nonisolated func buildRequestData(from head: HTTPRequestHead) -> HTTPRequestData {
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

        // swiftlint:disable:next force_unwrapping
        let fallbackURL = URL(string: "http://localhost/")!
        let parsedURL = URL(string: url) ?? URL(string: "http://\(host)/") ?? fallbackURL
        return HTTPRequestData(
            method: head.method.rawValue,
            url: parsedURL,
            httpVersion: "\(head.version.major).\(head.version.minor)",
            headers: headers,
            body: body,
            contentType: contentType
        )
    }

    private nonisolated func extractPath(from uri: String) -> String {
        if let urlComponents = URLComponents(string: uri) {
            return urlComponents.path.isEmpty ? "/" : urlComponents.path
        }
        return uri
    }

    private nonisolated func handleRuleAction(
        _ action: RuleAction,
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        urlPattern: String? = nil
    ) {
        switch action {
        case let .block(statusCode):
            sendErrorResponse(context: context, status: statusCode, requestData: requestData)

        case let .mapLocal(filePath, statusCode, isDirectory) where isDirectory:
            handleMapLocalDirectory(
                context: context,
                directoryPath: filePath,
                statusCode: statusCode,
                requestData: requestData,
                urlPattern: urlPattern ?? ""
            )

        case let .mapLocal(filePath, statusCode, _):
            handleMapLocal(context: context, filePath: filePath, statusCode: statusCode, requestData: requestData)

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
                responseHeaderOperations: responseOps.isEmpty ? nil : responseOps
            )

        case let .mapRemote(configuration):
            handleMapRemote(
                context: context,
                head: head,
                requestData: requestData,
                configuration: configuration
            )

        case let .throttle(delayMs):
            let delay = TimeAmount.milliseconds(Int64(delayMs))
            pendingThrottleTask = context.eventLoop.scheduleTask(in: delay) { [weak self] in
                guard let self else {
                    return
                }
                self.forwardRequest(context: context, head: head, requestData: requestData)
            }

        case let .networkCondition(_, delayMs):
            let delay = TimeAmount.milliseconds(Int64(delayMs))
            pendingThrottleTask = context.eventLoop.scheduleTask(in: delay) { [weak self] in
                guard let self else {
                    return
                }
                self.forwardRequest(context: context, head: head, requestData: requestData)
            }

        case let .breakpoint(phase):
            pendingBreakpointPhase = phase
            if phase == .request || phase == .both {
                handleBreakpoint(context: context, head: head, requestData: requestData)
            } else {
                forwardRequest(context: context, head: head, requestData: requestData)
            }
        }
    }

    private nonisolated func handleMapRemote(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        configuration: MapRemoteConfiguration
    ) {
        guard configuration.hasOverride else {
            forwardRequest(context: context, head: head, requestData: requestData)
            return
        }

        let originalURL = requestData.url
        let upstreamHost = configuration.host ?? (originalURL.host ?? "localhost")
        let scheme = configuration.scheme ?? (originalURL.scheme ?? "http")
        let port = configuration.port ?? (scheme == "https" ? 443 : (originalURL.port ?? 80))
        let path = configuration.path ?? originalURL.path
        let query = configuration.query ?? originalURL.query

        let effectivePath = path.isEmpty ? "/" : path
        let uri = query.map { "\(effectivePath)?\($0)" } ?? effectivePath

        var modifiedHead = head
        modifiedHead.uri = uri

        let hostHeaderValue: String = if configuration.preserveHostHeader {
            originalURL.host ?? upstreamHost
        } else {
            upstreamHost
        }
        modifiedHead.headers.replaceOrAdd(name: "Host", value: NetworkValidator.sanitizeHeaderValue(hostHeaderValue))

        var urlString = "\(scheme)://\(upstreamHost)"
        if port != 80, port != 443 {
            urlString += ":\(port)"
        }
        urlString += uri

        // swiftlint:disable:next force_unwrapping
        let fallbackURL = URL(string: "http://localhost/")!
        let modifiedData = HTTPRequestData(
            method: requestData.method,
            url: URL(string: urlString) ?? fallbackURL,
            httpVersion: requestData.httpVersion,
            headers: requestData.headers,
            body: requestData.body,
            contentType: requestData.contentType
        )

        forwardRequest(context: context, head: modifiedHead, requestData: modifiedData)
    }

    private nonisolated func handleMapLocal(
        context: ChannelHandlerContext,
        filePath: String,
        statusCode: Int,
        requestData: HTTPRequestData
    ) {
        guard let data = MapLocalFileValidator.loadFileData(at: filePath) else {
            sendErrorResponse(context: context, status: 404, requestData: requestData)
            return
        }

        let status = HTTPResponseStatus(statusCode: statusCode)
        let mimeType = MimeTypeResolver.mimeType(for: filePath)
        let responseData = HTTPResponseData(
            statusCode: statusCode,
            statusMessage: status.reasonPhrase,
            headers: [
                HTTPHeader(name: "Content-Length", value: "\(data.count)"),
                HTTPHeader(name: "Content-Type", value: mimeType),
            ],
            body: data
        )
        sendResponse(context: context, responseData: responseData, requestData: requestData)
    }

    private nonisolated func handleMapLocalDirectory(
        context: ChannelHandlerContext,
        directoryPath: String,
        statusCode: Int,
        requestData: HTTPRequestData,
        urlPattern: String
    ) {
        let requestPath = extractPath(from: requestData.url.absoluteString)
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: requestPath,
            urlPattern: urlPattern,
            directoryPath: directoryPath
        )
        switch result {
        case let .success(file):
            let status = HTTPResponseStatus(statusCode: statusCode)
            let responseData = HTTPResponseData(
                statusCode: statusCode,
                statusMessage: status.reasonPhrase,
                headers: [
                    HTTPHeader(name: "Content-Length", value: "\(file.data.count)"),
                    HTTPHeader(name: "Content-Type", value: file.mimeType),
                ],
                body: file.data
            )
            sendResponse(context: context, responseData: responseData, requestData: requestData)
        case .failure:
            sendErrorResponse(context: context, status: 404, requestData: requestData)
        }
    }

    /// Pauses the request and presents the breakpoint UI for user decision. The NIO
    /// event loop is freed via an EventLoopPromise that completes when the @MainActor
    /// breakpoint view model returns the user's choice.
    private nonisolated func handleBreakpoint(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData
    ) {
        guard let onBreakpointHit else {
            proxyHandlerLogger.warning("Breakpoint rule matched but no handler configured, forwarding")
            forwardRequest(context: context, head: head, requestData: requestData)
            return
        }

        let breakpointData = BreakpointRequestData(
            method: head.method.rawValue,
            url: requestData.url.absoluteString,
            headers: requestData.headers.map { EditableHeader(name: $0.name, value: $0.value) },
            body: requestData.body.flatMap { String(data: $0, encoding: .utf8) } ?? "",
            statusCode: 200,
            phase: .request
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
                self.executeBreakpointDecision(
                    decision,
                    modifiedData: modifiedData,
                    context: context,
                    head: head,
                    requestData: requestData
                )
            case let .failure(error):
                proxyHandlerLogger.error("Breakpoint handler failed: \(error.localizedDescription), forwarding")
                self.forwardRequest(context: context, head: head, requestData: requestData)
            }
        }
    }

    private nonisolated func executeBreakpointDecision(
        _ decision: BreakpointDecision,
        modifiedData: BreakpointRequestData,
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData
    ) {
        switch decision {
        case .execute:
            let built = BreakpointRequestBuilder.build(
                from: modifiedData,
                originalHead: head,
                originalRequestData: requestData
            )
            self.forwardRequest(context: context, head: built.head, requestData: built.requestData)
        case .abort:
            self.sendErrorResponse(context: context, status: 503, requestData: requestData)
        case .cancel:
            self.forwardRequest(context: context, head: head, requestData: requestData)
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
        head: HTTPRequestHead
    ) {
        guard let parsed = try? HostPortParser.parse(head.uri) else {
            proxyHandlerLogger.warning("SECURITY: Malformed CONNECT URI")
            sendErrorResponse(context: context, status: 400, requestData: buildRequestData(from: head))
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
        }.flatMap {
            let tlsHandler = TLSInterceptHandler(
                host: host,
                port: port,
                certificateManager: self.certificateManager,
                ruleEngine: self.ruleEngine,
                scriptPluginManager: self.scriptPluginManager,
                connectionLimiter: self.connectionLimiter,
                clientSourcePort: self.clientSourcePort,
                onTransactionComplete: self.onTransactionComplete,
                onBreakpointHit: self.onBreakpointHit
            )
            return context.pipeline.addHandler(tlsHandler)
        }.whenFailure { error in
            proxyHandlerLogger.error(
                "Failed to set up TLS handler for \(host): \(String(describing: error))"
            )
            context.close(promise: nil)
        }
    }

    nonisolated func forwardRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        responseHeaderOperations: [HeaderOperation]? = nil
    ) {
        var head = head
        var requestData = requestData

        if NoCacheHeaderMutator.isEnabled {
            requestData.headers = NoCacheHeaderMutator.apply(to: requestData.headers)
            head.headers = HTTPHeaders(requestData.headers.map { ($0.name, $0.value) })
        }

        let host = requestData.host
        let startTime = requestStartTime ?? .now()
        let graphQLInfo = GraphQLDetector.detect(request: requestData)
        let callback = onTransactionComplete

        guard !host.isEmpty else {
            sendErrorResponse(context: context, status: 400, requestData: requestData)
            return
        }

        let port: Int = requestData.url.port ?? (requestData.url.scheme == "https" ? 443 : 80)

        let connectTime = DispatchTime.now()

        guard connectionLimiter.acquire(host: host, port: port) else {
            proxyHandlerLogger.warning("Connection limit reached for \(host):\(port)")
            sendErrorResponse(context: context, status: 503, requestData: requestData)
            return
        }

        let limiter = connectionLimiter
        let useTLS = requestData.url.scheme == "https"
        ClientBootstrap(group: context.eventLoop)
            .connectTimeout(.seconds(5))
            .channelInitializer { channel in
                if useTLS {
                    do {
                        var tlsConfig = TLSConfiguration.makeClientConfiguration()
                        tlsConfig.certificateVerification = .fullVerification
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
            .connect(host: host, port: port)
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
                        onUpstreamClosed: { limiter.release(host: host, port: port) },
                        callback: callback
                    )
                case let .failure(error):
                    proxyHandlerLogger.error("Connection failed: \(error.localizedDescription)")
                    limiter.release(host: host, port: port)
                    self.sendErrorResponse(context: context, status: 502, requestData: requestData)
                }
            }
    }

    private nonisolated func relayRequest(
        context: ChannelHandlerContext,
        clientChannel: Channel,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        connectTime: DispatchTime,
        tcpTime: DispatchTime,
        responseHeaderOperations: [HeaderOperation]? = nil,
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
            headerResponseOperations: responseHeaderOperations,
            onBreakpointHit: onBreakpointHit,
            onTransactionComplete: callback,
            onChannelClosed: onUpstreamClosed
        )
        pendingBreakpointPhase = nil

        clientChannel.pipeline.addHandler(responseHandler).whenComplete { result in
            switch result {
            case .success:
                var modifiedHead = head
                // Proxy requests use absolute URIs (http://host/path); upstream servers
                // expect origin-form (just /path), so strip the scheme+host
                if !head.uri.hasPrefix("/") {
                    if let components = URLComponents(string: head.uri) {
                        modifiedHead.uri = components.path + (components.query.map { "?\($0)" } ?? "")
                    }
                }
                clientChannel.write(NIOAny(HTTPClientRequestPart.head(modifiedHead)), promise: nil)
                if let bodyData = requestData.body, !bodyData.isEmpty {
                    var bodyBuffer = clientChannel.allocator.buffer(capacity: bodyData.count)
                    bodyBuffer.writeBytes(bodyData)
                    clientChannel.write(
                        NIOAny(HTTPClientRequestPart.body(.byteBuffer(bodyBuffer))),
                        promise: nil
                    )
                }
                let endPromise = clientChannel.eventLoop.makePromise(of: Void.self)
                endPromise.futureResult.whenFailure { _ in
                    clientChannel.close(promise: nil)
                }
                clientChannel.writeAndFlush(
                    NIOAny(HTTPClientRequestPart.end(nil)),
                    promise: endPromise
                )
            case let .failure(error):
                proxyHandlerLogger.error(
                    "Failed to add response handler to upstream: \(error.localizedDescription)"
                )
                clientChannel.close(promise: nil)
                onUpstreamClosed()
                self.sendErrorResponse(context: context, status: 502, requestData: requestData)
            }
        }
    }

    nonisolated func sendErrorResponse(
        context: ChannelHandlerContext,
        status: Int,
        requestData: HTTPRequestData
    ) {
        guard context.channel.isActive else {
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
        transaction.sourcePort = clientSourcePort
        onTransactionComplete(transaction)
    }

    private nonisolated func sendResponse(
        context: ChannelHandlerContext,
        responseData: HTTPResponseData,
        requestData: HTTPRequestData
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
            state: .completed
        )
        transaction.sourcePort = clientSourcePort
        onTransactionComplete(transaction)
    }

    private nonisolated func completeTransaction(
        context: ChannelHandlerContext,
        requestData: HTTPRequestData,
        state: TransactionState
    ) {
        let transaction = HTTPTransaction(request: requestData, state: state)
        transaction.sourcePort = clientSourcePort
        onTransactionComplete(transaction)
    }
}
