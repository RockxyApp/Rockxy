import Foundation
@testable import Rockxy
import Testing

// MARK: - DeletedRowsStayDeletedTests

/// The visible list is rebuilt from the active Project's history whenever new traffic arrives,
/// so every way of removing rows must remove them from that history too.
@MainActor
struct DeletedRowsStayDeletedTests {
    @Test("A deleted row does not come back when new traffic arrives")
    func deletedRowStaysDeleted() {
        let coordinator = MainContentCoordinator()
        let kept = TestFixtures.makeTransaction(url: "https://api.example.com/kept")
        let deleted = TestFixtures.makeTransaction(url: "https://api.example.com/deleted")
        coordinator.processActiveProjectTestBatch([kept, deleted])

        coordinator.deleteTransactions([deleted])
        coordinator.processActiveProjectTestBatch([TestFixtures.makeTransaction(url: "https://api.example.com/next")])

        #expect(!coordinator.transactions.contains { $0.id == deleted.id })
        #expect(coordinator.transactions.contains { $0.id == kept.id })
    }

    @Test("Rows removed with their domain or app do not come back")
    func removedDomainAndAppStayRemoved() {
        let coordinator = MainContentCoordinator()
        let domainRow = TestFixtures.makeTransaction(url: "https://ads.example.com/banner")
        let appRow = TestFixtures.makeTransaction(url: "https://api.example.com/feed")
        appRow.clientApp = "Noisy App"
        coordinator.processActiveProjectTestBatch([domainRow, appRow])

        coordinator.removeDomainFromSidebar("ads.example.com")
        coordinator.removeAppFromSidebar("Noisy App")
        coordinator.processActiveProjectTestBatch([TestFixtures.makeTransaction(url: "https://api.example.com/next")])

        #expect(!coordinator.transactions.contains { $0.id == domainRow.id })
        #expect(!coordinator.transactions.contains { $0.id == appRow.id })
    }
}
