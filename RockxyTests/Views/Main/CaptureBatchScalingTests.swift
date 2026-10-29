import Foundation
@testable import Rockxy
import Testing

@MainActor
struct CaptureBatchScalingTests {
    @Test("A Stop burst refreshes large-history snapshots once across adjacent actor batches")
    func coalescesMainActorStopBurst() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 60_000
        coordinator.processActiveProjectTestBatch((0 ..< 50_000).map { _ in TestFixtures.makeTransaction() })
        let live = (0 ..< 1_000).map { _ in TestFixtures.makeTransaction(state: .active) }
        coordinator.processActiveProjectTestBatch(live)
        let clock = ContinuousClock()
        live.forEach { $0.state = .failed }
        let baselineToken = coordinator.workspaceStore.activeWorkspace.refreshToken
        let baselineStart = clock.now
        for start in stride(from: 0, to: live.count, by: 50) {
            coordinator.handleLiveTransactionUpdate(Array(live[start ..< start + 50]))
        }
        let baselineDuration = baselineStart.duration(to: clock.now)
        #expect(coordinator.workspaceStore.activeWorkspace.refreshToken == baselineToken + 20)
        live.forEach { $0.state = .completed }
        let coalescedToken = coordinator.workspaceStore.activeWorkspace.refreshToken
        let coalescedStart = clock.now
        for start in stride(from: 0, to: live.count, by: 50) {
            coordinator.enqueueLiveTransactionUpdates(Array(live[start ..< start + 50]))
        }
        #expect(coordinator.filteredRows.suffix(1_000).allSatisfy { $0.state == .failed })
        coordinator.flushQueuedLiveTransactionUpdates()
        let coalescedDuration = coalescedStart.duration(to: clock.now)
        #expect(coordinator.workspaceStore.activeWorkspace.refreshToken == coalescedToken + 1)
        #expect(coordinator.filteredRows.suffix(1_000).allSatisfy { $0.state == .completed })
        #expect(coordinator.transactions.count == 51_000)
        #expect(coordinator.pendingLiveRowUpdates.isEmpty)
        #expect(coordinator.liveRowRefreshTask == nil)
        print("CAPTURE_STOP_BURST batches=20 rows=1000 direct=\(baselineDuration) coalesced=\(coalescedDuration)")
    }

    @Test("Queued live refreshes recheck ownership after a capture context changes")
    func queuedRefreshRejectsStaleContext() {
        let coordinator = MainContentCoordinator()
        let row = TestFixtures.makeTransaction(state: .active)
        coordinator.processActiveProjectTestBatch([row])
        row.state = .failed
        coordinator.enqueueLiveTransactionUpdates([row])
        let project = coordinator.projectStore.activeProjectID
        coordinator.captureGenerationByProjectID[project, default: 0] &+= 1
        coordinator.refreshCaptureContextSnapshot()
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.filteredRows.first?.state == .active)
        #expect(coordinator.pendingLiveRowUpdates.isEmpty)
    }

    @Test("A large history accepts and completes live batches without duplicate rows or lost failures")
    func largeHistoryLiveBatch() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 60_000
        let history = (0 ..< 50_000).map { _ in TestFixtures.makeTransaction() }
        coordinator.processActiveProjectTestBatch(history)
        #expect(coordinator.transactions.count == 50_000)
        let live = (0 ..< 1_000).map { _ in
            let request = TestFixtures.makeRequest(url: "ws://fixture.invalid/events")
            return HTTPTransaction(
                request: request, state: .active,
                webSocketConnection: WebSocketConnection(upgradeRequest: request)
            )
        }
        let clock = ContinuousClock()
        let start = clock.now
        coordinator.processActiveProjectTestBatch(live)
        let appendDuration = start.duration(to: clock.now)
        #expect(coordinator.transactions.count == 51_000)
        live.forEach { $0.state = .failed }
        let closeStart = clock.now
        coordinator.processActiveProjectTestBatch(live)
        let closeDuration = closeStart.duration(to: clock.now)
        #expect(coordinator.transactions.count == 51_000)
        #expect(coordinator.filteredRows.count == 51_000)
        #expect(coordinator.filteredRows.suffix(1_000).allSatisfy { $0.state == .failed })
        #expect(Set(coordinator.transactions.map(\.id)).count == 51_000)
        print("CAPTURE_SCALING history=50000 live=1000 append=\(appendDuration) completion=\(closeDuration)")
    }
}
