import Foundation
@testable import Rockxy
import Testing

// Comprehensive tests for Block List feature models: HTTPMethodFilter,
// BlockMatchType, BlockActionType, and BlockListViewModel rule creation.

// MARK: - HTTPMethodFilterTests

struct HTTPMethodFilterTests {
    @Test("All cases are defined")
    func allCases() {
        #expect(HTTPMethodFilter.allCases.count == 10)
        #expect(HTTPMethodFilter.query.methodValue == "QUERY")
    }

    @Test("ANY method returns nil for rule matching")
    func anyMethodValue() {
        #expect(HTTPMethodFilter.any.methodValue == nil)
    }

    @Test("Non-ANY methods return their raw value")
    func nonAnyMethodValues() {
        #expect(HTTPMethodFilter.get.methodValue == "GET")
        #expect(HTTPMethodFilter.post.methodValue == "POST")
        #expect(HTTPMethodFilter.put.methodValue == "PUT")
        #expect(HTTPMethodFilter.delete.methodValue == "DELETE")
        #expect(HTTPMethodFilter.patch.methodValue == "PATCH")
        #expect(HTTPMethodFilter.head.methodValue == "HEAD")
        #expect(HTTPMethodFilter.options.methodValue == "OPTIONS")
        #expect(HTTPMethodFilter.trace.methodValue == "TRACE")
    }

    @Test("Raw values match HTTP method strings")
    func rawValues() {
        for method in HTTPMethodFilter.allCases {
            #expect(method.rawValue == method.rawValue.uppercased() || method == .any)
        }
    }
}

// MARK: - BlockMatchTypeTests

struct BlockMatchTypeTests {
    @Test("All cases are defined")
    func allCases() {
        #expect(BlockMatchType.allCases.count == 2)
    }

    @Test("Display names match design spec")
    func displayNames() {
        #expect(BlockMatchType.wildcard.rawValue == "Use Wildcard")
        #expect(BlockMatchType.regex.rawValue == "Use Regex")
    }
}

// MARK: - BlockActionTypeTests

struct BlockActionTypeTests {
    @Test("All cases are defined")
    func allCases() {
        #expect(BlockActionType.allCases.count == 2)
    }

    @Test("returnForbidden returns 403")
    func returnForbiddenProperties() {
        let action = BlockActionType.returnForbidden
        #expect(action.statusCode == 403)
    }

    @Test("dropConnection returns 0 status")
    func dropConnectionProperties() {
        let action = BlockActionType.dropConnection
        #expect(action.statusCode == 0)
    }

    @Test("Display names match design spec")
    func displayNames() {
        #expect(BlockActionType.returnForbidden.rawValue == "Return 403 Forbidden")
        #expect(BlockActionType.dropConnection.rawValue == "Drop Connection")
    }

    @Test("All blocking actions have non-negative status codes")
    func statusCodesAreNonNegative() {
        for action in BlockActionType.allCases {
            #expect(action.statusCode >= 0)
        }
    }
}

// MARK: - BlockListViewModelTests

