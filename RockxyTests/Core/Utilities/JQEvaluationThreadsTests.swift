import Foundation
@testable import Rockxy
import Testing

// A traffic table showing a jq custom column used to create a thread, and reserve a fresh 64 MB
// stack, for every newly visible row, and then block the thread doing the drawing on it. These
// tests hold the two properties that replaced that: evaluations reuse a parked thread, and a
// filter already running never delays another one -- a shared worker with a queue would be
// cheaper still, and would fill the table's visible rows one slow step at a time.

// MARK: - JQEvaluationThreadsTests

struct JQEvaluationThreadsTests {
    // MARK: Internal

    @Test("Sequential evaluations reuse a parked thread instead of starting one each time")
    func sequentialEvaluationsReuseAParkedThread() {
        let threads = ObservedThreads()
        for _ in 0 ..< Self.sequentialEvaluations {
            let finished = DispatchSemaphore(value: 0)
            JQEvaluationThreads.shared.run {
                threads.record(Thread.current)
                finished.signal()
            }
            // Each unit of work completes before the next is submitted, so a worker that parks
            // for reuse is the one that takes the next one.
            finished.wait()
        }

        #expect(threads.count < Self.sequentialEvaluations, "every sequential evaluation started a new thread")
    }

    @Test("An evaluation already running never delays another one")
    func busyWorkerDoesNotDelayAnotherEvaluation() async throws {
        let occupied = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        JQEvaluationThreads.shared.run {
            occupied.signal()
            release.wait()
        }
        // Returns only once a worker is genuinely stuck inside the pool.
        occupied.wait()
        defer { release.signal() }

        // Work is never queued behind that worker, so this resolves while it is still held.
        let filter = try JQFilter(".id")
        let output = try await filter.run(json: Data(#"{"id":7}"#.utf8))

        #expect(output.values.count == 1)
        #expect(output.isTruncated == false)
    }

    // MARK: Private

    /// Records which threads the pool handed work to. Locked because the identities are written
    /// from the workers and read back here.
    private final class ObservedThreads: @unchecked Sendable {
        // MARK: Internal

        var count: Int {
            lock.withLock { identities.count }
        }

        func record(_ thread: Thread) {
            lock.withLock { identities.insert(ObjectIdentifier(thread)) }
        }

        // MARK: Private

        private let lock = NSLock()
        private var identities: Set<ObjectIdentifier> = []
    }

    private static let sequentialEvaluations = 8
}
