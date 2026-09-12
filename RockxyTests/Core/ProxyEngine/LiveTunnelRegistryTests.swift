import Foundation
import NIOCore
import NIOEmbedded
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - CloseFlag

/// Records whether a channel's `closeFuture` has fired. Proves the *actual* downstream
/// channel was closed, not merely that a predicate returned true.
private final class CloseFlag: @unchecked Sendable {
    private(set) var isClosed = false

    func observe(_ channel: Channel) {
        channel.closeFuture.whenComplete { [self] _ in
            lock.lock()
            isClosed = true
            lock.unlock()
        }
    }

    var closed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }

    private let lock = NSLock()
}

private enum LiveTunnelIntegrationError: Error {
    case missingBoundPort
    case proxyResponse(String)
    case timeout(String)
}

private final class ConnectResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    init(responsePromise: EventLoopPromise<Void>) {
        self.responsePromise = responsePromise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        received += buffer.readString(length: buffer.readableBytes) ?? ""
        guard !completed, received.contains("\r\n\r\n") else {
            return
        }

        completed = true
        if received.contains(" 200 ") {
            responsePromise.succeed(())
        } else {
            responsePromise.fail(LiveTunnelIntegrationError.proxyResponse(received))
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if !completed {
            completed = true
            responsePromise.fail(error)
        }
        context.close(promise: nil)
    }

    private let responsePromise: EventLoopPromise<Void>
    private var received = ""
    private var completed = false
}

/// Records that the injected application resolver ran, so a test can wait for asynchronous
/// identity resolution to complete before asserting a preserve/close outcome deterministically.
private final class ResolutionGate: @unchecked Sendable {
    func markResolved() {
        lock.lock()
        resolvedCount += 1
        lock.unlock()
    }

    var resolved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolvedCount > 0
    }

    private let lock = NSLock()
    private var resolvedCount = 0
}

private final class FutureCompletionGate: @unchecked Sendable {
    func complete(_ result: Result<Void, Error>, promise: EventLoopPromise<Void>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        promise.completeWith(result)
    }

    private let lock = NSLock()
    private var completed = false
}

// MARK: - LiveTunnelRegistryTests

/// Exercises the live-tunnel reset seam with the *real* raw/intercept predicate
/// (`TLSInterceptHandler.initialTunnelMode`) wired to isolated `SSLProxyingManager` /
/// `BypassProxyManager` instances, and real `EmbeddedChannel`s so each assertion proves the
/// downstream channel is genuinely closed (or preserved) after a policy change.
@MainActor
struct LiveTunnelRegistryTests {
    @Test("enabling SSL proxying closes a real live CONNECT tunnel through ProxyServer")
    func proxyServerClosesLiveConnectAfterRuleEnabled() async throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()

        sslManager.clearAutoPassthrough()
        sslManager.replaceAllRules([])
        sslManager.setEnabled(false)
        sslManager.setBypassDomains("")
        sslManager.forceGlobalPassthrough = false
        #expect(!sslManager.shouldIntercept("127.0.0.1"))

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let rawTunnelReadyPromise = group.next().makePromise(of: Void.self)
        var originChannel: Channel?
        var clientChannel: Channel?
        var proxyServer: ProxyServer?

        do {
            let origin = try await ServerBootstrap(group: group)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.eventLoop.makeSucceededVoidFuture()
                }
                .bind(host: "127.0.0.1", port: 0)
                .get()
            originChannel = origin
            guard let originPort = origin.localAddress?.port else {
                throw LiveTunnelIntegrationError.missingBoundPort
            }

            // Reserve an ephemeral port, then immediately hand it to ProxyServer.
            let reservation = try await ServerBootstrap(group: group)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .bind(host: "127.0.0.1", port: 0)
                .get()
            guard let proxyPort = reservation.localAddress?.port else {
                throw LiveTunnelIntegrationError.missingBoundPort
            }
            try await reservation.close().get()

