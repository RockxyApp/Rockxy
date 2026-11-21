import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - BreakpointLifecycleTests

// Lifecycle regressions: a client that disconnects while a breakpoint is paused must
// drain the queue and must never cause the proxy to contact the origin afterwards.

@Suite(.serialized)
@MainActor
struct BreakpointLifecycleTests {
    // MARK: Internal

    /// BP_LC1 — request paused, client disconnects: the queue drains within a bounded
    /// wait and the origin never receives the request.
    @Test("client disconnect during a request pause drains the queue and skips the origin")
    func clientDisconnectDrainsQueueWithoutOriginHit() async throws {
        try await withLifecycleHarness { origin, harness in
            let matchingRule = await origin.matchingRule("pause")
            await harness.addRule(
                .breakpointTest(matchingRule: matchingRule, phases: .request)
            )
            let proxyPort = try await harness.startProxy()
            let originURL = await origin.url("pause")

            // A raw client makes the downstream connection lifetime explicit. The request
            // pauses before the proxy ever connects to the origin.
            let client = try BreakpointRawHTTPClient.connect(proxyPort: proxyPort, requestURL: originURL)
            defer { client.close() }

            let paused = try await harness.awaitNextPause(timeout: 8)
            #expect(paused.method == "GET")

            // Closing the descriptor sends a real FIN while the item is still paused.
            client.close()

            // The paused queue must drain on its own (no user resolution) within a bound.
            try await waitUntilQueueDrains(harness, timeout: 8)

            // Settle briefly, then assert the origin was never contacted.
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(await origin.requestCount() == 0)
        }
    }

    /// BP_LC2 — stopping the live proxy while an item is paused drains the queue
    /// without forwarding the held request to the origin.
    @Test("stopping the proxy drains a paused breakpoint queue without forwarding")
    func stopDrainsPausedQueue() async throws {
        try await withLifecycleHarness { origin, harness in
            let matchingRule = await origin.matchingRule("stop")
            await harness.addRule(.breakpointTest(matchingRule: matchingRule, phases: .request))
            let proxyPort = try await harness.startProxy()
            let originURL = await origin.url("stop")
            let client = try BreakpointRawHTTPClient.connect(proxyPort: proxyPort, requestURL: originURL)
            defer { client.close() }

            _ = try await harness.awaitNextPause(timeout: 8)
            await harness.stopProxyOnly()

            #expect(harness.manager.pausedItems.isEmpty)
            #expect(await origin.requestCount() == 0)
        }
    }

    @Test("proxy restart closes stale registered client channels")
    func proxyRestartClosesStaleChannels() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let registry = ProxyChildChannelRegistry()
            let staleChannel = try await makeActiveChannel(on: eventLoopGroup)
            registry.register(staleChannel)
            #expect(staleChannel.isActive)

            await registry.prepareForStart()
            #expect(!staleChannel.isActive)

