import Foundation
@testable import Rockxy
import Testing

@MainActor
@Suite("Nearby iOS transfer import")
struct NearbyTransferImportTests {
    @Test("Import preserves current traffic and opens a dedicated workspace")
    func importPreservesCurrentTraffic() async throws {
        let coordinator = MainContentCoordinator()
        let existing = TestFixtures.makeTransaction(url: "https://mac.example.com/current")
        coordinator.transactions = [existing]
        coordinator.recomputeFilteredTransactions()
        let currentWorkspace = coordinator.activeWorkspace

        let session = RockxyNearbyTransferSession(
            version: "1",
            metadata: .init(
                title: "iPhone Debug Session",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                appVersion: "1.0",
                deviceName: "iPhone"
            ),
            transactions: [
                .init(
                    id: UUID().uuidString,
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    request: .init(
                        method: "GET",
                        url: "https://ios.example.com/debug",
                        headers: ["Authorization": "Masked before upload"],
                        body: nil,
                        statusCode: nil,
                        contentType: nil
                    ),
                    response: .init(
                        method: nil,
                        url: nil,
                        headers: ["Content-Type": "application/json"],
                        body: .init(size: 2, content: "{}"),
                        statusCode: 200,
                        contentType: "application/json"
                    ),
                    timing: nil,
                    clientApp: "Example iOS App"
                )
            ]
        )

        try await coordinator.importNearbyTransfer(session, deviceName: "Stephen's iPhone")

        #expect(coordinator.transactions.count == 2)
        #expect(coordinator.transactions.contains { $0.id == existing.id })
        #expect(currentWorkspace.filteredTransactions.map(\.id) == [existing.id])
        #expect(coordinator.workspaceStore.workspaces.count == 2)
        #expect(coordinator.activeWorkspace.title == "iPhone Debug Session")
        #expect(coordinator.activeWorkspace.filteredTransactions.count == 1)
        #expect(coordinator.activeWorkspace.filteredTransactions.first?.request.host == "ios.example.com")
    }
}
