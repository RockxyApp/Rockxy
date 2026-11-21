import Foundation
import os
@testable import Rockxy
import Testing

// Regression tests for the ownership of the session actor's 100 ms batch flush loop.
// Nothing stopped it before, so after the first Start it ran for the rest of the process;
// and the obvious fix -- stopping it when the proxy stops -- would stall Babylon SDK
// ingest, Repeat, and Compose, which all deliver through the same actor while the proxy
// is stopped.

struct BatchTimerProducerTests {
    /// Stopping one producer while another is registered must leave the loop running, or
    /// pressing Stop would silently end Babylon's delivery.
    @Test("A producer leaving while another remains keeps the loop running")
    func loopSurvivesWhileAnotherProducerRemains() async {
        let manager = TrafficSessionManager()
        await manager.startBatchTimer(for: .proxy)
        await manager.startBatchTimer(for: .babylon)
        var running = await manager.isBatchTimerRunning
        #expect(running)

        await manager.stopBatchTimer(for: .proxy)
        running = await manager.isBatchTimerRunning
        #expect(running)

        await manager.stopBatchTimer(for: .babylon)
        running = await manager.isBatchTimerRunning
        #expect(!running)
    }

    /// Unregistering a producer that was never registered must not end the loop the other
    /// one owns.
    @Test("Unregistering an absent producer leaves the loop alone")
    func unknownProducerDoesNotStopTheLoop() async {
        let manager = TrafficSessionManager()
        await manager.startBatchTimer(for: .babylon)
        await manager.stopBatchTimer(for: .proxy)
        let running = await manager.isBatchTimerRunning
        #expect(running)
        await manager.stopBatchTimer()
    }

    /// What is still buffered when the last producer leaves has to be delivered, or a row
    /// captured inside the last interval before Stop would never reach the list. The flush
    /// happens inside the stop call, so it has already run when the call returns.
    @Test("The last producer leaving flushes what is still buffered")
    func lastProducerFlushesBeforeTheLoopEnds() async {
        let manager = TrafficSessionManager()
        let recorder = BatchRecorder()
        await manager.setOnBatchReady { batch, _ in recorder.record(batch) }
        await manager.startBatchTimer(for: .proxy)

        let row = TestFixtures.makeTransaction(url: "https://api.example.com/just-before-stop")
        await manager.addTransaction(row)
        await manager.stopBatchTimer(for: .proxy)
        #expect(recorder.deliveredIDs == [row.id])
        let running = await manager.isBatchTimerRunning
        #expect(!running)
    }

    /// Repeat, Compose, and Babylon ingest deliver without declaring themselves as
    /// producers, and all of them work while the proxy is stopped. Their rows have to be
    /// flushed on the interval rather than waiting for 50 of them to pile up, so a
    /// delivery arms the loop -- and the loop retires itself once the buffer is empty
    /// again, which is what keeps it from being pinned for the rest of the process.
    @Test("A delivery with no registered producer is flushed, then the loop retires")
    func deliveryWithoutAProducerArmsAndThenRetiresTheLoop() async {
        let manager = TrafficSessionManager()
        let recorder = BatchRecorder()
        await manager.setOnBatchReady { batch, _ in recorder.record(batch) }
        var running = await manager.isBatchTimerRunning
        #expect(!running)

        let repeated = TestFixtures.makeTransaction(url: "https://api.example.com/repeat")
        await manager.addTransaction(repeated)
        running = await manager.isBatchTimerRunning
        #expect(running)
        #expect(await recorder.waitForCount(1))
        #expect(recorder.deliveredIDs == [repeated.id])

        var attempts = 0
        while await manager.isBatchTimerRunning, attempts < 80 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(50))
        }
        running = await manager.isBatchTimerRunning
        #expect(!running)
    }

    /// A registered producer keeps the loop even with an empty buffer, so a row arriving
    /// during capture never has to wait for a later delivery to wake the loop up.
    @Test("A registered producer keeps the loop running over an empty buffer")
    func registeredProducerKeepsTheLoopOverAnEmptyBuffer() async {
        let manager = TrafficSessionManager()
        await manager.startBatchTimer(for: .proxy)
        try? await Task.sleep(for: .milliseconds(400))
        let running = await manager.isBatchTimerRunning
        #expect(running)
        await manager.stopBatchTimer()
    }

    /// Registering is idempotent and must never replace a live handle. A registration that
    /// cancelled and restarted the loop would postpone the flush past its interval every
    /// time, so under a steady stream the interval would never elapse and nothing smaller
    /// than a full 50-row batch would ever be delivered.
    @Test("Re-announcing on every delivery does not postpone the flush")
    func reAnnouncingDoesNotPostponeTheFlush() async {
        let manager = TrafficSessionManager()
        let recorder = BatchRecorder()
        await manager.setOnBatchReady { batch, _ in recorder.record(batch) }
        await manager.startBatchTimer(for: .babylon)

        // Twenty rows, under the 50-row size trigger, re-announced faster than the 100 ms
        // interval: only the timer can deliver these.
        for index in 0 ..< 20 {
            await manager.startBatchTimer(for: .babylon)
            await manager.addTransaction(TestFixtures.makeTransaction(url: "https://babylon.example.com/\(index)"))
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(await recorder.waitForCount(1))
        await manager.stopBatchTimer()
    }
}

// MARK: - BatchRecorder

private final class BatchRecorder: @unchecked Sendable {
    // MARK: Internal

    var deliveredIDs: [UUID] {
        state.withLock { $0.ids }
    }

    func record(_ batch: [HTTPTransaction]) {
        let ids = batch.map(\.id)
        state.withLock {
            $0.ids.append(contentsOf: ids)
            $0.batches += 1
        }
    }

    func waitForCount(_ count: Int) async -> Bool {
        for _ in 0 ..< 100 {
            if state.withLock({ $0.ids.count }) >= count {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    // MARK: Private

    private let state = OSAllocatedUnfairLock(initialState: (ids: [UUID](), batches: 0))
}
