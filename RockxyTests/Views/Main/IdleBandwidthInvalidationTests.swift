import Foundation
import Observation
import os
@testable import Rockxy
import Testing

// Regression tests for the footer speeds invalidating their observers while nothing moves.

@MainActor
struct IdleBandwidthInvalidationTests {
    // MARK: Internal

    /// The decay timer calls this four times a second for as long as the proxy is up, and
    /// `@Observable` does not dedupe an equal assignment. Writing 0 over 0 therefore
    /// invalidated every observer of the footer speeds on an idle machine -- including the
    /// centre pane, which reads them in the same `body` that counts the available rows.
    @Test("A decay tick that changes nothing does not invalidate the speeds")
    func idleTickDoesNotInvalidate() {
        let coordinator = MainContentCoordinator()
        coordinator.recomputeInstantaneousSpeeds()
        #expect(coordinator.uploadSpeed == 0)
        #expect(coordinator.downloadSpeed == 0)

        let invalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = coordinator.uploadSpeed
            _ = coordinator.downloadSpeed
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        coordinator.recomputeInstantaneousSpeeds()
        let observed = invalidated.withLock { $0 }
        #expect(!observed)
    }

    /// The positive control for the test above: suppressing an equal write must not
    /// suppress a real one, or the footer would stop reporting throughput.
    @Test("A tick that changes a speed still invalidates it")
    func changedSpeedStillInvalidates() {
        let coordinator = MainContentCoordinator()
        let now = Date()

        let invalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = coordinator.downloadSpeed
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        coordinator.recordTrafficMetrics(for: [makeTransaction(responseSize: 2_048)], at: now)
        let observed = invalidated.withLock { $0 }
        #expect(observed)
        #expect(coordinator.downloadSpeed == 2_048)
    }

    /// The equal-write suppression sits in the one place both the decay path and the
    /// reset paths write through, so the window still has to decay to zero on its own.
    @Test("The sample window still decays to zero once its samples age out")
    func sampleWindowStillDecays() {
        let coordinator = MainContentCoordinator()
        let now = Date()
        coordinator.recordTrafficMetrics(for: [makeTransaction(responseSize: 512)], at: now)
        #expect(coordinator.downloadSpeed == 512)

        // Past the 1-second window, so the samples are dropped and the speeds fall to 0.
        coordinator.recomputeInstantaneousSpeeds(now: now.addingTimeInterval(2))
        #expect(coordinator.trafficSamples.isEmpty)
        #expect(coordinator.downloadSpeed == 0)
        #expect(coordinator.uploadSpeed == 0)
        // The cumulative total is not a rate and must survive the decay.
        #expect(coordinator.totalDataSize == 512)
    }

    // MARK: Private

    private func makeTransaction(responseSize: Int) -> HTTPTransaction {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/body")
        transaction.response = TestFixtures.makeResponse(
            statusCode: 200,
            body: Data(repeating: 0xBB, count: responseSize)
        )
        return transaction
    }
}
