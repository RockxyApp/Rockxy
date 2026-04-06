import Foundation
import os

// Defines the UI state for a single workspace tab.

@MainActor @Observable
final class WorkspaceState: Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        title: String = String(localized: "All Traffic"),
        isClosable: Bool = true,
        initialFilter: FilterCriteria = .empty
    ) {
        self.id = id
        self.title = title
        self.isClosable = isClosable
        self.filterCriteria = initialFilter
    }

    // MARK: Internal

    static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WorkspaceState")

    let id: UUID
    var title: String
    var isClosable: Bool

    // Navigation
    var activeMainTab: MainTab = .traffic
    var sidebarSelection: SidebarItem?
    var inspectorTab: InspectorTab = .headers
    var inspectorLayout: InspectorLayout = .hidden

    // Selection
    var selectedTransaction: HTTPTransaction?
    var selectedLogEntry: LogEntry?

    // Filtering
    var filterCriteria: FilterCriteria = .empty
    var filterRules: [FilterRule] = [FilterRule()]
    var isFilterBarVisible: Bool = false
    var filteredTransactions: [HTTPTransaction] = []

    // Table-facing derived state (derived from filteredTransactions via deriveFilteredRows)
    var filteredRows: [RequestListRow] = []
    var refreshToken: Int = 0

    /// Set true only by the genuine append fast-path in appendFilteredTransactions.
    /// The table checks this to decide between insertRows (safe append) and reloadData.
    /// Reset to false by deriveFilteredRows after each derivation cycle.
    var lastDeriveWasAppendOnly: Bool = false

    /// Sort state (user preference, persists across session clears)
    var activeSortDescriptors: [NSSortDescriptor] = []

    // Sidebar (per-workspace view of captured data)
    var domainTree: [DomainNode] = []
    var domainIndexMap: [String: Int] = [:]
    var appNodes: [AppInfo] = []
    var appNodeIndexMap: [String: Int] = [:]

    func reset() {
        filteredTransactions.removeAll()
        filteredRows.removeAll()
        refreshToken += 1
        // activeSortDescriptors intentionally preserved — sort is a user preference
        selectedTransaction = nil
        selectedLogEntry = nil
        domainTree.removeAll()
        domainIndexMap.removeAll()
        appNodes.removeAll()
        appNodeIndexMap.removeAll()
    }
}
