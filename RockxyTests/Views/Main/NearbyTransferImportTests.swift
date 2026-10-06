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

    @Test("Import keeps every transferred transaction past the live-history cap")
    func importIsNotTrimmedByLiveHistoryCap() async throws {
        let coordinator = MainContentCoordinator(policy: SingleEntryHistoryPolicy())
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let transferred = (0 ..< 3).map { index in
            RockxyNearbyTransferSession.Transaction(
                id: UUID().uuidString,
                timestamp: timestamp,
                request: .init(
                    method: "GET",
                    url: "https://ios.example.com/\(index)",
                    headers: [:],
                    body: nil,
                    statusCode: nil,
                    contentType: nil
                ),
                response: nil,
                timing: nil,
                clientApp: "Example iOS App"
            )
        }
        let session = RockxyNearbyTransferSession(
            version: "1",
            metadata: .init(
                title: "Bounded Import",
                createdAt: timestamp,
                appVersion: "1.0",
                deviceName: "iPhone"
            ),
            transactions: transferred
        )

        try await coordinator.importNearbyTransfer(session, deviceName: "iPhone")

        let retainedIDs = Set(coordinator.transactions.map(\.id))
        #expect(coordinator.transactions.count == 3)
        #expect(coordinator.activeWorkspace.filteredTransactions.count == 3)
        #expect(coordinator.activeWorkspace.filteredTransactions.allSatisfy { retainedIDs.contains($0.id) })
    }
}

private struct SingleEntryHistoryPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1
}
