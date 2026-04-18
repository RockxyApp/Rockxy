import Crypto
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import NIOTLS
import os
import SwiftASN1
import X509

// Defines `TLSInterceptHandler`, which handles tls intercept flow in the proxy engine.

nonisolated(unsafe) private let tlsLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "TLSInterceptHandler"
)

// MARK: - RecentFailureTracker

/// Tracks recent TLS handshake failures per host to suppress duplicate noise.
/// Thread-safe via NSLock; designed for use from NIO event loops.
final class RecentFailureTracker: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        windowSeconds: Double = 30.0,
        nowProvider: @escaping @Sendable () -> DispatchTime = DispatchTime.now
    ) {
        self.windowSeconds = windowSeconds
        self.nowProvider = nowProvider
    }

    // MARK: Internal

    struct FailureInfo {
        var count: Int
        var lastFailed: DispatchTime
    }

    func recordFailure(host: String) -> FailureInfo {
        lock.lock()
        defer { lock.unlock() }
        let now = nowProvider()

        if let existing = failures[host] {
            let lastFailed = existing.lastFailed.uptimeNanoseconds
            let current = now.uptimeNanoseconds

            if current >= lastFailed {
                let elapsed = Double(current - lastFailed) / 1_000_000_000
                if elapsed < windowSeconds {
                    let updated = FailureInfo(count: existing.count + 1, lastFailed: now)
                    failures[host] = updated
                    return updated
                }
            } else {
                let updated = FailureInfo(count: existing.count + 1, lastFailed: now)
                failures[host] = updated
                return updated
            }
        }
        let fresh = FailureInfo(count: 1, lastFailed: now)
        failures[host] = fresh
        return fresh
    }

    // MARK: Private

    private var failures: [String: FailureInfo] = [:]
    private let lock = NSLock()
    private let windowSeconds: Double
    private let nowProvider: @Sendable () -> DispatchTime
}

// MARK: - TLSInterceptHandler

