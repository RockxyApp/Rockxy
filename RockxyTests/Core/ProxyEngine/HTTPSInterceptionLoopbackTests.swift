import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
@testable import Rockxy
import Testing

// MARK: - HTTPSInterceptionLoopbackTests

/// End-to-end HTTPS interception without touching the macOS keychain trust store.
///
/// The harness generates a throwaway root CA through the shared `CertificateManager` (test
/// storage overrides), boots a TLS origin on loopback whose leaf is minted by that same CA,
/// and drives a real CONNECT + TLS handshake through a `ProxyServer` whose SSL policy decrypts
/// everything. The client trusts only the test root, so a decrypted round trip proves that
/// Rockxy presented its own leaf and relayed the origin's response.
@Suite(.serialized)
struct HTTPSInterceptionLoopbackTests {
    @Test("A decrypted HTTPS round trip is captured when the upstream certificate is accepted")
    func decryptedRoundTripWithRelaxedUpstreamTrust() async throws {
        try await HTTPSLoopbackHarness.run(acceptUntrustedUpstream: true) { harness in
            let response = try await harness.get("/secure/items")

            #expect(response.status == 200)
            #expect(response.headerValue(HTTPSLoopbackHarness.originMarkerHeader) == "tls-origin")
            #expect(response.body == Data(#"{"secure":true}"#.utf8))

            try await Task.sleep(for: .milliseconds(300))
            let captured = await harness.capturedTransactions()
            let decrypted = captured.first { $0.request.url.path == "/secure/items" }
            let summary = captured
                .map {
                    "\($0.request.method) \($0.request.url.absoluteString) state=\($0.state) ssl=\(String(describing: $0.sslCapture))"
                }
            #expect(decrypted != nil, "the decrypted request must appear as its own transaction; captured=\(summary)")
            #expect(decrypted?.request.url.scheme == "https")
            #expect(decrypted?.response?.statusCode == 200)
            #expect(decrypted?.response?.body == Data(#"{"secure":true}"#.utf8))
        }
    }

    @Test("The TLS key log records secrets for both legs of a decrypted connection")
    func tlsKeyLogRecordsBothLegs() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-keylog-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        try TLSKeyLogWriter.shared.setDestination(url)
        defer { try? TLSKeyLogWriter.shared.setDestination(nil) }

