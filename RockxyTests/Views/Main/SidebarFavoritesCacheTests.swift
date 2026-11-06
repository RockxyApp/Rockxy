import Foundation
@testable import Rockxy
import Testing

// Regression tests for the Library navigator's favourites cache across capture and removal.

@MainActor
struct SidebarFavoritesCacheTests {
    /// The cache key carried `transactions.count`, so every captured request was a
    /// guaranteed miss and the six scans behind the pinned, saved, and noted lists ran
    /// again -- for an append that cannot change which rows the user marked.
    @Test("An append does not invalidate the favourites cache")
    func appendKeepsTheCache() {
        let coordinator = MainContentCoordinator()
        let pinned = TestFixtures.makeTransaction(url: "https://api.example.com/keep", statusCode: 200)
        coordinator.processActiveProjectTestBatch([pinned])
        coordinator.togglePin(for: pinned)
        #expect(coordinator.allPinnedTransactions.map(\.id) == [pinned.id])

        let revision = coordinator.sidebarFavoritesRevision
        coordinator.processActiveProjectTestBatch(
            (0 ..< 5).map {
                TestFixtures.makeTransaction(url: "https://api.example.com/new/\($0)", statusCode: 200)
            }
        )

        #expect(coordinator.sidebarFavoritesRevision == revision)
        #expect(coordinator.allPinnedTransactions.map(\.id) == [pinned.id])
    }

    @Test("Pinning a row invalidates the favourites cache")
    func pinningInvalidatesTheCache() {
        let coordinator = MainContentCoordinator()
        let first = TestFixtures.makeTransaction(url: "https://api.example.com/one", statusCode: 200)
        let second = TestFixtures.makeTransaction(url: "https://api.example.com/two", statusCode: 200)
        coordinator.processActiveProjectTestBatch([first, second])
        coordinator.togglePin(for: first)
        let revision = coordinator.sidebarFavoritesRevision

        coordinator.togglePin(for: second)

        #expect(coordinator.sidebarFavoritesRevision != revision)
        #expect(Set(coordinator.allPinnedTransactions.map(\.id)) == Set([first.id, second.id]))
    }

    /// The point of the revision key: an append no longer invalidates, so a removal has to.
    /// A cached list that outlived its rows would still name a row the history has dropped,
    /// which is a correctness bug rather than a stale-looking one -- the Library navigator
    /// would offer a row nothing can resolve any more.
    @Test("Evicting a pinned row drops it from the cached favourites")
    func evictionDropsEvictedFavorites() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 4
        let pinned = TestFixtures.makeTransaction(url: "https://api.example.com/old", statusCode: 200)
        coordinator.processActiveProjectTestBatch([pinned])
        coordinator.togglePin(for: pinned)
        #expect(coordinator.allPinnedTransactions.map(\.id) == [pinned.id])

        coordinator.processActiveProjectTestBatch(
            (0 ..< 4).map {
                TestFixtures.makeTransaction(url: "https://api.example.com/new/\($0)", statusCode: 200)
            }
        )

        #expect(!coordinator.transactions.contains { $0.id == pinned.id })
        #expect(!coordinator.allPinnedTransactions.contains { $0.id == pinned.id })
    }

    /// Clear Session empties the history without touching the favourites revision; it is
    /// the session generation in the key that retires the cached lists there.
    @Test("Clearing the session drops the cached favourites")
    func clearingDropsTheCachedFavorites() async {
        let coordinator = MainContentCoordinator()
        let pinned = TestFixtures.makeTransaction(url: "https://api.example.com/keep", statusCode: 200)
        coordinator.processActiveProjectTestBatch([pinned])
        coordinator.togglePin(for: pinned)
        #expect(coordinator.allPinnedTransactions.map(\.id) == [pinned.id])

        await coordinator.clearSession()

        #expect(!coordinator.allPinnedTransactions.contains { $0.id == pinned.id })
    }
}
