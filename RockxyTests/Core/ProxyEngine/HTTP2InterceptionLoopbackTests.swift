import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOHTTP2
import NIOPosix
import NIOSSL
import NIOTLS
@testable import Rockxy
import Testing

// MARK: - HTTP2InterceptionLoopbackTests

/// End-to-end HTTP/2 through a decrypting `ProxyServer` on loopback: a client that negotiates
/// ALPN through CONNECT, and origins that speak HTTP/2 or only HTTP/1.1. The HTTP/2 option is
/// forced through its test seam, never through the app's shared defaults.
@Suite(.serialized)
struct HTTP2InterceptionLoopbackTests {
    @Test("With HTTP/2 on, both legs negotiate h2, trailers reach the client, and the row records 2.0")
    func http2EndToEnd() async throws {
        try await HTTP2LoopbackHarness.run(http2Enabled: true, originSpeaksHTTP2: true) { harness in
            let result = try await harness.get(paths: ["/h2/items"], offering: ["h2"])

            #expect(result.negotiatedProtocol == "h2")
            let response = try #require(result.responses.first)
            #expect(response.status == 200)
            #expect(response.headers.first(name: "x-origin-protocol") == "h2")
            #expect(response.body == Data("hello /h2/items".utf8))
            #expect(response.trailers?.first(name: "grpc-status") == "0")

            let row = try await harness.transaction(path: "/h2/items")
            #expect(row.request.httpVersion == "2.0")
            #expect(row.serverHTTPVersion == "2")
            #expect(row.response?.statusCode == 200)
            #expect(row.response?.trailers?.contains { $0.name == "grpc-status" && $0.value == "0" } == true)
            // The stream's Connection Log describes the shared connection it rode on.
            let tls = try #require(row.connectionLog?.tls)
            #expect(tls.offeredProtocols == ["h2", "http/1.1"])
            #expect(tls.negotiatedProtocol == "h2")
            #expect(tls.handshakeDuration != nil)
            #expect(tls.version?.hasPrefix("TLSv1.") == true)
        }
    }

    @Test("Concurrent streams on one client connection each become their own row")
    func concurrentStreamsAreSeparateRows() async throws {
        try await HTTP2LoopbackHarness.run(http2Enabled: true, originSpeaksHTTP2: true) { harness in
            let paths = ["/h2/a", "/h2/b", "/h2/c"]
            let result = try await harness.get(paths: paths, offering: ["h2"])

            #expect(Set(result.responses.map(\.body)) == Set(paths.map { Data("hello \($0)".utf8) }))
            for path in paths {
                let row = try await harness.transaction(path: path)
                #expect(row.response?.statusCode == 200)
            }
        }
    }

    @Test("An HTTP/2 client reaches an HTTP/1.1-only origin through Rockxy")
    func http2ClientToHTTP1Origin() async throws {
        try await HTTP2LoopbackHarness.run(http2Enabled: true, originSpeaksHTTP2: false) { harness in
            let result = try await harness.get(paths: ["/h1/origin"], offering: ["h2"])

            #expect(result.negotiatedProtocol == "h2")
            #expect(result.responses.first?.status == 200)
            #expect(result.responses.first?.headers.first(name: "x-origin-protocol") == "http/1.1")
            let row = try await harness.transaction(path: "/h1/origin")
            #expect(row.request.httpVersion == "2.0")
            #expect(row.serverHTTPVersion == "1.1")
        }
    }

    @Test("A WebSocket handshake never offers HTTP/2 to the origin, other requests do when enabled")
    func upgradeRequestsStayOnHTTP1Upstream() {
        HTTP2ProxyOptions.setOverride(true)
        defer { HTTP2ProxyOptions.setOverride(nil) }
        var upgrade = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/socket")
        upgrade.headers.add(name: "Upgrade", value: "websocket")
        upgrade.headers.add(name: "Connection", value: "Upgrade")
        let plain = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/items")

        #expect(!HTTP2ProxyOptions.offersHTTP2Upstream(for: upgrade))
        #expect(HTTP2ProxyOptions.offersHTTP2Upstream(for: plain))

        HTTP2ProxyOptions.setOverride(false)
        #expect(!HTTP2ProxyOptions.offersHTTP2Upstream(for: plain))
    }