            let freshChannel = try await makeActiveChannel(on: eventLoopGroup)
            registry.register(freshChannel)
            #expect(freshChannel.isActive)
            await registry.closeAllAndWait()
            #expect(!freshChannel.isActive)
            try await eventLoopGroup.shutdownGracefully()
        } catch {
            try? await eventLoopGroup.shutdownGracefully()
            throw error
        }
    }

    /// A channel whose close never completes used to suspend `prepareForStart()` forever,
    /// which the user sees as a Start button that never comes back. The wait is now
    /// bounded and the straggler is dropped so the next run can proceed.
    @Test("a client channel that never finishes closing stops blocking proxy start")
    func startDrainIsBounded() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        var wedged: (channel: Channel, swallowClose: SwallowCloseHandler)?
        do {
            let registry = ProxyChildChannelRegistry()
            let pair = try await makeUncloseableChannel(on: eventLoopGroup)
            wedged = pair
            registry.register(pair.channel)

            let startedAt = ContinuousClock.now
            await registry.prepareForStart()
            let elapsed = startedAt.duration(to: .now)

            #expect(elapsed >= ProxyChildChannelRegistry.startDrainTimeout)
            #expect(elapsed < ProxyChildChannelRegistry.startDrainTimeout + .seconds(5))

            // Start must have cleared `isShuttingDown` despite the straggler, otherwise
            // every connection the new run accepts is closed on arrival.
            let freshChannel = try await makeActiveChannel(on: eventLoopGroup)
            registry.register(freshChannel)
            #expect(freshChannel.isActive)

            await registry.closeAllAndWait()
            try await unwedge(pair.channel, removing: pair.swallowClose)
            try await eventLoopGroup.shutdownGracefully()
        } catch {
            if let wedged {
                try? await unwedge(wedged.channel, removing: wedged.swallowClose)
            }
            try? await eventLoopGroup.shutdownGracefully()
            throw error
        }
    }

    /// Stop bounded its own wait but awaited every close future first, with no deadline
    /// on that phase, so a channel that never finished closing still hung Stop.
    @Test("a client channel that never finishes closing stops blocking proxy stop")
    func stopDrainIsBoundedAcrossTheClosePhase() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        var wedged: (channel: Channel, swallowClose: SwallowCloseHandler)?
        do {
            let registry = ProxyChildChannelRegistry()
            let pair = try await makeUncloseableChannel(on: eventLoopGroup)
            wedged = pair
            registry.register(pair.channel)

            let startedAt = ContinuousClock.now
            await registry.closeAllAndWait(timeout: .milliseconds(200))
            let elapsed = startedAt.duration(to: .now)

            #expect(elapsed < .seconds(5))
            try await unwedge(pair.channel, removing: pair.swallowClose)
            try await eventLoopGroup.shutdownGracefully()
        } catch {
            if let wedged {
                try? await unwedge(wedged.channel, removing: wedged.swallowClose)
            }
            try? await eventLoopGroup.shutdownGracefully()
            throw error
        }
    }

    /// A bridge that never completes used to suspend `stop()` forever, which the user
    /// sees as a Stop button that never comes back. The wait is now bounded and reports
    /// what outlived it.
    @Test("A breakpoint bridge that never completes stops waiting at its deadline")
    func bridgeDrainIsBounded() async {
        let tracker = BreakpointBridgeTracker()
        let lease = tracker.begin()
        let startedAt = ContinuousClock.now
        let outstanding = await tracker.waitUntilIdle(timeout: .milliseconds(200))
        let elapsed = startedAt.duration(to: .now)

        #expect(outstanding == 1)
        #expect(elapsed < .seconds(5))

        // The lease completing after its deadline must not resume the waiter a second
        // time; a double resume of a CheckedContinuation traps.
        lease.finish()
        #expect(await tracker.waitUntilIdle(timeout: .milliseconds(200)) == 0)
    }

    /// The deadline is an upper bound, not a delay: a normal drain must return as soon
    /// as the last bridge completes.
    @Test("Breakpoint bridge drain returns as soon as the last bridge completes")
    func bridgeDrainReturnsOnCompletion() async {
        let tracker = BreakpointBridgeTracker()
        let lease = tracker.begin()
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            lease.finish()
        }

        let startedAt = ContinuousClock.now
        let outstanding = await tracker.waitUntilIdle(timeout: .seconds(30))
        let elapsed = startedAt.duration(to: .now)

        #expect(outstanding == 0)
        #expect(elapsed < .seconds(10))
    }

    // MARK: Private

    private func withLifecycleHarness(
        _ body: (CountingOriginServer, BreakpointTestHarness) async throws -> Void
    )
        async throws
    {
        let origin = try await CountingOriginServer.start()
        var harness: BreakpointTestHarness?
        do {
            let started = try await BreakpointTestHarness.start()
            harness = started
            try await body(origin, started)
            await started.stop()
            await origin.stop()
        } catch {
            // Await teardown on failure too; a timeout must not leak listeners into later tests.
            await harness?.stop()
            await origin.stop()
            throw error
        }
    }

    private func waitUntilQueueDrains(
        _ harness: BreakpointTestHarness,
        timeout seconds: TimeInterval
    )
        async throws
    {
        let ticks = Int(seconds / 0.01)
        for _ in 0 ..< ticks {
            if harness.manager.pausedItems.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record(
            "Breakpoint queue did not drain after client disconnect (\(harness.manager.pausedItems.count) still paused)."
        )
    }

    /// A channel whose pipeline swallows `close`, standing in for one wedged by a
    /// saturated event loop: its `closeFuture` never fires, so any unbounded wait on it
    /// never returns.
    private func makeUncloseableChannel(
        on group: EventLoopGroup
    ) async throws
        -> (channel: Channel, swallowClose: SwallowCloseHandler)
    {
        let channel = try await makeActiveChannel(on: group)
        let swallowClose = SwallowCloseHandler()
        try await channel.pipeline.addHandler(swallowClose).get()
        return (channel, swallowClose)
    }

    /// Lets a deliberately unclosable channel close for real before the test tears its
    /// event-loop group down. `shutdownGracefully()` waits for every channel with no
    /// deadline, so leaving one permanently unclosable hangs the whole test run — which is
    /// what an earlier version of these tests did, for four hours.
    private func unwedge(_ channel: Channel, removing swallowClose: SwallowCloseHandler) async throws {
        try? await channel.pipeline.removeHandler(swallowClose).get()
        try? await channel.close().get()
    }

    private func makeActiveChannel(on group: EventLoopGroup) async throws -> Channel {
        try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeSucceededVoidFuture()
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
    }
}

