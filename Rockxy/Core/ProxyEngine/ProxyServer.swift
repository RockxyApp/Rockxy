import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import os

/// Logger must be nonisolated(unsafe) because NIO channel handlers are called
/// from event loop threads outside Swift's structured concurrency.
nonisolated(unsafe) private let proxyServerLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "ProxyServer"
)

// MARK: - BreakpointClientLivenessProbeHandler

/// Provides a one-shot transport read while an HTTP response is intentionally
/// withheld by a breakpoint. NIO's pipelining helper normally pauses socket reads
/// until the response finishes; without this probe, a peer FIN cannot reach the
/// breakpoint handler and its queued item would remain paused.
private final class BreakpointClientLivenessProbeHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = NIOAny
}

extension Channel {
    /// Requests one transport-level read from the handler positioned before the HTTP
    /// pipelining helper. The read stays bounded to a single socket read and therefore
    /// preserves the helper's back-pressure for pipelined requests.
    nonisolated func probeBreakpointClientLiveness() {
        let pipeline = self.pipeline
        eventLoop.execute {
            pipeline.context(handlerType: BreakpointClientLivenessProbeHandler.self).whenSuccess { context in
                context.read()
            }
        }
    }
}

// MARK: - ProxyChildChannelRegistry

/// Tracks accepted client channels so proxy shutdown can close and await every live
/// connection before its event-loop group is torn down.
final class ProxyChildChannelRegistry: @unchecked Sendable {
    // MARK: Internal

    func prepareForStart() async {
        var staleChannelCount = 0
        while true {
            let staleChannels = beginShutdown()
            staleChannelCount += staleChannels.count
            await close(staleChannels)
            await waitUntilEmpty()
            guard finishPreparingForStartIfEmpty() else {
                continue
            }
            break
        }
        if staleChannelCount > 0 {
            proxyServerLogger.warning("Closed \(staleChannelCount) stale client channels before proxy restart")
        }
    }

    func register(_ channel: Channel) {
        let identifier = ObjectIdentifier(channel)
        lock.lock()
        let shouldClose = isShuttingDown
        channels[identifier] = channel
        lock.unlock()

        channel.closeFuture.whenComplete { [weak self] _ in
            self?.remove(identifier)
        }
        if shouldClose {
            channel.close(promise: nil)
        }
    }

    func closeAllAndWait() async {
        let snapshot = beginShutdown()
        await close(snapshot)
        await waitUntilEmpty()
    }

    // MARK: Private

    private let lock = NSLock()
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var isShuttingDown = false
    private var emptyWaiters: [CheckedContinuation<Void, Never>] = []

    private func beginShutdown() -> [Channel] {
        lock.lock()
        isShuttingDown = true
        let snapshot = Array(channels.values)
        lock.unlock()
        return snapshot
    }

    private func close(_ channels: [Channel]) async {
        await withTaskGroup(of: Void.self) { group in
            for channel in channels {
                group.addTask {
                    try? await channel.close().get()
                }
            }
        }
    }

