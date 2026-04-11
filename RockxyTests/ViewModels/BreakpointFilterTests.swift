import Foundation
@testable import Rockxy
import Testing

// Tests filtering behavior in `BreakpointRulesViewModel`.

@MainActor
struct BreakpointFilterTests {
    // MARK: - Name Filtering

    @Test("Filter by name matches partial text")
    func filterByNameMatchesPartialText() {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "api.example.com",
            urlPattern: "https://api.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.filterColumn = .name
        vm.filterText = "api"

        #expect(vm.filteredBreakpointRules.count == 1)
        #expect(vm.filteredBreakpointRules.first?.name == "api.example.com")
    }

    @Test("Filter by name is case insensitive")
    func filterByNameIsCaseInsensitive() {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "api.example.com",
            urlPattern: "https://api.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.filterColumn = .name
        vm.filterText = "API"

        #expect(vm.filteredBreakpointRules.count == 1)
        #expect(vm.filteredBreakpointRules.first?.name == "api.example.com")
    }

    // MARK: - Matching Rule Filtering

    @Test("Filter by matching rule matches URL pattern")
    func filterByMatchingRuleMatchesPattern() {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Example API",
            urlPattern: "https://example.com/api",
            httpMethod: .any,
            matchType: .regex,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )
        vm.filterColumn = .matchingRule
        vm.filterText = "example"

        #expect(vm.filteredBreakpointRules.count == 1)
    }

    // MARK: - Method Filtering

    @Test("Filter by method matches exact method")
    func filterByMethodMatchesExactMethod() {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "POST endpoint",
            urlPattern: "https://api.test.com/submit",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )
        vm.filterColumn = .method
        vm.filterText = "POST"

        #expect(vm.filteredBreakpointRules.count == 1)
    }

    @Test("Filter by method matches ANY for nil method")
    func filterByMethodMatchesANYForNilMethod() {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Any method rule",
            urlPattern: "https://api.test.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        vm.filterColumn = .method
        vm.filterText = "ANY"

        #expect(vm.filteredBreakpointRules.count == 1)
    }

    // MARK: - Empty and No-Match Filtering

    @Test("Empty filter returns all rules")
    func emptyFilterReturnsAllRules() {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Rule A",
            urlPattern: "https://a.com/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Rule B",
            urlPattern: "https://b.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: false,
            phaseResponse: true,
            includeSubpaths: true
        )
        vm.filterText = ""

        #expect(vm.filteredBreakpointRules.count == 2)
    }

    @Test("Filter with no match returns empty")
    func filterWithNoMatchReturnsEmpty() {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Real Rule",
            urlPattern: "https://real.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.filterColumn = .name
        vm.filterText = "nonexistent"

        #expect(vm.filteredBreakpointRules.isEmpty)
    }

    // MARK: - Defaults

    @Test("Filter column defaults to name")
    func filterColumnDefaultsToName() {
        let vm = BreakpointRulesViewModel()

        #expect(vm.filterColumn == .name)
    }

    // MARK: - Reactivity

    @Test("Filter updates reactively when filterText changes")
    func filterUpdatesReactively() {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "alpha.example.com",
            urlPattern: "https://alpha.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "beta.other.com",
            urlPattern: "https://beta.other.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        vm.filterColumn = .name
        vm.filterText = "alpha"
        #expect(vm.filteredBreakpointRules.count == 1)

        vm.filterText = ""
        #expect(vm.filteredBreakpointRules.count == 2)
    }
}
