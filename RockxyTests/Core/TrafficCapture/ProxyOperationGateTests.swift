import Foundation
@testable import Rockxy
import Testing

// Regression tests for the gate that keeps a termination cleanup out of the middle of an enable.

// MARK: - ProxyOperationGateTests

/// Deterministic rather than timing-based: the second thread is only released once the first is
/// provably inside its operation, so what these observe is the ordering itself.
struct ProxyOperationGateTests {
    @Test("A cleanup cannot start while an enable still has commands to write")
    func operationsDoNotInterleave() {
        let gate = ProxyOperationGate()
        let events = EventLog()
        let enableIsInside = DispatchSemaphore(value: 0)
        let cleanupHasBeenAsked = DispatchSemaphore(value: 0)
        let cleanupFinished = DispatchSemaphore(value: 0)

        let enable = Thread {
            gate.withOperation {
                events.append("enable:backup-published")
                enableIsInside.signal()
                // The cleanup thread is now asking for the gate. Every remaining proxy command of
                // this enable has to land before it gets in: restoring and clearing the backup
                // here would leave the user overridden with no restore point at all.
                cleanupHasBeenAsked.wait()
                events.append("enable:commands-written")
            }
        }
        let cleanup = Thread {
            cleanupHasBeenAsked.signal()
            gate.withOperation {
                events.append("cleanup:restored")
            }
            cleanupFinished.signal()
        }

        enable.start()
        enableIsInside.wait()
        cleanup.start()
        cleanupFinished.wait()

        #expect(events.entries == [
            "enable:backup-published",
            "enable:commands-written",
            "cleanup:restored",
        ])
    }

    @Test("An operation can roll back its own failure without waiting on itself")
    func nestedOperationsOnOneThreadDoNotDeadlock() {
        let gate = ProxyOperationGate()
        let events = EventLog()

        gate.withOperation {
            events.append("enable")
            // A failing enable legitimately contains the rollback of its own work. A plain lock
            // would deadlock here while doing nothing about the cross-thread case the gate exists
            // for.
            gate.withOperation {
                events.append("rollback")
            }
        }

        #expect(events.entries == ["enable", "rollback"])
    }

    @Test("A throwing operation releases the gate")
    func aThrownErrorDoesNotStrandTheGate() {
        let gate = ProxyOperationGate()

        #expect(throws: (any Error).self) {
            try gate.withOperation { throw TestFailure() }
        }

        // The next operation must not be blocked by the one that failed — the settings still need
        // putting back.
        #expect(gate.withOperation { true })
    }
}

// MARK: - ProxyAsyncOperationGateTests

struct ProxyAsyncOperationGateTests {
    @Test("Suspending lifecycle operations cannot overlap")
    func lifecycleOperationsDoNotInterleave() async {
        let gate = ProxyAsyncOperationGate()
        let events = AsyncEventLog()
        let firstEntered = AsyncLatch()
        let releaseFirst = AsyncLatch()
        let secondRequested = AsyncLatch()

        let first = Task {
            await gate.withOperation {
                await events.append("first:start")
                await firstEntered.signal()
                await releaseFirst.wait()
                await events.append("first:end")
            }
        }
        await firstEntered.wait()

        let second = Task {
            await secondRequested.signal()
            await gate.withOperation {
                await events.append("second:start")
            }
        }
        await secondRequested.wait()
        await releaseFirst.signal()

        await first.value
        await second.value
        #expect(await events.entries == ["first:start", "first:end", "second:start"])
    }

    @Test("A throwing async operation releases the lifecycle gate")
    func aThrownAsyncErrorDoesNotStrandTheGate() async {
        let gate = ProxyAsyncOperationGate()

        await #expect(throws: (any Error).self) {
            try await gate.withOperation { throw TestFailure() }
        }

        #expect(await gate.withOperation { true })
    }
}

// MARK: - ProxyOperationSessionPolicyTests

/// The gate orders operations but says nothing about which session they belong to. These cover the
/// second half of that: work queued while an override was live, let through only once the session
/// it belonged to is still the one running.
struct ProxyOperationSessionPolicyTests {
    @Test("Work queued for the running session runs")
    func theRunningSessionMayProceed() {
        #expect(ProxyOperationSessionPolicy.mayRun(
            queuedGeneration: 7,
            currentGeneration: 7,
            overrideIsActive: true
        ))
    }

    @Test("Work queued before a cleanup does not run after it")
    func workFromAnEndedSessionIsRefused() {
        // The cleanup restored every service and deleted the restore point. Letting this write
        // through now would put Rockxy's bypass list back on the user's machine with nothing left
        // on disk to undo it.
        #expect(!ProxyOperationSessionPolicy.mayRun(
            queuedGeneration: 7,
            currentGeneration: 8,
            overrideIsActive: false
        ))
        // And the same when a new session has already started: this write carries the old one's
        // list, for services the new one may not even cover.
        #expect(!ProxyOperationSessionPolicy.mayRun(
            queuedGeneration: 7,
            currentGeneration: 8,
            overrideIsActive: true
        ))
    }

    @Test("Work is refused while no override is in place, whatever the generation says")
    func workWithoutAnOverrideIsRefused() {
        #expect(!ProxyOperationSessionPolicy.mayRun(
            queuedGeneration: 7,
            currentGeneration: 7,
            overrideIsActive: false
        ))
    }
}

