import Foundation
@testable import Rockxy
import Testing

@MainActor
struct BreakpointRuleEditorStoreTests {
    @Test("openNew stores quick-create context and clears editing rule")
    func openNewStoresQuickCreateContext() {
        let store = BreakpointRuleEditorStore.shared
        let baseline = store.draftVersion
        let context = BreakpointEditorContextBuilder.fromDomain("example.com")
        var didSave = false

        store.openNew(context: context) { _, _, _, _, _, _, _ in
            didSave = true
        }

        store.onSave?("", "", .any, .wildcard, true, true, true)

        #expect(store.editorContext?.sourceHost == "example.com")
        #expect(store.editingRule == nil)
        #expect(store.draftVersion == baseline &+ 1)
        #expect(didSave)
    }

    @Test("openExisting stores editing rule and clears quick-create context")
    func openExistingStoresEditingRule() {
        let store = BreakpointRuleEditorStore.shared
        let baseline = store.draftVersion
        let rule = ProxyRule(
            name: "Edit me",
            matchCondition: RuleMatchCondition(urlPattern: "https://example.com/.*"),
            action: .breakpoint(phase: .both)
        )

        store.openExisting(rule) { _, _, _, _, _, _, _ in }

        #expect(store.editingRule?.id == rule.id)
        #expect(store.editorContext == nil)
        #expect(store.draftVersion == baseline &+ 1)
    }

    @Test("openNew without context resets editor state")
    func openNewWithoutContextResetsEditorState() {
        let store = BreakpointRuleEditorStore.shared
        let rule = ProxyRule(
            name: "Previous",
            matchCondition: RuleMatchCondition(urlPattern: "/old"),
            action: .breakpoint(phase: .both)
        )
        store.openExisting(rule) { _, _, _, _, _, _, _ in }
        let baseline = store.draftVersion

        store.openNew { _, _, _, _, _, _, _ in }

        #expect(store.editorContext == nil)
        #expect(store.editingRule == nil)
        #expect(store.draftVersion == baseline &+ 1)
    }

    @Test("save handler receives all add/edit field values")
    func saveHandlerReceivesAllFieldValues() throws {
        let store = BreakpointRuleEditorStore.shared
        var captured: (
            name: String,
            pattern: String,
            method: HTTPMethodFilter,
            matchType: RuleMatchType,
            request: Bool,
            response: Bool,
            includeSubpaths: Bool
        )?

        store.openNew {
            captured = ($0, $1, $2, $3, $4, $5, $6)
        }
        store.onSave?("API", "/v1/*", .patch, .wildcard, true, false, false)

        let saved = try #require(captured)
        #expect(saved.name == "API")
        #expect(saved.pattern == "/v1/*")
        #expect(saved.method == .patch)
        #expect(saved.matchType == .wildcard)
        #expect(saved.request)
        #expect(!saved.response)
        #expect(!saved.includeSubpaths)
    }
}
