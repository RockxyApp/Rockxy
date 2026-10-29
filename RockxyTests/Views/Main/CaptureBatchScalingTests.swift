import Foundation
@testable import Rockxy
import Testing

@MainActor
struct CaptureBatchScalingTests {
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