/// Performs HTTPS man-in-the-middle interception after a CONNECT tunnel is established.
///
/// When added to the pipeline, it requests a per-host TLS certificate from
/// `CertificateManager` (signed by Rockxy's root CA), then reconfigures the channel
/// pipeline: NIOSSLServerHandler (client-facing TLS) -> HTTP codecs ->
/// `HTTPSProxyRelayHandler` (forwards decrypted traffic to the real upstream over a
/// separate TLS connection).
///
/// If certificate generation fails (e.g., SSL pinned host), falls back to a raw TCP
/// tunnel via `RawTunnelHandler` so the connection still works — just without inspection.
final class TLSInterceptHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        host: String,
        port: Int,
        certificateManager: CertificateManager,
        ruleEngine: RuleEngine,
        scriptPluginManager: ScriptPluginManager? = nil,
        connectionLimiter: ConnectionLimiter,
        sslProxyingManager: SSLProxyingManager = .shared,
        clientSourcePort: UInt16? = nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? = nil
    ) {
        self.host = host
        self.port = port
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.connectionLimiter = connectionLimiter
        self.sslProxyingManager = sslProxyingManager
        self.clientSourcePort = clientSourcePort
        self.onTransactionComplete = onTransactionComplete
        self.onBreakpointHit = onBreakpointHit
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    nonisolated static func makeTunnelTransaction(
        host: String,
        port: Int,
        statusCode: Int,
        statusMessage: String,
        state: TransactionState,
        sourcePort: UInt16?,
        isTLSFailure: Bool = false
    )
        -> HTTPTransaction
    {
        let hostPart: String = if host.contains(":"), !host.hasPrefix("["), !host.hasSuffix("]") {
            "[\(host)]"
        } else {
            host
        }

        guard let tunnelURL = URL(string: "https://\(hostPart):\(port)") else {
            tlsLogger.warning("Failed to build CONNECT tunnel URL for host \(host, privacy: .public):\(port)")
            var fallbackComponents = URLComponents()
            fallbackComponents.scheme = "https"
            fallbackComponents.host = "invalid-tunnel.local"
            fallbackComponents.port = 443
            let fallbackURL = fallbackComponents.url ?? URL(fileURLWithPath: "/")
            return makeTunnelTransaction(
                host: fallbackURL.host ?? "invalid-tunnel.local",
                port: fallbackURL.port ?? 443,
                statusCode: statusCode,
                statusMessage: statusMessage,
                state: state,
                sourcePort: sourcePort,
                isTLSFailure: isTLSFailure
            )
        }
        let requestData = HTTPRequestData(
            method: "CONNECT",
            url: tunnelURL,
            httpVersion: "1.1",
            headers: [],
            body: nil,
            contentType: nil
        )
        let transaction = HTTPTransaction(
            request: requestData,
            response: HTTPResponseData(
                statusCode: statusCode,
                statusMessage: statusMessage,
                headers: []
            ),
            state: state
        )
        transaction.sourcePort = sourcePort
        transaction.isTLSFailure = isTLSFailure
        return transaction
    }

    /// Central raw-tunnel wiring helper. Successful passthrough capture depends on this
    /// path completing and invoking `onSuccess`, so keep all raw CONNECT success setup in
    /// one place instead of reimplementing the relay chain in multiple handlers.
    nonisolated static func completeRawTunnelSetup(
        serverChannel: Channel,
        clientChannel: Channel,
        prepareClientChannel: EventLoopFuture<Void>,
        enableClientAutoRead: Bool = false,
        onSuccess: @escaping @Sendable () -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        let toClient = RawTunnelHandler(peerChannel: clientChannel)
        let toServer = RawTunnelHandler(peerChannel: serverChannel)

        serverChannel.pipeline.addHandler(toClient).flatMap {
            prepareClientChannel
        }.flatMap {
            clientChannel.pipeline.addHandler(toServer)
        }.flatMap {
            if enableClientAutoRead {
                return clientChannel.setOption(ChannelOptions.autoRead, value: true)
            }
            return clientChannel.eventLoop.makeSucceededVoidFuture()
        }.whenComplete { result in
            switch result {
            case .success:
                onSuccess()
            case let .failure(error):
                onFailure(error)
            }
        }
    }

    nonisolated func handlerAdded(context: ChannelHandlerContext) {
        setupTLSPipeline(context: context)
    }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        bufferedData.append(data)
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        tlsLogger.error("TLS handler error for \(self.host): \(error.localizedDescription)")
        context.close(promise: nil)
    }

    // MARK: Private

    private let host: String
    private let port: Int
    private let certificateManager: CertificateManager
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let connectionLimiter: ConnectionLimiter
    private let sslProxyingManager: SSLProxyingManager
    private let clientSourcePort: UInt16?
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?
    private var bufferedData: [NIOAny] = []

    /// Asynchronously fetches a per-host cert then rewires the pipeline on the event loop.
    /// The async cert generation (actor-isolated) is bridged to NIO via `makeFutureWithTask`.
    nonisolated private func setupTLSPipeline(context: ChannelHandlerContext) {
        let host = self.host
        let port = self.port

        if !sslProxyingManager.shouldIntercept(host) {
            tlsLogger.info("No SSL proxying rule for \(host), passing through as raw tunnel")
            setupRawTunnel(context: context, host: host, port: port)
            return
        }

        if sslProxyingManager.isAutoPassthrough(host) {
            tlsLogger.info("Auto-passthrough for \(host) (previous TLS rejection), raw tunnel")
            setupRawTunnel(context: context, host: host, port: port)
            return
        }

        let eventLoop = context.eventLoop
        let certManager = self.certificateManager
        let ruleEngine = self.ruleEngine
        let callback = self.onTransactionComplete
        let scriptPluginManager = self.scriptPluginManager
        let sourcePort = self.clientSourcePort
        let breakpointHit = self.onBreakpointHit

        let certFuture: EventLoopFuture<(leafPEM: String, keyPEM: String)> =
            eventLoop.makeFutureWithTask {
                let result = try await certManager.certificateForHost(host)

                var serializer = DER.Serializer()
                try result.certificate.serialize(into: &serializer)
                let leafPEM = PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
                let keyPEM = result.privateKey.pemRepresentation

                return (leafPEM: leafPEM, keyPEM: keyPEM)
            }

        certFuture.whenComplete { result in
            guard context.channel.isActive else {
                tlsLogger.debug("Client disconnected during cert generation for \(host)")
                return
            }
            switch result {
            case let .success(certResult):
                self.installTLSHandlers(
                    context: context,
                    leafPEM: certResult.leafPEM,
                    keyPEM: certResult.keyPEM,
                    host: host,
                    port: port,
                    ruleEngine: ruleEngine,
                    scriptPluginManager: scriptPluginManager,
                    callback: callback,
                    breakpointHit: breakpointHit
                )
            case let .failure(error):
                tlsLogger.error("Certificate generation failed for \(host): \(error.localizedDescription)")
                self.setupRawTunnel(context: context, host: host, port: port)
            }
        }
    }

    nonisolated private func installTLSHandlers(
        context: ChannelHandlerContext,
        leafPEM: String,
        keyPEM: String,
        host: String,
        port: Int,
        ruleEngine: RuleEngine,
        scriptPluginManager: ScriptPluginManager?,
        callback: @escaping @Sendable (HTTPTransaction) -> Void,
        breakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? = nil
    ) {
        guard !leafPEM.isEmpty, !keyPEM.isEmpty else {
            tlsLogger.warning("Empty certificate data for \(host), passing through raw bytes")
            setupRawTunnel(context: context, host: host, port: port)
            return
        }

        do {
            let sslContext = try createServerSSLContext(leafPEM: leafPEM, keyPEM: keyPEM)
            let sslHandler = NIOSSLServerHandler(context: sslContext)

            let postHandshake = PostHandshakeHandler(
                host: host,
                port: port,
                ruleEngine: ruleEngine,
                scriptPluginManager: scriptPluginManager,
                connectionLimiter: self.connectionLimiter,
                sslProxyingManager: self.sslProxyingManager,
                clientSourcePort: self.clientSourcePort,
                onTransactionComplete: callback,
                onBreakpointHit: breakpointHit
            )

            let detector = ProtocolDetectorHandler(
                sslHandler: sslHandler,
                host: host,
                port: port,
                postHandshake: postHandshake,
                connectionLimiter: self.connectionLimiter
            )

            let pipeline = context.pipeline
            let channel = context.channel

            // Remove self and leftover HTTP codecs, then build the detection pipeline:
            //   Head → ProtocolDetector → NIOSSLServerHandler → ConnectionLogger → PostHandshakeHandler → Tail
            // NIOSSLServerHandler is added FIRST (at .first), then ProtocolDetector is
            // added at .first BEFORE it. On first channelRead, the detector forwards TLS
            // data naturally via context.fireChannelRead to the next handler (NIOSSLServerHandler).
            // This avoids the broken channel.pipeline.fireChannelRead replay pattern.
            let buffered = self.bufferedData
            pipeline.removeHandler(context: context).flatMap {
                ProxyPipeline.removeHTTPServerPipeline(from: pipeline, on: channel.eventLoop)
            }.flatMap {
                pipeline.addHandler(sslHandler, position: .first)
            }.flatMap {
                pipeline.addHandler(detector, position: .first)
            }.flatMap {
                pipeline.addHandler(postHandshake)
            }.flatMap {
                channel.setOption(ChannelOptions.autoRead, value: true)
            }.whenComplete { result in
                switch result {
                case .success:
                    tlsLogger.debug("Protocol detector installed for \(host), waiting for first bytes")
                    if !buffered.isEmpty {
                        tlsLogger.debug("Replaying \(buffered.count) buffered read(s) for \(host)")
                        for data in buffered {
                            channel.pipeline.fireChannelRead(data)
                        }
                        channel.pipeline.fireChannelReadComplete()
                    }
                case let .failure(error):
                    tlsLogger.error("Pipeline setup failed for \(host): \(String(describing: error))")
                    channel.close(promise: nil)
                }
            }
        } catch {
            tlsLogger.error("SSL context creation failed for \(host): \(String(describing: error))")
            setupRawTunnel(context: context, host: host, port: port)
        }
    }

    nonisolated private func createServerSSLContext(
        leafPEM: String,
        keyPEM: String
    )
        throws -> NIOSSLContext
    {
        let certificate = try NIOSSLCertificate(bytes: Array(leafPEM.utf8), format: .pem)
        let privateKey = try NIOSSLPrivateKey(bytes: Array(keyPEM.utf8), format: .pem)

        let chain: [NIOSSLCertificateSource] = [.certificate(certificate)]

        var config = TLSConfiguration.makeServerConfiguration(
            certificateChain: chain,
            privateKey: .privateKey(privateKey)
        )
        config.minimumTLSVersion = .tlsv12
        config.applicationProtocols = ["http/1.1"]

        return try NIOSSLContext(configuration: config)
    }

    nonisolated private func setupRawTunnel(
        context: ChannelHandlerContext,
        host: String,
        port: Int
    ) {
        guard connectionLimiter.acquire(host: host, port: port) else {
            tlsLogger.warning("Connection limit reached for \(host):\(port), closing")
            context.close(promise: nil)
            return
        }
        let limiter = connectionLimiter

        ClientBootstrap(group: context.eventLoop)
            .connectTimeout(.seconds(5))
            .connect(host: host, port: port)
            .whenComplete { result in
                switch result {
                case let .success(serverChannel):
                    serverChannel.closeFuture.whenComplete { _ in
                        limiter.release(host: host, port: port)
                    }
                    let clientChannel = context.channel
                    Self.completeRawTunnelSetup(
                        serverChannel: serverChannel,
                        clientChannel: clientChannel,
                        prepareClientChannel: context.pipeline.removeHandler(context: context),
                        enableClientAutoRead: true
                    ) {
                        self.onTransactionComplete(
                            Self.makeTunnelTransaction(
                                host: host,
                                port: port,
                                statusCode: 200,
                                statusMessage: "Connection Established",
                                state: .completed,
                                sourcePort: self.clientSourcePort
                            )
                        )
                    } onFailure: { error in
                        tlsLogger.error(
                            "Raw tunnel setup failed: \(error.localizedDescription)"
                        )
                        serverChannel.close(promise: nil)
                        context.channel.close(promise: nil)
                    }
                case let .failure(error):
                    limiter.release(host: host, port: port)
                    tlsLogger.error(
                        "Raw tunnel connection failed to \(host):\(port): \(error.localizedDescription)"
                    )
                    context.close(promise: nil)
                }
            }
    }
}