            let proxy = ProxyServer(
                configuration: ProxyConfiguration(
                    port: proxyPort,
                    listenAddress: "127.0.0.1",
                    listenIPv6: false
                ),
                sslProxyingManager: sslManager,
                bypassProxyManager: bypassManager,
                onTransactionComplete: { transaction in
                    if transaction.request.method == "CONNECT", transaction.sslCapture == .tunneled {
                        rawTunnelReadyPromise.succeed(())
                    }
                }
            )
            proxyServer = proxy
            try await proxy.start()

            let responsePromise = group.next().makePromise(of: Void.self)
            let client = try await ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(ConnectResponseHandler(responsePromise: responsePromise))
                }
                .connect(host: "127.0.0.1", port: proxyPort)
                .get()
            clientChannel = client

            var request = client.allocator.buffer(capacity: 128)
            request.writeString(
                "CONNECT 127.0.0.1:\(originPort) HTTP/1.1\r\n" +
                    "Host: 127.0.0.1:\(originPort)\r\n\r\n"
            )
            try await client.writeAndFlush(request).get()
            try await wait(
                for: responsePromise.futureResult,
                timeout: .seconds(3),
                label: "waiting for CONNECT 200 response"
            )
            #expect(client.isActive)
            try await wait(
                for: rawTunnelReadyPromise.futureResult,
                timeout: .seconds(3),
                label: "waiting for raw CONNECT registration"
            )

            // This is the issue #310 transition: the browser already owns a live raw CONNECT,
            // then the user enables SSL Proxying for that host. ProxyServer's real notification
            // observer must close the existing client connection so the next request creates a
            // fresh CONNECT that can enter interception.
            sslManager.addRule(SSLProxyingRule(domain: "127.0.0.1", listType: .include))
            #expect(!sslManager.shouldIntercept("127.0.0.1"))
            sslManager.setEnabled(true)
            #expect(sslManager.shouldIntercept("127.0.0.1"))
            try await wait(
                for: client.closeFuture,
                timeout: .seconds(3),
                label: "waiting for live raw CONNECT reset"
            )
            #expect(!client.isActive)

            await proxy.stop()
            proxyServer = nil
            try await origin.close().get()
            originChannel = nil
            try await group.shutdownGracefully()
        } catch {
            if let clientChannel, clientChannel.isActive {
                try? await clientChannel.close().get()
            }
            if let proxyServer {
                await proxyServer.stop()
            }
            if let originChannel, originChannel.isActive {
                try? await originChannel.close().get()
            }
            try? await group.shutdownGracefully()
            throw error
        }
    }

    @Test("policy change resets the matching raw tunnel but preserves unrelated hosts")
    func resetsMatchingPreservesUnrelated() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")

        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)

        let matchChannel = EmbeddedChannel()
        let otherChannel = EmbeddedChannel()
        let matchFlag = CloseFlag()
        let otherFlag = CloseFlag()
        matchFlag.observe(matchChannel)
        otherFlag.observe(otherChannel)

        let generation = registry.currentGeneration()
        registry.registerRawTunnel(
            channel: matchChannel,
            host: "match.example.com",
            reason: .noSSLProxyingRule,
            decisionGeneration: generation
        )
        registry.registerRawTunnel(
            channel: otherChannel,
            host: "other.example.com",
            reason: .noSSLProxyingRule,
            decisionGeneration: generation
        )
        #expect(registry.trackedTunnelCount() == 2)

        sslManager.addRule(SSLProxyingRule(domain: "match.example.com", listType: .include))
        registry.invalidateTunnelsNowRequiringInterception()
        drain(matchChannel)
        drain(otherChannel)

        #expect(matchFlag.closed)
        #expect(!otherFlag.closed)

        _ = try? matchChannel.finish()
        _ = try? otherChannel.finish()
    }

    @Test("application Decrypt resets only matching application's live tunnel")
    func applicationDecryptResetsOnlyMatchingApplication() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let appA = ClientApplicationIdentity.bundle(identifier: "com.example.AppA", displayName: "App A")
        let appB = ClientApplicationIdentity.bundle(identifier: "com.example.AppB", displayName: "App B")
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")

        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)
        let appAChannel = EmbeddedChannel()
        let appBChannel = EmbeddedChannel()
        let unresolvedChannel = EmbeddedChannel()
        let appAFlag = CloseFlag()
        let appBFlag = CloseFlag()
        let unresolvedFlag = CloseFlag()
        appAFlag.observe(appAChannel)
        appBFlag.observe(appBChannel)
        unresolvedFlag.observe(unresolvedChannel)

        let generation = registry.currentGeneration()
        registry.registerRawTunnel(
            channel: appAChannel,
            host: "shared.example.com",
            application: appA,
            reason: .noSSLProxyingRule,
            decisionGeneration: generation
        )
        registry.registerRawTunnel(
            channel: appBChannel,
            host: "shared.example.com",
            application: appB,
            reason: .noSSLProxyingRule,
            decisionGeneration: generation
        )
        registry.registerRawTunnel(
            channel: unresolvedChannel,
            host: "shared.example.com",
            application: nil,
            reason: .noSSLProxyingRule,
            decisionGeneration: generation
        )

        sslManager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .include))
        registry.invalidateTunnelsNowRequiringInterception()
        drain(appAChannel)
        drain(appBChannel)
        drain(unresolvedChannel)

        #expect(appAFlag.closed)
        #expect(!appBFlag.closed)
        #expect(!unresolvedFlag.closed)
        #expect(registry.trackedTunnelCount() == 2)

        _ = try? appAChannel.finish()
        _ = try? appBChannel.finish()
        _ = try? unresolvedChannel.finish()
    }

    @Test("first application rule resolves old unidentified tunnels and resets only the matching app")
    func applicationDecryptLazilyResolvesExistingTunnels() async throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let chrome = ClientApplicationIdentity.bundle(
            identifier: "com.google.Chrome",
            displayName: "Google Chrome"
        )
        let safari = ClientApplicationIdentity.bundle(
            identifier: "com.apple.Safari",
            displayName: "Safari"
        )
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")

        let registry = LiveTunnelRegistry(
            shouldInterceptNow: { host, application in
                TLSInterceptHandler.initialTunnelMode(
                    host: host,
                    sslProxyingManager: sslManager,
                    bypassProxyManager: bypassManager,
                    application: application
                ) == .intercept
            },
            shouldResolveApplicationNow: {
                sslManager.hasEnabledApplicationRules()
            },
            resolveApplication: { descriptor in
                descriptor.clientPort == 51_001 ? chrome : safari
            }
        )
        let chromeChannel = EmbeddedChannel()
        let safariChannel = EmbeddedChannel()
        let chromeFlag = CloseFlag()
        let safariFlag = CloseFlag()
        chromeFlag.observe(chromeChannel)
        safariFlag.observe(safariChannel)

        let generation = registry.currentGeneration()
        registry.registerRawTunnel(
            channel: chromeChannel,
            host: "shared.example.com",
            connectionDescriptor: makeDescriptor(clientPort: 51_001),
            reason: .noSSLProxyingRule,
            decisionGeneration: generation
        )
        registry.registerRawTunnel(
            channel: safariChannel,
            host: "shared.example.com",
            connectionDescriptor: makeDescriptor(clientPort: 51_002),
            reason: .noSSLProxyingRule,
            decisionGeneration: generation
        )

        sslManager.addApplicationRule(ApplicationSSLProxyingRule(identity: chrome, listType: .include))
        registry.invalidateTunnelsNowRequiringInterception()

        for _ in 0 ..< 100 {
            drain(chromeChannel)
            drain(safariChannel)
            if chromeFlag.closed {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(chromeFlag.closed)
        #expect(!safariFlag.closed)
        #expect(registry.trackedTunnelCount() == 1)

        _ = try? chromeChannel.finish()
        _ = try? safariChannel.finish()
    }

    @Test("host Decrypt preserves an unresolved tunnel whose resolved application has a Tunnel rule")
    func hostDecryptPreservesResolvedApplicationTunnel() async throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let tunneledApp = ClientApplicationIdentity.bundle(
            identifier: "com.example.Tunneled",
            displayName: "Tunneled App"
        )
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")

        let gate = ResolutionGate()
        let registry = makeResolvingRegistry(
            sslManager: sslManager,
            bypassManager: bypassManager
        ) { _ in
            gate.markResolved()
            return tunneledApp
        }

        // The tunnel is registered while no application rules exist, so its identity stays
        // unresolved (host-only fast path). Only the later mutation makes it resolvable.
        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: "shared.example.com",
            connectionDescriptor: makeDescriptor(clientPort: 51_010),
            reason: .noSSLProxyingRule,
            decisionGeneration: registry.currentGeneration()
        )
        #expect(registry.trackedTunnelCount() == 1)

        // A host-wide Decrypt plus an application Tunnel rule that must outrank it once resolved.
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        sslManager.addApplicationRule(ApplicationSSLProxyingRule(identity: tunneledApp, listType: .exclude))
        registry.invalidateTunnelsNowRequiringInterception()
        try await settleResolution(gate: gate, channel: channel)

        #expect(!flag.closed)
        #expect(registry.trackedTunnelCount() == 1)

        _ = try? channel.finish()
    }

    @Test("host Decrypt closes an unresolved tunnel once resolution returns nil")
    func hostDecryptClosesAfterNilResolution() async throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let unrelatedApp = ClientApplicationIdentity.bundle(
            identifier: "com.example.Unrelated",
            displayName: "Unrelated App"
        )
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")

        let gate = ResolutionGate()
        let registry = makeResolvingRegistry(
            sslManager: sslManager,
            bypassManager: bypassManager
        ) { _ in
            gate.markResolved()
            return nil
        }

        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: "shared.example.com",
            connectionDescriptor: makeDescriptor(clientPort: 51_020),
            reason: .noSSLProxyingRule,
            decisionGeneration: registry.currentGeneration()
        )

        // An enabled application rule turns on lazy resolution; the host itself gains a Decrypt
        // rule. Resolution cannot identify the client, so the host-only decision closes it.
        sslManager.addApplicationRule(ApplicationSSLProxyingRule(identity: unrelatedApp, listType: .include))
        sslManager.addRule(SSLProxyingRule(domain: "shared.example.com", listType: .include))
        registry.invalidateTunnelsNowRequiringInterception()

        for _ in 0 ..< 200 {
            drain(channel)
            if flag.closed {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(gate.resolved)
        #expect(flag.closed)

        _ = try? channel.finish()
    }

    @Test("raced registration defers to an asynchronously resolved application Tunnel")
    func racedRegistrationRespectsResolvedApplicationTunnel() async throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let tunneledApp = ClientApplicationIdentity.bundle(
            identifier: "com.example.RacedTunnel",
            displayName: "Raced Tunnel App"
        )
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")

        let gate = ResolutionGate()
        let registry = makeResolvingRegistry(
            sslManager: sslManager,
            bypassManager: bypassManager
        ) { _ in
            gate.markResolved()
            return tunneledApp
        }

        // The raw classification was taken under the old (no-rule) policy.
        let decisionGeneration = registry.currentGeneration()

        // Policy mutates before the tunnel registers: host-wide Decrypt plus the application
        // Tunnel rule that must outrank it once the identity resolves.
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        sslManager.addApplicationRule(ApplicationSSLProxyingRule(identity: tunneledApp, listType: .exclude))
        registry.invalidateTunnelsNowRequiringInterception()

        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: "shared.example.com",
            connectionDescriptor: makeDescriptor(clientPort: 51_030),
            reason: .noSSLProxyingRule,
            decisionGeneration: decisionGeneration
        )
        try await settleResolution(gate: gate, channel: channel)

        #expect(gate.resolved)
        #expect(!flag.closed)
        #expect(registry.trackedTunnelCount() == 1)

        _ = try? channel.finish()
    }

    @Test("non-raced unresolved registration does not enter a reconnect loop")
    func nonRacedUnresolvedRegistrationDoesNotResolveOrClose() async throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let application = ClientApplicationIdentity.bundle(
            identifier: "com.example.LongRunningTool",
            displayName: "Long Running Tool"
        )
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        sslManager.addApplicationRule(ApplicationSSLProxyingRule(identity: application, listType: .exclude))

        let gate = ResolutionGate()
        let registry = makeResolvingRegistry(
            sslManager: sslManager,
            bypassManager: bypassManager
        ) { _ in
            gate.markResolved()
            return application
        }
        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)

        registry.registerRawTunnel(
            channel: channel,
            host: "stable.example.com",
            connectionDescriptor: makeDescriptor(clientPort: 51_035),
            reason: .unresolvedApplicationIdentity,
            decisionGeneration: registry.currentGeneration()
        )
        try await Task.sleep(for: .milliseconds(50))
        drain(channel)

        #expect(!gate.resolved)
        #expect(!flag.closed)
        #expect(registry.trackedTunnelCount() == 1)

        _ = try? channel.finish()
    }

    @Test("raced registration falls back to the host decision when no resolver is available")
    func racedRegistrationWithoutResolverStillCloses() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let application = ClientApplicationIdentity.bundle(
            identifier: "com.example.Unresolvable",
            displayName: "Unresolvable App"
        )
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")

        let registry = LiveTunnelRegistry(
            shouldInterceptNow: { host, identity in
                TLSInterceptHandler.initialTunnelMode(
                    host: host,
                    sslProxyingManager: sslManager,
                    bypassProxyManager: bypassManager,
                    application: identity
                ) == .intercept
            },
            shouldResolveApplicationNow: { sslManager.hasEnabledApplicationRules() }
        )
        let decisionGeneration = registry.currentGeneration()
        sslManager.addApplicationRule(ApplicationSSLProxyingRule(identity: application, listType: .include))
        sslManager.addRule(SSLProxyingRule(domain: "shared.example.com", listType: .include))
        registry.invalidateTunnelsNowRequiringInterception()

        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: "shared.example.com",
            connectionDescriptor: makeDescriptor(clientPort: 51_040),
            reason: .noSSLProxyingRule,
            decisionGeneration: decisionGeneration
        )
        drain(channel)

        #expect(flag.closed)
        #expect(registry.trackedTunnelCount() == 0)
        _ = try? channel.finish()
    }

    @Test("application Tunnel preserves its connection when host Decrypt resets others")
    func applicationTunnelBeatsHostDecryptDuringReset() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let appA = ClientApplicationIdentity.bundle(identifier: "com.example.AppA", displayName: "App A")
        let appB = ClientApplicationIdentity.bundle(identifier: "com.example.AppB", displayName: "App B")
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")

        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)
        let excludedChannel = EmbeddedChannel()
        let includedChannel = EmbeddedChannel()
        let excludedFlag = CloseFlag()
        let includedFlag = CloseFlag()
        excludedFlag.observe(excludedChannel)
        includedFlag.observe(includedChannel)

        let generation = registry.currentGeneration()
        registry.registerRawTunnel(
            channel: excludedChannel,
            host: "api.example.com",
            application: appA,
            reason: .noSSLProxyingRule,
            decisionGeneration: generation
        )
        registry.registerRawTunnel(
            channel: includedChannel,
            host: "api.example.com",
            application: appB,
            reason: .noSSLProxyingRule,
            decisionGeneration: generation
        )

        sslManager.addApplicationRule(ApplicationSSLProxyingRule(identity: appA, listType: .exclude))
        sslManager.addRule(SSLProxyingRule(domain: "api.example.com", listType: .include))
        registry.invalidateTunnelsNowRequiringInterception()
        drain(excludedChannel)
        drain(includedChannel)

        #expect(!excludedFlag.closed)
        #expect(includedFlag.closed)
        #expect(registry.trackedTunnelCount() == 1)

        _ = try? excludedChannel.finish()
        _ = try? includedChannel.finish()
    }

    @Test("raw classification that raced a policy mutation is closed at registration")
    func racedRawClassificationClosedAtRegistration() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")

        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)

        // Decision was taken under the old (no-rule → raw) policy.
        let decisionGeneration = registry.currentGeneration()

        // Policy mutates before this tunnel manages to register.
        sslManager.addRule(SSLProxyingRule(domain: "match.example.com", listType: .include))
        registry.invalidateTunnelsNowRequiringInterception()

        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: "match.example.com",
            reason: .noSSLProxyingRule,
            decisionGeneration: decisionGeneration
        )
        drain(channel)

        // The stale raw decision must not be tracked — it is closed immediately so the client
        // reconnects into interception.
        #expect(flag.closed)
        #expect(registry.trackedTunnelCount() == 0)

        _ = try? channel.finish()
    }

    @Test("closing a channel drains it from the registry (shutdown compatibility)")
    func channelCloseDrainsRegistry() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)

        let channel = EmbeddedChannel()
        registry.registerRawTunnel(
            channel: channel,
            host: "drain.example.com",
            reason: .noSSLProxyingRule,
            decisionGeneration: registry.currentGeneration()
        )
        #expect(registry.trackedTunnelCount() == 1)

        // EmbeddedChannel queues closeFuture callbacks on its embedded loop. Drain that loop to
        // mirror the real proxy stop path waiting for channel teardown to complete.
        channel.close(promise: nil)
        drain(channel)
        #expect(registry.trackedTunnelCount() == 0)

        _ = try? channel.finish()
    }

    @Test("retryInterception closes a live auto-passthrough tunnel via the manager notification")
    func retryClearsAutoPassthroughTunnel() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")
        let host = "retry.example.com"
        // The host is in scope for interception, but a recent TLS rejection parks it in
        // auto-passthrough so its live tunnel is raw.
        sslManager.addRule(SSLProxyingRule(domain: host, listType: .include))
        sslManager.markHostForPassthrough(host)

        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)

        // Mirror ProxyServer's observer: a policy change drives the same invalidation seam.
        let observer = NotificationCenter.default.addObserver(
            forName: .sslProxyingStateDidChange,
            object: nil,
            queue: nil
        ) { _ in
            registry.invalidateTunnelsNowRequiringInterception()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: host,
            reason: .autoPassthrough,
            decisionGeneration: registry.currentGeneration()
        )
        // Still auto-passthrough, so the tunnel is tracked (not interceptable yet).
        #expect(registry.trackedTunnelCount() == 1)
        #expect(!flag.closed)

        // Clearing the fallback posts .sslProxyingStateDidChange; the observer invalidates and the
        // now-interceptable raw tunnel is closed so the next request enters interception.
        #expect(sslManager.retryInterception(for: host))
        drain(channel)
        #expect(flag.closed)

        _ = try? channel.finish()
    }

    @Test("explicit retry resets stale tunnel without churning a later pinned tunnel")
    func acceptedHandshakeRecoveryDoesNotChurnPinnedTunnel() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let application = ClientApplicationIdentity.bundle(
            identifier: "com.example.PinnedClient",
            displayName: "Pinned Client"
        )
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))

        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)
        let observer = NotificationCenter.default.addObserver(
            forName: .sslProxyingStateDidChange,
            object: nil,
            queue: nil
        ) { _ in
            registry.invalidateTunnelsNowRequiringInterception()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let staleHost = "stale.example.com"
        sslManager.markHostForPassthrough(staleHost, application: application)
        let staleChannel = EmbeddedChannel()
        let staleFlag = CloseFlag()
        staleFlag.observe(staleChannel)
        registry.registerRawTunnel(
            channel: staleChannel,
            host: staleHost,
            application: application,
            reason: .autoPassthrough,
            decisionGeneration: registry.currentGeneration()
        )

        #expect(sslManager.retryInterception(clientIdentifiers: [application.identifier]) == 1)
        drain(staleChannel)
        #expect(staleFlag.closed)

        // If the same client then rejects a genuinely pinned host, ordinary accepted handshakes
        // must not clear that newly established protection or reset its raw tunnel.
        let pinnedHost = "pinned.example.com"
        sslManager.markHostForPassthrough(pinnedHost, application: application)
        let pinnedChannel = EmbeddedChannel()
        let pinnedFlag = CloseFlag()
        pinnedFlag.observe(pinnedChannel)
        registry.registerRawTunnel(
            channel: pinnedChannel,
            host: pinnedHost,
            application: application,
            reason: .autoPassthrough,
            decisionGeneration: registry.currentGeneration()
        )

        drain(pinnedChannel)
        #expect(!pinnedFlag.closed)
        #expect(sslManager.isAutoPassthrough(pinnedHost, application: application))
        #expect(registry.trackedTunnelCount() == 1)

        _ = try? staleChannel.finish()
        _ = try? pinnedChannel.finish()
    }

    @Test("clearing all auto-passthrough hosts closes newly interceptable live raw tunnels")
    func clearAllAutoPassthroughClosesTunnelViaNotification() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")
        let host = "certificate-ready.example.com"
        sslManager.addRule(SSLProxyingRule(domain: host, listType: .include))
        sslManager.markHostForPassthrough(host)

        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)
        let observer = NotificationCenter.default.addObserver(
            forName: .sslProxyingStateDidChange,
            object: nil,
            queue: nil
        ) { _ in
            registry.invalidateTunnelsNowRequiringInterception()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: host,
            reason: .autoPassthrough,
            decisionGeneration: registry.currentGeneration()
        )

        sslManager.clearAutoPassthrough()
        drain(channel)

        #expect(flag.closed)
        #expect(registry.trackedTunnelCount() == 0)

        _ = try? channel.finish()
    }

    @Test("removing a bypass entry closes the now-interceptable live raw tunnel")
    func bypassRemovalClosesTunnelViaNotification() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        let host = "bypass-removal.example.com"
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")
        sslManager.addRule(SSLProxyingRule(domain: host, listType: .include))
        bypassManager.addDomain(host)

        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)
        let observer = NotificationCenter.default.addObserver(
            forName: .bypassProxyListDidChange,
            object: nil,
            queue: nil
        ) { _ in
            registry.invalidateTunnelsNowRequiringInterception()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: host,
            reason: .bypassProxyList,
            decisionGeneration: registry.currentGeneration()
        )

        let matchingIDs = Set(bypassManager.domains.filter { $0.matches(host) }.map(\.id))
        bypassManager.removeDomains(ids: matchingIDs)
        drain(channel)

        #expect(flag.closed)
        #expect(registry.trackedTunnelCount() == 0)
        _ = try? channel.finish()
    }

    @Test("bypassed host tunnel is never reset by a policy change")
    func bypassedHostPreserved() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        sslManager.setEnabled(true)
        sslManager.setBypassDomains("")
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        bypassManager.addDomain("bypass.example.com")

        let registry = makeRegistry(sslManager: sslManager, bypassManager: bypassManager)

        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: "bypass.example.com",
            reason: .bypassProxyList,
            decisionGeneration: registry.currentGeneration()
        )

        registry.invalidateTunnelsNowRequiringInterception()

        #expect(!flag.closed)
        #expect(registry.trackedTunnelCount() == 1)

        _ = try? channel.finish()
    }

    @Test("remote client auto-passthrough survives connection-aware policy invalidation")
    func remoteClientPassthroughSurvivesInvalidation() throws {
        let sslManager = makeSSLProxyingManager()
        let bypassManager = makeBypassProxyManager()
        sslManager.addRule(SSLProxyingRule(domain: "*", listType: .include))
        let descriptor = ProxyConnectionDescriptor(
            acceptedAt: .now(),
            clientHost: "192.0.2.42",
            clientPort: 51_100,
            proxyHost: "0.0.0.0",
            proxyPort: 9_090
        )
        let clientIdentifier = try #require(TLSInterceptHandler.clientScopeIdentifier(
            application: nil,
            connectionDescriptor: descriptor
        ))
        sslManager.markHostForPassthrough("pinned.example", clientIdentifier: clientIdentifier)

        let registry = LiveTunnelRegistry(shouldInterceptConnectionNow: { host, application, connection in
            TLSInterceptHandler.initialTunnelMode(
                host: host,
                sslProxyingManager: sslManager,
                bypassProxyManager: bypassManager,
                application: application,
                clientIdentifier: TLSInterceptHandler.clientScopeIdentifier(
                    application: application,
                    connectionDescriptor: connection
                )
            ) == .intercept
        })
        let channel = EmbeddedChannel()
        let flag = CloseFlag()
        flag.observe(channel)
        registry.registerRawTunnel(
            channel: channel,
            host: "pinned.example",
            connectionDescriptor: descriptor,
            reason: .autoPassthrough,
            decisionGeneration: registry.currentGeneration()
        )

        registry.invalidateTunnelsNowRequiringInterception()
        drain(channel)

        #expect(!flag.closed)
        #expect(registry.trackedTunnelCount() == 1)
        _ = try? channel.finish()
    }

    // MARK: Private

    private func makeRegistry(
        sslManager: SSLProxyingManager,
        bypassManager: BypassProxyManager
    )
        -> LiveTunnelRegistry
    {
        LiveTunnelRegistry(shouldInterceptNow: { host, application in
            TLSInterceptHandler.initialTunnelMode(
                host: host,
                sslProxyingManager: sslManager,
                bypassProxyManager: bypassManager,
                application: application
            ) == .intercept
        })
    }

    /// Builds a registry whose lazy application resolution is gated on the manager actually
    /// having enabled application rules (matching production wiring) and whose resolver is
    /// injected so a test can decide which identity a descriptor maps to.
    private func makeResolvingRegistry(
        sslManager: SSLProxyingManager,
        bypassManager: BypassProxyManager,
        resolver: @escaping @Sendable (ProxyConnectionDescriptor) async -> ClientApplicationIdentity?
    )
        -> LiveTunnelRegistry
    {
        LiveTunnelRegistry(
            shouldInterceptNow: { host, application in
                TLSInterceptHandler.initialTunnelMode(
                    host: host,
                    sslProxyingManager: sslManager,
                    bypassProxyManager: bypassManager,
                    application: application
                ) == .intercept
            },
            shouldResolveApplicationNow: { sslManager.hasEnabledApplicationRules() },
            resolveApplication: resolver
        )
    }

    /// Drains the embedded channel until the injected resolver has run, then a few more cycles so
    /// any post-resolution close is flushed — leaving a definitive preserve/close state to assert.
    private func settleResolution(gate: ResolutionGate, channel: EmbeddedChannel) async throws {
        for _ in 0 ..< 200 {
            drain(channel)
            if gate.resolved {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0 ..< 5 {
            drain(channel)
            try await Task.sleep(for: .milliseconds(5))
        }
        drain(channel)
    }

    private func makeSSLProxyingManager() -> SSLProxyingManager {
        SSLProxyingManager(
            storageURL: makeTempURL(prefix: "rockxy-live-tunnel-ssl"),
            passthroughStorageURL: makeTempURL(prefix: "rockxy-live-tunnel-passthrough")
        )
    }

    private func makeBypassProxyManager() -> BypassProxyManager {
        BypassProxyManager(storageURL: makeTempURL(prefix: "rockxy-live-tunnel-bypass"))
    }

    private func makeDescriptor(clientPort: UInt16) -> ProxyConnectionDescriptor {
        ProxyConnectionDescriptor(
            acceptedAt: .now(),
            clientHost: "127.0.0.1",
            clientPort: clientPort,
            proxyHost: "127.0.0.1",
            proxyPort: 9_090
        )
    }

    private func wait(
        for future: EventLoopFuture<Void>,
        timeout: TimeAmount,
        label: String
    ) async throws {
        let resultPromise = future.eventLoop.makePromise(of: Void.self)
        let gate = FutureCompletionGate()
        future.whenComplete { result in
            gate.complete(result, promise: resultPromise)
        }
        let timeoutTask = future.eventLoop.scheduleTask(in: timeout) {
            gate.complete(
                .failure(LiveTunnelIntegrationError.timeout(label)),
                promise: resultPromise
            )
        }
        defer { timeoutTask.cancel() }
        try await resultPromise.futureResult.get()
    }

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }

    private func drain(_ channel: EmbeddedChannel) {
        channel.embeddedEventLoop.run()
    }
}
