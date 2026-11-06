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

    @Test("the total wait is one shared deadline and names every step it gave up on")
    func sharedDeadlineAcrossStuckSteps() {
        // Three stuck steps must cost one budget, not three, and the quick step must not be
        // reported. The budget here is tiny so the test never sleeps for the real one.
        let release = DispatchSemaphore(value: 0)
        let started = Date()
        let unfinished = TerminationCleanupBarrier.wait(budget: 0.15, steps: [
            .init(name: "stuck-a") { release.wait() },
            .init(name: "quick") {},
            .init(name: "stuck-b") { release.wait() },
            .init(name: "stuck-c") { release.wait() },
        ])
        let waited = Date().timeIntervalSince(started)

        #expect(Set(unfinished) == ["stuck-a", "stuck-b", "stuck-c"])
        #expect(waited < 1)
        for _ in 0 ..< 3 {
            release.signal()
        }
    }

    @Test("every step finishing inside the budget reports nothing unfinished")
    func allStepsFinish() {
        #expect(TerminationCleanupBarrier.wait(budget: 5, steps: [
            .init(name: "a") {},
            .init(name: "b") {},
        ]).isEmpty)
    }

    @Test("the shipped budget is three seconds and well under the old ten")
    func budgetIsPinned() {
        // Pinned deliberately: this number is a product decision about how long Quit may appear
        // to hang, not an implementation detail, so a silent change should fail here.
        #expect(TerminationCleanupBarrier.budget == 3)
    }
}