    private func finishPreparingForStartIfEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard channels.isEmpty else {
            return false
        }
        isShuttingDown = false
        return true
    }

    private func remove(_ identifier: ObjectIdentifier) {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        channels.removeValue(forKey: identifier)
        if channels.isEmpty {
            waiters = emptyWaiters
            emptyWaiters.removeAll()
        } else {
            waiters = []
        }
        lock.unlock()
        waiters.forEach { $0.resume() }
    }

    private func waitUntilEmpty() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if channels.isEmpty {
                lock.unlock()
                continuation.resume()
            } else {
                emptyWaiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

// MARK: - BreakpointBridgeTracker

/// Counts breakpoint Task-to-NIO promise bridges. Shutdown waits for their promise
/// completion callbacks while the event loops are still alive.
final class BreakpointBridgeTracker: @unchecked Sendable {
    // MARK: Internal

    final class Lease: @unchecked Sendable {
        // MARK: Lifecycle

        fileprivate init(owner: BreakpointBridgeTracker) {
            self.owner = owner
        }

        // MARK: Internal

        func finish() {
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }
            isFinished = true
            lock.unlock()
            owner?.finish()
            owner = nil
        }

        // MARK: Private

        private let lock = NSLock()
        private var owner: BreakpointBridgeTracker?
        private var isFinished = false
    }

    func begin() -> Lease {
        lock.lock()
        activeCount += 1
        lock.unlock()
        return Lease(owner: self)
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if activeCount == 0 {
                lock.unlock()
                continuation.resume()
            } else {
                idleWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var activeCount = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    private func finish() {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        precondition(activeCount > 0, "Breakpoint bridge tracker underflow")
        activeCount -= 1
        if activeCount == 0 {
            waiters = idleWaiters
            idleWaiters.removeAll()
        } else {
            waiters = []
        }
        lock.unlock()
        waiters.forEach { $0.resume() }
    }
}

// MARK: - ConnectionLogger

/// Logs when a new client TCP connection is accepted or closed. Added near the start
/// of each child pipeline so connection lifecycle remains visible even when later
/// handlers fail or swallow errors.
private final class ConnectionLogger: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = NIOAny

    func channelActive(context: ChannelHandlerContext) {
        let remote = context.remoteAddress?.description ?? "unknown"
        proxyServerLogger.info("New TCP connection from \(remote)")
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        proxyServerLogger.debug("TCP connection closed")
        context.fireChannelInactive()
    }
}

// MARK: - ConnectionTimeoutHandler

/// Enforces an idle timeout on client connections. If no data is read within
/// the configured timeout, the channel is closed to prevent resource leaks.
private final class ConnectionTimeoutHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(timeout: TimeAmount) {
        self.timeout = timeout
    }

    // MARK: Internal

    typealias InboundIn = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        rescheduleTimeout(context: context)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        rescheduleTimeout(context: context)
        context.fireChannelRead(data)
    }

    // MARK: Private

    private let timeout: TimeAmount
    private var timeoutTask: Scheduled<Void>?

    private func rescheduleTimeout(context: ChannelHandlerContext) {
        timeoutTask?.cancel()
        timeoutTask = context.eventLoop.scheduleTask(in: timeout) {
            proxyServerLogger.debug("Connection idle timeout exceeded, closing channel")
            context.close(promise: nil)
        }
    }
}

// MARK: - ProxyServer

