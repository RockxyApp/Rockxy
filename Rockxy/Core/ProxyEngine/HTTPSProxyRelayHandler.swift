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
final class HTTPSProxyRelayHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        host: String,
        port: Int,
        ruleEngine: RuleEngine,
        scriptPluginManager: ScriptPluginManager? = nil,
        connectionLimiter: ConnectionLimiter,
        clientSourcePort: UInt16? = nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? = nil
    ) {
        self.host = host
        self.port = port
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.connectionLimiter = connectionLimiter
        self.clientSourcePort = clientSourcePort
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

        case let .body(buffer):
            accumulatedBodySize += buffer.readableBytes
            guard accumulatedBodySize <= ProxyLimits.maxRequestBodySize else {
                httpsRelayLogger
                    .warning("SECURITY: HTTPS request body exceeds \(ProxyLimits.maxRequestBodySize) bytes, rejecting")
                sendErrorResponse(context: context, status: 413)
                requestHead = nil
                requestBody = nil
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
        }
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let sslError = error as? NIOSSLError, case .uncleanShutdown = sslError {
            context.close(promise: nil)
            return
        }
        httpsRelayLogger.error("HTTPS relay error for \(self.host): \(String(describing: error))")
        context.close(promise: nil)
    }

    // MARK: Private

    private let host: String
    private let port: Int
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let connectionLimiter: ConnectionLimiter
    private let clientSourcePort: UInt16?
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?

    private var pendingBreakpointPhase: BreakpointRulePhase?

    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?
    private var requestStartTime: DispatchTime?
    private var accumulatedBodySize: Int = 0

    nonisolated private func makeTransactionCallback(
        for matchedRule: ProxyRule?
    )
        -> @Sendable (HTTPTransaction) -> Void
    {
        let downstream = onTransactionComplete
        let matchedRuleID = matchedRule?.id
        let matchedRuleName = matchedRule?.name
        let matchedRuleActionSummary = matchedRule?.action.matchedRuleActionSummary
        let matchedRulePattern = matchedRule?.matchCondition.urlPattern

        return { transaction in
            transaction.matchedRuleID = matchedRuleID
            transaction.matchedRuleName = matchedRuleName
            transaction.matchedRuleActionSummary = matchedRuleActionSummary
            transaction.matchedRulePattern = matchedRulePattern
            downstream(transaction)
        }
    }

    nonisolated private func forwardHTTPSRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead
    ) {
        pendingBreakpointPhase = nil
        let headers = head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }
        let body: Data? = if let buf = requestBody, buf.readableBytes > 0 {
            if let bytes = buf.getBytes(at: buf.readerIndex, length: buf.readableBytes) {
                Data(bytes)
            } else {
                nil
            }
        } else {
            nil
        }
        let urlString = "https://\(host)\(head.uri)"
        // swiftlint:disable:next force_unwrapping
        let fallbackURL = URL(string: "https://localhost/")!
        let parsedURL = URL(string: urlString) ?? URL(string: "https://\(host)/") ?? fallbackURL
        var requestData = HTTPRequestData(
            method: head.method.rawValue,
            url: parsedURL,
            httpVersion: "\(head.version.major).\(head.version.minor)",
            headers: headers,
            body: body,
            contentType: ContentTypeDetector.detect(headers: headers, body: body)
        )

        var head = head
        if NoCacheHeaderMutator.isEnabled {
            requestData.headers = NoCacheHeaderMutator.apply(to: requestData.headers)
            head.headers = HTTPHeaders(requestData.headers.map { ($0.name, $0.value) })
        }

        let startTime = requestStartTime ?? .now()
        let graphQLInfo = GraphQLDetector.detect(request: requestData)
        let callback = onTransactionComplete

        let eventLoop = context.eventLoop
        let ruleEngine = self.ruleEngine

        eventLoop.makeFutureWithTask {
            await ruleEngine.evaluateRule(
                method: head.method.rawValue,
                url: parsedURL,
                headers: requestData.headers
            )
        }.whenComplete { [weak self] result in
            guard let self else {
                return
            }
            let matchedRule: ProxyRule? = (try? result.get()) ?? nil
            let matchedRuleCallback = self.makeTransactionCallback(for: matchedRule)

            if let matchedRule {
                self.handleRuleAction(
                    matchedRule.action,
                    context: context,
                    head: head,
                    requestData: requestData,
                    graphQLInfo: graphQLInfo,
                    startTime: startTime,
                    callback: matchedRuleCallback,
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
                    self.connectToUpstream(
                        context: context,
                        head: head,
                        requestData: modifiedRequest,
                        graphQLInfo: graphQLInfo,
                        startTime: startTime,
                        callback: callback
                    )
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

    nonisolated private func connectToUpstream(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        responseHeaderOperations: [HeaderOperation]? = nil,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        let upstreamHost = self.host
        let upstreamPort = self.port

        guard connectionLimiter.acquire(host: upstreamHost, port: upstreamPort) else {
            httpsRelayLogger.warning("Connection limit reached for \(upstreamHost):\(upstreamPort)")
            sendErrorResponse(context: context, status: 503)
            return
        }

        let connectTime = DispatchTime.now()
        let limiter = connectionLimiter

        do {
            var clientTLSConfig = TLSConfiguration.makeClientConfiguration()
            clientTLSConfig.certificateVerification = .fullVerification
            let sslContext = try NIOSSLContext(configuration: clientTLSConfig)

            ClientBootstrap(group: context.eventLoop)
                .connectTimeout(.seconds(5))
                .channelInitializer { channel in
                    do {
                        let sslHandler = try NIOSSLClientHandler(
                            context: sslContext,
                            serverHostname: self.host
                        )
                        return channel.pipeline.addHandler(sslHandler).flatMap {
                            channel.pipeline.addHTTPClientHandlers()
                        }
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
                .connect(host: host, port: port)
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
                        callback: callback
                    )
                }
        } catch {
            httpsRelayLogger.error("Client TLS setup failed: \(error.localizedDescription)")
            limiter.release(host: upstreamHost, port: upstreamPort)
            sendErrorResponse(context: context, status: 502)
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
                sourcePort: self.clientSourcePort,
                breakpointPhase: self.pendingBreakpointPhase,
                headerResponseOperations: responseHeaderOperations,
                onBreakpointHit: self.onBreakpointHit,
                onTransactionComplete: callback,
                onChannelClosed: { limiter.release(host: upstreamHost, port: upstreamPort) }
            )
            self.pendingBreakpointPhase = nil
            clientChannel.pipeline.addHandler(responseHandler).whenComplete { result in
                switch result {
                case .success:
                    clientChannel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
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
                    httpsRelayLogger.error(
                        "Failed to add response handler to upstream: \(error.localizedDescription)"
                    )
                    clientChannel.close(promise: nil)
                    limiter.release(host: upstreamHost, port: upstreamPort)
                    self.sendErrorResponse(context: context, status: 502)
                }
            }

        case let .failure(error):
            httpsRelayLogger.error("Upstream connection failed: \(error.localizedDescription)")
            limiter.release(host: upstreamHost, port: upstreamPort)
            self.sendErrorResponse(context: context, status: 502)
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
        urlPattern: String? = nil
    ) {
        switch action {
        case let .block(statusCode):
            sendBlockResponse(
                context: context,
                status: statusCode,
                requestData: requestData,
                callback: callback
            )

        case let .mapLocal(filePath, statusCode, isDirectory) where isDirectory:
            handleMapLocalDirectory(
                context: context,
                directoryPath: filePath,
                statusCode: statusCode,
                requestData: requestData,
                callback: callback,
                urlPattern: urlPattern ?? ""
            )

        case let .mapLocal(filePath, statusCode, _):
            handleMapLocal(
                context: context,
                filePath: filePath,
                statusCode: statusCode,
                requestData: requestData,
                callback: callback
            )

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

        case let .networkCondition(_, delayMs):
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
        transaction.sourcePort = clientSourcePort
        callback(transaction)
    }

    nonisolated private func handleMapLocal(
        context: ChannelHandlerContext,
        filePath: String,
        statusCode: Int,
        requestData: HTTPRequestData,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        guard let data = MapLocalFileValidator.loadFileData(at: filePath) else {
            httpsRelayLogger.error("Map local file rejected or not found: \(filePath)")
            sendBlockResponse(context: context, status: 404, requestData: requestData, callback: callback)
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
        sendMappedResponse(context: context, responseData: responseData, requestData: requestData, callback: callback)
    }

    nonisolated private func handleMapLocalDirectory(
        context: ChannelHandlerContext,
        directoryPath: String,
        statusCode: Int,
        requestData: HTTPRequestData,
        callback: @escaping @Sendable (HTTPTransaction) -> Void,
        urlPattern: String
    ) {
        let requestPath = requestData.url.path
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
            sendMappedResponse(
                context: context,
                responseData: responseData,
                requestData: requestData,
                callback: callback
            )
        case .failure:
            sendBlockResponse(context: context, status: 404, requestData: requestData, callback: callback)
        }
    }

    nonisolated private func handleMapRemote(
        context: ChannelHandlerContext,
        configuration: MapRemoteConfiguration,
        head: HTTPRequestHead,
        requestData: HTTPRequestData,
        graphQLInfo: GraphQLInfo?,
        startTime: DispatchTime,
        callback: @escaping @Sendable (HTTPTransaction) -> Void
    ) {
        let originalURL = requestData.url
        let remoteHost = configuration.host ?? (originalURL.host ?? self.host)
        let scheme = configuration.scheme ?? (originalURL.scheme ?? "https")
        let remotePort = configuration.port ?? (scheme == "https" ? 443 : 80)
        let remotePath = configuration.path ?? originalURL.path
        let remoteQuery = configuration.query ?? originalURL.query

        let effectivePath = remotePath.isEmpty ? "/" : remotePath
        let uri = remoteQuery.map { "\(effectivePath)?\($0)" } ?? effectivePath

        var modifiedHead = head
        modifiedHead.uri = uri

        let hostHeaderValue: String = if configuration.preserveHostHeader {
            originalURL.host ?? remoteHost
        } else {
            remoteHost
        }
        modifiedHead.headers.replaceOrAdd(name: "Host", value: NetworkValidator.sanitizeHeaderValue(hostHeaderValue))

        var urlString = "\(scheme)://\(remoteHost)"
        if remotePort != 80, remotePort != 443 {
            urlString += ":\(remotePort)"
        }
        urlString += uri

        // swiftlint:disable:next force_unwrapping
        let fallbackURL = URL(string: "https://localhost/")!
        let modifiedRequestData = HTTPRequestData(
            method: requestData.method,
            url: URL(string: urlString) ?? fallbackURL,
            httpVersion: requestData.httpVersion,
            headers: requestData.headers,
            body: requestData.body,
            contentType: requestData.contentType
        )

        guard connectionLimiter.acquire(host: remoteHost, port: remotePort) else {
            httpsRelayLogger.warning("Connection limit reached for \(remoteHost):\(remotePort)")
            sendErrorResponse(context: context, status: 503)
            return
        }
        let limiter = connectionLimiter

        if scheme == "https" {
            let connectTime = DispatchTime.now()
            do {
                var clientTLSConfig = TLSConfiguration.makeClientConfiguration()
                clientTLSConfig.certificateVerification = .fullVerification
                let sslContext = try NIOSSLContext(configuration: clientTLSConfig)

                ClientBootstrap(group: context.eventLoop)
                    .connectTimeout(.seconds(5))
                    .channelInitializer { channel in
                        do {
                            let sslHandler = try NIOSSLClientHandler(
                                context: sslContext,
                                serverHostname: remoteHost
                            )
                            return channel.pipeline.addHandler(sslHandler).flatMap {
                                channel.pipeline.addHTTPClientHandlers()
                            }
                        } catch {
                            return channel.eventLoop.makeFailedFuture(error)
                        }
                    }
                    .connect(host: remoteHost, port: remotePort)
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
                            head: modifiedHead,
                            requestData: modifiedRequestData,
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
                sendErrorResponse(context: context, status: 502)
            }
        } else {
            let connectTime = DispatchTime.now()
            ClientBootstrap(group: context.eventLoop)
                .connectTimeout(.seconds(5))
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers()
                }
                .connect(host: remoteHost, port: remotePort)
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
                        head: modifiedHead,
                        requestData: modifiedRequestData,
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
            state: .completed
        )
        transaction.sourcePort = clientSourcePort
        callback(transaction)
    }

    nonisolated private func sendErrorResponse(
        context: ChannelHandlerContext,
        status: Int
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

        let urlString = "https://\(host)\(head.uri)"
        let breakpointData = BreakpointRequestData(
            method: head.method.rawValue,
            url: urlString,
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
            let built = BreakpointRequestBuilder.build(
                from: modifiedData,
                originalHead: head,
                originalRequestData: requestData,
                isHTTPS: true,
                originalHost: self.host
            )
            self.connectToUpstream(
                context: context,
                head: built.head,
                requestData: built.requestData,
                graphQLInfo: graphQLInfo,
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
