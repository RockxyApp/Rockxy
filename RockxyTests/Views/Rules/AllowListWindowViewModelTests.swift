import Foundation
@testable import Rockxy
import Testing

// MARK: - AllowListWindowViewModelTests

/// `AllowListWindowViewModel` tests exercise view model methods directly. The view model
/// owns selection + all rule-CRUD action methods (add / edit / duplicate / remove /
/// toggle + `reconcileSelectionAfterRulesChange`). All tests inject a fresh
/// `AllowListManager` via `init(manager:)` and mutate only through the public API.
@MainActor
struct AllowListWindowViewModelTests {
    // MARK: Internal

    // MARK: - Initial State

    @Test
    func initialStateIsEmpty() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        #expect(viewModel.filteredRules.isEmpty)
        #expect(viewModel.selectedRuleID == nil)
        #expect(viewModel.editorSession == nil)
        #expect(!viewModel.isFilterBarVisible)
        #expect(viewModel.filterText.isEmpty)
        #expect(!viewModel.isAllowListActive)
    }

    // MARK: - Filter Bar

    @Test
    func filterBarVisibilityToggles() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        #expect(!viewModel.isFilterBarVisible)
        viewModel.isFilterBarVisible = true
        #expect(viewModel.isFilterBarVisible)
    }

    @Test
    func filterByNameColumn() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "GitHub API",
            urlPattern: "*github.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        viewModel.addRule(
            ruleName: "Stripe",
            urlPattern: "*stripe.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        viewModel.addRule(
            ruleName: "GitLab",
            urlPattern: "*gitlab.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )

        viewModel.filterColumn = .name
        viewModel.filterText = "git"
        let filtered = viewModel.filteredRules
        #expect(filtered.count == 2)
        #expect(filtered.map(\.name).sorted() == ["GitHub API", "GitLab"])
    }

    @Test
    func filterByMethodColumn() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "r1",
            urlPattern: "*a*",
            httpMethod: .get,
            matchType: .wildcard,
            includeSubpaths: true
        )
        viewModel.addRule(
            ruleName: "r2",
            urlPattern: "*b*",
            httpMethod: .post,
            matchType: .wildcard,
            includeSubpaths: true
        )
        viewModel.addRule(
            ruleName: "r3",
            urlPattern: "*c*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )

        viewModel.filterColumn = .method
        viewModel.filterText = "POST"
        let filtered = viewModel.filteredRules
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "r2")
    }

    @Test
    func filterByMatchingRuleColumn() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "r1",
            urlPattern: "*github.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        viewModel.addRule(
            ruleName: "r2",
            urlPattern: "*stripe.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )

        viewModel.filterColumn = .matchingRule
        viewModel.filterText = "stripe"
        let filtered = viewModel.filteredRules
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "r2")
    }

    // MARK: - Add Flow

    @Test
    func addRuleSelectsNewRule() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "API",
            urlPattern: "*example.com*",
            httpMethod: .get,
            matchType: .wildcard,
            includeSubpaths: true
        )

        #expect(viewModel.manager.rules.count == 1)
        #expect(viewModel.manager.rules[0].name == "API")
        #expect(viewModel.manager.rules[0].method == "GET")
        #expect(viewModel.selectedRuleID == viewModel.manager.rules[0].id)
        #expect(viewModel.filteredRules.count == 1)
    }

    @Test
    func addRuleWithEmptyNameUsesPattern() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "",
            urlPattern: "*example.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )

        #expect(viewModel.manager.rules[0].name == "*example.com*")
    }

    // MARK: - Edit Flow

    @Test
    func updateRulePreservesSelection() throws {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "orig",
            urlPattern: "*a.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let originalID = try #require(viewModel.selectedRuleID)

        viewModel.updateRule(
            id: originalID,
            ruleName: "renamed",
            urlPattern: "*renamed.com*",
            httpMethod: .post,
            matchType: .regex,
            includeSubpaths: false
        )

        #expect(viewModel.manager.rules.count == 1)
        #expect(viewModel.manager.rules[0].id == originalID)
        #expect(viewModel.manager.rules[0].name == "renamed")
        #expect(viewModel.manager.rules[0].rawPattern == "*renamed.com*")
        #expect(viewModel.manager.rules[0].method == "POST")
        #expect(viewModel.manager.rules[0].matchType == .regex)
        #expect(!viewModel.manager.rules[0].includeSubpaths)
        #expect(viewModel.selectedRuleID == originalID)
    }

    // MARK: - Duplicate Flow

    @Test
    func duplicateSelectedCopiesAndSelects() throws {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "orig",
            urlPattern: "*a.com*",
            httpMethod: .get,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let originalID = try #require(viewModel.selectedRuleID)

        viewModel.duplicateSelected()

        #expect(viewModel.manager.rules.count == 2)
        let copy = viewModel.manager.rules[1]
        #expect(copy.id != originalID)
        #expect(copy.name == "Copy of orig")
        #expect(copy.rawPattern == "*a.com*")
        #expect(copy.method == "GET")
        #expect(copy.matchType == .wildcard)
        #expect(viewModel.selectedRuleID == copy.id)
    }

    @Test
    func duplicateSelectedIsNoopWhenNothingSelected() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "orig",
            urlPattern: "*a.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        viewModel.selectedRuleID = nil

        viewModel.duplicateSelected()
        #expect(viewModel.manager.rules.count == 1)
    }

    // MARK: - Remove Flow

    @Test
    func removeSelectedRemovesAndClearsSelection() throws {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "a",
            urlPattern: "*a.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let removedID = try #require(viewModel.selectedRuleID)

        viewModel.removeSelected()

        #expect(viewModel.manager.rules.isEmpty)
        #expect(viewModel.selectedRuleID == nil)
        #expect(!viewModel.manager.rules.contains { $0.id == removedID })
    }

    // MARK: - Toggle Flow

    @Test
    func toggleRuleFlipsEnabledPreservingSelection() throws {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "a",
            urlPattern: "*a.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let ruleID = try #require(viewModel.selectedRuleID)

        viewModel.toggleRule(id: ruleID)
        #expect(!viewModel.manager.rules[0].isEnabled)
        #expect(viewModel.selectedRuleID == ruleID)

        viewModel.toggleRule(id: ruleID)
        #expect(viewModel.manager.rules[0].isEnabled)
    }

    // MARK: - Master Toggle

    @Test
    func setActiveUpdatesManager() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.setActive(true)
        #expect(viewModel.manager.isActive)
        #expect(viewModel.isAllowListActive)

        viewModel.setActive(false)
        #expect(!viewModel.manager.isActive)
        #expect(!viewModel.isAllowListActive)
    }

    // MARK: - Selection Reconciliation

    @Test
    func reconcileClearsSelectionWhenUUIDDisappearsViaReplaceAll() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "a",
            urlPattern: "*a.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        #expect(viewModel.selectedRuleID != nil)

        // External mutation via the manager's public API — selected UUID disappears.
        viewModel.manager.replaceAll([
            AllowListRule(
                name: "z",
                rawPattern: "*z.com*",
                method: nil,
                matchType: .wildcard,
                includeSubpaths: true
            ),
        ])
        viewModel.reconcileSelectionAfterRulesChange()

        #expect(viewModel.selectedRuleID == nil)
    }

    @Test
    func reconcilePreservesSelectionWhenUUIDPresentAfterUpdate() throws {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "orig",
            urlPattern: "*a.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let originalID = try #require(viewModel.selectedRuleID)

        // Update via the manager's public API — UUID still exists.
        var updated = viewModel.manager.rules[0]
        updated.name = "renamed-externally"
        viewModel.manager.updateRule(updated)
        viewModel.reconcileSelectionAfterRulesChange()

        #expect(viewModel.selectedRuleID == originalID)
    }

    @Test
    func reconcileIsNoopWhenNothingSelected() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.selectedRuleID = nil
        viewModel.reconcileSelectionAfterRulesChange()
        #expect(viewModel.selectedRuleID == nil)
    }

    // MARK: - Editor Session (sheet state is identity-driven)

    @Test
    func presentNewRuleEditorAssignsCreateSession() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        #expect(viewModel.editorSession == nil)
        viewModel.presentNewRuleEditor()

        let session = try? #require(viewModel.editorSession)
        if case .create(nil) = session?.mode {
            // expected — blank new rule
        } else {
            Issue.record("expected .create(nil) mode, got \(String(describing: session?.mode))")
        }
    }

    @Test
    func presentEditorForContextAssignsCreateSessionWithContext() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        let tx = TestFixtures.makeTransaction(method: "GET", url: "https://api.github.com/repos")
        let context = AllowListEditorContextBuilder.fromTransaction(tx)
        viewModel.presentEditorForContext(context)

        let session = try? #require(viewModel.editorSession)
        if case let .create(ctx?) = session?.mode {
            #expect(ctx.sourceHost == "api.github.com")
            #expect(ctx.origin == .selectedTransaction)
        } else {
            Issue.record("expected .create with context, got \(String(describing: session?.mode))")
        }
    }

    @Test
    func presentEditorForEditingAssignsEditSession() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "api",
            urlPattern: "*example.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let rule = viewModel.manager.rules[0]
        viewModel.presentEditorForEditing(rule)

        let session = try? #require(viewModel.editorSession)
        if case let .edit(editingRule) = session?.mode {
            #expect(editingRule.id == rule.id)
        } else {
            Issue.record("expected .edit mode, got \(String(describing: session?.mode))")
        }
    }

    @Test
    func dismissEditorClearsSession() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.presentNewRuleEditor()
        #expect(viewModel.editorSession != nil)

        viewModel.dismissEditor()
        #expect(viewModel.editorSession == nil)
    }

    /// Regression: a fresh quick-create while the editor is already open must
    /// replace the current session with a new identity so SwiftUI's
    /// `.sheet(item:)` tears down the old sheet view (dropping its stale
    /// `@State` draft) and re-inits with the new context.
    @Test
    func secondQuickCreateReplacesOpenEditorSessionWithFreshIdentity() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        let firstTx = TestFixtures.makeTransaction(method: "GET", url: "https://first.example.com/a")
        let firstContext = AllowListEditorContextBuilder.fromTransaction(firstTx)
        viewModel.presentEditorForContext(firstContext)

        let firstSession = try? #require(viewModel.editorSession)
        let firstID = firstSession?.id

        // Second quick-create arrives while the sheet is still open.
        let secondTx = TestFixtures.makeTransaction(method: "POST", url: "https://second.example.com/b")
        let secondContext = AllowListEditorContextBuilder.fromTransaction(secondTx)
        viewModel.presentEditorForContext(secondContext)

        let secondSession = try? #require(viewModel.editorSession)
        #expect(secondSession?.id != firstID, "session id must change so .sheet(item:) rebuilds")

        if case let .create(ctx?) = secondSession?.mode {
            #expect(ctx.sourceHost == "second.example.com")
            #expect(ctx.sourceMethod == "POST")
        } else {
            Issue.record("expected second session to carry the new context")
        }
    }

    @Test
    func newRuleAfterEditReplacesSessionWithFreshIdentity() {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "orig",
            urlPattern: "*example.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )
        viewModel.presentEditorForEditing(viewModel.manager.rules[0])
        let editSessionID = viewModel.editorSession?.id

        viewModel.presentNewRuleEditor()
        #expect(viewModel.editorSession?.id != editSessionID)
        if case .create(nil) = viewModel.editorSession?.mode {
            // expected
        } else {
            Issue.record("expected .create(nil) mode after presentNewRuleEditor")
        }
    }

    @Test
    func reconcileClearsSelectionAfterImport() throws {
        let (viewModel, url) = makeSetup()
        defer { cleanup(url) }

        viewModel.addRule(
            ruleName: "orig",
            urlPattern: "*a.com*",
            httpMethod: .any,
            matchType: .wildcard,
            includeSubpaths: true
        )

        // Export then import with different UUIDs (via replaceAll to simulate import side-effect).
        let newRule = AllowListRule(
            name: "imported",
            rawPattern: "*imported.com*",
            method: nil,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let data = try JSONEncoder().encode(
            ImportPayload(schemaVersion: 2, isActive: true, rules: [newRule])
        )
        try viewModel.manager.importRulesJSON(data)
        viewModel.reconcileSelectionAfterRulesChange()

        #expect(viewModel.selectedRuleID == nil)
        #expect(viewModel.manager.rules.count == 1)
        #expect(viewModel.manager.rules[0].name == "imported")
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeSetup() -> (AllowListWindowViewModel, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("allow-list-\(UUID()).json")
        let manager = AllowListManager(storageURL: url)
        return (AllowListWindowViewModel(manager: manager), url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        let legacy = url.deletingLastPathComponent().appendingPathComponent("allow-list.legacy.json")
        try? FileManager.default.removeItem(at: legacy)
    }
}

// MARK: - ImportPayload

/// Mirror of the private `AllowListStorage` shape so we can build fixture import data
/// without needing to expose the internal type.
private struct ImportPayload: Encodable {
    let schemaVersion: Int
    let isActive: Bool
    let rules: [AllowListRule]
}
