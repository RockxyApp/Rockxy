import Foundation
@testable import Rockxy
import Testing

// Comprehensive tests for Block List feature models: HTTPMethodFilter,
// BlockMatchType, BlockActionType, and BlockListViewModel rule creation.

// MARK: - HTTPMethodFilterTests

struct HTTPMethodFilterTests {
    @Test("All cases are defined")
    func allCases() {
        #expect(HTTPMethodFilter.allCases.count == 9)
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

struct BlockListViewModelTests {
    @Test("addBlockRule with wildcard creates correct pattern")
    @MainActor
    func addWildcardRule() {
        let vm = BlockListViewModel()

        vm.addBlockRule(
            ruleName: "Block ChatGPT",
            urlPattern: "*chatgpt.com/*",
            httpMethod: .any,
            matchType: .wildcard,
            blockAction: .returnForbidden,
            includeSubpaths: true
        )

        #expect(vm.blockRules.count == 1)
        let rule = vm.blockRules.first
        #expect(rule?.name == "Block ChatGPT")
        #expect(rule?.matchCondition.method == nil)
        #expect(rule?.matchCondition.urlPattern?.contains(".*") == true)
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
}
