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

/// Tracks recent TLS handshake failures per host and originating client to suppress duplicate
/// noise without allowing one application to hide another application's evidence.
/// Thread-safe via NSLock; designed for use from NIO event loops.
final class RecentFailureTracker: @unchecked Sendable {
    static let certificateRejections = RecentFailureTracker()

    // MARK: Lifecycle

    init(
        windowSeconds: Double = 30.0,
        maximumEntries: Int = 2_048,
        nowProvider: @escaping @Sendable () -> DispatchTime = DispatchTime.now
    ) {
        self.windowSeconds = windowSeconds
        self.maximumEntries = max(1, maximumEntries)
        self.nowProvider = nowProvider
    }

    // MARK: Internal

    struct FailureInfo {
        var count: Int
        var lastFailed: DispatchTime
    }

    func recordFailure(host: String, clientIdentifier: String? = nil) -> FailureInfo {
        lock.lock()
        defer { lock.unlock() }
        let now = nowProvider()
        let key = FailureKey(host: host, clientIdentifier: clientIdentifier)
        pruneIfNeeded(now: now, preserving: key)

        if let existing = failures[key] {
            let lastFailed = existing.lastFailed.uptimeNanoseconds
            let current = now.uptimeNanoseconds

            if current >= lastFailed {
                let elapsed = Double(current - lastFailed) / 1_000_000_000
                if elapsed < windowSeconds {
                    let updated = FailureInfo(count: existing.count + 1, lastFailed: now)
                    failures[key] = updated
                    return updated
                }
            } else {
                let updated = FailureInfo(count: existing.count + 1, lastFailed: now)
                failures[key] = updated
                return updated
            }
        }
        let fresh = FailureInfo(count: 1, lastFailed: now)
        failures[key] = fresh
        return fresh
    }

    func recordIdentifiedFailure(host: String, clientIdentifier: String?) -> FailureInfo? {
        guard let clientIdentifier,
              !clientIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return recordFailure(host: host, clientIdentifier: clientIdentifier)
    }

    func recordSuccess(host: String, clientIdentifier: String? = nil) {
        lock.lock()
        failures.removeValue(forKey: FailureKey(host: host, clientIdentifier: clientIdentifier))
        lock.unlock()
    }

    /// Re-arms certificate-rejection evidence for the selected client scopes without
    /// disturbing unrelated applications or remote devices.
    func reset(clientIdentifiers: Set<String>) {
        let normalizedIdentifiers = Set(clientIdentifiers.compactMap { identifier -> String? in
            let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty ? nil : normalized
        })
        guard !normalizedIdentifiers.isEmpty else {
            return
        }

        lock.lock()
        failures = failures.filter { key, _ in
            guard let clientIdentifier = key.clientIdentifier else {
                return true
            }
            return !normalizedIdentifiers.contains(clientIdentifier)
        }
        lock.unlock()
    }

    func reset() {
        lock.lock()
        failures.removeAll()
        lock.unlock()
    }

