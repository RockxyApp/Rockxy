import Foundation
@testable import Rockxy
import Testing

struct FocusNavigatorStateTests {
    @Test("Traffic signals classify status, timing, and rule effects")
    func trafficSignalMatching() {
        let error = TestFixtures.makeTransaction(statusCode: 503)
        let slow = TestFixtures.makeTransactionWithTiming(ttfb: 1.2)
        let ruled = TestFixtures.makeTransaction()
        ruled.matchedRuleID = UUID()

        #expect(TrafficSignal.errors.matches(error))
        #expect(!TrafficSignal.errors.matches(slow))
        #expect(TrafficSignal.slow.matches(slow))
        #expect(TrafficSignal.rulesHit.matches(ruled))
    }

    @Test("Toggling a traffic signal filters and then restores traffic")
    @MainActor
    func trafficSignalFiltering() {
        let coordinator = MainContentCoordinator()
        let success = TestFixtures.makeTransaction(statusCode: 200)
        let error = TestFixtures.makeTransaction(statusCode: 500)
        coordinator.transactions = [success, error]
        coordinator.recomputeFilteredTransactions()

        coordinator.toggleTrafficSignal(.errors)
        #expect(coordinator.filteredTransactions.map(\.id) == [error.id])
        #expect(coordinator.activeWorkspace.activeTrafficSignal == .errors)

        coordinator.toggleTrafficSignal(.errors)
        #expect(coordinator.filteredTransactions.map(\.id) == [success.id, error.id])
        #expect(coordinator.activeWorkspace.activeTrafficSignal == nil)
    }

    @Test("Focus Sets round-trip through durable encoding")
    func focusSetCoding() throws {
        let original = FocusSet(
            name: "Checkout",
            appName: "Safari",
            domain: "example.com",
            pathPrefix: "/v1",
            excludedPathPrefix: "/v1/health"
        )

        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([FocusSet].self, from: data)

        #expect(decoded == [original])
    }

    @Test("Focus Set applies inclusions before exclusions")
    func focusSetMatching() {
        let included = TestFixtures.makeTransaction(url: "https://api.example.com/v1/orders")
        included.clientApp = "Safari"
        let excluded = TestFixtures.makeTransaction(url: "https://api.example.com/health")
        excluded.clientApp = "Safari"
        let otherApp = TestFixtures.makeTransaction(url: "https://api.example.com/v1/orders")
        otherApp.clientApp = "Chrome"
        let focus = FocusSet(
            name: "Checkout",
            appName: "Safari",
            domain: "example.com",
            pathPrefix: "/",
            excludedPathPrefix: "/health"
        )

        #expect(focus.matches(included))
        #expect(!focus.matches(excluded))
        #expect(!focus.matches(otherApp))
        #expect(focus.ruleCount == 4)
    }

    @Test("Muted traffic source matches only its scope")
    func mutedSourceMatching() {
        let transaction = TestFixtures.makeTransaction(url: "https://telemetry.example.com/events")

        #expect(MutedTrafficSource.host("telemetry.example.com").matches(transaction))
        #expect(MutedTrafficSource.pathPrefix("/events").matches(transaction))
        #expect(!MutedTrafficSource.host("api.example.com").matches(transaction))
    }

    @Test("Applying focus preserves visible selection and clears hidden selection")
    @MainActor
    func selectionReconciliation() {
        let coordinator = MainContentCoordinator()
        let visible = TestFixtures.makeTransaction(url: "https://api.example.com/v1/orders")
        let hidden = TestFixtures.makeTransaction(url: "https://noise.example.net/events")
        coordinator.transactions = [visible, hidden]
        coordinator.recomputeFilteredTransactions()
        coordinator.selectedTransactionIDs = [visible.id]
        coordinator.selectTransaction(visible)

        let focus = FocusSet(name: "API", domain: "example.com")
        coordinator.saveFocusSet(focus)
        #expect(coordinator.selectedTransaction?.id == visible.id)

        coordinator.selectedTransactionIDs = [hidden.id]
        coordinator.selectTransaction(hidden)
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.selectedTransaction == nil)
        #expect(coordinator.selectedTransactionIDs.isEmpty)
    }
}