@Suite(.serialized)
struct BlockListViewModelTests {
    @Test("addBlockRule with wildcard creates correct pattern")
    @MainActor
    func addWildcardRule() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "Block Example API",
            urlPattern: "*example-api.local/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        #expect(vm.blockRules.count == 1)
        let rule = vm.blockRules.first
        #expect(rule?.name == "Block Example API")
        #expect(rule?.matchCondition.method == nil)
        #expect(rule?.matchCondition.urlPattern?.contains(".*") == true)
        #expect(rule?.matchCondition.sourceURLPattern == "*example-api.local/*")
        #expect(rule?.matchCondition.matchType == .wildcard)
        #expect(rule?.matchCondition.includeSubpaths == true)
    }

    @Test("addBlockRule with regex passes pattern through unchanged")
    @MainActor
    func addRegexRule() {
        let vm = BlockListViewModel()
        let rawRegex = "^https://tracker\\.analytics\\.io/.*$"

        vm.addBlockRule(
            ruleName: "Block Tracker",
            urlPattern: rawRegex,
            httpMethod: .get,
            matchType: .regex,
            blockAction: .returnForbidden,
            includeSubpaths: false
        )

        #expect(vm.blockRules.count == 1)
        let rule = vm.blockRules.first
        #expect(rule?.name == "Block Tracker")
        #expect(rule?.matchCondition.urlPattern == rawRegex)
        #expect(rule?.matchCondition.method == "GET")
    }

    @Test("addBlockRule with empty name uses URL pattern as name")
    @MainActor
    func emptyNameUsesPattern() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "",
            urlPattern: "*.ads.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        #expect(vm.blockRules.first?.name == "*.ads.example.com/*")
    }

    @Test("addBlockRule with specific HTTP method sets method on condition")
    @MainActor
    func specificMethodSetsCondition() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "Block POST",
            urlPattern: "*.example.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        #expect(vm.blockRules.first?.matchCondition.method == "POST")
    }

    @Test("addBlockRule with ANY method leaves method nil")
    @MainActor
    func anyMethodLeavesNil() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "Block All",
            urlPattern: "*.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        #expect(vm.blockRules.first?.matchCondition.method == nil)
    }

    @Test("addBlockRule with dropConnection action uses status code 0")
    @MainActor
    func dropConnectionUsesZeroStatusCode() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "Drop Connection",
            urlPattern: "*.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .dropConnection,
            includeSubpaths: true
        )

        if case let .block(statusCode) = vm.blockRules.first?.action {
            #expect(statusCode == 0)
        } else {
            Issue.record("Expected .block action")
        }
    }

    @Test("addBlockRule with returnForbidden uses status code 403")
    @MainActor
    func returnForbiddenUses403() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "Block",
            urlPattern: "*.example.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        if case let .block(statusCode) = vm.blockRules.first?.action {
            #expect(statusCode == 403)
        } else {
            Issue.record("Expected .block action")
        }
    }

    @Test("Wildcard includeSubpaths appends .* suffix to pattern")
    @MainActor
    func includeSubpathsAppendsSuffix() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "With subpaths",
            urlPattern: "https://example.com",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        let pattern = vm.blockRules.first?.matchCondition.urlPattern ?? ""
        #expect(pattern.hasSuffix(".*"))
    }

    @Test("Wildcard without includeSubpaths anchors with end-of-path assertion")
    @MainActor
    func noSubpathsAnchorsEnd() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "No subpaths",
            urlPattern: "https://example.com",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: false
        )

        let pattern = vm.blockRules.first?.matchCondition.urlPattern ?? ""
        #expect(!pattern.hasSuffix(".*"))
        #expect(pattern.hasSuffix("($|[?#])"))
    }

    @Test("blockRules filters only block-type rules")
    @MainActor
    func blockRulesFiltering() {
        let vm = BlockListViewModel()
        vm.addBlockRule(
            ruleName: "Test",
            urlPattern: "*.test.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        #expect(vm.blockRules.count == 1)
        #expect(vm.ruleCount == 1)
    }

    @Test("removeSelected removes the correct rule")
    @MainActor
    func removeSelected() {
        let vm = BlockListViewModel()
        vm.addBlockRule(
            ruleName: "Rule A",
            urlPattern: "*.a.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )
        vm.addBlockRule(
            ruleName: "Rule B",
            urlPattern: "*.b.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        #expect(vm.blockRules.count == 2)
        vm.selectedRuleID = vm.blockRules.first?.id
        vm.removeSelected()
        #expect(vm.blockRules.count == 1)
        #expect(vm.blockRules.first?.name == "Rule B")
        #expect(vm.selectedRuleID == nil)
    }

    @Test("removeRule deletes clicked row without requiring current selection")
    @MainActor
    func removeRuleByID() {
        let vm = BlockListViewModel()
        vm.addBlockRule(
            ruleName: "Rule A",
            urlPattern: "*.a.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )
        vm.addBlockRule(
            ruleName: "Rule B",
            urlPattern: "*.b.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        let secondID = vm.blockRules[1].id
        vm.selectedRuleID = vm.blockRules[0].id
        vm.removeRule(id: secondID)

        #expect(vm.blockRules.count == 1)
        #expect(vm.blockRules.first?.name == "Rule A")
        #expect(vm.selectedRuleID == vm.blockRules.first?.id)
    }

    @Test("duplicateSelected creates a copy and selects it")
    @MainActor
    func duplicateSelected() {
        let vm = BlockListViewModel()
        vm.addBlockRule(
            ruleName: "Original",
            urlPattern: "*.copy.com/*",
            httpMethod: .post,
            matchType: .wildcard,
            blockAction: .dropConnection,
            includeSubpaths: true
        )

        vm.selectedRuleID = vm.blockRules.first?.id
        vm.duplicateSelected()

        #expect(vm.blockRules.count == 2)
        #expect(vm.blockRules[1].name == "Copy of Original")
        #expect(vm.selectedRuleID == vm.blockRules[1].id)
        #expect(vm.blockRules[1].matchCondition.method == "POST")
        if case let .block(statusCode) = vm.blockRules[1].action {
            #expect(statusCode == 0)
        } else {
            Issue.record("Expected block action")
        }
    }

    @Test("updateBlockRule preserves id and enabled state")
    @MainActor
    func updateBlockRule() throws {
        let vm = BlockListViewModel()
        vm.addBlockRule(
            ruleName: "Original",
            urlPattern: "*.old.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )
        let id = try #require(vm.blockRules.first?.id)
        vm.toggleRule(id: id)

        vm.updateBlockRule(
            id: id,
            ruleName: "Updated",
            urlPattern: "^https://new.example/.*$",
            httpMethod: .get,
            matchType: .regex,
            blockAction: .dropConnection,
            includeSubpaths: false
        )

        let updated = try #require(vm.blockRules.first)
        #expect(updated.id == id)
        #expect(updated.name == "Updated")
        #expect(updated.isEnabled == false)
        #expect(updated.matchCondition.method == "GET")
        #expect(updated.matchCondition.urlPattern == "^https://new.example/.*$")
        #expect(updated.matchCondition.sourceURLPattern == "^https://new.example/.*$")
        #expect(updated.matchCondition.matchType == .regex)
        #expect(updated.matchCondition.includeSubpaths == false)
    }

    @Test("importBlockRules preserves non-block rules and selects first imported block")
    @MainActor
    func importBlockRulesPreservesNonBlockRules() {
        let vm = BlockListViewModel()
        vm.addBlockRule(
            ruleName: "Existing Block",
            urlPattern: "*.old.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )
        let throttle = TestFixtures.makeRule(name: "Throttle", action: .throttle(delayMs: 100))
        vm.handleRulesDidChange(Notification(name: .rulesDidChange, object: vm.allRules + [throttle]))
        let imported = TestFixtures.makeRule(name: "Imported Block", action: .block(statusCode: 403))

        vm.importBlockRules([imported])

        #expect(vm.allRules.contains { $0.id == throttle.id })
        #expect(vm.blockRules.count == 1)
        #expect(vm.blockRules.first?.id == imported.id)
        #expect(vm.selectedRuleID == imported.id)
    }

    @Test("importBlockRules with no imported blocks clears selection and preserves non-block rules")
    @MainActor
    func importBlockRulesEmptyClearsSelectionAndPreservesNonBlockRules() throws {
        let vm = BlockListViewModel()
        let existingBlock = TestFixtures.makeRule(name: "Existing Block", action: .block(statusCode: 403))
        let throttle = TestFixtures.makeRule(name: "Throttle", action: .throttle(delayMs: 100))
        vm.handleRulesDidChange(Notification(name: .rulesDidChange, object: [existingBlock, throttle]))
        vm.selectedRuleID = existingBlock.id

        vm.importBlockRules([])

        #expect(vm.blockRules.isEmpty)
        #expect(vm.allRules.count == 1)
        #expect(vm.allRules.first?.id == throttle.id)
        #expect(vm.selectedRuleID == nil)
    }

    @Test("exportBlockRules serializes only block rules from current mixed rule list")
    @MainActor
    func exportBlockRulesSerializesOnlyBlockRules() throws {
        let vm = BlockListViewModel()
        let block = TestFixtures.makeRule(name: "Exported Block", action: .block(statusCode: 403))
        let throttle = TestFixtures.makeRule(name: "Throttle", action: .throttle(delayMs: 100))
        vm.handleRulesDidChange(Notification(name: .rulesDidChange, object: [block, throttle]))

        let data = try vm.exportBlockRules()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let blockRules = try #require(object["blockRules"] as? [[String: Any]])

        #expect(blockRules.count == 1)
        #expect(blockRules.first?["name"] as? String == "Exported Block")
    }

    // MARK: - Editor Session Flow

    @Test("presentNewRuleEditor opens blank create session")
    @MainActor
    func presentNewRuleEditorAssignsCreateSession() throws {
        let vm = BlockListViewModel()

        vm.presentNewRuleEditor()

        let session = try #require(vm.editorSession)
        guard case .create(nil) = session.mode else {
            Issue.record("expected .create(nil) mode")
            return
        }
    }

    @Test("presentEditorForContext opens create session with quick-create context")
    @MainActor
    func presentEditorForContextAssignsCreateSessionWithContext() throws {
        let vm = BlockListViewModel()
        let context = BlockRuleEditorContextBuilder.fromDomain("api.example.com")

        vm.presentEditorForContext(context)

        let session = try #require(vm.editorSession)
        guard case let .create(receivedContext?) = session.mode else {
            Issue.record("expected .create(context) mode")
            return
        }
        #expect(receivedContext.origin == .domainQuickCreate)
        #expect(receivedContext.sourceHost == "api.example.com")
        #expect(receivedContext.defaultPattern == "*api.example.com/")
    }

    @Test("second quick-create replaces open block editor session with fresh identity")
    @MainActor
    func secondQuickCreateReplacesOpenEditorSessionWithFreshIdentity() throws {
        let vm = BlockListViewModel()
        vm.presentEditorForContext(BlockRuleEditorContextBuilder.fromDomain("first.example.com"))
        let firstID = try #require(vm.editorSession?.id)

        vm.presentEditorForContext(BlockRuleEditorContextBuilder.fromDomain("second.example.com"))

        let secondSession = try #require(vm.editorSession)
        #expect(secondSession.id != firstID)
        guard case let .create(context?) = secondSession.mode else {
            Issue.record("expected second session to carry context")
            return
        }
        #expect(context.sourceHost == "second.example.com")
    }

    @Test("presentEditorForEditing opens edit session for selected row")
    @MainActor
    func presentEditorForEditingAssignsEditSession() throws {
        let vm = BlockListViewModel()
        let rule = TestFixtures.makeRule(name: "Editable", action: .block(statusCode: 403))

        vm.presentEditorForEditing(rule)

        let session = try #require(vm.editorSession)
        guard case let .edit(editingRule) = session.mode else {
            Issue.record("expected .edit mode")
            return
        }
        #expect(editingRule.id == rule.id)
        #expect(editingRule.name == "Editable")
    }

    @Test("dismissEditor clears block editor session")
    @MainActor
    func dismissEditorClearsSession() {
        let vm = BlockListViewModel()
        vm.presentNewRuleEditor()

        vm.dismissEditor()

        #expect(vm.editorSession == nil)
    }

    // MARK: - Selection Reconciliation

    @Test("handleRulesDidChange clears selection when selected block rule disappears")
    @MainActor
    func handleRulesDidChangeClearsMissingBlockSelection() {
        let vm = BlockListViewModel()
        let block = TestFixtures.makeRule(name: "Selected Block", action: .block(statusCode: 403))
        vm.handleRulesDidChange(Notification(name: .rulesDidChange, object: [block]))
        vm.selectedRuleID = block.id

        let replacement = TestFixtures.makeRule(name: "Replacement", action: .block(statusCode: 403))
        vm.handleRulesDidChange(Notification(name: .rulesDidChange, object: [replacement]))

        #expect(vm.selectedRuleID == nil)
    }

    @Test("handleRulesDidChange clears selection when selected rule is no longer a block rule")
    @MainActor
    func handleRulesDidChangeClearsSelectionForNonBlockRule() {
        let vm = BlockListViewModel()
        let block = TestFixtures.makeRule(name: "Selected Block", action: .block(statusCode: 403))
        vm.handleRulesDidChange(Notification(name: .rulesDidChange, object: [block]))
        vm.selectedRuleID = block.id

        let sameIDNonBlock = ProxyRule(
            id: block.id,
            name: "Same ID Throttle",
            matchCondition: block.matchCondition,
            action: .throttle(delayMs: 100)
        )
        vm.handleRulesDidChange(Notification(name: .rulesDidChange, object: [sameIDNonBlock]))

        #expect(vm.blockRules.isEmpty)
        #expect(vm.selectedRuleID == nil)
    }

    @Test("toggleRule toggles enabled state")
    @MainActor
    func toggleRule() throws {
        let vm = BlockListViewModel()
        vm.addBlockRule(
            ruleName: "Toggle Test",
            urlPattern: "*.toggle.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        let ruleID = try #require(vm.blockRules.first?.id)
        #expect(vm.blockRules.first?.isEnabled == true)
        vm.toggleRule(id: ruleID)
        #expect(vm.blockRules.first?.isEnabled == false)
        vm.toggleRule(id: ruleID)
        #expect(vm.blockRules.first?.isEnabled == true)
    }

    @Test("All HTTP method filters can be used to create rules")
    @MainActor
    func allMethodFilters() {
        let vm = BlockListViewModel()

        for method in HTTPMethodFilter.allCases {
            vm.addBlockRule(
                ruleName: "Rule \(method.rawValue)",
                urlPattern: "*.example.com/*",
                httpMethod: method,
                matchType: .wildcard,
                blockAction: .returnForbidden,
                includeSubpaths: true
            )
        }

        #expect(vm.blockRules.count == HTTPMethodFilter.allCases.count)
    }

    @Test("All action types can be used to create rules")
    @MainActor
    func allActionTypes() {
        let vm = BlockListViewModel()

        for action in BlockActionType.allCases {
            vm.addBlockRule(
                ruleName: "Rule \(action.rawValue)",
                urlPattern: "*.example.com/*",
                httpMethod: .any,
                matchType: .wildcard,
                blockAction: action,
                includeSubpaths: true
            )
        }

        #expect(vm.blockRules.count == BlockActionType.allCases.count)
    }

    @Test("All match types can be used to create rules")
    @MainActor
    func allMatchTypes() {
        let vm = BlockListViewModel()

        for matchType in BlockMatchType.allCases {
            vm.addBlockRule(
                ruleName: "Rule \(matchType.rawValue)",
                urlPattern: "*.example.com/*",
                httpMethod: .any,
                matchType: matchType,
                blockAction: .returnForbidden,
                includeSubpaths: true
            )
        }

        #expect(vm.blockRules.count == BlockMatchType.allCases.count)
    }

    @Test("Wildcard escapes special regex characters in pattern")
    @MainActor
    func wildcardEscapesSpecialChars() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "Escape test",
            urlPattern: "https://example.com/path?q=1",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: false
        )

        let pattern = vm.blockRules.first?.matchCondition.urlPattern ?? ""
        // The ? in ?q=1 should be escaped by NSRegularExpression then converted to .
        // The pattern should contain ".q" (the escaped ?) but not the literal "?q"
        #expect(!pattern.contains("?q"))
        #expect(pattern.contains(".q"))
    }

    @Test("Wildcard converts * to .* and ? to .")
    @MainActor
    func wildcardConversion() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "Wildcard convert",
            urlPattern: "*.example.com/?page",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: false
        )

        let pattern = vm.blockRules.first?.matchCondition.urlPattern ?? ""
        #expect(pattern.contains(".*"))
        #expect(pattern.contains(".page"))
    }

    // MARK: - Quota Rollback

    @Test("addBlockRule at quota rolls back optimistic append")
    @MainActor
    func addBlockRuleQuotaRollback() async {
        await RuleTestLock.shared.acquire()
        let savedGate = RulePolicyGate.shared
        let engineSnapshot = await RuleEngine.shared.allRules
        await RuleEngine.shared.replaceAll([])

        let existing = TestFixtures.makeRule(name: "Existing", action: .block(statusCode: 403))
        await RuleEngine.shared.addRule(existing)

        RulePolicyGate.shared = RulePolicyGate(policy: BlockQuotaPolicy())

        let vm = BlockListViewModel()
        await vm.refreshFromEngine()
        let beforeCount = vm.blockRules.count

        vm.addBlockRule(
            ruleName: "Overflow",
            urlPattern: "*.overflow.com",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: false
        )

        #expect(vm.blockRules.count == beforeCount + 1)

        for _ in 0 ..< 500 {
            if vm.blockRules.count == beforeCount {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(vm.blockRules.count == beforeCount)

        RulePolicyGate.shared = savedGate
        await RuleEngine.shared.replaceAll(engineSnapshot)
        await RuleTestLock.shared.release()
    }

    @Test("toggleRule enable at quota rolls back optimistic toggle")
    @MainActor
    func toggleRuleEnableAtQuotaRollback() async {
        await RuleTestLock.shared.acquire()
        let savedGate = RulePolicyGate.shared
        let engineSnapshot = await RuleEngine.shared.allRules
        await RuleEngine.shared.replaceAll([])

        let active = TestFixtures.makeRule(name: "Active", action: .block(statusCode: 403))
        await RuleEngine.shared.addRule(active)

        var disabled = TestFixtures.makeRule(name: "Disabled", action: .block(statusCode: 403))
        disabled.isEnabled = false
        await RuleEngine.shared.addRule(disabled)

        RulePolicyGate.shared = RulePolicyGate(policy: BlockQuotaPolicy())

        let vm = BlockListViewModel()
        await vm.refreshFromEngine()

        #expect(vm.allRules.first { $0.id == disabled.id }?.isEnabled == false)

        vm.toggleRule(id: disabled.id)
        #expect(vm.allRules.first { $0.id == disabled.id }?.isEnabled == true)

        for _ in 0 ..< 500 {
            if vm.allRules.first(where: { $0.id == disabled.id })?.isEnabled == false {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(vm.allRules.first { $0.id == disabled.id }?.isEnabled == false)

        RulePolicyGate.shared = savedGate
        await RuleEngine.shared.replaceAll(engineSnapshot)
        await RuleTestLock.shared.release()
    }
}

// MARK: - BlockQuotaPolicy

private struct BlockQuotaPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 1
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
}
