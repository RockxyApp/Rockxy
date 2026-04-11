import Foundation
@testable import Rockxy
import Testing

@MainActor
struct BreakpointRulesViewModelTests {
    @Test("addBreakpointRule with wildcard creates correct pattern with .* conversions")
    func addBreakpointRuleWithWildcard() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Break API",
            urlPattern: "*api.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        #expect(vm.breakpointRules.count == 1)
        let rule = vm.breakpointRules.first
        #expect(rule?.name == "Break API")
        #expect(rule?.matchCondition.urlPattern?.contains(".*") == true)
    }

    @Test("addBreakpointRule with regex passes pattern through unchanged")
    func addBreakpointRuleWithRegex() {
        let vm = BreakpointRulesViewModel()
        let rawRegex = "^https://api\\.example\\.com/v2/.*$"

        vm.addBreakpointRule(
            ruleName: "Regex Break",
            urlPattern: rawRegex,
            httpMethod: .get,
            matchType: .regex,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )

        #expect(vm.breakpointRules.count == 1)
        let rule = vm.breakpointRules.first
        #expect(rule?.name == "Regex Break")
        #expect(rule?.matchCondition.urlPattern == rawRegex)
    }

    @Test("addBreakpointRule with empty name falls back to URL pattern")
    func addBreakpointRuleWithEmptyName() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "",
            urlPattern: "*.example.com/api/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        #expect(vm.breakpointRules.first?.name == "*.example.com/api/*")
    }

    @Test("addBreakpointRule with specific HTTP method sets method on condition")
    func addBreakpointRuleWithSpecificMethod() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "POST Break",
            urlPattern: "*.example.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        #expect(vm.breakpointRules.first?.matchCondition.method == "POST")
    }

    @Test("addBreakpointRule with ANY method leaves method nil")
    func addBreakpointRuleWithAnyMethod() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Any Method",
            urlPattern: "*.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        #expect(vm.breakpointRules.first?.matchCondition.method == nil)
    }

    @Test("addBreakpointRule with request-only phase creates .request action")
    func addBreakpointRuleRequestOnlyPhase() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Request Only",
            urlPattern: "*.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        if case let .breakpoint(phase) = vm.breakpointRules.first?.action {
            #expect(phase == .request)
        } else {
            Issue.record("Expected breakpoint action")
        }
    }

    @Test("addBreakpointRule with response-only phase creates .response action")
    func addBreakpointRuleResponseOnlyPhase() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Response Only",
            urlPattern: "*.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: false,
            phaseResponse: true,
            includeSubpaths: true
        )

        if case let .breakpoint(phase) = vm.breakpointRules.first?.action {
            #expect(phase == .response)
        } else {
            Issue.record("Expected breakpoint action")
        }
    }

    @Test("addBreakpointRule with both phases creates .both action")
    func addBreakpointRuleBothPhases() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Both Phases",
            urlPattern: "*.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        if case let .breakpoint(phase) = vm.breakpointRules.first?.action {
            #expect(phase == .both)
        } else {
            Issue.record("Expected breakpoint action")
        }
    }

    @Test("Wildcard includeSubpaths appends .* suffix to pattern")
    func addBreakpointRuleIncludeSubpaths() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "With Subpaths",
            urlPattern: "https://example.com",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let pattern = vm.breakpointRules.first?.matchCondition.urlPattern ?? ""
        #expect(pattern.hasSuffix(".*"))
    }

    @Test("Wildcard without includeSubpaths anchors with end-of-path assertion")
    func addBreakpointRuleWithoutSubpaths() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "No Subpaths",
            urlPattern: "https://example.com",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: false
        )

        let pattern = vm.breakpointRules.first?.matchCondition.urlPattern ?? ""
        #expect(!pattern.hasSuffix(".*"))
        #expect(pattern.hasSuffix("($|[?#])"))
    }

    @Test("Wildcard escapes special regex characters in URL pattern")
    func wildcardEscapesSpecialChars() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Escape Test",
            urlPattern: "https://example.com/path?q=1",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: false
        )

        let pattern = vm.breakpointRules.first?.matchCondition.urlPattern ?? ""
        #expect(!pattern.contains("?q"))
        #expect(pattern.contains(".q"))
    }

    @Test("Wildcard converts * to .* and ? to .")
    func wildcardConvertsStarAndQuestion() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Wildcard Convert",
            urlPattern: "*.example.com/?page",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: false
        )

        let pattern = vm.breakpointRules.first?.matchCondition.urlPattern ?? ""
        #expect(pattern.contains(".*"))
        #expect(pattern.contains(".page"))
    }

    @Test("breakpointRules filters only breakpoint-type rules")
    func breakpointRulesFiltersOnlyBreakpointType() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Breakpoint Rule",
            urlPattern: "*.test.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        #expect(vm.breakpointRules.count == 1)
        if case .breakpoint = vm.breakpointRules.first?.action {
            // correct
        } else {
            Issue.record("Expected breakpoint action type")
        }
    }

    @Test("removeSelected removes the correct rule and clears selection")
    func removeSelectedRemovesCorrectRule() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Rule A",
            urlPattern: "*.a.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Rule B",
            urlPattern: "*.b.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        #expect(vm.breakpointRules.count == 2)
        vm.selectedRuleID = vm.breakpointRules.first?.id
        vm.removeSelected()
        #expect(vm.breakpointRules.count == 1)
        #expect(vm.breakpointRules.first?.name == "Rule B")
        #expect(vm.selectedRuleID == nil)
    }

    @Test("toggleRule toggles the enabled state")
    func toggleRuleTogglesEnabledState() throws {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Toggle Test",
            urlPattern: "*.toggle.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let ruleID = try #require(vm.breakpointRules.first?.id)
        #expect(vm.breakpointRules.first?.isEnabled == true)
        vm.toggleRule(id: ruleID)
        #expect(vm.breakpointRules.first?.isEnabled == false)
        vm.toggleRule(id: ruleID)
        #expect(vm.breakpointRules.first?.isEnabled == true)
    }

    @Test("duplicateRule creates new rule with 'Copy of' prefix and selects it")
    func duplicateRuleCreatesNewRuleWithCopyPrefix() throws {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Original",
            urlPattern: "*.original.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        let originalID = try #require(vm.breakpointRules.first?.id)
        vm.duplicateRule(id: originalID)

        #expect(vm.breakpointRules.count == 2)
        let duplicate = vm.breakpointRules.last
        #expect(duplicate?.name == "Copy of Original")
        #expect(duplicate?.id != originalID)
        #expect(vm.selectedRuleID == duplicate?.id)
    }

    @Test("ruleCount reflects breakpoint rules only")
    func ruleCountReflectsBreakpointRulesOnly() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "Rule 1",
            urlPattern: "*.one.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Rule 2",
            urlPattern: "*.two.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        #expect(vm.ruleCount == vm.breakpointRules.count)
        #expect(vm.ruleCount == 2)
    }

    @Test("addBreakpointRule selects the newly added rule")
    func addRuleSelectsNewRule() {
        let vm = BreakpointRulesViewModel()

        vm.addBreakpointRule(
            ruleName: "New Rule",
            urlPattern: "*.new.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        let addedRule = vm.breakpointRules.first
        #expect(addedRule != nil)
        #expect(vm.selectedRuleID == addedRule?.id)
    }

    // MARK: - Edit mode

    @Test("updateRule updates the existing rule in place without creating a duplicate")
    func updateRuleDoesNotCreateDuplicate() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Original",
            urlPattern: "*.original.com/*",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        let ruleID = try #require(vm.breakpointRules.first?.id)

        vm.updateRule(
            id: ruleID,
            ruleName: "Edited",
            urlPattern: "*.edited.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        #expect(vm.breakpointRules.count == 1)
        let rule = try #require(vm.breakpointRules.first)
        #expect(rule.id == ruleID)
        #expect(rule.name == "Edited")
        #expect(rule.matchCondition.method == "POST")
    }

    @Test("updateRule keeps the edited rule selected after save")
    func updateRuleKeepsSelectionStable() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Rule A",
            urlPattern: "*.a.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        vm.addBreakpointRule(
            ruleName: "Rule B",
            urlPattern: "*.b.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        let ruleBID = try #require(vm.breakpointRules.last?.id)
        vm.selectedRuleID = ruleBID

        vm.updateRule(
            id: ruleBID,
            ruleName: "Rule B Edited",
            urlPattern: "*.b2.com/*",
            httpMethod: .put,
            matchType: .wildcard,
            phaseRequest: false,
            phaseResponse: true,
            includeSubpaths: true
        )

        #expect(vm.selectedRuleID == ruleBID)
        #expect(vm.breakpointRules.first { $0.id == ruleBID }?.name == "Rule B Edited")
    }

    @Test("updateRule with empty name falls back to URL pattern")
    func updateRuleEmptyNameUsesPattern() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Original",
            urlPattern: "*.orig.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        let ruleID = try #require(vm.breakpointRules.first?.id)

        vm.updateRule(
            id: ruleID,
            ruleName: "",
            urlPattern: "*.new.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        #expect(vm.breakpointRules.first?.name == "*.new.com/*")
    }

    @Test("updateRule with unknown id is a no-op")
    func updateRuleUnknownIDNoOp() {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Only",
            urlPattern: "*.only.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        vm.updateRule(
            id: UUID(),
            ruleName: "Ghost",
            urlPattern: "*.ghost.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )

        #expect(vm.breakpointRules.count == 1)
        #expect(vm.breakpointRules.first?.name == "Only")
    }

    @Test("updateRule changes phase from .both to .request only")
    func updateRuleChangesPhase() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Phase Test",
            urlPattern: "*.phase.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        let ruleID = try #require(vm.breakpointRules.first?.id)

        vm.updateRule(
            id: ruleID,
            ruleName: "Phase Test",
            urlPattern: "*.phase.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: true
        )

        if case let .breakpoint(phase) = vm.breakpointRules.first?.action {
            #expect(phase == .request)
        } else {
            Issue.record("Expected breakpoint action")
        }
    }

    @Test("duplicateRule does not edit the original (regression guard)")
    func duplicateRuleLeavesOriginalUnchanged() throws {
        let vm = BreakpointRulesViewModel()
        vm.addBreakpointRule(
            ruleName: "Source",
            urlPattern: "*.src.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: true
        )
        let originalID = try #require(vm.breakpointRules.first?.id)
        let originalName = try #require(vm.breakpointRules.first?.name)

        vm.duplicateRule(id: originalID)

        #expect(vm.breakpointRules.count == 2)
        let original = try #require(vm.breakpointRules.first { $0.id == originalID })
        #expect(original.name == originalName)
        #expect(vm.selectedRuleID != originalID)
    }

    // MARK: - Filter visibility

    @Test("isFilterBarVisible defaults to hidden")
    func filterBarDefaultsHidden() {
        let vm = BreakpointRulesViewModel()
        #expect(vm.isFilterBarVisible == false)
    }

    @Test("toggling isFilterBarVisible preserves filterText")
    func toggleFilterBarPreservesFilterText() {
        let vm = BreakpointRulesViewModel()
        vm.filterText = "api"
        vm.isFilterBarVisible = true
        #expect(vm.filterText == "api")
    }
}