// MARK: - PostHandshakeHandler

/// Sits after NIOSSLServerHandler in the pipeline during TLS handshake. Listens for
/// `TLSUserEvent.handshakeCompleted`, then adds HTTP codecs and HTTPSProxyRelayHandler.
/// This prevents HTTP encoders from seeing raw TLS handshake bytes (which caused the
/// fatal "tried to decode as HTTPPart but found IOData" crash).
final class PostHandshakeHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        host: String,
        port: Int,
        ruleEngine: RuleEngine,
        scriptPluginManager: ScriptPluginManager?,
        connectionLimiter: ConnectionLimiter,
        sslProxyingManager: SSLProxyingManager,
        clientSourcePort: UInt16? = nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? = nil
    ) {
        self.host = host
        self.port = port
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.connectionLimiter = connectionLimiter
        self.sslProxyingManager = sslProxyingManager
        self.clientSourcePort = clientSourcePort
        self.onTransactionComplete = onTransactionComplete
        self.onBreakpointHit = onBreakpointHit
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer

    nonisolated func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is TLSUserEvent {
            guard !handshakeResolved else {
                return
            }
            handshakeResolved = true
            tlsLogger.info("TLS handshake completed for \(self.host) — adding HTTP codecs")

            let httpHandler = HTTPSProxyRelayHandler(
                host: host,
                port: port,
                ruleEngine: ruleEngine,
                scriptPluginManager: scriptPluginManager,
                connectionLimiter: connectionLimiter,
                clientSourcePort: clientSourcePort,
                onTransactionComplete: onTransactionComplete,
                onBreakpointHit: onBreakpointHit
            )

            let pipeline = context.pipeline
            pipeline.removeHandler(context: context).flatMap {
                pipeline.configureHTTPServerPipeline()
            }.flatMap {
                pipeline.addHandler(httpHandler)
            }.whenFailure { error in
                tlsLogger.error("Post-handshake pipeline setup failed for \(self.host): \(error.localizedDescription)")
                context.close(promise: nil)
            }
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard !handshakeResolved else {
            context.close(promise: nil)
            return
        }
        handshakeResolved = true
        let failInfo = Self.recentTLSFailures.recordFailure(host: host)
        let isCertRejection = Self.isCertificateRejection(error)

        if isCertRejection {
            sslProxyingManager.markHostForPassthrough(host)
        }

        if failInfo.count > 1 {
            tlsLogger.debug("Suppressing duplicate TLS failure for \(self.host) (count: \(failInfo.count))")
            context.close(promise: nil)
            return
        }

        if isCertRejection {
            tlsLogger.warning(
                "TLS cert rejected by client for \(self.host): \(String(describing: error)), marking auto-passthrough"
            )
            NotificationCenter.default.post(
                name: .tlsMitmRejected,
                object: nil,
                userInfo: ["host": host]
            )
        } else {
            tlsLogger.warning(
                "TLS error for \(self.host): \(String(describing: error)) — ambiguous, skipping passthrough"
            )
        }

        onTransactionComplete(
            TLSInterceptHandler.makeTunnelTransaction(
                host: host,
                port: port,
                statusCode: 0,
                statusMessage: "TLS Handshake Failed",
                state: .failed,
                sourcePort: clientSourcePort,
                isTLSFailure: true
            )
        )

        tearDownAndPassthrough(context: context)
    }

    nonisolated func makeSuccessfulTunnelTransaction() -> HTTPTransaction {
        TLSInterceptHandler.makeTunnelTransaction(
            host: host,
            port: port,
            statusCode: 200,
            statusMessage: "Connection Established",
            state: .completed,
            sourcePort: clientSourcePort
        )
    }

    nonisolated func recordSuccessfulTunnel() {
        onTransactionComplete(makeSuccessfulTunnelTransaction())
    }

    // MARK: Private

    private static let recentTLSFailures = RecentFailureTracker()

    private let host: String
    private let port: Int
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let connectionLimiter: ConnectionLimiter
    private let sslProxyingManager: SSLProxyingManager
    private let clientSourcePort: UInt16?
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?
    private var handshakeResolved = false

    /// Returns true if the error indicates the client rejected our generated certificate.
    /// BoringSSL errors are opaque strings, so we match against known alert patterns.
    private static func isCertificateRejection(_ error: Error) -> Bool {
        let desc = String(describing: error).lowercased()
        let certRejectionPatterns = [
            "certificate_unknown",
            "bad_certificate",
            "certificate_revoked",
            "certificate_expired",
            "unknown_ca",
            "certificate_verify_failed",
        ]
        return certRejectionPatterns.contains { desc.contains($0) }
    }

    /// Tear down failed TLS pipeline and attempt raw passthrough to the upstream server.
    /// After a client rejects the MITM certificate, the TLS session is dead but the
    /// underlying TCP socket may still be open. Setting up a raw tunnel allows Chrome
    /// to retry on the same or new connection without showing a privacy interstitial.
    nonisolated private func tearDownAndPassthrough(context: ChannelHandlerContext) {
        let host = self.host
        let port = self.port
        let channel = context.channel
        let limiter = self.connectionLimiter

        guard channel.isActive else {
            tlsLogger.debug("Channel already closed for \(host), skipping passthrough")
            return
        }

        guard limiter.acquire(host: host, port: port) else {
            tlsLogger.warning("Connection limit reached for \(host):\(port), closing")
            channel.close(promise: nil)
            return
        }

        let pipeline = context.pipeline

        pipeline.handler(type: NIOSSLServerHandler.self).flatMap { sslHandler in
            pipeline.removeHandler(sslHandler)
        }.flatMapError { _ in
            context.eventLoop.makeSucceededVoidFuture()
        }.flatMap {
            pipeline.removeHandler(context: context)
        }.flatMapError { _ in
            context.eventLoop.makeSucceededVoidFuture()
        }.flatMap {
            ClientBootstrap(group: context.eventLoop)
                .connectTimeout(.seconds(5))
                .connect(host: host, port: port)
        }.whenComplete { result in
            switch result {
            case let .success(serverChannel):
                serverChannel.closeFuture.whenComplete { _ in
                    limiter.release(host: host, port: port)
                }
                TLSInterceptHandler.completeRawTunnelSetup(
                    serverChannel: serverChannel,
                    clientChannel: channel,
                    prepareClientChannel: channel.eventLoop.makeSucceededVoidFuture()
                ) {
                    tlsLogger.info("Current-connection passthrough established for \(host)")
                } onFailure: { _ in
                    serverChannel.close(promise: nil)
                    channel.close(promise: nil)
                }
            case let .failure(error):
                limiter.release(host: host, port: port)
                tlsLogger.warning(
                    "Current-connection passthrough failed for \(host): \(error.localizedDescription), closing"
                )
                channel.close(promise: nil)
            }
        }
    }
}

