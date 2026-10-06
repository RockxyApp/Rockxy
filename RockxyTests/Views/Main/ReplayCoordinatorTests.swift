import Foundation
@testable import Rockxy
import Testing

// Non-visual tests for `MainContentCoordinator+Replay`: a fast replay becomes its own
// captured row in the active Project and is selected when its batch lands.

@MainActor
@Suite("Replay coordinator")
struct ReplayCoordinatorTests {
    @Test("Replayed row copies the request, carries the new response, and is attributed to Rockxy")
    func replayedTransactionShape() {
        let source = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.openai.com/v1/chat/completions"
        )
        source.request.body = Data(#"{"model":"gpt-4o","stream":true,"messages":[]}"#.utf8)
        source.clientApp = "openai-python"
        let response = TestFixtures.makeResponse(
            statusCode: 200,
            headers: [HTTPHeader(name: "Content-Type", value: "text/event-stream")],
            body: Data("data: {}\n\n".utf8)
        )
        let context = TrafficCaptureContext(projectID: UUID(), sessionID: UUID(), generation: 3)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let replayed = MainContentCoordinator.makeReplayTransaction(
            from: source,
            response: response,
            startedAt: startedAt,
            state: .completed,
            now: startedAt.addingTimeInterval(1.25)
        )
        replayed.assignCaptureContextIfMissing(context)

        #expect(replayed.id != source.id)
        #expect(replayed.timestamp == startedAt)
        #expect(replayed.request.method == "POST")
        #expect(replayed.request.url == source.request.url)
        #expect(replayed.request.body == source.request.body)
        #expect(replayed.captureContext == context)
        #expect(replayed.response?.statusCode == 200)
        #expect(replayed.response?.body == response.body)
        #expect(replayed.state == .completed)
        #expect(replayed.measuredDuration == 1.25)
        #expect(replayed.displayDuration == 1.25)
        #expect(replayed.clientApp == RockxyIdentity.current.displayName)
        #expect(replayed.sslCapture == .intercepted)
    }

    @Test("Replay row is selected when its batch reaches the active list")
    func replayRowSelectedOnArrival() {
        let coordinator = MainContentCoordinator()
        let original = TestFixtures.makeTransaction(url: "https://api.example.com/original")
        original.assignCaptureContextIfMissing(coordinator.activeCaptureContext)
        coordinator.processBatch([original], generation: coordinator.sessionGeneration)
        coordinator.selectedTransactionIDs = [original.id]
        coordinator.selectTransaction(original)

        let replayed = MainContentCoordinator.makeReplayTransaction(
            from: original,
            response: TestFixtures.makeResponse(statusCode: 503),
            startedAt: Date(),
            state: .completed
        )
        replayed.assignCaptureContextIfMissing(coordinator.activeCaptureContext)
        coordinator.pendingReplaySelectionIDs.insert(replayed.id)
        coordinator.processBatch([replayed], generation: coordinator.sessionGeneration)

        #expect(coordinator.transactions.map(\.id) == [original.id, replayed.id])
        #expect(coordinator.selectedTransaction?.id == replayed.id)
        #expect(coordinator.selectedTransactionIDs == [replayed.id])
        #expect(coordinator.pendingReplaySelectionIDs.isEmpty)
    }

    @Test("Replay row hidden by the current filter is not force-selected")
    func hiddenReplayRowKeepsSelection() {
        let coordinator = MainContentCoordinator()
        let original = TestFixtures.makeTransaction(url: "https://api.example.com/original")
        original.assignCaptureContextIfMissing(coordinator.activeCaptureContext)
        coordinator.processBatch([original], generation: coordinator.sessionGeneration)
        coordinator.selectedTransactionIDs = [original.id]
        coordinator.selectTransaction(original)
        coordinator.filterCriteria.searchField = .statusCode
        coordinator.filterCriteria.searchText = "200"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [original.id])

        let replayed = MainContentCoordinator.makeReplayTransaction(
            from: original,
            response: TestFixtures.makeResponse(statusCode: 503),
            startedAt: Date(),
            state: .completed
        )
        replayed.assignCaptureContextIfMissing(coordinator.activeCaptureContext)
        coordinator.pendingReplaySelectionIDs.insert(replayed.id)
        coordinator.processBatch([replayed], generation: coordinator.sessionGeneration)

        #expect(coordinator.selectedTransaction?.id == original.id)
        #expect(coordinator.pendingReplaySelectionIDs.isEmpty)
    }

    @Test("Repeating several rows reports one summary with inflected counts")
    func batchReplaySummary() {
        let clean = MainContentCoordinator.batchReplayToast(sent: 3, failed: 0, skipped: 0)
        #expect(clean.text == "Repeated 3 requests")
        #expect(clean.style == .success)

        let mixed = MainContentCoordinator.batchReplayToast(sent: 2, failed: 1, skipped: 1)
        #expect(mixed.text == "Repeated 2 requests — 1 request failed — 1 request can't be repeated")
        #expect(mixed.style == .warning)
    }

    @Test("Too many selected rows are refused before anything is sent")
    func batchReplayCap() {
        let coordinator = MainContentCoordinator()
        let rows = (0 ... MainContentCoordinator.maximumBatchReplayCount).map {
            TestFixtures.makeTransaction(url: "https://api.example.com/\($0)")
        }
        coordinator.performReplay(for: rows)
        #expect(coordinator.activeToast?.style == .warning)
        #expect(coordinator.activeToast?.text.contains("\(MainContentCoordinator.maximumBatchReplayCount)") == true)
    }
}