/// Entry point for the proxy engine. Manages the SwiftNIO server lifecycle —
/// binds to a local port, accepts inbound connections, and installs the HTTP
/// proxy channel pipeline on each child channel. All proxy traffic flows
/// through channel handlers created here.
///
/// Actor isolation ensures start/stop state transitions are data-race-free,
/// while the NIO event loop group handles actual I/O concurrency.
actor ProxyServer {
    // MARK: Lifecycle

    init(
        configuration: ProxyConfiguration = .default,
        certificateManager: CertificateManager = .shared,
        ruleEngine: RuleEngine = RuleEngine(),
        scriptPluginManager: ScriptPluginManager? = nil,
        sslProxyingManager: SSLProxyingManager? = nil,
        bypassProxyManager: BypassProxyManager? = nil,
        upstreamProxySnapshotProvider: @escaping @Sendable () -> UpstreamProxyResolvedConfiguration? = { nil },
        captureContextProvider: @escaping @Sendable () -> TrafficCaptureContext? = { nil },
        clientIdentityHandleProvider: (@Sendable (ProxyConnectionDescriptor) -> ClientIdentityHandle?)? = nil,
        clientIdentityResolver: @escaping @Sendable (ProxyConnectionDescriptor) async -> ClientApplicationIdentity? = {
            await ProcessResolver.shared.identityResolver.resolveIdentity(descriptor: $0)
        },
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void = { _ in },
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? = nil
    ) {
        self.configuration = configuration
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.sslProxyingManagerOverride = sslProxyingManager
        self.bypassProxyManagerOverride = bypassProxyManager
        self.upstreamProxySnapshotProvider = upstreamProxySnapshotProvider
        self.captureContextProvider = captureContextProvider
        self.clientIdentityHandleProvider = clientIdentityHandleProvider
        self.clientIdentityResolver = clientIdentityResolver
        self.onTransactionComplete = onTransactionComplete
        self.onBreakpointHit = onBreakpointHit
    }

    // MARK: Internal

    var isRunning: Bool {
        serverChannel != nil
    }

    /// Default provider: resolves every accepted local connection. TLS rejection recovery and
    /// trust diagnostics are application-scoped even when no application rule exists, so
    /// sampling here would make identical traffic alternate between an app identity and the
    /// unsafe global `nil` bucket. The resolver coalesces burst lookups off the event loop.
    @Sendable
    static func defaultClientIdentityHandleProvider(
        sslProxyingManager _: SSLProxyingManager
    )
        -> @Sendable (ProxyConnectionDescriptor) -> ClientIdentityHandle?
    {
        { descriptor in
            guard let clientHost = descriptor.clientHost,
                  ClientConnectionMatcher.isLocalSource(clientHost) else
            {
                return nil
            }
            let processResolver = ProcessResolver.shared
            return ClientIdentityHandle(descriptor: descriptor, resolver: processResolver.identityResolver)
        }
    }

    /// Wraps a transaction callback so every emitted transaction — raw CONNECT, TLS failure,
    /// intercepted HTTP, WebSocket — inherits the connection's resolved application identity
    /// and a matching `clientApp` label. Stamping is a non-blocking read of the retained
    /// identity; when unresolved, `clientApp` is left for downstream port-map enrichment.
    static func makeIdentityStampingCallback(
        handle: ClientIdentityHandle?,
        downstream: @escaping @Sendable (HTTPTransaction) -> Void
    )
        -> @Sendable (HTTPTransaction) -> Void
    {
        guard let handle else {
            return downstream
        }
        return { transaction in
            if let identity = handle.currentIdentity {
                if transaction.clientApplicationIdentity == nil {
                    transaction.clientApplicationIdentity = identity
                }
                if transaction.clientApp == nil {
                    transaction.clientApp = identity.displayName
                }
            }
            downstream(transaction)
        }
    }

    func start() async throws {
        guard serverChannel == nil, !isStopping else {
            Self.logger.warning("Proxy server is already running or stopping")
            return
        }

        await childChannelRegistry.prepareForStart()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.eventLoopGroup = group

        let certManager = certificateManager
        let ruleEng = ruleEngine
        let scriptMgr = scriptPluginManager
        let limiter = connectionLimiter
        let callback = onTransactionComplete
        let captureProvider = captureContextProvider
        let breakpointHit = onBreakpointHit
        let childRegistry = childChannelRegistry
        let bridgeTracker = breakpointBridgeTracker
        let identityProviderOverride = clientIdentityHandleProvider
        let identityResolver = clientIdentityResolver
        let proxyPort = configuration.port
        let sslManagerOverride = sslProxyingManagerOverride
        let bypassManagerOverride = bypassProxyManagerOverride
        // Resolve the UI-owned policy managers on their actor, then capture the stable references
        // in a registry whose reads use only their explicitly thread-safe, nonisolated methods.
        // A fresh registry per start also prevents closed-channel state leaking across restarts.
        let policyState = await MainActor.run {
            let sslProxyingManager = sslManagerOverride ?? SSLProxyingManager.shared
            let bypassProxyManager = bypassManagerOverride ?? BypassProxyManager.shared
            let registry = LiveTunnelRegistry(
                shouldInterceptConnectionNow: { host, application, connectionDescriptor in
                    let unresolvedApplicationMustTunnel = application == nil
                        && connectionDescriptor?.clientHost.map(ClientConnectionMatcher.isLocalSource) == true
                        && sslProxyingManager.hasEnabledApplicationTunnelRules()
                    return TLSInterceptHandler.initialTunnelMode(
                        host: host,
                        sslProxyingManager: sslProxyingManager,
                        bypassProxyManager: bypassProxyManager,
                        application: application,
                        clientIdentifier: TLSInterceptHandler.clientScopeIdentifier(
                            application: application,
                            connectionDescriptor: connectionDescriptor
                        ),
                        unresolvedApplicationMustTunnel: unresolvedApplicationMustTunnel
                    ) == .intercept
                },
                shouldResolveApplicationNow: {
                    sslProxyingManager.hasEnabledApplicationRules()
                },
                resolveApplication: identityResolver
            )
            return (registry, sslProxyingManager, bypassProxyManager)
        }
        let (tunnelRegistry, sslProxyingManager, bypassProxyManager) = policyState
        let identityProvider = identityProviderOverride
            ?? Self.defaultClientIdentityHandleProvider(sslProxyingManager: sslProxyingManager)
        liveTunnelRegistry = tunnelRegistry
        refreshUpstreamProxySnapshot()
        let upstreamProxyProvider: @Sendable () -> UpstreamProxyResolvedConfiguration? = {
            self.currentUpstreamProxyConfiguration()
        }

        upstreamProxyObserver = NotificationCenter.default.addObserver(
            forName: .upstreamProxyConfigurationDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else {
                return
            }
            Task {
                await self.refreshUpstreamProxySnapshot()
            }
        }

        // Any SSL-proxying mutation (inspector, settings, import, global enable) routes through
        // save()/forceGlobalPassthrough and posts this notification. Reset live raw tunnels the
        // new policy would now intercept so the client's next request is decrypted. The registry
        // itself is Sendable and thread-safe; the closure captures only it, not self.
        sslPolicyObserver = NotificationCenter.default.addObserver(
            forName: .sslProxyingStateDidChange,
            object: nil,
            queue: nil
        ) { _ in
            tunnelRegistry.invalidateTunnelsNowRequiringInterception()
        }

        // Bypass-list mutations also feed `initialTunnelMode`: removing a bypass entry can turn a
        // tracked `.bypassProxyList` raw tunnel into intercept mode while the client is still
        // connected through Rockxy. Route it through the same invalidation seam.
        bypassPolicyObserver = NotificationCenter.default.addObserver(
            forName: .bypassProxyListDidChange,
            object: nil,
            queue: nil
        ) { _ in
            tunnelRegistry.invalidateTunnelsNowRequiringInterception()
        }

        let bootstrap = ServerBootstrap(group: group)
            // Backlog of 256 pending connections before the OS starts rejecting
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                childRegistry.register(channel)
                // Capture an immutable connection descriptor at accept and start identity
                // resolution concurrently. The decorated callback stamps the resolved
                // identity onto every emitted transaction for rules and observed-app UI.
                let descriptor = ProxyConnectionDescriptor(
                    acceptedAt: DispatchTime.now(),
                    clientHost: channel.remoteAddress?.ipAddress,
                    clientPort: channel.remoteAddress?.port.flatMap { UInt16(exactly: $0) },
                    proxyHost: channel.localAddress?.ipAddress,
                    proxyPort: proxyPort
                )
                let identityHandle = identityProvider(descriptor)
                identityHandle?.startResolution()
                let decoratedCallback = ProxyServer.makeIdentityStampingCallback(
                    handle: identityHandle,
                    downstream: callback
                )
                return channel.pipeline.addHandler(BreakpointClientLivenessProbeHandler()).flatMap {
                    channel.pipeline.addHandler(ConnectionTimeoutHandler(timeout: .seconds(300)))
                }.flatMap {
                    channel.pipeline.addHandler(ConnectionLogger())
                }.flatMap {
                    channel.pipeline.configureHTTPServerPipeline()
                }.flatMap {
                    let handler = HTTPProxyHandler(
                        certificateManager: certManager,
                        ruleEngine: ruleEng,
                        scriptPluginManager: scriptMgr,
                        connectionLimiter: limiter,
                        sslProxyingManager: sslProxyingManager,
                        bypassProxyManager: bypassProxyManager,
                        upstreamProxySnapshotProvider: upstreamProxyProvider,
                        captureContextProvider: captureProvider,
                        clientIdentityHandle: identityHandle,
                        clientConnectionDescriptor: descriptor,
                        liveTunnelRegistry: tunnelRegistry,
                        onTransactionComplete: decoratedCallback,
                        onBreakpointHit: breakpointHit,
                        breakpointBridgeTracker: bridgeTracker
                    )
                    return channel.pipeline.addHandler(handler)
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            // Cap messages per read to bound per-channel memory usage under high throughput
            .childChannelOption(.maxMessagesPerRead, value: 16)

        do {
            let channel = try await bootstrap.bind(
                host: configuration.listenAddress,
                port: configuration.port
            ).get()
            self.serverChannel = channel
        } catch {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            // The observers were installed before `bind`. `stop()` guards on `serverChannel`,
            // which never got set on a failed start, so it can't clean them — remove them here or
            // a retry would overwrite the tokens and leak the originals.
            removePolicyObservers()
            liveTunnelRegistry = nil
            if let ioError = error as? IOError, ioError.errnoCode == EADDRINUSE {
                throw ProxyServerError.portInUse(configuration.port)
            }
            throw error
        }

        Self.logger.info(
            "Proxy server started on \(self.configuration.listenAddress):\(self.configuration.port)"
        )
    }

    func stop() async {
        guard let channel = serverChannel, !isStopping else {
            return
        }
        isStopping = true
        defer { isStopping = false }
        serverChannel = nil
        removePolicyObservers()

        do {
            try await channel.close().get()
        } catch {
            Self.logger.error("Error closing server channel: \(error.localizedDescription)")
        }

        await childChannelRegistry.closeAllAndWait()
        await breakpointBridgeTracker.waitUntilIdle()
        liveTunnelRegistry = nil

        if let group = eventLoopGroup {
            do {
                try await group.shutdownGracefully()
            } catch {
                Self.logger.error("Error shutting down event loop group: \(error.localizedDescription)")
            }
            eventLoopGroup = nil
        }

        Self.logger.info("Proxy server stopped")
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProxyServer")

    private let configuration: ProxyConfiguration
    private let certificateManager: CertificateManager
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let sslProxyingManagerOverride: SSLProxyingManager?
    private let bypassProxyManagerOverride: BypassProxyManager?
    private let upstreamProxySnapshotProvider: @Sendable () -> UpstreamProxyResolvedConfiguration?
    private let captureContextProvider: @Sendable () -> TrafficCaptureContext?
    private let clientIdentityHandleProvider: (@Sendable (ProxyConnectionDescriptor) -> ClientIdentityHandle?)?
    private let clientIdentityResolver: @Sendable (ProxyConnectionDescriptor) async -> ClientApplicationIdentity?
    private let connectionLimiter = ConnectionLimiter()
    private let childChannelRegistry = ProxyChildChannelRegistry()
    private let breakpointBridgeTracker = BreakpointBridgeTracker()
    /// Tracks live raw CONNECT tunnels so an SSL-policy change can reset exactly the tunnels the
    /// current effective policy would now intercept. The predicate mirrors the raw/intercept
    /// selection in `TLSInterceptHandler.initialTunnelMode`, including application-scoped rules.
    private var liveTunnelRegistry: LiveTunnelRegistry?
    private let onTransactionComplete: @Sendable (HTTPTransaction) -> Void
    private let onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (
        BreakpointDecision,
        BreakpointRequestData
    ))?

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
    private var isStopping = false
    private var upstreamProxyObserver: NSObjectProtocol?
    private var sslPolicyObserver: NSObjectProtocol?
    private var bypassPolicyObserver: NSObjectProtocol?
    private let upstreamProxySnapshotLock = NSLock()
    nonisolated(unsafe) private var upstreamProxyConfiguration: UpstreamProxyResolvedConfiguration?

    /// Removes every notification observer installed by `start()`. Safe to call on both the clean
    /// stop path and the failed-start path; each token is niled so a later start reinstalls fresh
    /// observers without leaking the originals.
    private func removePolicyObservers() {
        if let upstreamProxyObserver {
            NotificationCenter.default.removeObserver(upstreamProxyObserver)
            self.upstreamProxyObserver = nil
        }
        if let sslPolicyObserver {
            NotificationCenter.default.removeObserver(sslPolicyObserver)
            self.sslPolicyObserver = nil
        }
        if let bypassPolicyObserver {
            NotificationCenter.default.removeObserver(bypassPolicyObserver)
            self.bypassPolicyObserver = nil
        }
    }

    private func refreshUpstreamProxySnapshot() {
        let snapshot = upstreamProxySnapshotProvider()
        upstreamProxySnapshotLock.lock()
        upstreamProxyConfiguration = snapshot
        upstreamProxySnapshotLock.unlock()
    }

    nonisolated private func currentUpstreamProxyConfiguration() -> UpstreamProxyResolvedConfiguration? {
        upstreamProxySnapshotLock.lock()
        let snapshot = upstreamProxyConfiguration
        upstreamProxySnapshotLock.unlock()
        return snapshot
    }
}

// MARK: - ProxyServerError

nonisolated enum ProxyServerError: LocalizedError {
    case portInUse(Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .portInUse(port):
            "Port \(port) is already in use by another process. Stop the conflicting service or choose another port."
        }
    }
}
