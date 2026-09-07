import Foundation

/// Limits concurrent upstream connections per destination to prevent file descriptor exhaustion.
///
/// Each normalized (host, port) pair gets at most `maxPerDestination` concurrent connections.
/// The default accommodates parallel browser and IDE startup bursts while retaining a hard bound
/// against one destination consuming an unbounded number of file descriptors. Callers must
/// `acquire` before opening a connection and `release` when the connection closes.
///
/// Thread-safe via `NSLock` for use from NIO event loops.
final class ConnectionLimiter: @unchecked Sendable {
    // MARK: Lifecycle

    init(maxPerDestination: Int = 64) {
        precondition(maxPerDestination > 0)
        self.maxPerDestination = maxPerDestination
    }

    // MARK: Internal

    /// Attempts to reserve a connection slot. Returns `true` if allowed, `false` if at capacity.
    func acquire(host: String, port: Int) -> Bool {
        let dest = destination(host: host, port: port)
        lock.lock()
        defer { lock.unlock() }
        let current = counts[dest, default: 0]
        guard current < maxPerDestination else {
            return false
        }
        counts[dest] = current + 1
        return true
    }

    /// Releases a connection slot when the upstream channel closes.
    func release(host: String, port: Int) {
        let dest = destination(host: host, port: port)
        lock.lock()
        defer { lock.unlock() }
        let current = counts[dest, default: 0]
        if current <= 1 {
            counts.removeValue(forKey: dest)
        } else {
            counts[dest] = current - 1
        }
    }

    // MARK: Private

    private struct Destination: Hashable {
        let host: String
        let port: Int
    }

    private let maxPerDestination: Int
    private var counts: [Destination: Int] = [:]
    private let lock = NSLock()

    private func destination(host: String, port: Int) -> Destination {
        var normalizedHost = host.lowercased()
        if normalizedHost.hasSuffix(".") {
            normalizedHost.removeLast()
        }
        return Destination(host: normalizedHost, port: port)
    }
}
