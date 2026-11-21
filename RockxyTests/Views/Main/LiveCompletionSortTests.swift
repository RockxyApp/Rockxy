import Foundation
@testable import Rockxy
import Testing

@MainActor
struct LiveCompletionSortTests {
    @Test(
        "Completing a live row reapplies state and response-backed sorting",
        arguments: ["state", "resHeader.X-Sort", "resBody.$.sort"]
    )
    func completesInSortedOrder(key: String) {
        let coordinator = MainContentCoordinator()
        let live = TestFixtures.makeTransaction(state: .active)
        let peer = TestFixtures.makeTransaction(state: .active)
        live.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "X-Sort", value: "a")],
            body: Data(#"{"sort":"a"}"#.utf8)
        )
        peer.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "X-Sort", value: "m")],
            body: Data(#"{"sort":"m"}"#.utf8)
        )
        let workspace = coordinator.workspaceStore.activeWorkspace
        var ascending = true
        if key == "state" {
            let failed = RequestListRow(from: TestFixtures.makeTransaction(state: .failed))
            ascending = !RequestListRow.compare(
                failed, RequestListRow(from: live), using: [NSSortDescriptor(key: key, ascending: true)]
            )
        }
        workspace.activeSortDescriptors = [
            NSSortDescriptor(key: key, ascending: ascending),
            NSSortDescriptor(key: "row", ascending: true),
        ]
        coordinator.processActiveProjectTestBatch([live, peer])
        #expect(coordinator.filteredRows.map(\.id) == [live.id, peer.id])
        live.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "X-Sort", value: "z")],
            body: Data(#"{"sort":"z"}"#.utf8)
        )
        live.state = .failed
        coordinator.enqueueLiveTransactionUpdates([live])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.filteredRows.map(\.id) == [peer.id, live.id])
        #expect(coordinator.transactions.count == 2)
    }

    @Test("WebSocket frame-count sorting follows the final captured frame count")
    func closedWebSocketIsResorted() {
        let coordinator = MainContentCoordinator()
        let live = TestFixtures.makeTransaction(state: .active)
        let peer = TestFixtures.makeTransaction(state: .active)
        func frame() -> WebSocketFrameData {
            WebSocketFrameData(direction: .received, opcode: .text, payload: Data("x".utf8), isFinal: true)
        }
        live.webSocketConnection = WebSocketConnection(upgradeRequest: live.request, frames: [frame()])
        peer.webSocketConnection = WebSocketConnection(upgradeRequest: peer.request, frames: [frame(), frame()])
        coordinator.workspaceStore.activeWorkspace.activeSortDescriptors = [
            NSSortDescriptor(key: "queryName", ascending: true),
        ]
        coordinator.processActiveProjectTestBatch([live, peer])
        #expect(coordinator.filteredRows.map(\.id) == [live.id, peer.id])
        live.webSocketConnection?.addFrame(frame())
        live.webSocketConnection?.addFrame(frame())
        live.state = .completed
        coordinator.enqueueLiveTransactionUpdates([live])
        coordinator.flushQueuedLiveTransactionUpdates()
        #expect(coordinator.filteredRows.map(\.id) == [peer.id, live.id])
    }
}
