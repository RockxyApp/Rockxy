import Foundation
import NIOCore
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - ProxyHookTaskSlotTests

/// Tests for the seam that replaced `EventLoop.makeFutureWithTask` in the proxy handlers
/// (issue #416: work that kept running after the user pressed Stop).
///
/// Two properties are load-bearing and neither can be proved end to end: the handlers resolve
/// a rule evaluation in microseconds, so a loopback test cannot reliably disconnect a client
/// *while* a hook is in flight, and this layer has no way to inject a slow hook into a real
/// `RuleEngine` or `ScriptPluginManager`. They are asserted here, at the seam that decides
/// them, while `MapLocalLoopbackIntegrationTests` holds the end-to-end proof that a normal
/// request and a Block rule still behave through the rewritten path.
@Suite(.serialized)
struct ProxyHookTaskSlotTests {
    @Test("A hook outcome reaches the handler while the exchange is live")
    func deliversOutcomeWhileLive() async {
        let loop = HookTestEventLoop()
        defer { loop.shutdown() }
        let slot = ProxyHookTaskSlot()
        let delivered = HookValueBox<String>()

        slot.run(
            on: loop.next,
            hook: { "evaluated" },
            isLive: { true },
            onOutcome: { delivered.value = $0 }
        )

        #expect(await delivered.waitForValue() == "evaluated")
    }

    /// The defect this guards: a hook that resolved after its client had gone still ran its
    /// continuation, and the forward paths it reaches acquire a `ConnectionLimiter` slot and
    /// open a real origin connection for a client that is no longer there.
    @Test("A hook that resolves after the exchange ended delivers nothing")
    func dropsOutcomeOnceExchangeEnded() async {
        let loop = HookTestEventLoop()
        defer { loop.shutdown() }
        let slot = ProxyHookTaskSlot()
        let delivered = HookValueBox<String>()
        let hookRan = HookValueBox<Bool>()

        slot.run(
            on: loop.next,
            hook: {
                hookRan.value = true
                return "evaluated"
            },
            isLive: { false },
            onOutcome: { delivered.value = $0 }
        )

        // The hook itself still completes -- it is only the continuation that is suppressed,
        // which is why cancelling is not what stops the work and the gate is.
        #expect(await hookRan.waitForValue() == true)
        // Long enough for the promise to have hopped back to the event loop and run the gate.
        try await Task.sleep(for: .milliseconds(200))
        #expect(delivered.value == nil)
    }

    /// `makeFutureWithTask` discarded the Task, so before this slot there was no cancellation
    /// path at all. A hook that does observe cancellation now sees it.
    @Test("cancel() propagates into the retained hook Task")
    func cancelReachesTheHook() async {
        let loop = HookTestEventLoop()
        defer { loop.shutdown() }
        let slot = ProxyHookTaskSlot()
        let started = HookValueBox<Bool>()
        let delivered = HookValueBox<String>()

        slot.run(
            on: loop.next,
            hook: {
                started.value = true
                do {
                    try await Task.sleep(for: .seconds(30))
                    return "ran-to-completion"
                } catch {
                    return "cancelled"
                }
            },
            isLive: { true },
            onOutcome: { delivered.value = $0 }
        )

        #expect(await started.waitForValue() == true)
        slot.cancel()

        #expect(await delivered.waitForValue() == "cancelled")
    }

    /// `admitTunnel` composes its value into a NIO chain the SOCKS handler is blocked on for
    /// the reply byte it owes its client, so that variant is never gated.
    @Test("The future-shaped variant always delivers its value")
    func futureVariantAlwaysDelivers() async throws {
        let loop = HookTestEventLoop()
        defer { loop.shutdown() }
        let slot = ProxyHookTaskSlot()

        let admission = try await slot.run(on: loop.next) { HTTPProxyHandler.TunnelAdmission.blocked }.get()

        #expect(admission == .blocked)
    }

    /// One slot serves both phases of a request. They are sequential in the handlers, but a
    /// handle left behind by a previous phase must not outlive it.
    @Test("Starting a second hook cancels the handle the first one left behind")
    func reusingTheSlotCancelsTheStaleHook() async {
        let loop = HookTestEventLoop()
        defer { loop.shutdown() }
        let slot = ProxyHookTaskSlot()
        let firstStarted = HookValueBox<Bool>()
        let firstOutcome = HookValueBox<String>()
        let secondOutcome = HookValueBox<String>()

        slot.run(
            on: loop.next,
            hook: {
                firstStarted.value = true
                do {
                    try await Task.sleep(for: .seconds(30))
                    return "first-ran-to-completion"
                } catch {
                    return "first-cancelled"
                }
            },
            isLive: { true },
            onOutcome: { firstOutcome.value = $0 }
        )
        #expect(await firstStarted.waitForValue() == true)

        slot.run(
            on: loop.next,
            hook: { "second" },
            isLive: { true },
            onOutcome: { secondOutcome.value = $0 }
        )

        #expect(await secondOutcome.waitForValue() == "second")
        #expect(await firstOutcome.waitForValue() == "first-cancelled")
    }
}

// MARK: - HookTestEventLoop

/// One-thread event loop group with explicit teardown, so a test never leaves NIO threads
/// behind for the rest of the suite.
private final class HookTestEventLoop: @unchecked Sendable {
    // MARK: Internal

    var next: EventLoop {
        group.next()
    }

    /// Callback form, not `syncShutdownGracefully()`: these tests run as async functions on
    /// the cooperative pool, and a blocking wait there is what starved the pool in an earlier
    /// full-suite hang. Nothing afterwards depends on the thread being gone.
    func shutdown() {
        group.shutdownGracefully { _ in }
    }

    // MARK: Private

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}

// MARK: - HookValueBox

/// Lock-guarded one-shot box. The hook bodies and the event loop both write to it from
/// outside the test's own isolation, and `waitForValue` polls rather than using a
/// continuation so a value that never arrives fails the expectation instead of hanging the
/// suite.
private final class HookValueBox<Value: Sendable>: @unchecked Sendable {
    // MARK: Internal

    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    /// Polls for up to ~2 s. Generous because the hook bodies run as unstructured Tasks on the
    /// shared cooperative pool, and short because a missing value is a real failure.
    func waitForValue() async -> Value? {
        for _ in 0 ..< 200 {
            if let current = value {
                return current
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return value
    }

    // MARK: Private

    private let lock = NSLock()
    private var stored: Value?
}
