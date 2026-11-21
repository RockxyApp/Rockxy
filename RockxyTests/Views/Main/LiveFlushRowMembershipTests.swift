import Foundation
@testable import Rockxy
import Testing

// Regression tests for the gate that lets a live flush rewrite rows in place instead of
// re-filtering the whole retained capture.

@MainActor
struct LiveFlushRowMembershipTests {
    /// The gate exists so that a flush carrying rows whose visibility did not change costs
    /// the batch rather than the capture. A row that was visible and still matches must be
    /// provable, or the fast path never runs and the fix is inert.
    @Test("A visible row that still matches is proved in place")
    func visibleRowThatStillMatchesIsProvable() {
        let coordinator = MainContentCoordinator()
        let failure = TestFixtures.makeTransaction(url: "https://api.example.com/bad", statusCode: 500)
        coordinator.processActiveProjectTestBatch([failure])
        coordinator.activeWorkspace.activeTrafficSignal = .errors
        coordinator.recomputeFilteredTransactions()
        try? #require(coordinator.activeWorkspace.trafficSelectionIndex[failure.id] != nil)

        failure.measuredDuration = 2
        #expect(coordinator.liveUpdatesPreserveRowMembership([failure], in: coordinator.activeWorkspace))
    }

    /// The case the gate must never wave through: the user is filtered to failures and a
    /// pending row's response arrives as a 500, so the row has to appear. Rewriting in
    /// place would leave it off screen.
    @Test("A row that crosses into the filter is not proved in place")
    func rowEnteringTheFilterIsNotProvable() {
        let coordinator = MainContentCoordinator()
        let pending = TestFixtures.makeTransaction(
            url: "https://api.example.com/retry",
            statusCode: 200,
            state: .active
        )
        coordinator.processActiveProjectTestBatch([pending])
        coordinator.activeWorkspace.activeTrafficSignal = .errors
        coordinator.recomputeFilteredTransactions()
        try? #require(coordinator.activeWorkspace.trafficSelectionIndex[pending.id] == nil)

        pending.response = TestFixtures.makeResponse(statusCode: 500)
        pending.state = .failed
        #expect(!coordinator.liveUpdatesPreserveRowMembership([pending], in: coordinator.activeWorkspace))
    }

    /// And the reverse: a row that was on screen and no longer matches has to leave it.
    @Test("A row that drops out of the filter is not proved in place")
    func rowLeavingTheFilterIsNotProvable() {
        let coordinator = MainContentCoordinator()
        let recovering = TestFixtures.makeTransaction(
            url: "https://api.example.com/retry",
            statusCode: 503,
            state: .active
        )
        coordinator.processActiveProjectTestBatch([recovering])
        coordinator.activeWorkspace.activeTrafficSignal = .errors
        coordinator.recomputeFilteredTransactions()
        try? #require(coordinator.activeWorkspace.trafficSelectionIndex[recovering.id] != nil)

        recovering.response = TestFixtures.makeResponse(statusCode: 200)
        recovering.state = .completed
        #expect(!coordinator.liveUpdatesPreserveRowMembership([recovering], in: coordinator.activeWorkspace))
    }

    /// A sort on a column a live update can change needs the row set reordered, not
    /// rewritten, however the visibility works out.
    @Test("A sort that a live update can reorder is never proved in place")
    func stateDependentSortIsNeverProvable() {
        let coordinator = MainContentCoordinator()
        let row = TestFixtures.makeTransaction(url: "https://api.example.com/bad", statusCode: 500)
        coordinator.processActiveProjectTestBatch([row])
        coordinator.activeWorkspace.activeTrafficSignal = .errors
        coordinator.activeWorkspace.activeSortDescriptors = [
            NSSortDescriptor(key: "duration", ascending: true)
        ]
        coordinator.recomputeFilteredTransactions()

        #expect(!coordinator.liveUpdatesPreserveRowMembership([row], in: coordinator.activeWorkspace))
    }

    /// The pinned, saved and notes scopes draw from their own base lists, and absence from
    /// one of those is invisible to the filter predicate -- so a visible row there cannot be
    /// proved and must fall back to the authoritative recompute.
    @Test("A visible row outside the all-traffic scope is not proved in place")
    func nonAllTrafficScopeIsNotProvable() {
        let coordinator = MainContentCoordinator()
        let pinned = TestFixtures.makeTransaction(url: "https://api.example.com/pinned", statusCode: 200)
        coordinator.processActiveProjectTestBatch([pinned])
        coordinator.recomputeFilteredTransactions()
        try? #require(coordinator.activeWorkspace.trafficSelectionIndex[pinned.id] != nil)

        coordinator.activeWorkspace.filterCriteria.sidebarScope = .pinned
        #expect(!coordinator.liveUpdatesPreserveRowMembership([pinned], in: coordinator.activeWorkspace))
    }
}
