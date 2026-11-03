import NIOCore

// Defines `ProxyHookTaskSlot`, the retained-and-gated bridge the proxy handlers use to run
// one async hook per exchange.

// MARK: - ProxyHookTaskSlot

/// Event-loop-confined slot holding the one async hook an exchange has in flight: rule
/// evaluation, a script request or response hook, or identity-gated rule matching.
///
/// Replaces `EventLoop.makeFutureWithTask` at those call sites, for two reasons found while
/// tracing issue #416 ("after capturing for hours the app lags, and pressing Stop can hang"):
///
/// 1. `makeFutureWithTask` discards the `Task` it creates, so none of those hooks had a
///    cancellation path of any kind. This slot keeps the handle the way `pendingBreakpointTask`
///    already does for the breakpoint bridge, so a dead exchange can at least stop asking for
///    more work. Keeping the handle is *not* on its own enough to drain a backlog: the awaited
///    work (`RuleEngine`, `ScriptPluginManager`, `ScriptRuntime`) checks `Task.isCancelled`
///    nowhere, and a task suspended on an actor hop is not cancellable in Swift, so a queued
///    hook still runs and still retains its `HTTPRequestData` until it does. Making that
///    cancellation effective needs a check inside those actors, which is not in this layer.
/// 2. Nothing gated the completion on the exchange still being alive, and that is what
///    actually cost work after Stop. A hook that resolved after its client had gone — exactly
///    what a backlog does when the user stops capture — still ran its continuation, and the
///    forward paths it reaches (`forwardRequest`, `connectToUpstream`) acquire a
///    `ConnectionLimiter` slot and open a real TCP/TLS connection to the origin for a client
///    that is no longer there. `isLive` below is what stops that.
///
/// A dropped outcome is never a changed outcome: the gate only ever fires once the exchange is
/// over, so a rule evaluation can never be downgraded to "no rule matched" — and a Block rule
/// never turned into a pass-through — on a connection that could still observe it.
///
/// Confined to one event loop. Every method must be called from the channel's own loop, which
/// is the only place the handler state these outcomes mutate is safe. Marked
/// `@unchecked Sendable` on the same grounds as the handlers that own it.
final class ProxyHookTaskSlot: @unchecked Sendable {
    // MARK: Internal

    /// Runs `hook` as a retained `Task` and delivers its value to `onOutcome` on `eventLoop`,
    /// but only while `isLive` still holds.
    ///
    /// One slot per handler is deliberate: the hooks of an exchange are sequential phases
    /// (rules, then the request script hook), so a handler never has two in flight, and a
    /// per-request slot would be one more thing to clear.
    func run<Value: Sendable>(
        on eventLoop: EventLoop,
        hook: @escaping @Sendable () async -> Value,
        isLive: @escaping @Sendable () -> Bool,
        onOutcome: @escaping @Sendable (Value) -> Void
    ) {
        run(on: eventLoop, hook: hook).whenComplete { [weak self] result in
            self?.task = nil
            // A hook body cannot throw, so a failure here is only a cancelled promise; either
            // way there is no outcome to act on.
            guard let value = try? result.get(), isLive() else {
                return
            }
            onOutcome(value)
        }
    }

    /// Future-shaped variant for the call sites that compose the hook's value into a NIO chain
    /// instead of resuming handler state from it (`admitTunnel`). Those chains owe their caller
    /// an answer — a SOCKS client is waiting on a reply byte — so they get the retained handle
    /// without the liveness gate; dropping the value there would strand the SOCKS handshake
    /// rather than save work.
    @discardableResult
    func run<Value: Sendable>(
        on eventLoop: EventLoop,
        hook: @escaping @Sendable () async -> Value
    )
        -> EventLoopFuture<Value>
    {
        let promise = eventLoop.makePromise(of: Value.self)
        // Sequential by construction, but a stale handle here would outlive its exchange.
        task?.cancel()
        task = promise.completeWithTask(hook)
        return promise.futureResult
    }

    /// Cancels whatever hook is in flight.
    ///
    /// Callers must only reach this once the exchange is genuinely over. A cancelled hook has
    /// no trustworthy outcome, so cancelling a live one is how a Block rule would quietly
    /// become a pass-through.
    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: Private

    private var task: Task<Void, Never>?
}