// MARK: - ProtocolDetectorHandler

/// Sits before NIOSSLServerHandler in the pipeline. Examines the first byte of
/// incoming data to determine if the client is speaking TLS. If yes, forwards
/// data naturally to the next handler (NIOSSLServerHandler) via context.fireChannelRead
/// and removes itself. If no, tears down TLS handlers and sets up a raw tunnel.
///
/// This forward-based approach avoids the broken channel.pipeline.fireChannelRead
/// replay pattern that causes WRONG_VERSION_NUMBER errors.
final class ProtocolDetectorHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        sslHandler: NIOSSLServerHandler,
        host: String,
        port: Int,
        postHandshake: PostHandshakeHandler,
        connectionLimiter: ConnectionLimiter
    ) {
        self.sslHandler = sslHandler
        self.host = host
        self.port = port
        self.postHandshake = postHandshake
        self.connectionLimiter = connectionLimiter
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if detected {
            context.fireChannelRead(data)
            return
        }
        detected = true

        let buffer = unwrapInboundIn(data)
        guard let firstByte = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) else {
            context.close(promise: nil)
            return
        }

        // TLS record content types: 0x14=ChangeCipherSpec, 0x15=Alert,
        // 0x16=Handshake, 0x17=ApplicationData, 0x18=Heartbeat.
        // 0x80=SSLv2 ClientHello (legacy compatibility).
        let isTLS = (firstByte >= 0x14 && firstByte <= 0x18) || firstByte == 0x80

        if isTLS {
            tlsLogger.debug("TLS detected for \(self.host), forwarding to NIOSSLServerHandler")
            // Forward naturally to the next handler (NIOSSLServerHandler) in the pipeline.
            // No replay needed — data flows through the normal NIO path.
            context.fireChannelRead(data)
            // Remove ourselves so future reads go directly to NIOSSLServerHandler.
            context.pipeline.removeHandler(context: context, promise: nil)
        } else {
            tlsLogger
                .info(
                    "Non-TLS data (0x\(String(firstByte, radix: 16))) in CONNECT tunnel for \(self.host), falling back to raw tunnel"
                )
            tearDownForRawTunnel(context: context, firstData: data)
        }
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        tlsLogger.warning("ProtocolDetector error for \(self.host): \(String(describing: error))")
        context.close(promise: nil)
    }

    // MARK: Private

    private let sslHandler: NIOSSLServerHandler
    private let host: String
    private let port: Int
    private let postHandshake: PostHandshakeHandler
    private let connectionLimiter: ConnectionLimiter
    private var detected = false

    /// Remove NIOSSLServerHandler and PostHandshakeHandler, then set up a raw TCP relay.
    nonisolated private func tearDownForRawTunnel(
        context: ChannelHandlerContext,
        firstData: NIOAny
    ) {
        let host = self.host
        let port = self.port
        let channel = context.channel
        let sslHandler = self.sslHandler
        let postHandshake = self.postHandshake
        let limiter = self.connectionLimiter

        guard limiter.acquire(host: host, port: port) else {
            tlsLogger.warning("Connection limit reached for \(host):\(port), closing")
            channel.close(promise: nil)
            return
        }

        // Remove TLS-related handlers before setting up the raw tunnel
        let pipeline = context.pipeline
        pipeline.removeHandler(sslHandler).flatMapError { _ in
            context.eventLoop.makeSucceededVoidFuture()
        }.flatMap {
            pipeline.removeHandler(postHandshake)
        }.flatMapError { _ in
            context.eventLoop.makeSucceededVoidFuture()
        }.flatMap {
            pipeline.removeHandler(context: context)
        }.flatMap {
            ClientBootstrap(group: context.eventLoop)
                .connectTimeout(.seconds(5))
                .connect(host: host, port: port)
        }.whenComplete { result in
            switch result {
            case let .success(serverChannel):
                serverChannel.closeFuture.whenComplete { _ in
                    limiter.release(host: host, port: port)
                }
                TLSInterceptHandler.completeRawTunnelSetup(
                    serverChannel: serverChannel,
                    clientChannel: channel,
                    prepareClientChannel: channel.eventLoop.makeSucceededVoidFuture()
                ) {
                    self.postHandshake.recordSuccessfulTunnel()
                    // Forward the first non-TLS data to the upstream once the raw tunnel is live.
                    channel.pipeline.fireChannelRead(firstData)
                    channel.pipeline.fireChannelReadComplete()
                } onFailure: { _ in
                    serverChannel.close(promise: nil)
                    channel.close(promise: nil)
                }
            case let .failure(error):
                limiter.release(host: host, port: port)
                tlsLogger.error("Raw tunnel connection failed to \(host):\(port): \(String(describing: error))")
                channel.close(promise: nil)
            }
        }
    }
}

