import Foundation
@testable import Rockxy
import Testing

// MARK: - SelectionSessionExportTests

@MainActor
struct SelectionSessionExportTests {
    @Test("Rockxy Session format exports every transaction and saves a reopenable file")
    func sessionFormatProperties() {
        let format = TrafficExportFormat.rockxySession
        #expect(!format.isOpenAPI)
        #expect(format.isEligible(TestFixtures.makeWebSocketTransaction()))
        #expect(format.defaultFileName == "rockxy-export.rockxysession")
        #expect(format.privacyNote.contains("bodies"))
        #expect(TrafficExportFormat.allCases.first == .rockxySession)
    }

    @Test("Session export data round-trips only the chosen rows with their capture span")
    func sessionExportRoundTrips() throws {
        let early = HTTPTransaction(
            timestamp: Date(timeIntervalSince1970: 1_000),
            request: TestFixtures.makeRequest(url: "https://api.example.com/early"),
            state: .completed
        )
        let late = HTTPTransaction(
            timestamp: Date(timeIntervalSince1970: 2_000),
            request: TestFixtures.makeRequest(url: "https://api.example.com/late"),
            state: .completed
        )
        late.comment = "keep me"

        let data = try MainContentCoordinator.sessionExportData([late, early])
        let session = try SessionSerializer.deserialize(from: data)

        #expect(session.transactions.count == 2)
        #expect(session.metadata.transactionCount == 2)
        #expect(session.metadata.captureStartDate == early.timestamp)
        #expect(session.metadata.captureEndDate == late.timestamp)
        let restored = session.transactions.map { $0.toLiveModel() }
        #expect(restored.map(\.request.url.path) == ["/late", "/early"])
        #expect(restored.first?.comment == "keep me")
    }

    @Test("Right-click export covers the whole selection when the clicked row is selected")
    func contextExportUsesSelection() {
        let coordinator = MainContentCoordinator()
        let first = TestFixtures.makeTransaction(url: "https://alpha.example.com/1")
        let second = TestFixtures.makeTransaction(url: "https://beta.example.com/2")
        let third = TestFixtures.makeTransaction(url: "https://gamma.example.com/3")
        coordinator.transactions = [first, second, third]
        coordinator.recomputeFilteredTransactions()
        coordinator.selectTransactions([first.id, third.id], primaryID: third.id)

        #expect(coordinator.contextExportTransactions(clicked: third).map(\.id) == [first.id, third.id])
        #expect(coordinator.contextExportTransactions(clicked: second).map(\.id) == [second.id])
    }

    @Test("Sidebar domain and app exports collect only matching rows")
    func sidebarExportMembership() {
        let coordinator = MainContentCoordinator()
        let api = TestFixtures.makeTransaction(url: "https://api.example.com/v1/users")
        api.clientApp = "Safari"
        let apiOther = TestFixtures.makeTransaction(url: "https://api.example.com/v2/items")
        apiOther.clientApp = "curl"
        let cdn = TestFixtures.makeTransaction(url: "https://cdn.example.org/logo.png")
        cdn.clientApp = "Safari"
        coordinator.transactions = [api, apiOther, cdn]

        #expect(coordinator.sidebarDomainExportTransactions("api.example.com", pathPrefix: nil).count == 2)
        #expect(
            coordinator.sidebarDomainExportTransactions("api.example.com", pathPrefix: "/v1").map(\.id) == [api.id]
        )
        #expect(coordinator.sidebarAppExportTransactions("Safari").map(\.id) == [api.id, cdn.id])
    }
}
