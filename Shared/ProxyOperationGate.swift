import Foundation

// MARK: - ProxyOperationGate

/// Serializes the app's whole proxy operations against each other.
///
/// Enabling a direct override, disabling it, and the cleanup a termination signal runs are all
/// multi-command sequences over the same services and the same backup file. They arrive on
/// different threads — a signal handler, the main thread at termination, a capture task — so
/// without a gate the cleanup can read the backup, restore every service, and clear the file
/// while the enable loop still has proxy commands left to write. The user is then left with an
/// override and no restore point at all.
///
/// The gate is deliberately **blocking** and **reentrant**. Blocking, because refusing a
/// termination cleanup would leave the override in place with nothing else coming to undo it —
/// waiting for the enable to finish is the point. Reentrant, because an operation legitimately
/// contains the rollback of its own failure, and a plain lock would deadlock on that nesting
/// while doing nothing about the cross-thread case this exists for.
final class ProxyOperationGate: @unchecked Sendable {
    // MARK: Internal

    /// Runs `body` with no other proxy operation in progress. Nested calls on the same thread run
    /// straight through, so a failing enable can roll itself back without waiting on itself.
    func withOperation<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: Private

    private let lock = NSRecursiveLock()
}

// MARK: - ProxyAsyncOperationGate

/// Serializes complete asynchronous proxy lifecycle operations.
///
/// Helper-backed enable and restore calls suspend while XPC work is in flight. A blocking lock
/// cannot safely span those suspension points, but releasing the lock early lets an older disable
/// continuation clear the state and observer belonging to a newer enable. This gate keeps the
/// complete asynchronous operation ordered while allowing the executing task to suspend.
final class ProxyAsyncOperationGate: @unchecked Sendable {
    // MARK: Internal

    func withOperation<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    // MARK: Private

    private let lock = NSLock()
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isHeld {
                waiters.append(continuation)
                lock.unlock()
            } else {
                isHeld = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    private func release() {
        lock.lock()
        let next = waiters.isEmpty ? nil : waiters.removeFirst()
        if next == nil {
            isHeld = false
        }
        lock.unlock()
        next?.resume()
    }
}

// MARK: - ProxyOperationSessionPolicy

/// Decides whether proxy work queued for one override session may still run once it reaches the
/// gate.
///
/// The gate serializes operations but says nothing about which session they belong to. A bypass
/// write queued while an override was live waits behind a disable or a termination cleanup, and
/// the cleanup restores every service and clears the backup — so by the time the write is let
/// through, the settings it is about to change are the user's again and nothing on disk could undo
/// it. The generation is bumped by whatever ends a session, and it is read inside the gate, so
/// work queued before that point cannot start after it.
enum ProxyOperationSessionPolicy {
    static func mayRun(
        queuedGeneration: UInt64,
        currentGeneration: UInt64,
        overrideIsActive: Bool
    )
        -> Bool
    {
        overrideIsActive && queuedGeneration == currentGeneration
    }
}
