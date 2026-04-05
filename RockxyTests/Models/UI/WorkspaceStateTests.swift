import Foundation
@testable import Rockxy
import Testing

// Regression tests for `WorkspaceState` in the models ui layer.

@MainActor
struct WorkspaceStateTests {
    @Test("Default workspace initializes with expected defaults")
    func defaultInit() {
        let workspace = WorkspaceState()
        #expect(workspace.title == String(localized: "All Traffic"))
        #expect(workspace.isClosable == true)
        #expect(workspace.activeMainTab == .traffic)
        #expect(workspace.sidebarSelection == nil)
        #expect(workspace.inspectorTab == .headers)
        #expect(workspace.inspectorLayout == .hidden)
        #expect(workspace.selectedTransaction == nil)
        #expect(workspace.selectedLogEntry == nil)
        #expect(workspace.filterCriteria.isEmpty)
        #expect(workspace.filterRules.count == 1)
        #expect(workspace.isFilterBarVisible == false)
        #expect(workspace.filteredTransactions.isEmpty)
        #expect(workspace.domainTree.isEmpty)
        #expect(workspace.appNodes.isEmpty)
    }

    @Test("Custom workspace initializes with provided values")
    func customInit() {
        let filter = FilterCriteria(searchText: "api", isSearchEnabled: true)
        let workspace = WorkspaceState(
            title: "API Traffic",
            isClosable: true,
            initialFilter: filter
        )
        #expect(workspace.title == "API Traffic")
        #expect(workspace.isClosable == true)
        #expect(workspace.filterCriteria.searchText == "api")
    }

    @Test("Non-closable workspace preserves flag")
    func nonClosable() {
        let workspace = WorkspaceState(title: "Default", isClosable: false)
        #expect(workspace.isClosable == false)
    }

    @Test("Each workspace has unique ID")
    func uniqueIDs() {
        let ws1 = WorkspaceState()
        let ws2 = WorkspaceState()
        #expect(ws1.id != ws2.id)
    }

    @Test("Reset clears mutable state but preserves identity")
    func resetPreservesIdentity() {
        let workspace = WorkspaceState(title: "Test")
        let originalID = workspace.id
        let originalTitle = workspace.title

        // Mutate state
        workspace.activeMainTab = .logs
        workspace.filteredTransactions = [TestFixtures.makeTransaction()]
        workspace.selectedTransaction = TestFixtures.makeTransaction()
        workspace.domainTree = [DomainNode(id: "test", domain: "test.com", requestCount: 1, children: [])]

        workspace.reset()

        #expect(workspace.id == originalID)
        #expect(workspace.title == originalTitle)
        #expect(workspace.filteredTransactions.isEmpty)
        #expect(workspace.selectedTransaction == nil)
        #expect(workspace.selectedLogEntry == nil)
        #expect(workspace.domainTree.isEmpty)
        #expect(workspace.appNodes.isEmpty)
        // activeMainTab is NOT reset (navigation state preserved)
    }

    @Test("Workspace state is independent between instances")
    func stateIndependence() {
        let ws1 = WorkspaceState(title: "Tab 1")
        let ws2 = WorkspaceState(title: "Tab 2")

        ws1.activeMainTab = .logs
        ws1.isFilterBarVisible = true
        ws1.selectedTransaction = TestFixtures.makeTransaction()

        #expect(ws2.activeMainTab == .traffic)
        #expect(ws2.isFilterBarVisible == false)
        #expect(ws2.selectedTransaction == nil)
    }

    @Test("Workspace accepts sidebar domain filter")
    func sidebarDomainFilter() {
        var filter = FilterCriteria.empty
        filter.sidebarDomain = "example.com"
        let workspace = WorkspaceState(title: "example.com", initialFilter: filter)
        #expect(workspace.filterCriteria.sidebarDomain == "example.com")
        #expect(!workspace.filterCriteria.isEmpty)
    }

    @Test("Workspace accepts sidebar app filter")
    func sidebarAppFilter() {
        var filter = FilterCriteria.empty
        filter.sidebarApp = "Safari"
        let workspace = WorkspaceState(title: "Safari", initialFilter: filter)
        #expect(workspace.filterCriteria.sidebarApp == "Safari")
    }

    @Test("Reset preserves sort descriptors")
    func resetPreservesSortDescriptors() {
        let workspace = WorkspaceState()
        workspace.activeSortDescriptors = [NSSortDescriptor(key: "url", ascending: true)]
        workspace.filteredRows = [RequestListRow(from: TestFixtures.makeTransaction())]

        workspace.reset()

        #expect(!workspace.activeSortDescriptors.isEmpty)
        #expect(workspace.activeSortDescriptors.first?.key == "url")
        #expect(workspace.filteredRows.isEmpty)
    }

    @Test("Reset clears filteredRows and increments refreshToken")
    func resetClearsRowsAndToken() {
        let workspace = WorkspaceState()
        workspace.filteredRows = [RequestListRow(from: TestFixtures.makeTransaction())]
        let tokenBefore = workspace.refreshToken

        workspace.reset()

        #expect(workspace.filteredRows.isEmpty)
        #expect(workspace.refreshToken > tokenBefore)
    }
}
