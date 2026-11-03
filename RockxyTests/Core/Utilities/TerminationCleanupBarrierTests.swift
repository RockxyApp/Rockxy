import Foundation
@testable import Rockxy
import Testing

struct TerminationCleanupBarrierTests {
    @Test("work that finishes inside the budget is reported as finished")
    func reportsCompletion() {
        #expect(TerminationCleanupBarrier.wait(budget: 5) {})
    }

    @Test("the wait is bounded, and the work it gave up waiting for still runs to completion")
    func boundsTheWaitWithoutCancellingTheWork() {
        // Both halves matter. The bound is what stops Quit beachballing for minutes, and the
        // uncancelled completion is why the user's system proxy still gets restored: the barrier
        // is allowed to stop waiting, never to abandon the restore.
        let completed = DispatchSemaphore(value: 0)
        let started = Date()
        let finishedInBudget = TerminationCleanupBarrier.wait(budget: 0.2) {
            Thread.sleep(forTimeInterval: 1)
            completed.signal()
        }
        let waited = Date().timeIntervalSince(started)

        #expect(!finishedInBudget)
        #expect(waited < 1)
        #expect(completed.wait(timeout: .now() + 10) == .success)
    }

    @Test("the shipped budget is the documented ten seconds")
    func budgetIsPinned() {
        // Pinned deliberately: this number is a product decision about how long Quit may appear
        // to hang, not an implementation detail, so a silent change should fail here.
        #expect(TerminationCleanupBarrier.budget == 10)
    }
}
