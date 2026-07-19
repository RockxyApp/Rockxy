import Foundation
import os

// Defines the UI state for a single workspace tab.

enum ContextDockTab: Equatable {
    case details
    case aiAssistant
}

@MainActor @Observable
final class WorkspaceState: Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        title: String = String(localized: "All Traffic"),
        isClosable: Bool = true,
        initialFilter: FilterCriteria = .empty,
        inspectorLayout: InspectorLayout = .hidden,
        isContextDockVisible: Bool = false,
        allowsAutomaticInspectorReveal: Bool = true
    ) {
        self.id = id
        self.title = title
        self.isClosable = isClosable
        self.filterCriteria = initialFilter
        self.inspectorLayout = inspectorLayout
        self.isContextDockVisible = isContextDockVisible
        self.allowsAutomaticInspectorReveal = allowsAutomaticInspectorReveal
        self.focusSets = FocusSetPersistence.load()
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
    var inspectorLayout: InspectorLayout
    var isContextDockVisible: Bool
    var contextDockTab: ContextDockTab = .details
    var allowsAutomaticInspectorReveal: Bool
    var debugAssistantState: DebugAssistantState = .idle
    var modelInvestigationState: ModelInvestigationState = .idle
    var debugAssistantMessages: [DebugAssistantMessage] = []
    var debugAssistantDraft = ""
    var debugAssistantConversationID = UUID()
    var debugAssistantConversationTitle = String(localized: "New Conversation")
    var debugAssistantConversationCreatedAt = Date()
    var debugAssistantConversationUpdatedAt = Date()
    var debugAssistantConversations: [DebugAssistantConversation] = []
    var debugAssistantUsesConfiguredModel = true
    var debugAssistantReviewPack: InvestigationContextPack?
    var debugAssistantReviewConfiguration: AssistantProviderConfiguration?
    var debugAssistantReviewModelAccessEnabled = false
    var isPreparingDebugAssistantReview = false
    var focusNavigatorMode: FocusNavigatorMode = .browse
    var activeTrafficSignal: TrafficSignal?
    var focusSets: [FocusSet] = []
    var activeFocusSetID: UUID?
    var mutedTrafficSources: Set<MutedTrafficSource> = []

    // Selection
    var selectedTransaction: HTTPTransaction?
    var selectedLogEntry: LogEntry?
    var selectedTransactionIDs: Set<UUID> = []

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
    var totalDomainCount = 0
    var domainIndexMap: [String: Int] = [:]
    var domainGroupingIndex = DomainGroupingIndex()
    var appNodes: [AppInfo] = []
    var appNodeIndexMap: [String: Int] = [:]

    var activeFocusSet: FocusSet? {
        focusSets.first { $0.id == activeFocusSetID }
    }

    func reset() {
        filteredTransactions.removeAll()
        filteredRows.removeAll()
        refreshToken += 1
        // activeSortDescriptors intentionally preserved — sort is a user preference
        selectedTransaction = nil
        selectedLogEntry = nil
        selectedTransactionIDs.removeAll()
        debugAssistantState = .idle
        modelInvestigationState = .idle
        debugAssistantMessages.removeAll()
        debugAssistantDraft = ""
        debugAssistantConversationID = UUID()
        debugAssistantConversationTitle = String(localized: "New Conversation")
        debugAssistantConversationCreatedAt = Date()
        debugAssistantConversationUpdatedAt = Date()
        debugAssistantConversations.removeAll()
        debugAssistantReviewPack = nil
        debugAssistantReviewConfiguration = nil
        debugAssistantReviewModelAccessEnabled = false
        isPreparingDebugAssistantReview = false
        domainTree.removeAll()
        totalDomainCount = 0
        domainIndexMap.removeAll()
        domainGroupingIndex.removeAll()
        appNodes.removeAll()
        appNodeIndexMap.removeAll()
    }
}
