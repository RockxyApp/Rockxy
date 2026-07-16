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

    @Test("Focus Set editor suggestions are trimmed, unique, and sorted")
    func focusSetEditorSuggestions() {
        let first = TestFixtures.makeTransaction(url: "https://beta.example.com/v1/orders")
        first.clientApp = "Safari"
        let duplicate = TestFixtures.makeTransaction(url: "https://api.example.com/v1/orders")
        duplicate.clientApp = " Chrome "
        let second = TestFixtures.makeTransaction(url: "https://api.example.com/health")
        second.clientApp = "Chrome"
        let emptyApp = TestFixtures.makeTransaction(url: "https://api.example.com/health")
        emptyApp.clientApp = "  "

        let suggestions = FocusSetEditorSuggestions(
            transactions: [first, duplicate, second, emptyApp]
        )

        #expect(suggestions.applications.map(\.value) == ["Chrome", "Safari"])
        #expect(suggestions.applications.map(\.requestCount) == [2, 1])
        #expect(suggestions.domains.map(\.value) == ["api.example.com", "beta.example.com"])
        #expect(suggestions.domains.map(\.requestCount) == [3, 1])
        #expect(suggestions.paths.map(\.value) == ["/health", "/v1/orders"])
        #expect(suggestions.paths.map(\.requestCount) == [2, 2])
    }

    @Test("Captured picker limits its initial list but searches the complete catalog")
    func capturedPickerDisplayPolicy() {
        let suggestions = (0 ..< 500).map {
            CapturedValueSuggestion(value: "domain-\($0).example", requestCount: 500 - $0)
        }

        let initial = CapturedValueDisplayPolicy.displayed(suggestions, searchText: "")
        let searched = CapturedValueDisplayPolicy.displayed(suggestions, searchText: "domain-499")

        #expect(initial.count == 50)
        #expect(initial.first?.value == "domain-0.example")
        #expect(searched.map(\.value) == ["domain-499.example"])
    }

    @Test("Application icon resolver loads native macOS app icons")
    @MainActor
    func applicationIconResolution() {
        #expect(AppIconProvider.applicationIcon(named: "Safari", size: 20) != nil)
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

    @Test("Focus Set exposes include and exclude rules for sidebar presentation")
    func focusSetRuleDescriptors() {
        let focus = FocusSet(
            name: "Checkout",
            appName: "Safari",
            domain: "api.example.com",
            pathPrefix: "/v1/orders",
            excludedDomain: "telemetry.example.com",
            excludedPathPrefix: "/health"
        )

        #expect(focus.includedRules == [
            FocusSetRuleDescriptor(scope: .include, kind: .application, pattern: "Safari"),
            FocusSetRuleDescriptor(scope: .include, kind: .domain, pattern: "api.example.com"),
            FocusSetRuleDescriptor(scope: .include, kind: .pathPrefix, pattern: "/v1/orders"),
        ])
        #expect(focus.excludedRules == [
            FocusSetRuleDescriptor(scope: .exclude, kind: .domain, pattern: "telemetry.example.com"),
            FocusSetRuleDescriptor(scope: .exclude, kind: .pathPrefix, pattern: "/health"),
        ])
        #expect(focus.ruleCount == focus.includedRules.count + focus.excludedRules.count)
    }

    @Test("Muted traffic source matches only its scope")
    func mutedSourceMatching() {
        let transaction = TestFixtures.makeTransaction(url: "https://telemetry.example.com/events")

        #expect(MutedTrafficSource.host("telemetry.example.com").matches(transaction))
        #expect(MutedTrafficSource.pathPrefix("/events").matches(transaction))
        #expect(!MutedTrafficSource.host("api.example.com").matches(transaction))
    }

    @Test("Muted sources hide matching traffic without deleting captured requests")
    @MainActor
    func mutedSourceVisibility() {
        let coordinator = MainContentCoordinator()
        let telemetry = TestFixtures.makeTransaction(url: "https://telemetry.example.com/events")
        let api = TestFixtures.makeTransaction(url: "https://api.example.com/orders")
        coordinator.transactions = [telemetry, api]
        coordinator.recomputeFilteredTransactions()

        coordinator.muteTrafficSource(.host("telemetry.example.com"))

        #expect(coordinator.transactions.count == 2)
        #expect(coordinator.filteredTransactions.map(\.id) == [api.id])
        #expect(coordinator.mutedTransactionCount(for: .host("telemetry.example.com")) == 1)

        coordinator.unmuteAllTrafficSources()
        #expect(coordinator.filteredTransactions.map(\.id) == [telemetry.id, api.id])
    }

    @Test("Focus exclusions are local while muted sources remain workspace-wide")
    @MainActor
    func focusExcludeAndNoiseControlScopes() {
        let coordinator = MainContentCoordinator()
        let api = TestFixtures.makeTransaction(url: "https://api.example.com/orders")
        let health = TestFixtures.makeTransaction(url: "https://api.example.com/health")
        let telemetry = TestFixtures.makeTransaction(url: "https://telemetry.example.com/events")
        coordinator.transactions = [api, health, telemetry]
        coordinator.recomputeFilteredTransactions()

        coordinator.saveFocusSet(FocusSet(
            name: "Example API",
            domain: "example.com",
            excludedPathPrefix: "/health"
        ))
        #expect(coordinator.filteredTransactions.map(\.id) == [api.id, telemetry.id])

        coordinator.muteTrafficSource(.host("telemetry.example.com"))
        #expect(coordinator.filteredTransactions.map(\.id) == [api.id])

        coordinator.applyFocusSet(nil)
        #expect(coordinator.filteredTransactions.map(\.id) == [api.id, health.id])
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
