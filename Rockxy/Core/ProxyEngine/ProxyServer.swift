import Foundation
import NIOConcurrencyHelpers
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

    /// Upper bound on how long stop waits for in-flight client channels to close.
    /// Closing accepted local sockets is a sub-millisecond operation, so reaching this
    /// deadline means a channel is wedged rather than merely busy.
    static let drainTimeout: Duration = .seconds(5)

    /// Upper bound on how long start waits for channels left over from a previous run.
    /// Start can legitimately follow a stop that proceeded early, so a channel may still
    /// be finishing its close here; reaching this deadline means it is wedged.
    static let startDrainTimeout: Duration = .seconds(5)

    func prepareForStart() async {
        var staleChannelCount = 0
        var abandonedChannelCount = 0
        while true {
            let staleChannels = beginShutdown()
            staleChannelCount += staleChannels.count
            initiateClose(staleChannels)
            let stillClosing = await waitUntilEmpty(timeout: Self.startDrainTimeout)
            // Bounded on purpose: start is awaited inline before the UI settles, so an
            // unbounded wait here is a stuck Start button for as long as the slowest
            // channel takes. Dropping the stragglers is what lets `isShuttingDown` clear,
            // and it is safe for the same reason stop can proceed early: `close()` has
            // already been initiated on each one, so its handler's `channel.isActive`
            // gate is false and it can no longer start origin work or write a response.
            // The `closeFuture` removal that follows later is then a no-op.
            abandonedChannelCount += forget(stillClosing).count
            guard finishPreparingForStartIfEmpty() else {
                continue
            }
            break
        }
        if staleChannelCount > 0 {
            proxyServerLogger.warning("Closed \(staleChannelCount) stale client channels before proxy restart")
        }
        if abandonedChannelCount > 0 {
            proxyServerLogger
                .warning(
                    "Proxy start proceeded with \(abandonedChannelCount) client channels still closing after \(String(describing: Self.startDrainTimeout))"
                )
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

    /// Closes every live client channel and waits for them to finish closing, but only
    /// up to `timeout`. Stop is awaited inline before the UI settles, so an unbounded
    /// wait here shows up as a stuck Stop button for as long as the slowest channel
    /// takes. Proceeding early is safe: `close()` has already been initiated on every
    /// channel, so each handler's `channel.isActive` gate is false and a channel that
    /// outlives the deadline can no longer start origin work or write a response — it is
    /// only still finishing its own close.
    func closeAllAndWait(timeout: Duration = ProxyChildChannelRegistry.drainTimeout) async {
        let snapshot = beginShutdown()
        initiateClose(snapshot)
        let stillClosing = await waitUntilEmpty(timeout: timeout)
        if !stillClosing.isEmpty {
            proxyServerLogger
                .warning(
                    "Proxy stop proceeded with \(stillClosing.count) client channels still closing after \(String(describing: timeout))"
                )
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var isShuttingDown = false
    private var emptyWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    private func beginShutdown() -> [Channel] {
        lock.lock()
        isShuttingDown = true
        let snapshot = Array(channels.values)
        lock.unlock()
        return snapshot
    }

    /// Initiates close on every channel without awaiting completion, so the caller's
    /// bounded `waitUntilEmpty` is the only wait. Each channel's `closeFuture` removes it
    /// from the registry, so awaiting the close futures here as well would wait for the
    /// same event — but ahead of the deadline and without one, which is how a saturated
    /// event loop could hold stop past `drainTimeout` despite the bound.
    private func initiateClose(_ channels: [Channel]) {
        for channel in channels {
            channel.close(promise: nil)
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

    /// Drops channels from the registry without waiting for their close to complete and
    /// resumes empty waiters if that leaves it empty, so a wedged channel cannot hold the
    /// registry non-empty forever. Returns the channels it actually dropped.
    private func forget(_ staleChannels: [Channel]) -> [Channel] {
        var dropped: [Channel] = []
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        for staleChannel in staleChannels where channels.removeValue(forKey: ObjectIdentifier(staleChannel)) != nil {
            dropped.append(staleChannel)
        }
        if channels.isEmpty {
            waiters = Array(emptyWaiters.values)
            emptyWaiters.removeAll()
        } else {
            waiters = []
        }
        lock.unlock()
        waiters.forEach { $0.resume() }
        return dropped
    }

    private func remove(_ identifier: ObjectIdentifier) {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        channels.removeValue(forKey: identifier)
        if channels.isEmpty {
            waiters = Array(emptyWaiters.values)
            emptyWaiters.removeAll()
        } else {
            waiters = []
        }
        lock.unlock()
        waiters.forEach { $0.resume() }
    }

    /// Suspends until no channels remain, or until `timeout` elapses when one is given.
    /// Returns the channels that were still closing when the wait ended, so the caller
    /// can report a wedged drain. A `nil` timeout waits indefinitely.
    private func waitUntilEmpty(timeout: Duration?) async -> [Channel] {
        let waiterID = UUID()
        var timeoutTask: Task<Void, Never>?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if channels.isEmpty {
                lock.unlock()
                continuation.resume()
                return
            }
            emptyWaiters[waiterID] = continuation
            lock.unlock()
            // Armed only after the waiter is registered, so the deadline can never fire
            // against an id that `resumeEmptyWaiter` cannot find.
            if let timeout {
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.resumeEmptyWaiter(waiterID)
                }
            }
        }
        timeoutTask?.cancel()
        return registeredChannels()
    }

    /// Synchronous on purpose: `NSLock.lock()` is unavailable from an async context.
    private func registeredChannels() -> [Channel] {
        lock.lock()
        defer { lock.unlock() }
        return Array(channels.values)
    }

    /// Resumes one waiter by id, if it has not already been resumed by `remove(_:)`.
    /// Removing it under the lock is what makes the resume happen exactly once.
    private func resumeEmptyWaiter(_ waiterID: UUID) {
        lock.lock()
        let continuation = emptyWaiters.removeValue(forKey: waiterID)
        lock.unlock()
        continuation?.resume()
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

    /// Upper bound on how long stop waits for breakpoint bridges to complete.
    static let drainTimeout: Duration = .seconds(5)

    func begin() -> Lease {
        lock.lock()
        activeCount += 1
        lock.unlock()
        return Lease(owner: self)
    }

    /// Waits for outstanding breakpoint bridges to complete, but only up to `timeout`.
    /// Returns the number of bridges still outstanding when the wait ended.
    ///
    /// Proceeding early does not release a paused request to the origin: every client
    /// channel has already been closed by the time stop reaches this point, so each
    /// bridge's completion handler fails its `channel.isActive` gate and drops the
    /// request instead of forwarding it.
    @discardableResult
    func waitUntilIdle(timeout: Duration? = BreakpointBridgeTracker.drainTimeout) async -> Int {
        let waiterID = UUID()
        var timeoutTask: Task<Void, Never>?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if activeCount == 0 {
                lock.unlock()
                continuation.resume()
                return
            }
            idleWaiters[waiterID] = continuation
            lock.unlock()
            if let timeout {
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.resumeIdleWaiter(waiterID)
                }
            }
        }
        timeoutTask?.cancel()
        return outstandingBridgeCount()
    }

    // MARK: Private

    private let lock = NSLock()
    private var activeCount = 0
    private var idleWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Synchronous on purpose: `NSLock.lock()` is unavailable from an async context.
    private func outstandingBridgeCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return activeCount
    }

    private func finish() {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        precondition(activeCount > 0, "Breakpoint bridge tracker underflow")
        activeCount -= 1
        if activeCount == 0 {
            waiters = Array(idleWaiters.values)
            idleWaiters.removeAll()
        } else {
            waiters = []
        }
        lock.unlock()
        waiters.forEach { $0.resume() }
    }

    /// Resumes one waiter by id, if `finish()` has not already resumed it. Removing it
    /// under the lock is what makes the resume happen exactly once.
    private func resumeIdleWaiter(_ waiterID: UUID) {
        lock.lock()
        let continuation = idleWaiters.removeValue(forKey: waiterID)
        lock.unlock()
        continuation?.resume()
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
        upstreamTrustProvider: @escaping @Sendable () -> Bool = { UpstreamTrustPolicy.acceptsUntrustedCertificates },
        captureContextProvider: @escaping @Sendable () -> TrafficCaptureContext? = { nil },
        shouldBypassUserModifications: @escaping @Sendable (HTTPRequestData) -> Bool = { _ in false },
        clientIdentityHandleProvider: (@Sendable (ProxyConnectionDescriptor) -> ClientIdentityHandle?)? = nil,
        clientIdentityResolver: @escaping @Sendable (ProxyConnectionDescriptor) async -> ClientApplicationIdentity? = {
            await ProcessResolver.shared.identityResolver.resolveIdentity(descriptor: $0)
        },
        onTransactionComplete: @escaping @Sendable (HTTPTransaction) -> Void = { _ in },
        onBreakpointHit: (@Sendable (BreakpointRequestData) async -> (BreakpointDecision, BreakpointRequestData))? =
            nil,
        remoteAccessGate: RemoteAccessGate = .shared
    ) {
        self.configuration = configuration
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.scriptPluginManager = scriptPluginManager
        self.sslProxyingManagerOverride = sslProxyingManager
        self.bypassProxyManagerOverride = bypassProxyManager
        self.upstreamProxySnapshotProvider = upstreamProxySnapshotProvider
        self.upstreamTrustProvider = upstreamTrustProvider
        self.captureContextProvider = captureContextProvider
        self.shouldBypassUserModifications = shouldBypassUserModifications
        self.clientIdentityHandleProvider = clientIdentityHandleProvider
        self.clientIdentityResolver = clientIdentityResolver
        self.onTransactionComplete = onTransactionComplete
        self.onBreakpointHit = onBreakpointHit
        self.remoteAccessGate = remoteAccessGate
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

    /// Stamps the scripts that ran for the transaction's flow, so a request a script
    /// changed is never presented as untouched.
    static func makeScriptAttributionCallback(
        ledger: ScriptExecutionLedger?,
        downstream: @escaping @Sendable (HTTPTransaction) -> Void
    )
        -> @Sendable (HTTPTransaction) -> Void
    {
        guard let ledger else {
            return downstream
        }
        return { transaction in
            let names = ledger.scriptNames(for: transaction.request.flowID)
            if !names.isEmpty {
                transaction.appliedScriptNames = names
            }
            let previews = ledger.previews(for: transaction.request.flowID)
            if !previews.isEmpty {
                transaction.scriptPreviews = previews
            }
            downstream(transaction)
        }
    }

    /// Wraps a transaction callback so every emitted transaction — raw CONNECT, TLS failure,
    /// intercepted HTTP, WebSocket — inherits the connection's resolved application identity
    /// and a matching `clientApp` label. Stamping is a non-blocking read of the retained
    /// identity. When it is unresolved, the request's `User-Agent` supplies the same label
    /// the upstream relay derives, so a locally served response (Map Local, block, breakpoint
    /// abort) is attributed to the same client as the rest of its traffic instead of showing
    /// up as an unknown app; anything still unresolved is left for port-map enrichment.
    static func makeIdentityStampingCallback(
        handle: ClientIdentityHandle?,
        downstream: @escaping @Sendable (HTTPTransaction) -> Void
    )
        -> @Sendable (HTTPTransaction) -> Void
    {
        { transaction in
            if let identity = handle?.currentIdentity {
                if transaction.clientApplicationIdentity == nil {
                    transaction.clientApplicationIdentity = identity
                }
                if transaction.clientApp == nil {
                    transaction.clientApp = identity.displayName
                }
            }
            if transaction.clientApp == nil {
                transaction.clientApp = UpstreamResponseHandler.extractAppFromUserAgent(transaction.request.headers)
            }
            // A response Rockxy answers itself (Map Local, Block, breakpoint abort or redirect,
            // a failed upstream) does not carry the relay's GraphQL detection; label it with
            // the same operation so the row stays findable by its Operation column and filter.
            // Relayed responses without a rule already ran detection before forwarding.
            if transaction.graphQLInfo == nil,
               transaction.state != .completed || transaction.matchedRuleID != nil
            {
                transaction.graphQLInfo = GraphQLDetector.detect(request: transaction.request)
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
        let bypassUserModifications = shouldBypassUserModifications
        let breakpointHit = onBreakpointHit
        let childRegistry = childChannelRegistry
        let bridgeTracker = breakpointBridgeTracker
        let identityProviderOverride = clientIdentityHandleProvider
        let identityResolver = clientIdentityResolver
        let proxyPort = configuration.port
        // Resolved once per start rather than per request. `lanIPv4Addresses()` walks
        // `getifaddrs`, formats every AF_INET interface and sorts the result with a
        // locale-aware comparator; the loop guard used to pull it in as a default argument,
        // which Swift evaluates at the call site, so every CONNECT, SOCKS admission and plain
        // request paid for it on an event loop. Interface addresses change only when the
        // machine's networking does, and reverse-listener reconciliation refreshes the
        // snapshot for connections accepted afterwards.
        let localAddressBox = localAddressSnapshot
        localAddressBox.withLockedValue { $0 = RootCADownloadServer.lanIPv4Addresses() }
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

        installPolicyObservers(tunnelRegistry: tunnelRegistry)

        // One pipeline for the main listener and every reverse proxy listener; a reverse
        // listener adds only the request rewriter in front of the proxy handler.
        let accessGate = remoteAccessGate
        let makeChildPipeline: @Sendable (Channel, ReverseProxyTarget?)
            -> EventLoopFuture<Void> = { channel, reverseTarget in
                // Access Control: refuse other devices before any byte is read. A failed
                // initializer closes the connection.
                let access = accessGate.decision(
                    clientAddress: channel.remoteAddress?.ipAddress,
                    localAddress: channel.localAddress?.ipAddress
                )
                guard access == .allow else {
                    proxyServerLogger.info("Refused a connection from a device not allowed by Access Control")
                    return channel.eventLoop.makeFailedFuture(RemoteAccessRefusedError())
                }
                childRegistry.register(channel)
                // Capture an immutable connection descriptor at accept and start identity
                // resolution concurrently. The decorated callback stamps the resolved
                // identity onto every emitted transaction for rules and observed-app UI.
                let descriptor = ProxyConnectionDescriptor(
                    acceptedAt: DispatchTime.now(),
                    clientHost: channel.remoteAddress?.ipAddress,
                    clientPort: channel.remoteAddress?.port.flatMap { UInt16(exactly: $0) },
                    proxyHost: channel.localAddress?.ipAddress,
                    // The port this connection actually reached (main, reverse, or SOCKS listener),
                    // which identity resolution matches against the client's socket.
                    proxyPort: channel.localAddress?.port ?? reverseTarget?.localPort ?? proxyPort
                )
                let identityHandle = identityProvider(descriptor)
                identityHandle?.startResolution()
                if let identityHandle {
                    // Reclaim the identity work when this connection goes away: once the client
                    // socket is closed the lookup can no longer be matched against the OS
                    // connection table, and Stop and Quit reach it the same way, by closing
                    // every registered child channel. Registered exactly once here, in the
                    // child initializer, for the one handle that belongs to this channel —
                    // unlike `UpstreamResponseHandler`'s former per-request `closeFuture`
                    // callback, which could not be deregistered and so accumulated one
                    // callback per request on a long-lived client channel.
                    channel.closeFuture.whenComplete { _ in
                        identityHandle.cancel()
                    }
                }
                let decoratedCallback = ProxyServer.makeIdentityStampingCallback(
                    handle: identityHandle,
                    downstream: ProxyServer.makeScriptAttributionCallback(
                        ledger: scriptMgr?.executionLedger,
                        downstream: callback
                    )
                )
                return channel.pipeline.addHandler(BreakpointClientLivenessProbeHandler()).flatMap {
                    channel.pipeline.addHandler(ConnectionTimeoutHandler(timeout: .seconds(300)))
                }.flatMap {
                    channel.pipeline.addHandler(ConnectionLogger())
                }.flatMap {
                    channel.pipeline.configureHTTPServerPipeline()
                }.flatMap {
                    guard let reverseTarget else {
                        return channel.eventLoop.makeSucceededVoidFuture()
                    }
                    return channel.pipeline.addHandler(ReverseProxyRequestRewriter(target: reverseTarget))
                }.flatMap {
                    let handler = HTTPProxyHandler(
                        certificateManager: certManager,
                        ruleEngine: ruleEng,
                        scriptPluginManager: scriptMgr,
                        connectionLimiter: limiter,
                        sslProxyingManager: sslProxyingManager,
                        bypassProxyManager: bypassProxyManager,
                        upstreamProxySnapshotProvider: upstreamProxyProvider,
                        upstreamTrustProvider: self.upstreamTrustProvider,
                        captureContextProvider: captureProvider,
                        shouldBypassUserModifications: bypassUserModifications,
                        clientIdentityHandle: identityHandle,
                        clientConnectionDescriptor: descriptor,
                        localAddresses: localAddressBox.withLockedValue { $0 },
                        liveTunnelRegistry: tunnelRegistry,
                        onTransactionComplete: decoratedCallback,
                        onBreakpointHit: breakpointHit,
                        breakpointBridgeTracker: bridgeTracker
                    )
                    return channel.pipeline.addHandler(handler)
                }
            }
        childPipeline = makeChildPipeline

        let bootstrap = ServerBootstrap(group: group)
            // Backlog of 256 pending connections before the OS starts rejecting
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                makeChildPipeline(channel, nil)
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

    /// Reconciles reverse proxy listeners with `targets`: listeners that are no longer
    /// wanted (or changed) close, new ones bind on loopback. Returns the targets whose
    /// port could not be bound, keyed by target id. Requires a running proxy.
    @discardableResult
    func updateReverseProxies(_ targets: [ReverseProxyTarget]) async -> [UUID: ReverseProxyBindFailure] {
        await beginListenerReconcile()
        defer { endListenerReconcile() }
        // Reconciling listeners is the one routine point where the machine's networking may
        // have changed since start, so refresh the loop guard's address snapshot here instead
        // of re-resolving it per request.
        localAddressSnapshot.withLockedValue { $0 = RootCADownloadServer.lanIPv4Addresses() }
        let generation = listenerGeneration
        let wanted = Set(targets)
        for (target, channel) in reverseListeners where !wanted.contains(target) {
            try? await channel.close().get()
            reverseListeners.removeValue(forKey: target)
        }
        guard let group = eventLoopGroup, let childPipeline, serverChannel != nil else {
            return Dictionary(uniqueKeysWithValues: targets.map { ($0.id, .proxyNotRunning) })
        }

        var failures: [UUID: ReverseProxyBindFailure] = [:]
        for target in targets where reverseListeners[target] == nil {
            guard target.localPort != configuration.port else {
                failures[target.id] = .portInUse
                continue
            }
            let bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(.backlog, value: 64)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    childPipeline(channel, target)
                }
                .childChannelOption(.maxMessagesPerRead, value: 16)
            do {
                let channel = try await bootstrap.bind(host: "127.0.0.1", port: target.localPort).get()
                guard generation == listenerGeneration, serverChannel != nil else {
                    try? await channel.close().get()
                    failures[target.id] = .proxyNotRunning
                    continue
                }
                reverseListeners[target] = channel
                Self.logger.info("Reverse proxy listening on 127.0.0.1:\(target.localPort)")
            } catch {
                let inUse = (error as? IOError)?.errnoCode == EADDRINUSE
                failures[target.id] = inUse ? .portInUse : .bindFailed(error.localizedDescription)
            }
        }
        return failures
    }

    /// Starts, moves, or stops the SOCKS5 listener. It binds to the same address as
    /// the HTTP proxy, so it is reachable from other devices only when the proxy is.
    /// Pass `nil` to stop it. Requires a running proxy.
    @discardableResult
    func updateSOCKSListener(port: Int?) async -> ReverseProxyBindFailure? {
        await beginListenerReconcile()
        defer { endListenerReconcile() }
        let generation = listenerGeneration
        let host = configuration.listenAddress
        if let current = socksListener, current.port != port || current.host != host {
            try? await current.channel.close().get()
            socksListener = nil
        }
        guard let port else {
            return nil
        }
        guard socksListener == nil else {
            return nil
        }
        guard let group = eventLoopGroup, let childPipeline, serverChannel != nil else {
            return .proxyNotRunning
        }
        guard port != configuration.port else {
            return .portInUse
        }
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 128)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                childPipeline(channel, nil).flatMap {
                    channel.pipeline.addHandler(SOCKS5ServerHandler(), position: .first)
                }
            }
            .childChannelOption(.maxMessagesPerRead, value: 16)
        do {
            let channel = try await bootstrap.bind(host: host, port: port).get()
            guard generation == listenerGeneration, serverChannel != nil else {
                try? await channel.close().get()
                return .proxyNotRunning
            }
            socksListener = (channel, host, port)
            Self.logger.info("SOCKS5 listener on \(host):\(port)")
            return nil
        } catch {
            let inUse = (error as? IOError)?.errnoCode == EADDRINUSE
            return inUse ? .portInUse : .bindFailed(error.localizedDescription)
        }
    }

    /// How long one stop phase may wait: its own documented bound, capped by what is left of
    /// the shared `stopBudget` so the phases cannot add up past it.
    private static func phaseBudget(_ ownBound: Duration, since start: ContinuousClock.Instant) -> Duration {
        let remaining = stopBudget - (ContinuousClock.now - start)
        return min(ownBound, max(remaining, minimumPhaseBudget))
    }

    /// Runs `operation`, giving up after `timeout`, and reports whether it finished.
    ///
    /// Deliberately not a task group: a group awaits every child before it returns, so racing
    /// a sleeper against an operation that never completes would still never return. The
    /// operation runs in an unstructured task that is simply abandoned on the deadline, with a
    /// resume-once guard so the continuation is resumed exactly once — the same shape the
    /// helper connection already uses for its XPC deadlines.
    private static func awaitBounded(
        _ label: String,
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async -> Void
    ) async
        -> Bool
    {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let completed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let claim: @Sendable (Bool) -> Void = { didComplete in
                let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                    if alreadyResumed {
                        return false
                    }
                    alreadyResumed = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: didComplete)
                }
            }
            Task {
                await operation()
                claim(true)
            }
            Task {
                try? await Task.sleep(for: timeout)
                claim(false)
            }
        }
        if !completed {
            logger.warning("Proxy stop proceeded: \(label) did not finish within \(String(describing: timeout))")
        }
        return completed
    }

    func stop() async {
        guard let channel = serverChannel, !isStopping else {
            return
        }
        isStopping = true
        defer { isStopping = false }
        // One wall clock for the whole function. Every wait below is individually bounded and
        // every site documents that proceeding early is safe, but they ran one after another,
        // so what the Stop button actually cost was their sum — a ~21 s floor, more with
        // reverse listeners. Each phase now gets whatever is left of the shared budget.
        let stopStartedAt = ContinuousClock.now
        serverChannel = nil
        listenerGeneration &+= 1
        removePolicyObservers()
        // Reverse listeners are independent channels, so close them all at once under one
        // bound. Serially, one unresponsive listener's deadline was paid per listener.
        let listenerChannels = Array(reverseListeners.values)
        reverseListeners.removeAll()
        if !listenerChannels.isEmpty {
            await Self.awaitBounded(
                "reverse listener close",
                Self.phaseBudget(Self.listenerCloseTimeout, since: stopStartedAt)
            ) {
                await withTaskGroup(of: Void.self) { group in
                    for listener in listenerChannels {
                        group.addTask {
                            _ = try? await listener.close().get()
                        }
                    }
                }
            }
        }
        if let socksListener {
            await Self.awaitBounded(
                "SOCKS listener close",
                Self.phaseBudget(Self.listenerCloseTimeout, since: stopStartedAt)
            ) {
                try? await socksListener.channel.close().get()
            }
            self.socksListener = nil
        }
        childPipeline = nil

        await Self.awaitBounded(
            "server channel close",
            Self.phaseBudget(Self.listenerCloseTimeout, since: stopStartedAt)
        ) {
            do {
                try await channel.close().get()
            } catch {
                Self.logger.error("Error closing server channel: \(error.localizedDescription)")
            }
        }

        await childChannelRegistry.closeAllAndWait(
            timeout: Self.phaseBudget(ProxyChildChannelRegistry.drainTimeout, since: stopStartedAt)
        )
        let outstandingBridges = await breakpointBridgeTracker.waitUntilIdle(
            timeout: Self.phaseBudget(BreakpointBridgeTracker.drainTimeout, since: stopStartedAt)
        )
        if outstandingBridges > 0 {
            Self.logger
                .warning("Proxy stop proceeded with \(outstandingBridges) breakpoint bridges still outstanding")
        }
        liveTunnelRegistry = nil

        if let group = eventLoopGroup {
            // Bounded like every other wait in stop. `shutdownGracefully()` waits for every
            // registered channel with no deadline of its own, so one channel that never
            // finishes closing hangs Stop forever — observed directly: a test that made a
            // channel unclosable wedged here for over four hours. Giving up leaks the group's
            // threads until the straggler closes, which is strictly better than a Stop button
            // that never returns; the listeners are already closed, so no new work arrives.
            let completed = await Self.awaitBounded(
                "event loop group shutdown",
                Self.phaseBudget(Self.groupShutdownTimeout, since: stopStartedAt)
            ) {
                do {
                    try await group.shutdownGracefully()
                } catch {
                    Self.logger.error("Error shutting down event loop group: \(error.localizedDescription)")
                }
            }
            if !completed {
                Self.logger.warning("Proxy stop abandoned the event loop group shutdown; its threads outlive stop")
            }
            eventLoopGroup = nil
        }

        Self.logger.info("Proxy server stopped")
    }

    // MARK: Private

    /// Upper bound on closing one of our own listener channels during stop.
    private static let listenerCloseTimeout: Duration = .seconds(2)

    /// Upper bound on the event-loop group shutdown that ends stop.
    private static let groupShutdownTimeout: Duration = .seconds(5)

    /// Upper bound on the whole of `stop()`, shared by every bounded wait inside it.
    private static let stopBudget: Duration = .seconds(8)

    /// The smallest budget a phase is ever given. A phase whose operation has already
    /// finished still has to win the race against its deadline, so a fully spent budget
    /// would turn a clean shutdown into a run of false "did not finish" warnings.
    private static let minimumPhaseBudget: Duration = .milliseconds(200)

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProxyServer")
    nonisolated private static let tunnelInvalidationQueue = DispatchQueue(
        label: "\(RockxyIdentity.current.logSubsystem).live-tunnel-invalidation",
        qos: .utility
    )

    private let configuration: ProxyConfiguration
    private let certificateManager: CertificateManager
    private let ruleEngine: RuleEngine
    private let scriptPluginManager: ScriptPluginManager?
    private let sslProxyingManagerOverride: SSLProxyingManager?
    private let bypassProxyManagerOverride: BypassProxyManager?
    private let upstreamProxySnapshotProvider: @Sendable () -> UpstreamProxyResolvedConfiguration?
    private let upstreamTrustProvider: @Sendable () -> Bool
    private let captureContextProvider: @Sendable () -> TrafficCaptureContext?
    private let shouldBypassUserModifications: @Sendable (HTTPRequestData) -> Bool
    private let clientIdentityHandleProvider: (@Sendable (ProxyConnectionDescriptor) -> ClientIdentityHandle?)?
    private let clientIdentityResolver: @Sendable (ProxyConnectionDescriptor) async -> ClientApplicationIdentity?
    private let connectionLimiter = ConnectionLimiter()
    private let remoteAccessGate: RemoteAccessGate
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
    /// Child pipeline factory built by `start()`; reverse proxy listeners reuse it.
    private var childPipeline: (@Sendable (Channel, ReverseProxyTarget?) -> EventLoopFuture<Void>)?
    /// The machine's LAN IPv4 addresses, shared with every accepted connection so the proxy
    /// loop guard never has to resolve them on an event loop. Boxed because the child-channel
    /// initializer is a `@Sendable` closure that reads it outside the actor.
    private let localAddressSnapshot = NIOLockedValueBox<[String]>([])
    private var reverseListeners: [ReverseProxyTarget: Channel] = [:]
    private var socksListener: (channel: Channel, host: String, port: Int)?
    /// Bumped by every stop so a listener bind that finishes after the proxy stopped is discarded.
    private var listenerGeneration: UInt64 = 0
    private var isReconcilingListeners = false
    private var listenerReconcileWaiters: [CheckedContinuation<Void, Never>] = []
    private var serverChannel: Channel?
    private var isStopping = false
    private var upstreamProxyObserver: NSObjectProtocol?
    private var sslPolicyObserver: NSObjectProtocol?
    private var bypassPolicyObserver: NSObjectProtocol?
    private let upstreamProxySnapshotLock = NSLock()
    nonisolated(unsafe) private var upstreamProxyConfiguration: UpstreamProxyResolvedConfiguration?

    /// Reverse proxy and SOCKS reconciliation run one at a time; overlapping updates
    /// would otherwise race to bind the same port and report a stale status.
    private func beginListenerReconcile() async {
        if isReconcilingListeners {
            await withCheckedContinuation { listenerReconcileWaiters.append($0) }
        }
        isReconcilingListeners = true
    }

    private func endListenerReconcile() {
        if listenerReconcileWaiters.isEmpty {
            isReconcilingListeners = false
        } else {
            listenerReconcileWaiters.removeFirst().resume()
        }
    }

    /// Keeps the upstream proxy snapshot and live tunnels in step with settings changes.
    private func installPolicyObservers(tunnelRegistry: LiveTunnelRegistry) {
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
        // itself is Sendable and thread-safe. Dispatch invalidation away from the posting thread:
        // automatic TLS recovery can post from a NIO event loop, which must not synchronously
        // sweep and close unrelated live tunnels.
        sslPolicyObserver = NotificationCenter.default.addObserver(
            forName: .sslProxyingStateDidChange,
            object: nil,
            queue: nil
        ) { _ in
            Self.tunnelInvalidationQueue.async {
                tunnelRegistry.invalidateTunnelsNowRequiringInterception()
            }
        }

        // Bypass-list mutations also feed `initialTunnelMode`: removing a bypass entry can turn a
        // tracked `.bypassProxyList` raw tunnel into intercept mode while the client is still
        // connected through Rockxy. Route it through the same invalidation seam.
        bypassPolicyObserver = NotificationCenter.default.addObserver(
            forName: .bypassProxyListDidChange,
            object: nil,
            queue: nil
        ) { _ in
            Self.tunnelInvalidationQueue.async {
                tunnelRegistry.invalidateTunnelsNowRequiringInterception()
            }
        }
    }

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