// MARK: - RawTunnelHandler

/// Bidirectional byte-level relay between two channels. Used as a fallback when TLS
/// interception cannot be performed (cert generation failure, SSL pinning). Each side
/// of the tunnel gets its own RawTunnelHandler pointing at the peer channel.
final class RawTunnelHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(peerChannel: Channel) {
        self.peerChannel = peerChannel
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    nonisolated func handlerAdded(context: ChannelHandlerContext) {
        resetIdleTimeout(context: context)
    }

    nonisolated func handlerRemoved(context: ChannelHandlerContext) {
        idleTimeout?.cancel()
        idleTimeout = nil
    }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        resetIdleTimeout(context: context)
        let buffer = unwrapInboundIn(data)
        peerChannel.writeAndFlush(NIOAny(buffer), promise: nil)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        idleTimeout?.cancel()
        peerChannel.close(promise: nil)
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        idleTimeout?.cancel()
        peerChannel.close(promise: nil)
        context.close(promise: nil)
    }

    // MARK: Private

    private static let idleTimeoutDuration: TimeAmount = .seconds(60)

    private let peerChannel: Channel
    private var idleTimeout: Scheduled<Void>?

    nonisolated private func resetIdleTimeout(context: ChannelHandlerContext) {
        idleTimeout?.cancel()
        idleTimeout = context.eventLoop.scheduleTask(in: Self.idleTimeoutDuration) {
            tlsLogger.debug("Raw tunnel idle timeout, closing")
            context.close(promise: nil)
        }
    }
}
