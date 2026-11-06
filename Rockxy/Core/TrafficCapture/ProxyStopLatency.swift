import Foundation

// Primitives that keep a Stop from paying for system-proxy work serially or for work that has
// already been overtaken. Both are deliberately free of `networksetup` and of the manager, so
// the ordering and bounds they promise can be exercised with an injected command runner.

// MARK: - ProxyReadFanout

/// Runs independent, read-only `networksetup` queries concurrently, with a hard cap on how many
/// child processes are alive at once.
///
/// Only reads belong here. Two reads never change the answer to each other, and they take no
/// SystemConfiguration lock, so their order is irrelevant. Writes are NOT routed through this:
/// each `-set*` invocation is a read-modify-commit of the shared preferences set, two writes to
/// one service are order-dependent, and writes to different services are not shown to be safe
/// to interleave, so they stay on the caller's serial path.
///
/// Results come back in the order of `commands`, whatever order the children finished in, and a
/// failed command is reported as that slot's failure rather than ending the batch: the caller
/// decides what an unreadable service means.
enum ProxyReadFanout {
    // MARK: Internal

    static func run(
        _ commands: [[String]],
        maxConcurrent: Int,
        _ execute: @escaping @Sendable ([String]) throws -> String
    )
        -> [Result<String, any Error>]
    {
        guard !commands.isEmpty else {
            return []
        }
        guard commands.count > 1, maxConcurrent > 1 else {
            return commands.map { command in Result { try execute(command) } }
        }

        let slots = DispatchSemaphore(value: maxConcurrent)
        let group = DispatchGroup()
        let results = Slots(count: commands.count)
        for (index, command) in commands.enumerated() {
            // Waiting here, not inside the worker, is what caps live children: the next one is
            // not even spawned until a slot frees up.
            slots.wait()
            group.enter()
            // A dedicated thread rather than a pooled one: each worker blocks on a child and on
            // the pipe readers `networksetup` execution dispatches to the global pool, and
            // parking pool threads behind work that needs the pool is the starvation to avoid.
            let worker = Thread {
                results.store(Result { try execute(command) }, at: index)
                slots.signal()
                group.leave()
            }
            worker.qualityOfService = .userInitiated
            worker.start()
        }
        group.wait()
        return results.values
    }

    // MARK: Private

    private final class Slots: @unchecked Sendable {
        // MARK: Lifecycle

        init(count: Int) {
            storage = Array(
                repeating: .failure(ProxyReadFanoutError.neverRan),
                count: count
            )
        }

        // MARK: Internal

        var values: [Result<String, any Error>] {
            lock.withLock { storage }
        }

        func store(_ result: Result<String, any Error>, at index: Int) {
            lock.withLock { storage[index] = result }
        }

        // MARK: Private

        private let lock = NSLock()
        private var storage: [Result<String, any Error>]
    }
}

// MARK: - ProxyReadFanoutError

enum ProxyReadFanoutError: Error {
    /// A slot no worker filled in. Reported as a failed read, never as an empty success.
    case neverRan
}

// MARK: - ProxyEnableSupersession

/// Lets a Stop overtake an enable that is still running.
///
/// The lifecycle gate is first-in-first-out, so a Stop pressed during Start used to wait for the
/// whole enable (every service's baseline reads, seven writes each, the bypass list, and the
/// confirmation loop) and then spend its own restore undoing it. Each enable takes a mark when
/// it is *requested*, a Stop records itself when it is *requested*, and the enable checks the two
/// at the points where stopping is cheap and leaves the machine in a state the Stop (or the
/// enable's own rollback) can finish from.
///
/// A mark is taken at request time, not when the gate is acquired: an enable queued behind
/// another operation when a Stop arrives is just as stale as one already running, because the
/// Stop is ordered after it.
final class ProxyEnableSupersession: @unchecked Sendable {
    // MARK: Internal

    struct Mark: Equatable {
        fileprivate let stopRequests: UInt64
    }

    /// Called as a Stop (or a termination cleanup) is requested, before it waits for anything.
    func noteStopRequested() {
        lock.withLock { stopRequests &+= 1 }
    }

    func mark() -> Mark {
        lock.withLock { Mark(stopRequests: stopRequests) }
    }

    func isSuperseded(since mark: Mark) -> Bool {
        lock.withLock { stopRequests != mark.stopRequests }
    }

    // MARK: Private

    private let lock = NSLock()
    private var stopRequests: UInt64 = 0
}

// MARK: - ProxyPrimedRead

/// A read taken moments ago that may stand in for exactly one later read of the same subject.
///
/// A direct-mode restore plans against a read of every service, then the recovery loop reads the
/// first service again immediately before its first command. For the first service nothing has
/// been written in between (only the narrowed backup file, a local rename), so that second read
/// repeats the first and only adds a `networksetup` round trip before the first write. Standing
/// the planner's read in for it removes that round trip.
///
/// The narrow terms are the safety argument:
/// - **One subject, one use.** Only the named service is served, and only once. Every later
///   service, and the post-commit revalidation of this one, are live reads: those are the reads
///   that follow another service's writes or the record that licenses this one's.
/// - **Bounded age.** A primed value older than `maxAge` is refused, so a stalled backup write
///   between the two reads falls back to a live read instead of vouching for old state.
final class ProxyPrimedRead<Value>: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        subject: String,
        value: Value,
        maxAge: Duration = .seconds(1),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.subject = subject
        self.value = value
        self.maxAge = maxAge
        self.now = now
        capturedAt = now()
    }

    // MARK: Internal

    /// The value for `subject` if it is still unspent and young enough; `nil` otherwise. A call
    /// for the right subject spends the value whether or not it was young enough to serve.
    func take(for requested: String) -> Value? {
        lock.withLock { () -> Value? in
            guard requested == subject, !spent else {
                return nil
            }
            spent = true
            return capturedAt.duration(to: now()) <= maxAge ? value : nil
        }
    }

    // MARK: Private

    private let subject: String
    private let value: Value
    private let maxAge: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let capturedAt: ContinuousClock.Instant
    private let lock = NSLock()
    private var spent = false
}

// MARK: - ProxyPhaseTimer

/// Splits one operation into named phases so a measured Stop can be attributed to the part that
/// cost the time instead of to the operation as a whole. Durations only: no service names, no
/// settings, nothing captured.
struct ProxyPhaseTimer {
    // MARK: Lifecycle

    init(now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.now = now
        last = now()
    }

    // MARK: Internal

    /// Each phase's elapsed seconds, in the order they ended.
    private(set) var phases: [(name: String, seconds: TimeInterval)] = []

    /// "plan 120ms, publish 3ms": the phases in order.
    var summary: String {
        phases
            .map { "\($0.name) \(DurationFormatter.format(seconds: $0.seconds))" }
            .joined(separator: ", ")
    }

    /// Ends the phase that began at the previous mark (or at creation).
    mutating func mark(_ name: String) {
        let current = now()
        let elapsed = last.duration(to: current)
        phases.append((name, elapsed.proxyLatencySeconds))
        last = current
    }

    // MARK: Private

    private let now: () -> ContinuousClock.Instant
    private var last: ContinuousClock.Instant
}

extension Duration {
    /// Whole and fractional seconds, for the shared duration formatter.
    var proxyLatencySeconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
