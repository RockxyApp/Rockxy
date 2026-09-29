import Foundation
@testable import Rockxy
import Testing

// MARK: - TrafficSplitViewTests

@MainActor
struct TrafficSplitViewTests {
    @Test("A companion pane is not a tab and focusing it changes the active workspace")
    func storeCompanionLifecycle() throws {
        let store = WorkspaceStore()
        let tab = store.activeTab
        let companion = try #require(store.openSplit(for: tab.id))

        #expect(store.workspaces.count == 1)
        #expect(store.allWorkspaces.map(\.id) == [tab.id, companion.id])
        #expect(store.activeWorkspace === companion)
        #expect(store.activeWorkspaceID == tab.id)
        #expect(store.ownerTabID(ofCompanion: companion.id) == tab.id)

        store.focusPane(tab.id)
        #expect(store.activeWorkspace === tab)
        store.focusPane(companion.id)
        #expect(store.activeWorkspace === companion)

        // Opening again reuses the pane rather than adding a third.
        #expect(store.openSplit(for: tab.id) === companion)

        store.closeSplit(for: tab.id)
        #expect(store.activeWorkspace === tab)
        #expect(store.allWorkspaces.count == 1)
    }

    @Test("Closing a tab or switching Projects drops its companion pane")
    func companionFollowsItsTab() throws {
        let store = WorkspaceStore()
        let second = store.createWorkspace(title: "API")
        _ = try #require(store.openSplit(for: second.id))
        #expect(store.canCreateWorkspace)

        store.closeWorkspace(id: second.id)
        #expect(store.splitCompanion(for: second.id) == nil)
        #expect(store.allWorkspaces.count == store.workspaces.count)

        let first = store.activeTab
        _ = store.openSplit(for: first.id)
        store.applyTabSnapshots(store.captureTabSnapshots(), activeTabID: first.id)
        #expect(store.splitCompanion(for: first.id) == nil)
    }

    @Test("Community builds refuse split view; a policy that allows it opens the pane")
    func policyGate() {
        let community = MainContentCoordinator()
        #expect(!community.canUseTrafficSplitView)
        #expect(!community.showTrafficSplitView())
        #expect(!community.isTrafficSplitViewVisible)
        #expect(community.activeToast?.text == "Split view is unavailable in this build.")

        let pro = MainContentCoordinator(policy: SplitViewPolicy())
        #expect(pro.showTrafficSplitView())
        #expect(pro.isTrafficSplitViewVisible)
        pro.hideTrafficSplitView()
        #expect(!pro.isTrafficSplitViewVisible)
    }

    @Test("Both panes stay live and keep their own filter and selection")
    func panesAreIndependent() throws {
        let coordinator = MainContentCoordinator(policy: SplitViewPolicy())
        let api = TestFixtures.makeTransaction(url: "https://api.example.com/users")
        let cdn = TestFixtures.makeTransaction(url: "https://cdn.example.org/logo.png")
        api.assignCaptureContextIfMissing(coordinator.activeCaptureContext)
        cdn.assignCaptureContextIfMissing(coordinator.activeCaptureContext)
        coordinator.processBatch([api], generation: coordinator.sessionGeneration)

        var cdnOnly = FilterCriteria.empty
        cdnOnly.sidebarDomain = "cdn.example.org"
        #expect(coordinator.showTrafficSplitView(filter: cdnOnly))
        let secondary = try #require(coordinator.secondaryTrafficPane)
        let primary = coordinator.primaryTrafficPane

        // A batch captured while the second pane has focus reaches both panes.
        coordinator.processBatch([cdn], generation: coordinator.sessionGeneration)
        #expect(primary.filteredTransactions.map(\.id) == [api.id, cdn.id])
        #expect(secondary.filteredTransactions.map(\.id) == [cdn.id])

        // Selecting in the unfocused primary pane changes only that pane.
        #expect(coordinator.activeWorkspace === secondary)
        coordinator.selectTransactions([api.id], primaryID: api.id, in: primary)
        #expect(primary.selectedTransaction === api)
        #expect(secondary.selectedTransactionIDs.isEmpty)
        #expect(coordinator.activeWorkspace === secondary)

        coordinator.focusTrafficPane(primary)
        #expect(coordinator.selectedTransaction === api)
    }

    @Test("Opening a source in split view reuses the open pane with the new filter")
    func openSourceReusesPane() throws {
        let coordinator = MainContentCoordinator(policy: SplitViewPolicy())
        var first = FilterCriteria.empty
        first.sidebarApp = "Safari"
        coordinator.showTrafficSplitView(filter: first)
        let pane = try #require(coordinator.secondaryTrafficPane)

        var second = FilterCriteria.empty
        second.sidebarApp = "curl"
        coordinator.focusTrafficPane(coordinator.primaryTrafficPane)
        coordinator.showTrafficSplitView(filter: second)

        #expect(coordinator.secondaryTrafficPane === pane)
        #expect(pane.filterCriteria.sidebarApp == "curl")
        #expect(coordinator.activeWorkspace === pane)
    }
}

// MARK: - SplitViewPolicy

private struct SplitViewPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
    let allowsTrafficSplitView = true
}
