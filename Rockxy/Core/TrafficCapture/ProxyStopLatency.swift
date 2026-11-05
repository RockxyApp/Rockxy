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
