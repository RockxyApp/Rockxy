import Foundation
@testable import Rockxy
import Testing

struct FocusNavigatorStateTests {
    @Test("Errors include HTTP failures but exclude redirects and intentional blocks")
    func errorSignalMatching() {
        let clientError = TestFixtures.makeTransaction(statusCode: 404)
        let serverError = TestFixtures.makeTransaction(statusCode: 503)
        let redirect = TestFixtures.makeTransaction(statusCode: 302)
        let failed = TestFixtures.makeTransaction()
        failed.state = .failed
        let blocked = TestFixtures.makeTransaction()
        blocked.state = .blocked

        #expect(TrafficSignal.errors.matches(clientError))
        #expect(TrafficSignal.errors.matches(serverError))
        #expect(TrafficSignal.errors.matches(failed))
        #expect(!TrafficSignal.errors.matches(redirect))
        #expect(!TrafficSignal.errors.matches(blocked))
    }

    @Test("Slow uses measured duration with a one-second threshold")
    func slowSignalMatching() {
        let belowThreshold = TestFixtures.makeTransaction()
        belowThreshold.measuredDuration = 0.999
        let atThreshold = TestFixtures.makeTransaction()
        atThreshold.measuredDuration = 1
        let timed = TestFixtures.makeTransactionWithTiming(ttfb: 1.2)
        let unavailable = TestFixtures.makeTransaction()

        #expect(!TrafficSignal.slow.matches(belowThreshold))
        #expect(TrafficSignal.slow.matches(atThreshold))
        #expect(TrafficSignal.slow.matches(timed))
        #expect(!TrafficSignal.slow.matches(unavailable))
    }

    @Test("WebSocket recognizes schemes and valid HTTP upgrade handshakes")
    func webSocketSignalMatching() {
        let scheme = TestFixtures.makeTransaction(url: "wss://socket.example.com/events")
        let upgrade = TestFixtures.makeTransaction()
        upgrade.request.headers = [
            HTTPHeader(name: "Upgrade", value: "websocket"),
            HTTPHeader(name: "Connection", value: "keep-alive, Upgrade"),
        ]
        let incompleteUpgrade = TestFixtures.makeTransaction()
        incompleteUpgrade.request.headers = [HTTPHeader(name: "Upgrade", value: "websocket")]

        #expect(TrafficSignal.webSocket.matches(scheme))
        #expect(TrafficSignal.webSocket.matches(upgrade))
        #expect(!TrafficSignal.webSocket.matches(incompleteUpgrade))
    }

    @Test("GraphQL requires parsed operation metadata")
    func graphQLSignalMatching() {
        let graphQL = TestFixtures.makeTransaction(url: "https://api.example.com/graphql")
        graphQL.graphQLInfo = GraphQLInfo(
            operationName: "Checkout",
            operationType: .mutation,
            query: "mutation Checkout { checkout }",
            variables: nil
        )
        let pathOnly = TestFixtures.makeTransaction(url: "https://api.example.com/graphql")

        #expect(TrafficSignal.graphQL.matches(graphQL))
        #expect(!TrafficSignal.graphQL.matches(pathOnly))
    }

    @Test("Rules Hit supports current and legacy rule metadata")
    func rulesHitSignalMatching() {
        let current = TestFixtures.makeTransaction()
        current.matchedRuleID = UUID()
        let legacy = TestFixtures.makeTransaction()
        legacy.matchedRuleName = "Block telemetry"
        let untouched = TestFixtures.makeTransaction()

        #expect(TrafficSignal.rulesHit.matches(current))
        #expect(TrafficSignal.rulesHit.matches(legacy))
        #expect(!TrafficSignal.rulesHit.matches(untouched))
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
