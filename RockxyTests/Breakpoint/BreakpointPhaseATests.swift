import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct BreakpointPhaseATests {
    // BP_A1
    @Test("globalEnableTogglePersistsToEngine")
    func globalEnableTogglePersistsToEngine() async throws {
        try await BreakpointRuleTestIsolation.withSharedRuleState {
            let rule = ProxyRule.breakpointTest(matchingRule: "httpbin.org/get")
            await RuleSyncService.replaceAllRules([rule])
            await RuleSyncService.setBreakpointToolEnabled(false)

            let disabled = await RuleEngine.shared.evaluateBreakpointRule(
                method: "GET",
                url: TestEndpoints.httpbinHTTPS("get"),
                headers: []
            )
            #expect(disabled == nil)
            #expect(UserDefaults.standard.object(forKey: "breakpointToolEnabled") as? Bool == false)

            await RuleSyncService.setBreakpointToolEnabled(true)
            let enabled = await RuleEngine.shared.evaluateBreakpointRule(
                method: "GET",
                url: TestEndpoints.httpbinHTTPS("get"),
                headers: []
            )
            #expect(enabled?.id == rule.id)
        }
    }

    // BP_A2
    @Test("ruleEditorOpensWithDefaultDraft")
    func ruleEditorOpensWithDefaultDraft() {
        let store = BreakpointRuleEditorStore.shared
        store.openNew { _, _, _, _, _, _, _ in }
        let firstVersion = store.draftVersion
        #expect(store.editingRule == nil)
        #expect(store.editorContext == nil)

        store.openNew { _, _, _, _, _, _, _ in }
        #expect(store.editingRule == nil)
        #expect(store.editorContext == nil)
        #expect(store.draftVersion == firstVersion + 1)
    }

    // BP_A3a
    @Test("ruleDraftPersistsFieldName")
    func ruleDraftPersistsFieldName() {
        let rule = makeDraftRule(name: "Case 5 - auth profile")
        #expect(rule.name == "Case 5 - auth profile")
    }

    // BP_A3b
    @Test("ruleDraftPersistsFieldMatchingRule")
    func ruleDraftPersistsFieldMatchingRule() {
        let rule = makeDraftRule(matchingRule: "127.0.0.1:43210/rockxy-demo/profile")
        let decoded = AddBreakpointRuleSheet.decode(rule: rule)
        #expect(decoded.displayPattern == "127.0.0.1:43210/rockxy-demo/profile")
    }

    // BP_A3c
    @Test("ruleDraftPersistsFieldMethod")
    func ruleDraftPersistsFieldMethod() {
        let rule = makeDraftRule(method: .post)
        #expect(rule.matchCondition.method == "POST")
    }

    // BP_A3d
    @Test("ruleDraftPersistsFieldMatchType")
    func ruleDraftPersistsFieldMatchType() {
        let rule = makeDraftRule(matchingRule: #"https://httpbin\.org/get"#, matchType: .regex)
        let decoded = AddBreakpointRuleSheet.decode(rule: rule)
        #expect(decoded.matchType == RuleMatchType.regex)
    }

    // BP_A3e
    @Test("ruleDraftPersistsFieldIncludeSubpaths")
    func ruleDraftPersistsFieldIncludeSubpaths() {
        let rule = makeDraftRule(includeSubpaths: true)
        let decoded = AddBreakpointRuleSheet.decode(rule: rule)
        #expect(decoded.includeSubpaths == true)
    }

    // BP_A3f
    @Test("ruleDraftPersistsFieldPhases")
    func ruleDraftPersistsFieldPhases() {
        let rule = makeDraftRule(phaseRequest: true, phaseResponse: false)
        guard case let .breakpoint(phase) = rule.action else {
            Issue.record("Expected breakpoint action")
            return
        }
        #expect(phase == .request)
    }

    // BP_A4
    @Test("addButtonCommitsDraftToRuleList")
    func addButtonCommitsDraftToRuleList() {
        let viewModel = BreakpointRulesViewModel(syncsChanges: false)
        viewModel.addBreakpointRule(
            ruleName: "Add Test",
            urlPattern: "httpbin.org/get",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: false
        )
        #expect(viewModel.breakpointRules.count == 1)
        #expect(viewModel.selectedRule?.name == "Add Test")
    }

    // BP_A5
    @Test("ruleRoundTripThroughStorage")
    func ruleRoundTripThroughStorage() async throws {
        try await BreakpointRuleTestIsolation.withSharedRuleState {
            let rule = ProxyRule.breakpointTest(
                name: "Round Trip",
                matchingRule: "httpbin.org/anything",
                method: .patch,
                phases: .both,
                includeSubpaths: true
            )
            try RuleStore().saveRules([rule])
            let loaded = try #require(try RuleStore().loadRules().first)
            #expect(loaded.id == rule.id)
            #expect(loaded.name == "Round Trip")
            #expect(loaded.matchCondition.method == "PATCH")
            #expect(loaded.matchCondition.urlPattern == rule.matchCondition.urlPattern)
            #expect(loaded.isEnabled == true)
        }
    }

    @Test("breakpoint window refresh loads persisted rules after restart")
    func breakpointWindowRefreshLoadsPersistedRulesAfterRestart() async throws {
        try await BreakpointRuleTestIsolation.withSharedRuleState {
            let rule = ProxyRule.breakpointTest(
                name: "Persisted Breakpoint",
                matchingRule: "httpbin.org/restart",
                method: .get,
                phases: .both,
                includeSubpaths: true
            )
            try RuleStore().saveRules([rule])
            await RuleEngine.shared.replaceAll([])

            let viewModel = BreakpointRulesViewModel(syncsChanges: false)
            await viewModel.refreshFromEngine()

            #expect(viewModel.breakpointRules.count == 1)
            #expect(viewModel.breakpointRules.first?.id == rule.id)
            #expect(viewModel.breakpointRules.first?.name == "Persisted Breakpoint")
        }
    }

    // BP_A6
    @Test("perRuleEnableObservedWithoutRestart")
    func perRuleEnableObservedWithoutRestart() async {
        let engine = RuleEngine()
        let rule = ProxyRule.breakpointTest(matchingRule: "httpbin.org/get")
        await engine.addRule(rule)
        await engine.setEnabled(id: rule.id, enabled: false)
        let disabled = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("get"), headers: [])
        #expect(disabled == nil)

        await engine.setEnabled(id: rule.id, enabled: true)
        let enabled = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("get"), headers: [])
        #expect(enabled?.id == rule.id)
    }

    // BP_A7
    @Test("deleteRuleRemovesFromListAndStorage")
    func deleteRuleRemovesFromListAndStorage() async throws {
        try await BreakpointRuleTestIsolation.withSharedRuleState {
            let rule = ProxyRule.breakpointTest(matchingRule: "httpbin.org/get")
            await RuleSyncService.replaceAllRules([rule])
            await RuleSyncService.removeRule(id: rule.id)
            let engineRules = await RuleEngine.shared.allRules
            let storedRules = try RuleStore().loadRules()
            #expect(engineRules.isEmpty)
            #expect(storedRules.isEmpty)
        }
    }

    // BP_A8
    @Test("duplicateRuleCreatesIndependentCopy")
    func duplicateRuleCreatesIndependentCopy() {
        let viewModel = BreakpointRulesViewModel(syncsChanges: false)
        viewModel.addBreakpointRule(
            ruleName: "Original",
            urlPattern: "httpbin.org/get",
            httpMethod: .get,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: true,
            includeSubpaths: false
        )
        let original = viewModel.breakpointRules[0]
        viewModel.duplicateRule(id: original.id)

        #expect(viewModel.breakpointRules.count == 2)
        #expect(viewModel.breakpointRules[0].id != viewModel.breakpointRules[1].id)
        viewModel.updateRule(
            id: viewModel.breakpointRules[1].id,
            ruleName: "Copy Edited",
            urlPattern: "httpbin.org/headers",
            httpMethod: .post,
            matchType: .wildcard,
            phaseRequest: true,
            phaseResponse: false,
            includeSubpaths: false
        )
        #expect(viewModel.breakpointRules[0].name == "Original")
        #expect(viewModel.breakpointRules[1].name == "Copy Edited")
    }

    private func makeDraftRule(
        name: String = "Draft",
        matchingRule: String = "httpbin.org/get",
        method: HTTPMethodFilter = .any,
        matchType: RuleMatchType = .wildcard,
        phaseRequest: Bool = true,
        phaseResponse: Bool = true,
        includeSubpaths: Bool = false
    ) -> ProxyRule {
        let viewModel = BreakpointRulesViewModel(syncsChanges: false)
        viewModel.addBreakpointRule(
            ruleName: name,
            urlPattern: matchingRule,
            httpMethod: method,
            matchType: matchType,
            phaseRequest: phaseRequest,
            phaseResponse: phaseResponse,
            includeSubpaths: includeSubpaths
        )
        return viewModel.breakpointRules[0]
    }
}
