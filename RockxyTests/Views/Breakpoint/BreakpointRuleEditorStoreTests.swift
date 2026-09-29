import Foundation
@testable import Rockxy
import Testing

// MARK: - BreakpointRuleEditorStoreTests

/// `BreakpointRuleEditorStore` is a shared singleton, so these tests are
/// serialized to keep draftVersion / onSave assertions deterministic.
@Suite(.serialized)
@MainActor
struct BreakpointRuleEditorStoreTests {
    @Test("openNew stores quick-create context and clears editing rule")
    func openNewStoresQuickCreateContext() async {
        let store = BreakpointRuleEditorStore.shared
        let baseline = store.draftVersion
        let context = BreakpointEditorContextBuilder.fromDomain("example.com")
        var didSave = false

        store.openNew(context: context) { _, _, _, _, _, _, _, _ in
            didSave = true
            return true
        }

        // Snapshot shared-singleton state before the suspension point so a
        // concurrent suite touching the same singleton cannot perturb reads.
        let capturedHost = store.editorContext?.sourceHost
        let capturedEditingRule = store.editingRule
        let capturedVersion = store.draftVersion
        let handler = store.onSave

        let accepted = await handler?("", "", .any, .wildcard, true, true, true, nil)

        #expect(capturedHost == "example.com")
        #expect(capturedEditingRule == nil)
        #expect(capturedVersion == baseline &+ 1)
        #expect(didSave)
        #expect(accepted == true)
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

        store.openExisting(rule) { _, _, _, _, _, _, _, _ in true }

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
        store.openExisting(rule) { _, _, _, _, _, _, _, _ in true }
        let baseline = store.draftVersion

        store.openNew { _, _, _, _, _, _, _, _ in true }

        #expect(store.editorContext == nil)
        #expect(store.editingRule == nil)
        #expect(store.draftVersion == baseline &+ 1)
    }

    @Test("save handler receives all add/edit field values and returns its accepted result")
    func saveHandlerReceivesAllFieldValues() async throws {
        let store = BreakpointRuleEditorStore.shared
        var captured: CapturedSave?

        store.openNew {
            _ = $7
            captured = CapturedSave(
                name: $0,
                pattern: $1,
                method: $2,
                matchType: $3,
                request: $4,
                response: $5,
                includeSubpaths: $6
            )
            return false
        }
        let accepted = await store.onSave?("API", "/v1/*", .patch, .wildcard, true, false, false, nil)

        let saved = try #require(captured)
        #expect(saved.name == "API")
        #expect(saved.pattern == "/v1/*")
        #expect(saved.method == .patch)
        #expect(saved.matchType == .wildcard)
        #expect(saved.request)
        #expect(!saved.response)
        #expect(!saved.includeSubpaths)
        #expect(accepted == false)
    }

    @Test("a second quick-create replaces context, bumps version, and swaps the handler")
    func secondQuickCreateReplacesContextVersionAndHandler() async {
        let store = BreakpointRuleEditorStore.shared
        let baseline = store.draftVersion
        var firstHandlerCalled = false
        var secondHandlerCalled = false

        store.openNew(context: BreakpointEditorContextBuilder.fromDomain("first.example.com")) { _, _, _, _, _, _, _, _ in
            firstHandlerCalled = true
            return true
        }
        store.openNew(context: BreakpointEditorContextBuilder.fromDomain("second.example.com")) { _, _, _, _, _, _, _, _ in
            secondHandlerCalled = true
            return true
        }

        _ = await store.onSave?("", "", .any, .wildcard, true, true, true, nil)

        #expect(store.editorContext?.sourceHost == "second.example.com")
        #expect(store.editingRule == nil)
        #expect(store.draftVersion == baseline &+ 2)
        #expect(!firstHandlerCalled)
        #expect(secondHandlerCalled)
    }

    @Test("reset clears context, editing rule, and handler")
    func resetClearsContextRuleAndHandler() {
        let store = BreakpointRuleEditorStore.shared
        let rule = ProxyRule(
            name: "To reset",
            matchCondition: RuleMatchCondition(urlPattern: "/x"),
            action: .breakpoint(phase: .both)
        )
        store.openExisting(rule) { _, _, _, _, _, _, _, _ in true }

        store.reset()

        #expect(store.editorContext == nil)
        #expect(store.editingRule == nil)
        #expect(store.onSave == nil)
    }

    @Test("opening a new draft after editing clears the editing rule and swaps the handler")
    func newAfterEditClearsEditingRuleAndSwapsHandler() async {
        let store = BreakpointRuleEditorStore.shared
        let rule = ProxyRule(
            name: "Being edited",
            matchCondition: RuleMatchCondition(urlPattern: "https://edit.example.com/.*"),
            action: .breakpoint(phase: .both)
        )
        var editHandlerCalled = false
        var newHandlerCalled = false

        store.openExisting(rule) { _, _, _, _, _, _, _, _ in
            editHandlerCalled = true
            return true
        }
        let baseline = store.draftVersion

        store.openNew { _, _, _, _, _, _, _, _ in
            newHandlerCalled = true
            return true
        }
        _ = await store.onSave?("", "", .any, .wildcard, true, true, true, nil)

        #expect(store.editingRule == nil)
        #expect(store.editorContext == nil)
        #expect(store.draftVersion == baseline &+ 1)
        #expect(!editHandlerCalled)
        #expect(newHandlerCalled)
    }
}

// MARK: - CapturedSave

private struct CapturedSave {
    let name: String
    let pattern: String
    let method: HTTPMethodFilter
    let matchType: RuleMatchType
    let request: Bool
    let response: Bool
    let includeSubpaths: Bool
}