    var trackedEntryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return failures.count
    }

    // MARK: Private

    private struct FailureKey: Hashable {
        let host: String
        let clientIdentifier: String?

        init(host: String, clientIdentifier: String?) {
            self.host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.clientIdentifier = clientIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
    }

    private var failures: [FailureKey: FailureInfo] = [:]
    private let lock = NSLock()
    private let windowSeconds: Double
    private let maximumEntries: Int
    private let nowProvider: @Sendable () -> DispatchTime

    private func pruneIfNeeded(now: DispatchTime, preserving key: FailureKey) {
        guard failures.count >= maximumEntries, failures[key] == nil else {
            return
        }
        let current = now.uptimeNanoseconds
        failures = failures.filter { _, info in
            let previous = info.lastFailed.uptimeNanoseconds
            guard current >= previous else {
                return true
            }
            return Double(current - previous) / 1_000_000_000 < windowSeconds
        }
        guard failures.count >= maximumEntries,
              let oldest = failures.min(by: {
                  $0.value.lastFailed.uptimeNanoseconds < $1.value.lastFailed.uptimeNanoseconds
              })?.key
        else {
            return
        }
        failures.removeValue(forKey: oldest)
    }
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
        bypassProxyManager: BypassProxyManager = .shared,
        customCertificateManager: CustomCertificateManager = .shared,
        upstreamProxySnapshotProvider: @escaping @Sendable () -> UpstreamProxyResolvedConfiguration? = { nil },
        captureContextProvider: @escaping @Sendable () -> TrafficCaptureContext? = { nil },
        tunnelCaptureContext: TrafficCaptureContext? = nil,
        clientSourcePort: UInt16? = nil,
        clientApplicationIdentity: ClientApplicationIdentity? = nil,
        clientConnectionDescriptor: ProxyConnectionDescriptor? = nil,
        liveTunnelRegistry: LiveTunnelRegistry? = nil,
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? =
            nil,
        breakpointBridgeTracker: BreakpointBridgeTracker? = nil
    ) {
        self.host = host
        self.port = port
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.connectionLimiter = connectionLimiter
        self.sslProxyingManager = sslProxyingManager
        self.bypassProxyManager = bypassProxyManager
        self.customCertificateManager = customCertificateManager
        self.upstreamProxySnapshotProvider = upstreamProxySnapshotProvider
        self.captureContextProvider = captureContextProvider
        self.tunnelCaptureContext = tunnelCaptureContext
        self.clientSourcePort = clientSourcePort
        self.clientApplicationIdentity = clientApplicationIdentity
        self.clientConnectionDescriptor = clientConnectionDescriptor
        self.liveTunnelRegistry = liveTunnelRegistry
        self.onTransactionComplete = onTransactionComplete
        self.onBreakpointHit = onBreakpointHit
        self.breakpointBridgeTracker = breakpointBridgeTracker
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    enum InitialTunnelMode: Equatable {
        case rawTunnel(RawTunnelReason)
        case intercept
    }

    enum RawTunnelReason: Equatable {
        case bypassProxyList
        case noSSLProxyingRule
        case unresolvedApplicationIdentity
        case autoPassthrough
        case certificateRejection
        case handshakeFailure
    }

    /// Stable scope for TLS recovery. Local clients use their application identity. Remote
    /// devices use a one-way digest of their source address so failures from one device never
    /// disable interception for another and persisted recovery state does not expose the address.
    nonisolated static func clientScopeIdentifier(
        application: ClientApplicationIdentity?,
        connectionDescriptor: ProxyConnectionDescriptor?
    ) -> String? {
        if let application {
            return application.identifier
        }
        guard let sourceHost = connectionDescriptor?.clientHost,
              !ClientConnectionMatcher.isLocalSource(sourceHost)
        else {
            return nil
        }
        let normalized = sourceHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return "remote:\(digest)"
    }

    nonisolated static func makeTunnelTransaction(
        host: String,
        port: Int,
        statusCode: Int,
        statusMessage: String,
        state: TransactionState,
        sourcePort: UInt16?,
        measuredDuration: TimeInterval? = nil,
        isTLSFailure: Bool = false,
        sslCapture: HTTPTransaction.SSLCaptureMode? = nil,
        captureContext: TrafficCaptureContext? = nil,
        clientIdentifier: String? = nil
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
                measuredDuration: measuredDuration,
                isTLSFailure: isTLSFailure,
                sslCapture: sslCapture,
                captureContext: captureContext,
                clientIdentifier: clientIdentifier
            )
        }
        let requestData = HTTPRequestData(
            method: "CONNECT",
            url: tunnelURL,
            httpVersion: "1.1",
            headers: [],
            body: nil,
            contentType: nil,
            captureContext: captureContext
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
        transaction.measuredDuration = measuredDuration
        transaction.sourcePort = sourcePort
        transaction.isTLSFailure = isTLSFailure
        transaction.sslCapture = sslCapture
        transaction.tlsClientScopeIdentifier = clientIdentifier
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

    nonisolated static func makeServerTLSConfiguration(identity: CustomTLSIdentity) throws -> TLSConfiguration {
        var config = try TLSConfiguration.makeServerConfiguration(
            certificateChain: identity.certificateSources,
            privateKey: identity.privateKeySource
        )
        config.minimumTLSVersion = .tlsv12
        config.applicationProtocols = ["http/1.1"]
        return config
    }

    nonisolated static func initialTunnelMode(
        host: String,
        sslProxyingManager: SSLProxyingManager,
        bypassProxyManager: BypassProxyManager,
        application: ClientApplicationIdentity? = nil,
        clientIdentifier: String? = nil,
        unresolvedApplicationMustTunnel: Bool = false
    )
        -> InitialTunnelMode
    {
        if bypassProxyManager.isHostBypassed(host) {
            return .rawTunnel(.bypassProxyList)
        }

        if unresolvedApplicationMustTunnel {
            return .rawTunnel(.unresolvedApplicationIdentity)
        }

        if !sslProxyingManager.shouldIntercept(host: host, application: application) {
            return .rawTunnel(.noSSLProxyingRule)
        }

        if sslProxyingManager.isAutoPassthrough(
            host,
            clientIdentifier: clientIdentifier ?? application?.identifier
        ) {
            return .rawTunnel(.autoPassthrough)
        }

        return .intercept
    }

    /// Builds the CONNECT row for a tunnel that never came up. It is not a TLS handshake
    /// failure, so it stays visible in the normal request list rather than being filtered
    /// out as one.
    nonisolated func makeTunnelFailureTransaction(statusCode: Int, statusMessage: String) -> HTTPTransaction {
        Self.makeTunnelTransaction(
            host: host,
            port: port,
            statusCode: statusCode,
            statusMessage: statusMessage,
            state: .failed,
            sourcePort: clientSourcePort,
            measuredDuration: tunnelElapsedDuration(),
            captureContext: tunnelCaptureContext,
            clientIdentifier: Self.clientScopeIdentifier(
                application: clientApplicationIdentity,
                connectionDescriptor: clientConnectionDescriptor
            )
        )
    }

    /// Reports a tunnel that was rejected or could not connect. Called only from terminal
    /// paths that close the connection, so a tunnel still reports exactly once.
    nonisolated func recordTunnelFailure(statusCode: Int, statusMessage: String) {
        onTransactionComplete(makeTunnelFailureTransaction(statusCode: statusCode, statusMessage: statusMessage))
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
    private let bypassProxyManager: BypassProxyManager
    private let customCertificateManager: CustomCertificateManager
    private let upstreamProxySnapshotProvider: @Sendable () -> UpstreamProxyResolvedConfiguration?
    private let captureContextProvider: @Sendable () -> TrafficCaptureContext?
    private let tunnelCaptureContext: TrafficCaptureContext?
    private let clientSourcePort: UInt16?
    private let clientApplicationIdentity: ClientApplicationIdentity?
    private let clientConnectionDescriptor: ProxyConnectionDescriptor?
    private let liveTunnelRegistry: LiveTunnelRegistry?
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?
    private let breakpointBridgeTracker: BreakpointBridgeTracker?
    private var bufferedData: [NIOAny] = []
    private let tunnelStartedAt = DispatchTime.now()

    /// Asynchronously fetches a per-host cert then rewires the pipeline on the event loop.
    /// The async cert generation (actor-isolated) is bridged to NIO via `makeFutureWithTask`.
    nonisolated private func setupTLSPipeline(context: ChannelHandlerContext) {
        let host = self.host
        let port = self.port

        // Capture the policy generation BEFORE reading SSL policy, so a mutation racing this
        // classification is detectable when the raw tunnel is registered (see LiveTunnelRegistry).
        let decisionGeneration = liveTunnelRegistry?.currentGeneration() ?? 0

        let clientIdentifier = Self.clientScopeIdentifier(
            application: clientApplicationIdentity,
            connectionDescriptor: clientConnectionDescriptor
        )
        let unresolvedApplicationMustTunnel = clientApplicationIdentity == nil
            && clientConnectionDescriptor?.clientHost.map(ClientConnectionMatcher.isLocalSource) == true
            && sslProxyingManager.hasEnabledApplicationTunnelRules()
        switch Self.initialTunnelMode(
            host: host,
            sslProxyingManager: sslProxyingManager,
            bypassProxyManager: bypassProxyManager,
            application: clientApplicationIdentity,
            clientIdentifier: clientIdentifier,
            unresolvedApplicationMustTunnel: unresolvedApplicationMustTunnel
        ) {
        case let .rawTunnel(reason):
            switch reason {
            case .bypassProxyList:
                tlsLogger.info("Bypass proxy list matched \(host), passing through as raw tunnel")
            case .noSSLProxyingRule:
                tlsLogger.info("No SSL proxying rule for \(host), passing through as raw tunnel")
            case .unresolvedApplicationIdentity:
                tlsLogger.info(
                    "Application identity is unresolved while a Tunnel rule is active for \(host); failing closed to a raw tunnel"
                )
            case .autoPassthrough:
                tlsLogger.info("Auto-passthrough for \(host) (previous TLS rejection), raw tunnel")
            case .certificateRejection:
                tlsLogger.info("Certificate-rejection recovery for \(host), raw tunnel")
            case .handshakeFailure:
                tlsLogger.info("TLS-handshake recovery for \(host), raw tunnel")
            }
            setupRawTunnel(
                context: context,
                host: host,
                port: port,
                trackingReason: reason,
                decisionGeneration: decisionGeneration
            )
            return
        case .intercept:
            break
        }

        let eventLoop = context.eventLoop
        let certManager = self.certificateManager
        let customCertificateManager = self.customCertificateManager
        let ruleEngine = self.ruleEngine
        let callback = self.onTransactionComplete
        let scriptPluginManager = self.scriptPluginManager
        let sourcePort = self.clientSourcePort
        let breakpointHit = self.onBreakpointHit

        let certFuture: EventLoopFuture<CustomTLSIdentity> =
            eventLoop.makeFutureWithTask {
                if let customIdentity = customCertificateManager.serverIdentity(for: host) {
                    return customIdentity
                }

                let result = try await certManager.certificateForHost(host)

                var serializer = DER.Serializer()
                try result.certificate.serialize(into: &serializer)
                let leafPEM = PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
                let keyPEM = result.privateKey.pemRepresentation

                return CustomTLSIdentity(certificateChainPEM: [leafPEM], privateKeyPEM: keyPEM)
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
                    identity: certResult,
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
        identity: CustomTLSIdentity,
        host: String,
        port: Int,
        ruleEngine: RuleEngine,
        scriptPluginManager: ScriptPluginManager?,
        callback: @escaping @Sendable (HTTPTransaction) -> Void,
        breakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? = nil
    ) {
        guard !identity.certificateChainPEM.isEmpty, !identity.privateKeyPEM.isEmpty else {
            tlsLogger.warning("Empty certificate data for \(host), passing through raw bytes")
            setupRawTunnel(context: context, host: host, port: port)
            return
        }

        do {
            let sslContext = try NIOSSLContext(configuration: Self.makeServerTLSConfiguration(identity: identity))
            let sslHandler = NIOSSLServerHandler(context: sslContext)

            let postHandshake = PostHandshakeHandler(
                host: host,
                port: port,
                ruleEngine: ruleEngine,
                scriptPluginManager: scriptPluginManager,
                connectionLimiter: self.connectionLimiter,
                sslProxyingManager: self.sslProxyingManager,
                customCertificateManager: self.customCertificateManager,
                upstreamProxySnapshotProvider: self.upstreamProxySnapshotProvider,
                captureContextProvider: self.captureContextProvider,
                tunnelCaptureContext: self.tunnelCaptureContext,
                clientSourcePort: self.clientSourcePort,
                clientApplicationIdentity: self.clientApplicationIdentity,
                clientConnectionDescriptor: self.clientConnectionDescriptor,
                clientIdentifier: Self.clientScopeIdentifier(
                    application: self.clientApplicationIdentity,
                    connectionDescriptor: self.clientConnectionDescriptor
                ),
                liveTunnelRegistry: self.liveTunnelRegistry,
                onTransactionComplete: callback,
                onBreakpointHit: breakpointHit,
                breakpointBridgeTracker: self.breakpointBridgeTracker
            )

            let detector = ProtocolDetectorHandler(
                sslHandler: sslHandler,
                host: host,
                port: port,
                postHandshake: postHandshake,
                connectionLimiter: self.connectionLimiter,
                upstreamProxySnapshotProvider: self.upstreamProxySnapshotProvider
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

    /// Sets up a raw byte tunnel to the upstream.
    ///
    /// When `trackingReason` is non-nil the resulting live tunnel is registered with the
    /// `LiveTunnelRegistry` so a later SSL-policy change that makes this host eligible for
    /// interception can close it (forcing a fresh, intercepted CONNECT). Handshake recovery
    /// tunnels are registered by `PostHandshakeHandler` after its failed TLS handlers are removed.
    nonisolated private func setupRawTunnel(
        context: ChannelHandlerContext,
        host: String,
        port: Int,
        trackingReason: RawTunnelReason? = nil,
        decisionGeneration: UInt64 = 0
    ) {
        guard connectionLimiter.acquire(host: host, port: port) else {
            tlsLogger.warning("Connection limit reached for \(host):\(port), closing")
            recordTunnelFailure(statusCode: 503, statusMessage: "Connection Limit Reached")
            context.close(promise: nil)
            return
        }
        let limiter = connectionLimiter

        UpstreamProxyConnector.connect(
            eventLoop: context.eventLoop,
            targetScheme: "https",
            targetHost: host,
            targetPort: port,
            configuration: upstreamProxySnapshotProvider()
        ) { channel in
            channel.eventLoop.makeSucceededVoidFuture()
        }
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
                    // Track the live raw tunnel so a later policy change can reset it. The
                    // registry closes the channel immediately if the raw decision raced a
                    // mutation that now requires interception.
                    if let trackingReason {
                        self.liveTunnelRegistry?.registerRawTunnel(
                            channel: clientChannel,
                            host: host,
                            application: self.clientApplicationIdentity,
                            connectionDescriptor: self.clientConnectionDescriptor,
                            reason: trackingReason,
                            decisionGeneration: decisionGeneration
                        )
                    }
                    self.onTransactionComplete(
                        Self.makeTunnelTransaction(
                            host: host,
                            port: port,
                            statusCode: 200,
                            statusMessage: "Connection Established",
                            state: .completed,
                            sourcePort: self.clientSourcePort,
                            measuredDuration: self.tunnelElapsedDuration(),
                            sslCapture: .tunneled,
                            captureContext: self.tunnelCaptureContext,
                            clientIdentifier: Self.clientScopeIdentifier(
                                application: self.clientApplicationIdentity,
                                connectionDescriptor: self.clientConnectionDescriptor
                            )
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
                self.recordTunnelFailure(statusCode: 502, statusMessage: "Upstream Connection Failed")
                context.close(promise: nil)
            }
        }
    }

    nonisolated private func tunnelElapsedDuration() -> TimeInterval {
        let elapsedNanos = DispatchTime.now().uptimeNanoseconds - tunnelStartedAt.uptimeNanoseconds
        return TimeInterval(elapsedNanos) / 1_000_000_000.0
    }
}

// MARK: - PostHandshakeHandler

/// Sits after NIOSSLServerHandler in the pipeline during TLS handshake. Listens for
/// `TLSUserEvent.handshakeCompleted`, then adds HTTP codecs and HTTPSProxyRelayHandler.
/// This prevents HTTP encoders from seeing raw TLS handshake bytes (which caused the
/// fatal "tried to decode as HTTPPart but found IOData" crash).
final class PostHandshakeHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias RecoveryTunnelConnector = @Sendable (
        EventLoop,
        String,
        Int,
        UpstreamProxyResolvedConfiguration?
    ) -> EventLoopFuture<Channel>

    // MARK: Lifecycle

    init(
        host: String,
        port: Int,
        ruleEngine: RuleEngine,
        scriptPluginManager: ScriptPluginManager?,
        connectionLimiter: ConnectionLimiter,
        sslProxyingManager: SSLProxyingManager,
        customCertificateManager: CustomCertificateManager = .shared,
        upstreamProxySnapshotProvider: @escaping @Sendable () -> UpstreamProxyResolvedConfiguration? = { nil },
        captureContextProvider: @escaping @Sendable () -> TrafficCaptureContext? = { nil },
        tunnelCaptureContext: TrafficCaptureContext? = nil,
        clientSourcePort: UInt16? = nil,
        clientApplicationIdentity: ClientApplicationIdentity? = nil,
        clientConnectionDescriptor: ProxyConnectionDescriptor? = nil,
        clientIdentifier: String? = nil,
        liveTunnelRegistry: LiveTunnelRegistry? = nil,
        recentFailureTracker: RecentFailureTracker = .certificateRejections,
        handshakeFailureRecovery: (@Sendable () -> Void)? = nil,
        recoveryTunnelConnector: @escaping RecoveryTunnelConnector = { eventLoop, host, port, configuration in
            UpstreamProxyConnector.connect(
                eventLoop: eventLoop,
                targetScheme: "https",
                targetHost: host,
                targetPort: port,
                configuration: configuration
            ) { channel in
                channel.eventLoop.makeSucceededVoidFuture()
            }
        },
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void,
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? =
            nil,
        breakpointBridgeTracker: BreakpointBridgeTracker? = nil
    ) {
        self.host = host
        self.port = port
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.connectionLimiter = connectionLimiter
        self.sslProxyingManager = sslProxyingManager
        self.customCertificateManager = customCertificateManager
        self.upstreamProxySnapshotProvider = upstreamProxySnapshotProvider
        self.captureContextProvider = captureContextProvider
        self.tunnelCaptureContext = tunnelCaptureContext
        self.clientSourcePort = clientSourcePort
        self.clientApplicationIdentity = clientApplicationIdentity
        self.clientConnectionDescriptor = clientConnectionDescriptor
        self.clientIdentifier = clientIdentifier ?? clientApplicationIdentity?.identifier
        self.liveTunnelRegistry = liveTunnelRegistry
        self.recentFailureTracker = recentFailureTracker
        self.handshakeFailureRecovery = handshakeFailureRecovery
        self.recoveryTunnelConnector = recoveryTunnelConnector
        self.onTransactionComplete = onTransactionComplete
        self.onBreakpointHit = onBreakpointHit
        self.breakpointBridgeTracker = breakpointBridgeTracker
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
            if let clientIdentifier {
                recentFailureTracker.recordSuccess(
                    host: host,
                    clientIdentifier: clientIdentifier
                )
            }
            var acceptanceUserInfo = [TLSMITMNotificationUserInfoKey.host: host]
            if let clientIdentifier {
                acceptanceUserInfo[TLSMITMNotificationUserInfoKey.clientIdentifier] = clientIdentifier
            }
            NotificationCenter.default.post(
                name: .tlsMitmAccepted,
                object: nil,
                userInfo: acceptanceUserInfo
            )

            let httpHandler = HTTPSProxyRelayHandler(
                host: host,
                port: port,
                ruleEngine: ruleEngine,
                scriptPluginManager: scriptPluginManager,
                connectionLimiter: connectionLimiter,
                customCertificateManager: customCertificateManager,
                upstreamProxySnapshotProvider: upstreamProxySnapshotProvider,
                captureContextProvider: captureContextProvider,
                clientSourcePort: clientSourcePort,
                onTransactionComplete: onTransactionComplete,
                onBreakpointHit: onBreakpointHit,
                breakpointBridgeTracker: breakpointBridgeTracker
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
        let isCertRejection = Self.isCertificateRejection(error)
        let isPersistentInterceptionFailure = isCertRejection || Self.isTLSCompatibilityFailure(error)

        if isPersistentInterceptionFailure, let clientIdentifier {
            sslProxyingManager.markHostForPassthrough(host, clientIdentifier: clientIdentifier)
        }

        if isCertRejection {
            if let clientIdentifier {
                tlsLogger.info("Remembering certificate-rejection passthrough for \(self.host) and its client scope")
            } else {
                tlsLogger.info(
                    "TLS rejection for \(self.host) has no resolved client identity; using one-connection passthrough only"
                )
            }
            let shouldReportRejection = Self.shouldReportCertificateRejection(
                host: host,
                clientIdentifier: clientIdentifier,
                tracker: recentFailureTracker
            )
            if !shouldReportRejection {
                tlsLogger.debug(
                    "Suppressing duplicate TLS rejection notification for \(self.host) and the same client scope"
                )
            } else {
                tlsLogger.warning(
                    "TLS cert rejected by client for \(self.host): \(String(describing: error))"
                )
                NotificationCenter.default.post(
                    name: .tlsMitmRejected,
                    object: nil,
                    userInfo: Self.rejectionNotificationUserInfo(
                        host: host,
                        clientIdentifier: clientIdentifier
                    )
                )
            }
        } else {
            tlsLogger.warning(
                "TLS error for \(self.host): \(String(describing: error)) — recovering with a one-connection tunnel"
            )
        }

        if let handshakeFailureRecovery {
            recordTLSHandshakeFailure()
            handshakeFailureRecovery()
        } else {
            tearDownAndPassthrough(
                context: context,
                reason: isCertRejection ? .certificateRejection : .handshakeFailure
            )
        }
    }

    /// Builds the CONNECT row for a raw tunnel established after the handshake pipeline was
    /// torn down (non-TLS data seen inside the tunnel). This is a passthrough, not an
    /// interception, so it is captured as `.tunneled`.
    nonisolated func makeSuccessfulTunnelTransaction(
        statusMessage: String = "Connection Established"
    ) -> HTTPTransaction {
        TLSInterceptHandler.makeTunnelTransaction(
            host: host,
            port: port,
            statusCode: 200,
            statusMessage: statusMessage,
            state: .completed,
            sourcePort: clientSourcePort,
            measuredDuration: tunnelElapsedDuration(),
            sslCapture: .tunneled,
            captureContext: tunnelCaptureContext,
            clientIdentifier: clientIdentifier
        )
    }

    nonisolated func recordSuccessfulTunnel(
        statusMessage: String = "Connection Established"
    ) {
        onTransactionComplete(makeSuccessfulTunnelTransaction(statusMessage: statusMessage))
    }

    /// Builds the CONNECT row for a raw-tunnel fallback that was rejected or could not
    /// connect. It is not a TLS handshake failure, so it stays visible in the normal
    /// request list rather than being filtered out as one.
    nonisolated func makeTunnelFailureTransaction(statusCode: Int, statusMessage: String) -> HTTPTransaction {
        TLSInterceptHandler.makeTunnelTransaction(
            host: host,
            port: port,
            statusCode: statusCode,
            statusMessage: statusMessage,
            state: .failed,
            sourcePort: clientSourcePort,
            measuredDuration: tunnelElapsedDuration(),
            captureContext: tunnelCaptureContext,
            clientIdentifier: clientIdentifier
        )
    }

    /// Reports a fallback tunnel that never came up. Called only from terminal paths that
    /// close the connection, and mutually exclusive with `recordSuccessfulTunnel()`, so a
    /// tunnel still reports exactly once.
    nonisolated func recordTunnelFailure(statusCode: Int, statusMessage: String) {
        onTransactionComplete(makeTunnelFailureTransaction(statusCode: statusCode, statusMessage: statusMessage))
    }

    /// Registers a completed handshake-recovery tunnel with the same application and connection
    /// scope used for its original interception decision.
    nonisolated func registerRecoveryTunnel(
        channel: Channel,
        reason: TLSInterceptHandler.RawTunnelReason,
        decisionGeneration: UInt64
    ) {
        liveTunnelRegistry?.registerRawTunnel(
            channel: channel,
            host: host,
            application: clientApplicationIdentity,
            connectionDescriptor: clientConnectionDescriptor,
            reason: reason,
            decisionGeneration: decisionGeneration
        )
    }

    // MARK: Private

    private let host: String
    private let port: Int
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let connectionLimiter: ConnectionLimiter
    private let sslProxyingManager: SSLProxyingManager
    private let customCertificateManager: CustomCertificateManager
    private let upstreamProxySnapshotProvider: @Sendable () -> UpstreamProxyResolvedConfiguration?
    private let captureContextProvider: @Sendable () -> TrafficCaptureContext?
    private let tunnelCaptureContext: TrafficCaptureContext?
    private let clientSourcePort: UInt16?
    private let clientApplicationIdentity: ClientApplicationIdentity?
    private let clientConnectionDescriptor: ProxyConnectionDescriptor?
    private let clientIdentifier: String?
    private let liveTunnelRegistry: LiveTunnelRegistry?
    private let recentFailureTracker: RecentFailureTracker
    private let handshakeFailureRecovery: (@Sendable () -> Void)?
    private let recoveryTunnelConnector: RecoveryTunnelConnector
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?
    private let breakpointBridgeTracker: BreakpointBridgeTracker?
    private var handshakeResolved = false
    private let tunnelStartedAt = DispatchTime.now()

    /// Returns true if the error indicates the client rejected our generated certificate.
    /// BoringSSL errors are opaque strings, so we match against known alert patterns.
    private static func isCertificateRejection(_ error: Error) -> Bool {
        let desc = String(describing: error).lowercased()
        let certRejectionPatterns = [
            "certificate_unknown",
            "bad_certificate",
            "bad_certificate_hash_value",
            "certificate_revoked",
            "certificate_expired",
            "unsupported_certificate",
            "unknown_ca",
            "certificate_verify_failed",
        ]
        return certRejectionPatterns.contains { desc.contains($0) }
    }

    /// Failures caused by a TLS shape Rockxy cannot currently terminate should bypass MITM on
    /// the next connection, but must not be reported as certificate-trust evidence.
    private static func isTLSCompatibilityFailure(_ error: Error) -> Bool {
        let desc = String(describing: error).lowercased()
        let compatibilityPatterns = [
            "certificate_required",
            "handshake_failure",
            "no_application_protocol",
            "protocol_version",
            "unsupported_protocol",
            "wrong_version_number",
        ]
        return compatibilityPatterns.contains { desc.contains($0) }
    }

    nonisolated static func rejectionNotificationUserInfo(
        host: String,
        clientIdentifier: String?
    ) -> [String: String] {
        var userInfo = [TLSMITMNotificationUserInfoKey.host: host]
        if let clientIdentifier {
            userInfo[TLSMITMNotificationUserInfoKey.clientIdentifier] = clientIdentifier
        }
        return userInfo
    }

    /// Returns whether this rejection should produce user-facing evidence. Duplicate failures
    /// still continue through transaction capture and raw-tunnel recovery; only their repeated
    /// notification is suppressed.
    nonisolated static func shouldReportCertificateRejection(
        host: String,
        clientIdentifier: String?,
        tracker: RecentFailureTracker = .certificateRejections
    ) -> Bool {
        let failure = tracker.recordFailure(
            host: host,
            clientIdentifier: clientIdentifier
        )
        return failure.count == 1
    }

    nonisolated private func recordTLSHandshakeFailure() {
        onTransactionComplete(
            TLSInterceptHandler.makeTunnelTransaction(
                host: host,
                port: port,
                statusCode: 0,
                statusMessage: "TLS Handshake Failed",
                state: .failed,
                sourcePort: clientSourcePort,
                measuredDuration: tunnelElapsedDuration(),
                isTLSFailure: true,
                captureContext: tunnelCaptureContext,
                clientIdentifier: clientIdentifier
            )
        )
    }

    nonisolated private func tunnelElapsedDuration() -> TimeInterval {
        let elapsedNanos = DispatchTime.now().uptimeNanoseconds - tunnelStartedAt.uptimeNanoseconds
        return TimeInterval(elapsedNanos) / 1_000_000_000.0
    }

    /// Tear down failed TLS pipeline and attempt raw passthrough to the upstream server.
    /// After a client rejects the MITM certificate, the TLS session is dead but the
    /// underlying TCP socket may still be open. Setting up a raw tunnel allows Chrome
    /// to retry on the same or new connection without showing a privacy interstitial.
    nonisolated private func tearDownAndPassthrough(
        context: ChannelHandlerContext,
        reason: TLSInterceptHandler.RawTunnelReason
    ) {
        let host = self.host
        let port = self.port
        let channel = context.channel
        let limiter = self.connectionLimiter
        let decisionGeneration = liveTunnelRegistry?.currentGeneration() ?? 0

        guard channel.isActive else {
            tlsLogger.debug("Channel already closed for \(host), skipping passthrough")
            recordTLSHandshakeFailure()
            return
        }

        guard limiter.acquire(host: host, port: port) else {
            tlsLogger.warning("Connection limit reached for \(host):\(port), closing")
            recordTunnelFailure(statusCode: 503, statusMessage: "Connection Limit Reached")
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
            self.recoveryTunnelConnector(
                context.eventLoop,
                host,
                port,
                self.upstreamProxySnapshotProvider()
            )
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
                    self.registerRecoveryTunnel(
                        channel: channel,
                        reason: reason,
                        decisionGeneration: decisionGeneration
                    )
                    self.recordSuccessfulTunnel(
                        statusMessage: reason == .certificateRejection
                            ? "Tunneled — Client Rejected Certificate"
                            : "Tunneled — TLS Interception Unavailable"
                    )
                    tlsLogger.info("Current-connection passthrough established for \(host)")
                } onFailure: { error in
                    self.recordTunnelFailure(
                        statusCode: 502,
                        statusMessage: "Tunnel Setup Failed: \(error.localizedDescription)"
                    )
                    serverChannel.close(promise: nil)
                    channel.close(promise: nil)
                }
            case let .failure(error):
                limiter.release(host: host, port: port)
                tlsLogger.warning(
                    "Current-connection passthrough failed for \(host): \(error.localizedDescription), closing"
                )
                self.recordTunnelFailure(statusCode: 502, statusMessage: "Upstream Connection Failed")
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
        connectionLimiter: ConnectionLimiter,
        upstreamProxySnapshotProvider: @escaping @Sendable () -> UpstreamProxyResolvedConfiguration? = { nil }
    ) {
        self.sslHandler = sslHandler
        self.host = host
        self.port = port
        self.postHandshake = postHandshake
        self.connectionLimiter = connectionLimiter
        self.upstreamProxySnapshotProvider = upstreamProxySnapshotProvider
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
    private let upstreamProxySnapshotProvider: @Sendable () -> UpstreamProxyResolvedConfiguration?
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
            postHandshake.recordTunnelFailure(statusCode: 503, statusMessage: "Connection Limit Reached")
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
            UpstreamProxyConnector.connect(
                eventLoop: context.eventLoop,
                targetScheme: "https",
                targetHost: host,
                targetPort: port,
                configuration: self.upstreamProxySnapshotProvider()
            ) { channel in
                channel.eventLoop.makeSucceededVoidFuture()
            }
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
                self.postHandshake.recordTunnelFailure(statusCode: 502, statusMessage: "Upstream Connection Failed")
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