        try await HTTPSLoopbackHarness.run(acceptUntrustedUpstream: true) { harness in
            let response = try await harness.get("/secure/items")
            #expect(response.status == 200)
        }
        TLSKeyLogWriter.shared.flush()

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        // TLS 1.3 logs one CLIENT_TRAFFIC_SECRET_0 per handshake: client→Rockxy and Rockxy→origin.
        let trafficSecrets = lines.filter { $0.hasPrefix("CLIENT_TRAFFIC_SECRET_0 ") }
        #expect(trafficSecrets.count >= 2, "lines: \(lines.map { $0.prefix(24) })")
        #expect(lines.allSatisfy { $0.split(separator: " ").count == 3 })
    }

    @Test("An HTTPS request edited at a breakpoint to another server is sent to that server")
    func breakpointEditRedirectsHTTPSToAnotherServer() async throws {
        let manager = await MainActor.run { BreakpointManager() }
        let engine = RuleEngine()
        await engine.setBreakpointToolEnabled(true)
        await engine.addRule(ProxyRule(
            name: "Pause secure",
            matchCondition: RuleMatchCondition(urlPattern: ".*/secure/pause.*"),
            action: .breakpoint(phase: .request)
        ))
        try await HTTPSLoopbackHarness.run(
            acceptUntrustedUpstream: true,
            ruleEngine: engine,
            onBreakpointHit: { await manager.enqueueAndWait($0) }
        ) { harness in
            let redirectURL = "http://127.0.0.1:\(harness.plainOriginPort)/redirected?from=breakpoint"
            async let pending = harness.get("/secure/pause")

            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            var paused: PausedBreakpointItem?
            while paused == nil, ContinuousClock.now < deadline {
                paused = await MainActor.run { manager.pausedItems.first }
                if paused == nil {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            let item = try #require(paused)
            await MainActor.run {
                manager.updateDraft(id: item.id) { $0.url = redirectURL }
                manager.resolve(id: item.id, decision: .execute)
            }

            let response = try await pending
            #expect(response.status == 200)
            #expect(response.headerValue(HTTPSLoopbackHarness.originMarkerHeader) == "plain-origin")

            try await Task.sleep(for: .milliseconds(300))
            let row = await harness.capturedTransactions().first { $0.request.url.path == "/redirected" }
            #expect(row?.request.url.absoluteString == redirectURL)
            #expect(row?.request.headers.first { $0.name == "Host" }?.value == "127.0.0.1:\(harness.plainOriginPort)")
            #expect(row?.matchedRuleActionSummary?.hasPrefix("Map Remote") != true)
        }
    }

    @Test("Decrypted HTTPS to the emulator's host alias reaches the Mac's loopback origin")
    func emulatorAliasHTTPSReachesLoopback() async throws {
        guard !RootCADownloadServer.lanIPv4Addresses().contains(where: { $0.hasPrefix("10.0.2.") }) else {
            return
        }
        try await HTTPSLoopbackHarness.run(acceptUntrustedUpstream: true) { harness in
            let response = try await harness.getViaEmulatorAlias("/secure/metro")

            #expect(response.status == 200)
            #expect(response.headerValue(HTTPSLoopbackHarness.originMarkerHeader) == "tls-origin")

            try await Task.sleep(for: .milliseconds(300))
            let row = await harness.capturedTransactions().first { $0.request.url.path == "/secure/metro" }
            #expect(row?.request.url.host == "10.0.2.2")
            #expect(row?.response?.statusCode == 200)
        }
    }

    @Test("HTTPS through the SOCKS5 listener is decrypted like an HTTP CONNECT")
    func httpsViaSOCKSIsDecrypted() async throws {
        try await HTTPSLoopbackHarness.run(acceptUntrustedUpstream: true) { harness in
            let response = try await harness.getViaSOCKS("/secure/socks")

            #expect(response.status == 200)
            #expect(response.headerValue(HTTPSLoopbackHarness.originMarkerHeader) == "tls-origin")

            try await Task.sleep(for: .milliseconds(300))
            let decrypted = await harness.capturedTransactions().first { $0.request.url.path == "/secure/socks" }
            #expect(decrypted?.request.url.scheme == "https")
            #expect(decrypted?.response?.statusCode == 200)
        }
    }

    @Test("Plain HTTP sent through a CONNECT tunnel is relayed and captured as http://")
    func plainHTTPInsideConnectTunnelIsCaptured() async throws {
        try await HTTPSLoopbackHarness.run(acceptUntrustedUpstream: true) { harness in
            let response = try await harness.getPlainThroughTunnel("/tunneled/items")

            #expect(response.status == 200)
            #expect(response.headerValue(HTTPSLoopbackHarness.originMarkerHeader) == "plain-origin")

            try await Task.sleep(for: .milliseconds(300))
            let captured = await harness.capturedTransactions()
            let relayed = captured.first { $0.request.url.path == "/tunneled/items" }
            #expect(relayed != nil, "the tunneled request must be captured as its own row")
            #expect(relayed?.request.url.scheme == "http")
            #expect(relayed?.response?.statusCode == 200)
            // Nothing was decrypted, so the row must not claim an intercepted TLS session.
            #expect(relayed?.sslCapture != .intercepted)
            #expect(captured.contains { $0.request.method == "CONNECT" && $0.response?.statusCode == 200 })
        }
    }

    @Test("Plain HTTP inside a CONNECT tunnel is still captured when nothing is set to decrypt")
    func plainHTTPInsideTunnelIsCapturedWithoutInterception() async throws {
        try await HTTPSLoopbackHarness.run(acceptUntrustedUpstream: false, interceptTLS: false) { harness in
            let response = try await harness.getPlainThroughTunnel("/tunneled/no-rule")

            #expect(response.status == 200)
            #expect(response.headerValue(HTTPSLoopbackHarness.originMarkerHeader) == "plain-origin")

            try await Task.sleep(for: .milliseconds(300))
            let captured = await harness.capturedTransactions()
            let relayed = captured.first { $0.request.url.path == "/tunneled/no-rule" }
            #expect(relayed?.request.url.scheme == "http")
            #expect(relayed?.response?.statusCode == 200)
            #expect(relayed?.sslCapture != .intercepted)
        }
    }

    @Test("TLS inside a non-decrypted CONNECT tunnel still passes through untouched")
    func tlsInsideTunnelStaysRawWithoutInterception() async throws {
        try await HTTPSLoopbackHarness.run(acceptUntrustedUpstream: false, interceptTLS: false) { harness in
            // The client trusts the test root and the origin's leaf is signed by it, so an
            // untouched end-to-end TLS session succeeds; a MITM attempt would not.
            let response = try await harness.get("/raw/items")

            #expect(response.status == 200)
            #expect(response.headerValue(HTTPSLoopbackHarness.originMarkerHeader) == "tls-origin")

            try await Task.sleep(for: .milliseconds(300))
            let captured = await harness.capturedTransactions()
            #expect(!captured.contains { $0.request.url.path == "/raw/items" })
            #expect(captured.contains { $0.request.method == "CONNECT" && $0.sslCapture == .tunneled })
        }
    }

    @Test("Strict upstream validation answers 502 quickly and records the rejected handshake")
    func strictUpstreamTrustRejectsPrivateCAOrigin() async throws {
        try await HTTPSLoopbackHarness.run(acceptUntrustedUpstream: false) { harness in
            let started = ContinuousClock.now
            let response = try await harness.get("/secure/items")
            let elapsed = ContinuousClock.now - started

            // The client must not hang until its own timeout, and it must never see origin data.
            #expect(response.status == 502)
            #expect(response.headerValue(HTTPSLoopbackHarness.originMarkerHeader) == nil)
            #expect(elapsed < .seconds(5), "client waited \(elapsed) for the upstream failure")

            try await Task.sleep(for: .milliseconds(300))
            let captured = await harness.capturedTransactions()
            let failed = captured.first { $0.request.url.path == "/secure/items" }
            #expect(failed?.state == .failed)
            #expect(failed?.response?.statusCode == 502)
            #expect(failed?.response?.statusMessage.contains("TLS") == true)
        }
    }
}

// MARK: - HTTPSLoopbackHarness

private actor HTTPSLoopbackHarness {
    // MARK: Lifecycle

    private init(
        proxyServer: ProxyServer,
        proxyPort: Int,
        origin: TLSOriginFixtureServer,
        plainOrigin: TLSOriginFixtureServer,
        rootCertificate: NIOSSLCertificate,
        recorder: TransactionRecorder,
        cleanup: @escaping @Sendable () -> Void
    ) {
        self.proxyServer = proxyServer
        self.proxyPort = proxyPort
        self.origin = origin
        self.plainOrigin = plainOrigin
        self.rootCertificate = rootCertificate
        self.recorder = recorder
        self.cleanup = cleanup
    }

    // MARK: Internal

    static let originMarkerHeader = "X-Rockxy-TLS-Origin"
    static let originHost = "localhost"

    static func run(
        acceptUntrustedUpstream: Bool,
        interceptTLS: Bool = true,
        ruleEngine: RuleEngine = RuleEngine(),
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? = nil,
        _ body: (HTTPSLoopbackHarness) async throws -> Void
    )
        async throws
    {
        let harness = try await start(
            acceptUntrustedUpstream: acceptUntrustedUpstream,
            interceptTLS: interceptTLS,
            ruleEngine: ruleEngine,
            onBreakpointHit: onBreakpointHit
        )
        do {
            try await body(harness)
        } catch {
            await harness.stop()
            throw error
        }
        await harness.stop()
    }

    func capturedTransactions() -> [HTTPTransaction] {
        recorder.snapshot()
    }

    nonisolated var plainOriginPort: Int {
        plainOrigin.boundPort
    }

    /// Issues `GET http://localhost:<plainPort><path>` inside a CONNECT tunnel without any TLS,
    /// the way `ws://` clients and some HTTP libraries tunnel plain traffic through a proxy.
    func getPlainThroughTunnel(_ path: String) async throws -> LoopbackHTTPResponse {
        try await LoopbackHTTPSClient.get(
            host: Self.originHost,
            port: plainOrigin.boundPort,
            path: path,
            proxyPort: proxyPort,
            trustRoot: nil
        )
    }

    /// Issues `GET https://localhost:<originPort><path>` through the proxy: CONNECT, then a TLS
    /// handshake that trusts only the test root, then a plain HTTP/1.1 exchange inside it.
    func get(_ path: String) async throws -> LoopbackHTTPResponse {
        try await LoopbackHTTPSClient.get(
            host: Self.originHost,
            port: origin.boundPort,
            path: path,
            proxyPort: proxyPort,
            trustRoot: rootCertificate
        )
    }

    /// Issues `GET https://10.0.2.2:<originPort><path>`, the address an Android emulator uses for
    /// the Mac, from a loopback client the way emulator traffic arrives.
    func getViaEmulatorAlias(_ path: String) async throws -> LoopbackHTTPResponse {
        try await LoopbackHTTPSClient.get(
            host: "10.0.2.2",
            port: origin.boundPort,
            path: path,
            proxyPort: proxyPort,
            trustRoot: rootCertificate
        )
    }

    /// Issues the same HTTPS request through the SOCKS5 listener instead of an HTTP CONNECT.
    func getViaSOCKS(_ path: String) async throws -> LoopbackHTTPResponse {
        let socksPort = try Self.reserveLoopbackPort()
        if let failure = await proxyServer.updateSOCKSListener(port: socksPort) {
            throw LoopbackError.tunnelRefused(failure == .portInUse ? 1 : 2)
        }
        return try await LoopbackHTTPSClient.get(
            host: Self.originHost,
            port: origin.boundPort,
            path: path,
            proxyPort: socksPort,
            trustRoot: rootCertificate,
            useSOCKS: true
        )
    }

    func stop() async {
        await proxyServer.stop()
        await origin.stop()
        await plainOrigin.stop()
        cleanup()
    }

    // MARK: Private

    private let proxyServer: ProxyServer
    private let proxyPort: Int
    private let origin: TLSOriginFixtureServer
    private let plainOrigin: TLSOriginFixtureServer
    private let rootCertificate: NIOSSLCertificate
    private let recorder: TransactionRecorder
    private let cleanup: @Sendable () -> Void

    private static func start(
        acceptUntrustedUpstream: Bool,
        interceptTLS: Bool,
        ruleEngine: RuleEngine,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))?
    )
        async throws -> HTTPSLoopbackHarness
    {
        let overrides = try await installSharedTestOverrides()
        let manager = CertificateManager.shared
        try await manager.generateRootCA()

        let rootPEM = try #require(try await manager.getRootCAPEM())
        let rootCertificate = try NIOSSLCertificate(bytes: Array(rootPEM.utf8), format: .pem)
        let originIdentity = try await manager.certificateForHost(originHost).serverIdentity()

        let cleanup: @Sendable () -> Void = {
            overrides.cleanup()
        }

        let origin: TLSOriginFixtureServer
        let plainOrigin: TLSOriginFixtureServer
        do {
            origin = try await TLSOriginFixtureServer.start(identity: originIdentity)
        } catch {
            cleanup()
            throw error
        }
        do {
            plainOrigin = try await TLSOriginFixtureServer.start(identity: nil)
        } catch {
            await origin.stop()
            cleanup()
            throw error
        }

        let sslManager = await MainActor.run {
            let manager = SSLProxyingManager(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("rockxy-https-loopback-\(UUID().uuidString).json"),
                passthroughStorageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("rockxy-https-loopback-passthrough-\(UUID().uuidString).json")
            )
            manager.setEnabled(true)
            if interceptTLS {
                manager.addRule(SSLProxyingRule(domain: "*", listType: .include))
            }
            manager.forceGlobalPassthrough = false
            return manager
        }

        // The shared bypass list may carry the localhost presets from other tests; an isolated
        // manager keeps the loopback origin eligible for interception.
        let bypassManager = await MainActor.run {
            BypassProxyManager(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("rockxy-https-loopback-bypass-\(UUID().uuidString).json")
            )
        }

        let recorder = TransactionRecorder()
        let proxyPort = try reserveLoopbackPort()
        let proxyServer = ProxyServer(
            configuration: ProxyConfiguration(port: proxyPort, listenAddress: "127.0.0.1", listenIPv6: false),
            certificateManager: manager,
            ruleEngine: ruleEngine,
            sslProxyingManager: sslManager,
            bypassProxyManager: bypassManager,
            upstreamTrustProvider: { acceptUntrustedUpstream },
            onTransactionComplete: { recorder.record($0) },
            onBreakpointHit: onBreakpointHit
        )
        do {
            try await proxyServer.start()
        } catch {
            await origin.stop()
            await plainOrigin.stop()
            cleanup()
            throw error
        }

        return HTTPSLoopbackHarness(
            proxyServer: proxyServer,
            proxyPort: proxyPort,
            origin: origin,
            plainOrigin: plainOrigin,
            rootCertificate: rootCertificate,
            recorder: recorder,
            cleanup: cleanup
        )
    }

    private static func reserveLoopbackPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw LoopbackError.socket
        }
        defer { close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw LoopbackError.socket
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw LoopbackError.socket
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

// MARK: - TransactionRecorder

private final class TransactionRecorder: @unchecked Sendable {
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

// MARK: - LoopbackError

private enum LoopbackError: Error {
    case socket
    case timeout
    case tunnelRefused(Int)
    case noResponse
}

// MARK: - LoopbackHTTPResponse

private struct LoopbackHTTPResponse: Sendable {
    let status: Int
    let headers: HTTPHeaders
    let body: Data

    func headerValue(_ name: String) -> String? {
        headers.first(name: name)
    }
}

// MARK: - TLSOriginFixtureServer

/// Minimal HTTPS origin on loopback that answers every GET with a JSON body and a marker header.
private actor TLSOriginFixtureServer {
    // MARK: Lifecycle

    private init(group: MultiThreadedEventLoopGroup, channel: Channel, boundPort: Int) {
        self.group = group
        serverChannel = channel
        self.boundPort = boundPort
    }

    // MARK: Internal

    nonisolated let boundPort: Int

    /// `identity == nil` starts a plain-HTTP origin (used for tunneled http:// traffic).
    static func start(identity: CustomTLSIdentity?) async throws -> TLSOriginFixtureServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sslContext: NIOSSLContext? = try identity.map { identity in
            try NIOSSLContext(configuration: TLSInterceptHandler.makeServerTLSConfiguration(identity: identity, allowsHTTP2: false))
        }
        let marker = identity == nil ? "plain-origin" : "tls-origin"
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let transport: EventLoopFuture<Void> = if let sslContext {
                    channel.pipeline.addHandler(NIOSSLServerHandler(context: sslContext))
                } else {
                    channel.eventLoop.makeSucceededVoidFuture()
                }
                return transport.flatMap {
                    channel.pipeline.configureHTTPServerPipeline()
                }.flatMap {
                    channel.pipeline.addHandler(OriginResponder(marker: marker))
                }
            }
        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        guard let port = channel.localAddress?.port else {
            try? await channel.close().get()
            try? await group.shutdownGracefully()
            throw LoopbackError.socket
        }
        return TLSOriginFixtureServer(group: group, channel: channel, boundPort: port)
    }

    func stop() async {
        try? await serverChannel.close().get()
        try? await group.shutdownGracefully()
    }

    // MARK: Private

    private let group: MultiThreadedEventLoopGroup
    private let serverChannel: Channel
}

