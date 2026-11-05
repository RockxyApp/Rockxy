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

    /// How recent `refreshToken` bumps changed the row set, oldest first. See `recordRowChange`.
    @ObservationIgnored private(set) var rowChangeLedger: [RowChangeStep] = []

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
        recordRowChange(removedHead: 0, appended: 0, rewritten: indexes)
    }

    /// Appends the ledger entry for the mutation that just produced `refreshToken`.
    ///
    /// Call it immediately after the token bump. Each entry says how the row set at
    /// `refreshToken - 1` became the row set at `refreshToken`: rows removed from the head,
    /// rows added at the tail, and which surviving rows were replaced. A mutation that does
    /// not record an entry leaves a hole in the sequence, and the table then falls back to a
    /// full reload rather than guess -- so a new mutation path cannot forget to retire it.
    func recordRowChange(removedHead: Int, appended: Int, rewritten: IndexSet) {
        rowChangeLedger.append(
            RowChangeStep(
                token: refreshToken,
                removedHead: removedHead,
                appended: appended,
                rewritten: rewritten
            )
        )
        if rowChangeLedger.count > Self.rowChangeLedgerLimit {
            rowChangeLedger.removeFirst(rowChangeLedger.count - Self.rowChangeLedgerLimit)
        }
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

    /// Entries kept for the table to compose. A refresh coalesces a handful of mutations at
    /// most; a table further behind than this reloads instead.
    private static let rowChangeLedgerLimit = 32

    @ObservationIgnored private var rewriteChainTailToken: Int?
    @ObservationIgnored private var rewrittenRowIndexSet = IndexSet()

    /// Monotonic backing counter for `trafficRevealRequest`. Deliberately never reset so reveal
    /// generations stay strictly increasing across the workspace's lifetime.
    @ObservationIgnored private var trafficRevealGeneration = 0
}

// MARK: - RowChangeStep

/// One row-set mutation, as the table needs it to update without a full reload.
struct RowChangeStep: Equatable {
    /// The `refreshToken` this mutation produced.
    let token: Int
    /// Rows dropped from the front, in the coordinates of the set before the mutation.
    let removedHead: Int
    /// Rows added at the end.
    let appended: Int
    /// Surviving rows that were replaced, in the coordinates of the set after the mutation.
    let rewritten: IndexSet
}

// MARK: - RowChangeWindow

/// The net effect of a run of consecutive `RowChangeStep`s on the row set a table last drew.
struct RowChangeWindow: Equatable {
    /// Rows to drop from the front of the set the table last drew.
    var removedHead = 0
    /// Rows to add at the end of the new set.
    var appended = 0
    /// Rows of the new set that survived from the old one and were replaced, in new coordinates.
    var rewritten = IndexSet()

    /// Composes the steps for tokens `oldToken + 1 ... newToken`, or nil when the ledger
    /// does not cover that run exactly or a step removes rows an earlier step appended
    /// (the net effect is then no longer a head trim plus a tail append).
    static func compose(
        _ ledger: [RowChangeStep],
        after oldToken: Int,
        through newToken: Int,
        startingRowCount: Int
    )
        -> RowChangeWindow?
    {
        guard newToken > oldToken else {
            return nil
        }
        let steps = ledger.filter { $0.token > oldToken && $0.token <= newToken }
        guard steps.count == newToken - oldToken,
              zip(steps, (oldToken + 1) ... newToken).allSatisfy({ $0.token == $1 }) else
        {
            return nil
        }
        var window = RowChangeWindow()
        var count = startingRowCount
        for step in steps {
            guard step.removedHead >= 0,
                  step.appended >= 0,
                  step.removedHead <= count - window.appended else
            {
                return nil
            }
            if step.removedHead > 0 {
                window.rewritten.remove(integersIn: 0 ..< step.removedHead)
                window.rewritten.shift(startingAt: step.removedHead, by: -step.removedHead)
                window.removedHead += step.removedHead
            }
            count += step.appended - step.removedHead
            window.appended += step.appended
            window.rewritten.formUnion(step.rewritten)
        }
        // AppKit traps on a batch that nets smaller. Inside one
        // `beginUpdates`/`endUpdates`, `removeRows` followed by `insertRows` is reconciled
        // against a data source that already reports the final count, and a net shrink fails
        // that reconciliation -- measured directly against a real `NSTableView`: removing 6
        // and appending 5 aborts the process, while removing 5 and appending 5 or 6 is
        // accepted. The steady state at the history cap evicts exactly what it appends, so
        // the fast path still covers it; a batch that nets smaller reloads instead.
        guard window.appended >= window.removedHead else {
            return nil
        }
        // Rows in the appended region are inserted from the current set, never reloaded.
        window.rewritten = window.rewritten.intersection(IndexSet(integersIn: 0 ..< (count - window.appended)))
        return window
    }
}
