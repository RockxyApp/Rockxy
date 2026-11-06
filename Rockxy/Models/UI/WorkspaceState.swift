import Foundation
import os

// MARK: - ContextDockTab

// Defines the UI state for a single workspace tab.

enum ContextDockTab: Equatable {
    case details
    case aiAssistant
}

// MARK: - TrafficSelectionIndexEntry

struct TrafficSelectionIndexEntry {
    let transaction: HTTPTransaction
    let rowIndex: Int
}

// MARK: - TrafficRevealRequest

/// One-shot request for the AppKit request table to scroll a specific transaction into view.
///
/// The `generation` is a strictly increasing per-workspace token so the table can distinguish a
/// brand-new reveal from a value it has already consumed — even when the same `transactionID` is
/// targeted repeatedly (e.g. jumping to Last twice in a row on an unchanged view). Equatable
/// identity therefore hinges on `generation`, never on `transactionID` alone.
struct TrafficRevealRequest: Equatable {
    let transactionID: UUID
    let generation: Int
}

// MARK: - WorkspaceState

@MainActor @Observable
final class WorkspaceState: Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        title: String = String(localized: "All Traffic", bundle: RockxyLocalization.bundle),
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
    var sidebarSelection: SidebarItem? = .allApps
    var inspectorTab: InspectorTab = .headers
    var inspectorLayout: InspectorLayout
    var isContextDockVisible: Bool
    var contextDockTab: ContextDockTab = .details
    var allowsAutomaticInspectorReveal: Bool
    var debugAssistantState: DebugAssistantState = .idle
    var modelInvestigationState: ModelInvestigationState = .idle
    var debugAssistantProductHelpState: DebugAssistantProductHelpState = .idle
    var debugAssistantMessages: [DebugAssistantMessage] = []
    var debugAssistantDraft = ""
    var debugAssistantConversationID = UUID()
    var debugAssistantConversationTitle = String(localized: "New Conversation", bundle: RockxyLocalization.bundle)
    var debugAssistantConversationCreatedAt = Date()
    var debugAssistantConversationUpdatedAt = Date()
    var debugAssistantConversationContext: DebugAssistantConversationContext?
    var debugAssistantConversations: [DebugAssistantConversation] = []
    var debugAssistantUsesConfiguredModel = true
    var debugAssistantTrafficScope = AssistantTrustPolicy.defaultTrafficScope
    var debugAssistantReviewPack: InvestigationContextPack?
    var debugAssistantReviewRequest: AssistantCompletionRequest?
    var debugAssistantReviewConfiguration: AssistantProviderConfiguration?
    var debugAssistantReviewTrafficScope: AssistantTrafficScope?
    var debugAssistantReviewModelAccessEnabled = false
    var debugAssistantReviewSummary: DebugAssistantReviewSummary?
    var debugAssistantRequestedContextCount = 0
    var isPreparingDebugAssistantReview = false
    var isPreparingDebugAssistantReviewOverride = false
    var isDebugAssistantComposerFocusRequested = false
    var focusNavigatorMode: FocusNavigatorMode = .browse

    /// Report state for the Insights destination. Owned per Traffic Tab so scope, window,
    /// metric, and the last report survive switching tabs and closing the sidebar row.
    @ObservationIgnored let trafficInsights = TrafficInsightsViewModel()
    var activeTrafficSignal: TrafficSignal?
    var focusSets: [FocusSet] = []
    var activeFocusSetID: UUID?
    var mutedTrafficSources: Set<MutedTrafficSource> = []

    // Selection
    var selectedTransaction: HTTPTransaction?
    var selectedLogEntry: LogEntry?
    var selectedTransactionIDs: Set<UUID> = []

    /// One-shot request for the request table to scroll a transaction into view. Published by the
    /// coordinator's Jump-to-First/Last commands and consumed by the AppKit table, which tracks its
    /// last applied generation. Reset with the rest of the workspace selection state.
    var trafficRevealRequest: TrafficRevealRequest?

    /// Opt-in live-tail mode for this workspace. New visible traffic becomes the primary
    /// selection until the user deliberately selects a row, at which point the mode yields.
    /// Owned per-workspace so an inactive workspace can keep advancing independently.
    var isFollowingLiveTraffic = false

    // Filtering
    var filterCriteria: FilterCriteria = .empty
    var filterRules: [FilterRule] = [FilterRule()]
    var isFilterBarVisible: Bool = false
    var filteredTransactions: [HTTPTransaction] = []

    // Table-facing derived state (derived from filteredTransactions via deriveFilteredRows)
    var filteredRows: [RequestListRow] = []
    @ObservationIgnored var trafficSelectionIndex: [UUID: TrafficSelectionIndexEntry] = [:]
    var refreshToken: Int = 0

    /// Set true only by the genuine append fast-path in appendFilteredTransactions, and
    /// cleared by deriveFilteredRows (and reset) once a full derivation replaces the rows.
    /// The table reads this as the coarse "the last mutation only appended rows" signal.
    var lastDeriveWasAppendOnly: Bool = false

    /// Provenance for the append fast-path: the refreshToken of the base state that the
    /// current unbroken run of pure appends builds on. `nil` whenever the last row mutation
    /// was not a pure append (recompute, sort, enrichment, eviction, delete, reset). The
    /// first append of a chain records the pre-append token and later coalesced appends
    /// preserve it, so the request table can insert rows incrementally only when this origin
    /// is <= the token it has already applied — otherwise a non-append mutation was coalesced
    /// ahead of the append and the displayed prefix no longer matches the model.
    var appendChainOriginToken: Int?

    /// Provenance for the in-place rewrite fast-path, the counterpart of `appendChainOriginToken`
    /// for mutations that replace existing rows without adding, removing, or moving any.
    /// Client-app enrichment and live-stream refreshes are such mutations, and they land on
    /// every delivery batch for as long as capture runs. `origin` is the `refreshToken` of the
    /// base state the unbroken run of rewrites builds on, `tail` the token the last rewrite
    /// produced, and `indexes` every row index rewritten since `origin`.
    ///
    /// The chain is only trusted while `tail == refreshToken`. Every other row mutation bumps
    /// the token without touching these fields, so it retires the chain by itself and a new
    /// mutation path cannot forget to clear it.
    @ObservationIgnored private(set) var rewriteChainOriginToken: Int?
    /// Sort state (user preference, persists across session clears)
    var activeSortDescriptors: [NSSortDescriptor] = []

    // Sidebar (per-workspace view of captured data)
    var domainTree: [DomainNode] = []
    var totalDomainCount = 0
    var domainIndexMap: [String: Int] = [:]
    var domainGroupingIndex = DomainGroupingIndex()

    /// The `rootOrderRevision` `domainIndexMap` was last built for. Maintenance state, so
    /// `@ObservationIgnored`: nothing reads it but `refreshDomainTree`, which uses it to
    /// skip rebuilding the map on the batches that only changed counts. The root list is
    /// the one sidebar collection sized by the whole session rather than by the history
    /// cap, so rebuilding its map ten times a second was a cost that rose with capture
    /// length.
    @ObservationIgnored var domainIndexRevision: UInt?
    @ObservationIgnored var sidebarIndexSignature: [String?]?
    @ObservationIgnored var sidebarTransactionRevisions: [ObjectIdentifier: UInt64] = [:]
    @ObservationIgnored var rowProjectionLocale: String?
    var appNodes: [AppInfo] = []
    var appNodeIndexMap: [String: Int] = [:]
    var appGroupingIndex = AppGroupingIndex()

    /// The unbroken in-place rewrite run ending at the current `refreshToken`, if any.
    var activeRewriteChain: (originToken: Int, rowIndexes: IndexSet)? {
        guard let origin = rewriteChainOriginToken,
              rewriteChainTailToken == refreshToken else
        {
            return nil
        }
        return (origin, rewrittenRowIndexSet)
    }

    var activeFocusSet: FocusSet? {
        focusSets.first { $0.id == activeFocusSetID }
    }

    /// Publishes a rewrite of the rows at `indexes`: same count, same order, same identities.
    /// Replaces the append provenance (an append after this must not be inserted against a
    /// prefix that was just mutated) and extends or starts the rewrite chain.
    func recordInPlaceRowRewrite(at indexes: IndexSet) {
        lastDeriveWasAppendOnly = false
        appendChainOriginToken = nil
        if rewriteChainTailToken == refreshToken, rewriteChainOriginToken != nil {
            rewrittenRowIndexSet.formUnion(indexes)
        } else {
            rewriteChainOriginToken = refreshToken
            rewrittenRowIndexSet = indexes
        }
        refreshToken += 1
        rewriteChainTailToken = refreshToken
    }

    /// Publishes a fresh reveal request for `transactionID`, advancing the monotonic generation so
    /// the value differs from any previously consumed request — including a repeat of the same
    /// endpoint. The counter is never reset for the workspace's lifetime, guaranteeing one-shot
    /// identity even across session clears.
    func publishTrafficRevealRequest(for transactionID: UUID) {
        trafficRevealGeneration += 1
        trafficRevealRequest = TrafficRevealRequest(
            transactionID: transactionID,
            generation: trafficRevealGeneration
        )
    }

    func reset() {
        filteredTransactions.removeAll()
        filteredRows.removeAll()
        trafficSelectionIndex.removeAll()
        lastDeriveWasAppendOnly = false
        appendChainOriginToken = nil
        refreshToken += 1
        // activeSortDescriptors intentionally preserved — sort is a user preference
        selectedTransaction = nil
        selectedLogEntry = nil
        selectedTransactionIDs.removeAll()
        trafficRevealRequest = nil
        debugAssistantState = .idle
        modelInvestigationState = .idle
        debugAssistantProductHelpState = .idle
        debugAssistantMessages.removeAll()
        debugAssistantDraft = ""
        debugAssistantConversationID = UUID()
        debugAssistantConversationTitle = String(localized: "New Conversation", bundle: RockxyLocalization.bundle)
        debugAssistantConversationCreatedAt = Date()
        debugAssistantConversationUpdatedAt = Date()
        debugAssistantConversationContext = nil
        debugAssistantConversations.removeAll()
        debugAssistantTrafficScope = AssistantTrustPolicy.defaultTrafficScope
        debugAssistantReviewPack = nil
        debugAssistantReviewRequest = nil
        debugAssistantReviewConfiguration = nil
        debugAssistantReviewTrafficScope = nil
        debugAssistantReviewModelAccessEnabled = false
        debugAssistantReviewSummary = nil
        debugAssistantRequestedContextCount = 0
        isPreparingDebugAssistantReview = false
        isPreparingDebugAssistantReviewOverride = false
        isDebugAssistantComposerFocusRequested = false
        domainTree.removeAll()
        totalDomainCount = 0
        domainIndexMap.removeAll()
        domainIndexRevision = nil
        domainGroupingIndex.removeAll()
        sidebarIndexSignature = nil
        sidebarTransactionRevisions.removeAll()
        rowProjectionLocale = nil
        appNodes.removeAll()
        appNodeIndexMap.removeAll()
        appGroupingIndex.removeAll()
    }

    // MARK: Private

    @ObservationIgnored private var rewriteChainTailToken: Int?
    @ObservationIgnored private var rewrittenRowIndexSet = IndexSet()

    /// Monotonic backing counter for `trafficRevealRequest`. Deliberately never reset so reveal
    /// generations stay strictly increasing across the workspace's lifetime.
    @ObservationIgnored private var trafficRevealGeneration = 0
}