// MARK: - OriginResponder

private final class OriginResponder: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(marker: String) {
        self.marker = marker
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .end = unwrapInboundIn(data) else {
            return
        }
        let body = Data(#"{"secure":true}"#.utf8)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: "\(body.count)")
        headers.add(name: HTTPSLoopbackHarness.originMarkerHeader, value: marker)
        headers.add(name: "Connection", value: "close")
        context.write(
            wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers))),
            promise: nil
        )
        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    // MARK: Private

    private let marker: String
}

// MARK: - LoopbackHTTPSClient

/// Raw NIO client: CONNECT through the proxy, then upgrade the same channel to TLS that trusts
/// only the test root, then run one HTTP/1.1 request inside the tunnel.
private enum LoopbackHTTPSClient {
    static func get(
        host: String,
        port: Int,
        path: String,
        proxyPort: Int,
        trustRoot: NIOSSLCertificate?,
        useSOCKS: Bool = false
    )
        async throws -> LoopbackHTTPResponse
    {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { Task { try? await group.shutdownGracefully() } }

        let sslContext: NIOSSLContext? = try trustRoot.map { trustRoot in
            var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
            tlsConfiguration.trustRoots = .certificates([trustRoot])
            tlsConfiguration.certificateVerification = TLSServerName.sni(for: host) == nil
                ? .noHostnameVerification
                : .fullVerification
            return try NIOSSLContext(configuration: tlsConfiguration)
        }

        let promise = group.next().makePromise(of: LoopbackHTTPResponse.self)
        let channel = try await ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHandler(TunnelThenTLSHandler(
                    targetHost: host,
                    targetPort: port,
                    path: path,
                    sslContext: sslContext,
                    useSOCKS: useSOCKS,
                    promise: promise
                ))
            }
            .connect(host: "127.0.0.1", port: proxyPort)
            .get()
        let timeout = channel.eventLoop.scheduleTask(in: .seconds(15)) {
            promise.fail(LoopbackError.timeout)
        }
        defer {
            timeout.cancel()
            channel.close(promise: nil)
        }
        return try await promise.futureResult.get()
    }
}