    @Test("With HTTP/2 off, Rockxy offers only HTTP/1.1 and the exchange still succeeds")
    func http2DisabledFallsBackToHTTP1() async throws {
        try await HTTP2LoopbackHarness.run(http2Enabled: false, originSpeaksHTTP2: true) { harness in
            let result = try await harness.get(paths: ["/off"], offering: ["h2", "http/1.1"])

            #expect(result.negotiatedProtocol == "http/1.1")
            #expect(result.responses.first?.status == 200)
            #expect(result.responses.first?.headers.first(name: "x-origin-protocol") == "http/1.1")
            let row = try await harness.transaction(path: "/off")
            #expect(row.request.httpVersion == "1.1")
        }
    }
}

// MARK: - HTTP2LoopbackHarness

private actor HTTP2LoopbackHarness {
    // MARK: Lifecycle

    private init(
        proxyServer: ProxyServer,
        proxyPort: Int,
        origin: H2OriginServer,
        rootCertificate: NIOSSLCertificate,
        recorder: H2TransactionRecorder,
        cleanup: @escaping @Sendable () -> Void
    ) {
        self.proxyServer = proxyServer
        self.proxyPort = proxyPort
        self.origin = origin
        self.rootCertificate = rootCertificate
        self.recorder = recorder
        self.cleanup = cleanup
    }

    // MARK: Internal

    static let host = "localhost"

    static func run(
        http2Enabled: Bool,
        originSpeaksHTTP2: Bool,
        _ body: (HTTP2LoopbackHarness) async throws -> Void
    )
        async throws
    {
        HTTP2ProxyOptions.setOverride(http2Enabled)
        defer { HTTP2ProxyOptions.setOverride(nil) }
        let harness = try await start(originSpeaksHTTP2: originSpeaksHTTP2)
        do {
            try await body(harness)
        } catch {
            await harness.stop()
            throw error
        }
        await harness.stop()
    }

    func get(paths: [String], offering protocols: [String]) async throws -> H2ClientResult {
        try await H2Client.get(
            host: Self.host,
            port: origin.boundPort,
            paths: paths,
            proxyPort: proxyPort,
            trustRoot: rootCertificate,
            alpn: protocols
        )
    }

    func transaction(path: String) async throws -> HTTPTransaction {
        for _ in 0 ..< 40 {
            if let row = recorder.snapshot().first(where: { $0.request.url.path == path }) {
                return row
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let captured = recorder.snapshot().map { "\($0.request.method) \($0.request.url.absoluteString)" }
        Issue.record("no row for \(path); captured=\(captured)")
        throw H2LoopbackError.noResponse
    }

    func stop() async {
        await proxyServer.stop()
        await origin.stop()
        cleanup()
    }

    // MARK: Private

    private let proxyServer: ProxyServer
    private let proxyPort: Int
    private let origin: H2OriginServer
    private let rootCertificate: NIOSSLCertificate
    private let recorder: H2TransactionRecorder
    private let cleanup: @Sendable () -> Void

    private static func start(originSpeaksHTTP2: Bool) async throws -> HTTP2LoopbackHarness {
        let overrides = try await installSharedTestOverrides()
        let manager = CertificateManager.shared
        try await manager.generateRootCA()
        let rootPEM = try #require(try await manager.getRootCAPEM())
        let rootCertificate = try NIOSSLCertificate(bytes: Array(rootPEM.utf8), format: .pem)
        let originIdentity = try await manager.certificateForHost(host).serverIdentity()

        let origin: H2OriginServer
        do {
            origin = try await H2OriginServer.start(identity: originIdentity, speaksHTTP2: originSpeaksHTTP2)
        } catch {
            overrides.cleanup()
            throw error
        }

        let sslManager = await MainActor.run {
            let manager = SSLProxyingManager(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("rockxy-h2-loopback-\(UUID().uuidString).json"),
                passthroughStorageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("rockxy-h2-loopback-passthrough-\(UUID().uuidString).json")
            )
            manager.setEnabled(true)
            manager.addRule(SSLProxyingRule(domain: "*", listType: .include))
            manager.forceGlobalPassthrough = false
            return manager
        }
        let bypassManager = await MainActor.run {
            BypassProxyManager(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("rockxy-h2-loopback-bypass-\(UUID().uuidString).json")
            )
        }

        let recorder = H2TransactionRecorder()
        let proxyPort = try reserveLoopbackPort()
        let proxyServer = ProxyServer(
            configuration: ProxyConfiguration(port: proxyPort, listenAddress: "127.0.0.1", listenIPv6: false),
            certificateManager: manager,
            ruleEngine: RuleEngine(),
            sslProxyingManager: sslManager,
            bypassProxyManager: bypassManager,
            upstreamTrustProvider: { true },
            onTransactionComplete: { recorder.record($0) }
        )
        do {
            try await proxyServer.start()
        } catch {
            await origin.stop()
            overrides.cleanup()
            throw error
        }
        return HTTP2LoopbackHarness(
            proxyServer: proxyServer,
            proxyPort: proxyPort,
            origin: origin,
            rootCertificate: rootCertificate,
            recorder: recorder,
            cleanup: { overrides.cleanup() }
        )
    }

    private static func reserveLoopbackPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw H2LoopbackError.socket
        }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            throw H2LoopbackError.socket
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else {
            throw H2LoopbackError.socket
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

// MARK: - H2TransactionRecorder

private final class H2TransactionRecorder: @unchecked Sendable {
    // MARK: Internal

    func record(_ transaction: HTTPTransaction) {
        lock.lock()
        transactions.append(transaction)
        lock.unlock()
    }

    func snapshot() -> [HTTPTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return transactions
    }

    // MARK: Private

    private let lock = NSLock()
    private var transactions: [HTTPTransaction] = []
}

// MARK: - H2LoopbackError

private enum H2LoopbackError: Error {
    case socket
    case timeout
    case tunnelRefused(Int)
    case noResponse
}

// MARK: - H2Response

private struct H2Response: Sendable {
    let status: Int
    let headers: HTTPHeaders
    let body: Data
    let trailers: HTTPHeaders?
}

// MARK: - H2ClientResult

private struct H2ClientResult: Sendable {
    let negotiatedProtocol: String?
    let responses: [H2Response]
}

// MARK: - H2OriginServer

/// TLS origin that negotiates `h2` (when allowed) or HTTP/1.1, answers `hello <path>`, reports
/// the protocol it used in `x-origin-protocol`, and ends HTTP/2 responses with a trailer.
private actor H2OriginServer {
    // MARK: Lifecycle

    private init(group: MultiThreadedEventLoopGroup, channel: Channel, boundPort: Int) {
        self.group = group
        serverChannel = channel
        self.boundPort = boundPort
    }

    // MARK: Internal

    nonisolated let boundPort: Int

    static func start(identity: CustomTLSIdentity, speaksHTTP2: Bool) async throws -> H2OriginServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sslContext = try NIOSSLContext(
            configuration: TLSInterceptHandler.makeServerTLSConfiguration(identity: identity, allowsHTTP2: speaksHTTP2)
        )
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(NIOSSLServerHandler(context: sslContext)).flatMap {
                    channel.pipeline.addHandler(ApplicationProtocolNegotiationHandler { result, channel in
                        if case .negotiated("h2") = result {
                            return channel.configureHTTP2Pipeline(mode: .server, inboundStreamInitializer: { stream in
                                stream.pipeline.addHandlers([
                                    HTTP2FramePayloadToHTTP1ServerCodec(),
                                    H2OriginResponder(protocolName: "h2"),
                                ])
                            }).map { _ in }
                        }
                        return channel.pipeline.configureHTTPServerPipeline().flatMap {
                            channel.pipeline.addHandler(H2OriginResponder(protocolName: "http/1.1"))
                        }
                    })
                }
            }
        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        guard let port = channel.localAddress?.port else {
            try? await channel.close().get()
            try? await group.shutdownGracefully()
            throw H2LoopbackError.socket
        }
        return H2OriginServer(group: group, channel: channel, boundPort: port)
    }

    func stop() async {
        try? await serverChannel.close().get()
        try? await group.shutdownGracefully()
    }

    // MARK: Private

    private let group: MultiThreadedEventLoopGroup
    private let serverChannel: Channel
}

// MARK: - H2OriginResponder

private final class H2OriginResponder: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(protocolName: String) {
        self.protocolName = protocolName
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            path = head.uri
        case .body:
            break
        case .end:
            let body = "hello \(path)"
            var headers = HTTPHeaders()
            headers.add(name: "content-type", value: "text/plain")
            headers.add(name: "content-length", value: "\(body.utf8.count)")
            headers.add(name: "x-origin-protocol", value: protocolName)
            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
            buffer.writeString(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            let trailers: HTTPHeaders? = protocolName == "h2" ? HTTPHeaders([("grpc-status", "0")]) : nil
            context.writeAndFlush(wrapOutboundOut(.end(trailers)), promise: nil)
        }
    }

    // MARK: Private

    private let protocolName: String
    private var path = ""
}