// MARK: - ProxyBypassWriteSerializationTests

/// The scenario the gate and the session check exist for together, driven deterministically: a
/// bypass write that is already queued when a termination cleanup arrives.
struct ProxyBypassWriteSerializationTests {
    @Test("A bypass write queued before a cleanup issues no command after it")
    func aQueuedBypassWriteIsDroppedAfterCleanup() {
        let session = ProxySessionState()
        let gate = ProxyOperationGate()
        let events = EventLog()
        let cleanupIsInside = DispatchSemaphore(value: 0)
        let bypassIsWaiting = DispatchSemaphore(value: 0)
        let bypassFinished = DispatchSemaphore(value: 0)

        // The write is queued while the override is still live, so it carries that session.
        let queuedGeneration = session.generation

        let cleanup = Thread {
            gate.withOperation {
                events.append("cleanup:entered")
                cleanupIsInside.signal()
                // The bypass write is now blocked on the gate. Everything this cleanup does —
                // ending the session, restoring the services, and clearing the restore point —
                // has to land before it gets in. Ending the session comes first so there is no
                // post-restore window where queued work can still regard the override as active.
                bypassIsWaiting.wait()
                session.end()
                events.append("cleanup:restored-and-cleared")
            }
        }
        let bypassWrite = Thread {
            bypassIsWaiting.signal()
            gate.withOperation {
                guard ProxyOperationSessionPolicy.mayRun(
                    queuedGeneration: queuedGeneration,
                    currentGeneration: session.generation,
                    overrideIsActive: session.overrideIsActive
                ) else {
                    events.append("bypass:skipped")
                    return
                }
                events.append("bypass:commands-written")
            }
            bypassFinished.signal()
        }

        cleanup.start()
        cleanupIsInside.wait()
        bypassWrite.start()
        bypassFinished.wait()

        #expect(events.entries == [
            "cleanup:entered",
            "cleanup:restored-and-cleared",
            "bypass:skipped",
        ])
    }

    @Test("A bypass write that reaches the gate first still runs, and the cleanup waits for it")
    func aBypassWriteThatWinsTheRaceIsNotDropped() {
        let session = ProxySessionState()
        let gate = ProxyOperationGate()
        let events = EventLog()
        let queuedGeneration = session.generation

        gate.withOperation {
            guard ProxyOperationSessionPolicy.mayRun(
                queuedGeneration: queuedGeneration,
                currentGeneration: session.generation,
                overrideIsActive: session.overrideIsActive
            ) else {
                events.append("bypass:skipped")
                return
            }
            events.append("bypass:commands-written")
        }
        gate.withOperation {
            session.end()
            events.append("cleanup:restored-and-cleared")
        }

        #expect(events.entries == ["bypass:commands-written", "cleanup:restored-and-cleared"])
    }

    @Test("A rollback reached from a confirmation failure serializes without deadlocking")
    func aRollbackTakesTheGateWithoutDeadlocking() {
        let gate = ProxyOperationGate()
        let events = EventLog()

        // The enable has already let go of the gate by the time confirmation fails, so the
        // rollback takes it for real rather than nesting — and it must still not block on itself
        // when an enable does contain its own rollback.
        gate.withOperation { events.append("enable") }
        gate.withOperation {
            events.append("rollback")
            gate.withOperation { events.append("rollback:nested-restore") }
        }

        #expect(events.entries == ["enable", "rollback", "rollback:nested-restore"])
    }
}

// MARK: - ProxySessionState

/// The manager's session bookkeeping, reduced to the two values the gate's callers read.
private final class ProxySessionState: @unchecked Sendable {
    // MARK: Internal

    var generation: UInt64 {
        lock.withLock { currentGeneration }
    }

    var overrideIsActive: Bool {
        lock.withLock { isActive }
    }

    func end() {
        lock.withLock {
            isActive = false
            currentGeneration &+= 1
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var currentGeneration: UInt64 = 1
    private var isActive = true
}

// MARK: - EventLog

/// Orders observations made from two threads.
private final class EventLog: @unchecked Sendable {
    // MARK: Internal

    var entries: [String] {
        lock.withLock { recorded }
    }

    func append(_ event: String) {
        lock.withLock { recorded.append(event) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var recorded: [String] = []
}

// MARK: - Async Test Support

private actor AsyncEventLog {
    private(set) var entries: [String] = []

    func append(_ event: String) {
        entries.append(event)
    }
}

private actor AsyncLatch {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignaled else {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

// MARK: - TestFailure

private struct TestFailure: Error {}