// MARK: - TunnelThenTLSHandler

/// Writes the CONNECT line as raw bytes, waits for the proxy's `200`, then installs TLS + HTTP
/// client handlers behind itself and issues the real request.
private final class TunnelThenTLSHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        targetHost: String,
        targetPort: Int,
        path: String,
        sslContext: NIOSSLContext?,
        useSOCKS: Bool = false,
        promise: EventLoopPromise<LoopbackHTTPResponse>
    ) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.path = path
        self.sslContext = sslContext
        self.useSOCKS = useSOCKS
        self.promise = promise
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func channelActive(context: ChannelHandlerContext) {
        if useSOCKS {
            var greeting = context.channel.allocator.buffer(capacity: 3)
            greeting.writeBytes([0x05, 0x01, 0x00])
            context.writeAndFlush(wrapOutboundOut(greeting), promise: nil)
            return
        }
        let connect = "CONNECT \(targetHost):\(targetPort) HTTP/1.1\r\nHost: \(targetHost):\(targetPort)\r\n\r\n"
        var buffer = context.channel.allocator.buffer(capacity: connect.utf8.count)
        buffer.writeString(connect)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        pending.writeBuffer(&buffer)
        if useSOCKS {
            readSOCKS(context: context)
            return
        }
        guard let text = pending.getString(at: pending.readerIndex, length: pending.readableBytes),
              let headerEnd = text.range(of: "\r\n\r\n") else
        {
            return
        }
        let statusLine = String(text[..<headerEnd.lowerBound]).split(separator: "\r\n").first ?? ""
        let code = Int(statusLine.split(separator: " ").dropFirst().first ?? "") ?? 0
        guard code == 200 else {
            promise.fail(LoopbackError.tunnelRefused(code))
            context.close(promise: nil)
            return
        }

        installTransport(context: context)
    }

    /// SOCKS5: greeting reply (2 bytes), then CONNECT reply (10 bytes), then TLS.
    private func readSOCKS(context: ChannelHandlerContext) {
        if !socksGreetingDone {
            guard pending.readableBytes >= 2 else {
                return
            }
            pending.moveReaderIndex(forwardBy: 2)
            socksGreetingDone = true
            let name = Array(targetHost.utf8)
            var request = context.channel.allocator.buffer(capacity: 7 + name.count)
            request.writeBytes([0x05, 0x01, 0x00, 0x03, UInt8(name.count)] + name)
            request.writeBytes([UInt8(targetPort >> 8), UInt8(targetPort & 0xFF)])
            context.writeAndFlush(wrapOutboundOut(request), promise: nil)
        }
        guard pending.readableBytes >= 10 else {
            return
        }
        guard pending.getInteger(at: pending.readerIndex + 1, as: UInt8.self) == 0x00 else {
            promise.fail(LoopbackError.tunnelRefused(-1))
            context.close(promise: nil)
            return
        }
        pending.moveReaderIndex(forwardBy: 10)
        installTransport(context: context)
    }

    private func installTransport(context: ChannelHandlerContext) {
        let path = path
        let targetHost = targetHost
        let targetPort = targetPort
        let promise = promise
        let sslContext = sslContext
        context.pipeline.removeHandler(self).whenComplete { _ in
            do {
                let transport: EventLoopFuture<Void> = if let sslContext {
                    try context.channel.pipeline.addHandler(
                        NIOSSLClientHandler(context: sslContext, serverHostname: TLSServerName.sni(for: targetHost))
                    )
                } else {
                    context.channel.eventLoop.makeSucceededVoidFuture()
                }
                transport.flatMap {
                    context.channel.pipeline.addHTTPClientHandlers()
                }.flatMap {
                    context.channel.pipeline.addHandler(TunneledRequestHandler(
                        host: targetHost,
                        port: targetPort,
                        path: path,
                        promise: promise
                    ))
                }.whenFailure { error in
                    promise.fail(error)
                }
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

    private let targetHost: String
    private let targetPort: Int
    private let path: String
    private let sslContext: NIOSSLContext?
    private let useSOCKS: Bool
    private let promise: EventLoopPromise<LoopbackHTTPResponse>
    private var pending = ByteBufferAllocator().buffer(capacity: 256)
    private var socksGreetingDone = false
}

// MARK: - TunneledRequestHandler

private final class TunneledRequestHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(host: String, port: Int, path: String, promise: EventLoopPromise<LoopbackHTTPResponse>) {
        self.host = host
        self.port = port
        self.path = path
        self.promise = promise
    }

    // MARK: Internal

    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    func handlerAdded(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(host):\(port)")
        headers.add(name: "Connection", value: "close")
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: path, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
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
        case .end:
            promise.succeed(LoopbackHTTPResponse(status: status, headers: headers, body: body))
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        promise.fail(LoopbackError.noResponse)
    }

    // MARK: Private

    private let host: String
    private let port: Int
    private let path: String
    private let promise: EventLoopPromise<LoopbackHTTPResponse>
    private var status = 0
    private var headers = HTTPHeaders()
    private var body = Data()
}