// MARK: - H2Client

/// CONNECT through the proxy, TLS with the requested ALPN list, then either HTTP/2 streams (one
/// per path, concurrently) or a single HTTP/1.1 request.
private enum H2Client {
    static func get(
        host: String,
        port: Int,
        paths: [String],
        proxyPort: Int,
        trustRoot: NIOSSLCertificate,
        alpn: [String]
    )
        async throws -> H2ClientResult
    {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { Task { try? await group.shutdownGracefully() } }

        var tls = TLSConfiguration.makeClientConfiguration()
        tls.trustRoots = .certificates([trustRoot])
        tls.certificateVerification = .fullVerification
        tls.applicationProtocols = alpn
        let sslContext = try NIOSSLContext(configuration: tls)

        let promise = group.next().makePromise(of: H2ClientResult.self)
        let channel = try await ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHandler(H2TunnelHandler(
                    host: host,
                    port: port,
                    paths: paths,
                    sslContext: sslContext,
                    promise: promise
                ))
            }
            .connect(host: "127.0.0.1", port: proxyPort)
            .get()
        let timeout = channel.eventLoop.scheduleTask(in: .seconds(15)) {
            promise.fail(H2LoopbackError.timeout)
        }
        defer {
            timeout.cancel()
            channel.close(promise: nil)
        }
        return try await promise.futureResult.get()
    }
}