// MARK: - SwallowCloseHandler

/// Drops outbound `close` on the floor and leaves its promise unfulfilled, so the
/// channel's `closeFuture` never completes.
/// Stateless, so sharing it across the test's concurrency domains is safe.
final class SwallowCloseHandler: ChannelOutboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias OutboundIn = NIOAny

    func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        _ = context
        _ = mode
        _ = promise
    }
}

// MARK: - CountingOriginServer

/// A local origin server that records how many HTTP requests actually reached it, so a
/// test can prove the proxy never forwarded a paused-then-cancelled request.
private actor CountingOriginServer {
    // MARK: Internal

    static func start() async throws -> CountingOriginServer {
        let server = CountingOriginServer()
        try await server.start()
        return server
    }

    func url(_ path: String) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        guard let url = components.url else {
            preconditionFailure("Counting origin server produced an invalid URL.")
        }
        return url
    }

    func matchingRule(_ path: String) -> String {
        "\(host):\(port)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    func requestCount() -> Int {
        counter.value
    }

    func stop() async {
        let channel = serverChannel
        serverChannel = nil
        if let channel {
            try? await channel.close().get()
        }
        if let eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
        }
        eventLoopGroup = nil
        port = 0
    }

    // MARK: Private

    private let host = "127.0.0.1"
    private let counter = RequestCounter()
    private var port = 0
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    private func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group
        let counter = counter

        do {
            let channel = try await ServerBootstrap(group: group)
                .serverChannelOption(.backlog, value: 16)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(CountingOriginHandler(counter: counter))
                    }
                }
                .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .bind(host: host, port: 0)
                .get()

            guard let boundPort = channel.localAddress?.port else {
                try await channel.close().get()
                throw BreakpointHarnessError.socket("Unable to inspect counting origin port.")
            }
            serverChannel = channel
            port = boundPort
        } catch {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            throw error
        }
    }
}

// MARK: - RequestCounter

private final class RequestCounter: @unchecked Sendable {
    // MARK: Internal

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var count = 0
}

// MARK: - CountingOriginHandler

private final class CountingOriginHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(counter: RequestCounter) {
        self.counter = counter
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head:
            counter.increment()
        case .body:
            break
        case .end:
            respond(context: context)
        }
    }

    // MARK: Private

    private let counter: RequestCounter

    private func respond(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: 16)
        buffer.writeString(#"{"ok":true}"#)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
        headers.add(name: "Connection", value: "close")
        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}