// MARK: - H2TunnelHandler

private final class H2TunnelHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        host: String,
        port: Int,
        paths: [String],
        sslContext: NIOSSLContext,
        promise: EventLoopPromise<H2ClientResult>
    ) {
        self.host = host
        self.port = port
        self.paths = paths
        self.sslContext = sslContext
        self.promise = promise
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func channelActive(context: ChannelHandlerContext) {
        let connect = "CONNECT \(host):\(port) HTTP/1.1\r\nHost: \(host):\(port)\r\n\r\n"
        var buffer = context.channel.allocator.buffer(capacity: connect.utf8.count)
        buffer.writeString(connect)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        pending.writeBuffer(&buffer)
        guard let text = pending.getString(at: pending.readerIndex, length: pending.readableBytes),
              let headerEnd = text.range(of: "\r\n\r\n") else
        {
            return
        }
        let statusLine = String(text[..<headerEnd.lowerBound]).split(separator: "\r\n").first ?? ""
        let code = Int(statusLine.split(separator: " ").dropFirst().first ?? "") ?? 0
        guard code == 200 else {
            promise.fail(H2LoopbackError.tunnelRefused(code))
            context.close(promise: nil)
            return
        }
        let channel = context.channel
        let host = host
        let port = port
        let paths = paths
        let promise = promise
        let sslContext = sslContext
        context.pipeline.removeHandler(self).whenComplete { _ in
            do {
                let ssl = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                let alpn = ApplicationProtocolNegotiationHandler { result, channel in
                    Self.startRequests(
                        channel: channel,
                        result: result,
                        host: host,
                        port: port,
                        paths: paths,
                        promise: promise
                    )
                }
                channel.pipeline.addHandlers([ssl, alpn]).whenFailure { promise.fail($0) }
            } catch {
                promise.fail(error)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }

    // MARK: Private

    private let host: String
    private let port: Int
    private let paths: [String]
    private let sslContext: NIOSSLContext
    private let promise: EventLoopPromise<H2ClientResult>
    private var pending = ByteBufferAllocator().buffer(capacity: 256)

    private static func startRequests(
        channel: Channel,
        result: ALPNResult,
        host: String,
        port: Int,
        paths: [String],
        promise: EventLoopPromise<H2ClientResult>
    )
        -> EventLoopFuture<Void>
    {
        let negotiated: String? = if case let .negotiated(name) = result {
            name
        } else {
            nil
        }
        let responses = paths.map { _ in channel.eventLoop.makePromise(of: H2Response.self) }
        EventLoopFuture.whenAllSucceed(responses.map(\.futureResult), on: channel.eventLoop).whenComplete { outcome in
            switch outcome {
            case let .success(values):
                promise.succeed(H2ClientResult(negotiatedProtocol: negotiated, responses: values))
            case let .failure(error):
                promise.fail(error)
            }
        }

        guard negotiated == "h2" else {
            return channel.pipeline.addHTTPClientHandlers().flatMap {
                channel.pipeline.addHandler(H2RequestCollector(
                    host: host,
                    port: port,
                    path: paths[0],
                    promise: responses[0]
                ))
            }
        }
        return channel.configureHTTP2Pipeline(mode: .client, inboundStreamInitializer: nil).flatMap { multiplexer in
            let streams = zip(paths, responses).map { path, response in
                multiplexer.createStreamChannel { stream in
                    stream.pipeline.addHandlers([
                        HTTP2FramePayloadToHTTP1ClientCodec(httpProtocol: .https),
                        H2RequestCollector(host: host, port: port, path: path, promise: response),
                    ])
                }
            }
            return EventLoopFuture.andAllSucceed(streams.map { $0.map { _ in } }, on: channel.eventLoop)
        }
    }
}

// MARK: - H2RequestCollector

private final class H2RequestCollector: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(host: String, port: Int, path: String, promise: EventLoopPromise<H2Response>) {
        self.host = host
        self.port = port
        self.path = path
        self.promise = promise
    }

    // MARK: Internal

    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    func handlerAdded(context: ChannelHandlerContext) {
        guard context.channel.isActive else {
            return
        }
        sendRequest(context: context)
    }

    func channelActive(context: ChannelHandlerContext) {
        sendRequest(context: context)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            status = Int(head.status.code)
            headers = head.headers
        case var .body(buffer):
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case let .end(trailers):
            promise.succeed(H2Response(status: status, headers: headers, body: body, trailers: trailers))
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        promise.fail(H2LoopbackError.noResponse)
    }

    // MARK: Private

    private let host: String
    private let port: Int
    private let path: String
    private let promise: EventLoopPromise<H2Response>
    private var sent = false
    private var status = 0
    private var headers = HTTPHeaders()
    private var body = Data()

    private func sendRequest(context: ChannelHandlerContext) {
        guard !sent else {
            return
        }
        sent = true
        var headers = HTTPHeaders()
        headers.add(name: "host", value: "\(host):\(port)")
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: path, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
