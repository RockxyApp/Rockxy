import Foundation

// Extends `MainContentCoordinator` with selection behavior for the main workspace.

// MARK: - MainContentCoordinator + Selection

/// Coordinator extension for tracking the currently selected transaction, log entry,
/// and sidebar item across the three-column layout.
extension MainContentCoordinator {
    // MARK: - Selection Management

    func selectTransaction(_ transaction: HTTPTransaction?) {
        selectedTransaction = transaction
    }

    /// Applies a request-table selection as one coordinator transition. The table-facing
    /// indexes keep this path proportional to the number of selected rows instead of the
    /// total captured history, which is critical when the inspector opens over large sessions.
    /// `workspace` names the traffic pane whose table changed; it defaults to the focused one.
    func selectTransactions(_ ids: Set<UUID>, primaryID: UUID?, in pane: WorkspaceState? = nil) {
        let workspace = pane ?? activeWorkspace
        let isFocusedPane = workspace === activeWorkspace

        func validEntry(for id: UUID) -> TrafficSelectionIndexEntry? {
            guard let entry = workspace.trafficSelectionIndex[id],
                  workspace.filteredRows.indices.contains(entry.rowIndex),
                  workspace.filteredRows[entry.rowIndex].id == id else
            {
                return nil
            }
            return entry
        }

        let resolvedPrimaryID: UUID? = if let primaryID,
                                          ids.contains(primaryID),
                                          validEntry(for: primaryID) != nil
        {
            primaryID
        } else {
            ids.min { lhs, rhs in
                (validEntry(for: lhs)?.rowIndex ?? .max)
                    < (validEntry(for: rhs)?.rowIndex ?? .max)
            }
        }
        let transaction = resolvedPrimaryID.flatMap { validEntry(for: $0)?.transaction }
        let selectionChanged = workspace.selectedTransactionIDs != ids
            || workspace.selectedTransaction?.id != transaction?.id

        workspace.selectedTransactionIDs = ids
        workspace.selectedTransaction = transaction

        guard isFocusedPane else {
            return
        }
        if selectionChanged {
            resetDebugAssistantForSelectionChange()
        }
        if transaction != nil {
            revealInspectorForSelectionIfNeeded()
        }
    }

    /// Enables or disables live-tail selection on the active workspace. Enabling immediately
    /// reveals the newest request already visible in the active workspace so the control has an
    /// observable result even before another capture batch arrives; on an empty view it stays armed.
    ///
    /// Follow Live is deliberately chronological, so enabling reconciles against the active
    /// workspace's `filteredTransactions` (received order) rather than the display-sorted jump path.
    func setFollowingLiveTraffic(_ isEnabled: Bool) {
        isFollowingLiveTraffic = isEnabled
        guard isEnabled else {
            return
        }
        reconcileFollowLiveSelection(for: activeWorkspace)
    }

    func toggleFollowingLiveTraffic() {
        setFollowingLiveTraffic(!isFollowingLiveTraffic)
    }

    /// User-driven table navigation yields Follow Live for the active workspace. The request
    /// table suppresses this callback for coordinator-owned selection and scrolling updates.
    func userDidNavigateTrafficHistory() {
        isFollowingLiveTraffic = false
    }

    /// Advances live-tail selection for every workspace with Follow Live enabled — including
    /// inactive ones — using each workspace's own scope and filters. Workspaces without the mode
    /// keep their current selection.
    func followLatestVisibleTransaction(from batch: [HTTPTransaction]) {
        guard !batch.isEmpty else {
            return
        }
        for workspace in workspaceStore.allWorkspaces {
            reconcileFollowLiveSelection(for: workspace, acceptedBatch: batch)
        }
    }

    /// Reconciles a single workspace's Follow Live selection against its current filtered view.
    ///
    /// - With `acceptedBatch`, this is a batch-driven advance: the selection moves only when the
    ///   batch contributed a newly-visible transaction; otherwise the workspace stays armed and
    ///   keeps its current selection.
    /// - Without a batch (`nil`), this is a filter/scope reconcile: the selection snaps to the
    ///   newest currently-visible transaction, or clears any stale hidden selection while staying
    ///   armed when nothing is visible.
    ///
    /// The newest transaction is always taken from `filteredTransactions` (chronological), never
    /// the display-sorted `filteredRows`, so a custom column sort cannot change the chosen row.
    func reconcileFollowLiveSelection(
        for workspace: WorkspaceState,
        acceptedBatch batch: [HTTPTransaction]? = nil
    ) {
        guard workspace.isFollowingLiveTraffic else {
            return
        }

        let newest: HTTPTransaction?
        if let batch {
            let candidateIDs = Set(batch.map(\.id))
            newest = workspace.filteredTransactions.last { candidateIDs.contains($0.id) }
        } else {
            newest = workspace.filteredTransactions.last
        }

        guard let newest else {
            if batch == nil {
                clearFollowLiveSelection(in: workspace)
            }
            return
        }
        applyFollowLiveSelection(newest, in: workspace)
    }

    /// Applies a Follow Live selection. The active workspace routes through the coordinator
    /// selection path so inspector/assistant side effects fire; inactive workspaces are mutated
    /// directly to avoid triggering the active workspace's side effects.
    private func applyFollowLiveSelection(_ transaction: HTTPTransaction, in workspace: WorkspaceState) {
        if workspace === activeWorkspace {
            selectedTransactionIDs = [transaction.id]
            selectTransaction(transaction)
        } else {
            workspace.selectedTransactionIDs = [transaction.id]
            workspace.selectedTransaction = transaction
        }
    }

    /// Clears a stale Follow Live selection when nothing is currently visible, keeping the mode armed.
    private func clearFollowLiveSelection(in workspace: WorkspaceState) {
        if workspace === activeWorkspace {
            guard selectedTransaction != nil || !selectedTransactionIDs.isEmpty else {
                return
            }
            selectedTransactionIDs = []
            selectTransaction(nil)
        } else {
            workspace.selectedTransactionIDs = []
            workspace.selectedTransaction = nil
        }
    }

    func selectLogEntry(_ entry: LogEntry?) {
        selectedLogEntry = entry
    }

    func selectSidebarItem(_ item: SidebarItem?) {
        sidebarSelection = item

        // Any traffic-scoped selection leaves the Insights report. The report row clears the
        // sidebar scope like Apps or Domains and swaps the center content; search, protocol,
        // advanced, signal, focus-set, and noise filters keep applying to its Visible scope.
        if item == .insights {
            activeMainTab = .insights
        } else if activeMainTab == .insights {
            activeMainTab = .traffic
        }

        guard let item else {
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
            return
        }

        switch item {
        case let .domainNode(domain):
            filterCriteria.sidebarDomain = domain
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        case let .domainPath(domain, pathPrefix):
            filterCriteria.sidebarDomain = domain
            filterCriteria.sidebarPathPrefix = pathPrefix
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        case let .app(name, _):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = name
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        case .allApps,
             .allDomains,
             .insights:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        case .allSaved:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .saved
            filterCriteria.exactTransactionID = nil
            selectTransaction(nil)
            recomputeFilteredTransactions()
        case .allPinned:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .pinned
            filterCriteria.exactTransactionID = nil
            selectTransaction(nil)
            recomputeFilteredTransactions()
        case let .pinnedTransaction(id):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .pinned
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
            selectTransaction(transaction(for: id))
        case let .savedTransaction(id):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .saved
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
            selectTransaction(transaction(for: id))
        case .allNotes:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .notes
            filterCriteria.exactTransactionID = nil
            selectTransaction(nil)
            recomputeFilteredTransactions()
        case let .noteTransaction(id):
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .notes
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
            selectTransaction(transaction(for: id))
        default:
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
            filterCriteria.exactTransactionID = nil
            recomputeFilteredTransactions()
        }
    }

    func deleteSelectedTransaction() {
        var selected = resolveSelectedTransactions()
        if selected.isEmpty, let selectedTransaction {
            selected = [selectedTransaction]
        }
        guard !selected.isEmpty else {
            return
        }
        deleteTransactions(selected)
    }

    /// One-shot reveal request published by the active workspace's Jump commands for the AppKit
    /// request table to consume. Read-only forwarding — the table tracks its last applied generation.
    var trafficRevealRequest: TrafficRevealRequest? {
        activeWorkspace.trafficRevealRequest
    }

    /// Jumps to the first row in the current display order (after any active sort), selects its
    /// transaction, and publishes a fresh reveal request for the table. Uses `filteredRows`, not the
    /// chronological `filteredTransactions`, so the endpoint matches what the user actually sees.
    func selectFirstFilteredTransaction() {
        revealDisplayEndpoint(activeWorkspace.filteredRows.first)
    }

    /// Jumps to the last row in the current display order (after any active sort). Follow Live is
    /// unaffected — this is a manual navigation command, not a live-tail toggle.
    func selectLastFilteredTransaction() {
        revealDisplayEndpoint(activeWorkspace.filteredRows.last)
    }

    /// Resolves a display-order endpoint row through `trafficSelectionIndex`, applies it as the
    /// active-workspace selection, and publishes a one-shot reveal request. Fails safely — no
    /// selection change, no reveal — when the view is empty or the selection index is stale/missing
    /// for the endpoint row. Never touches `isFollowingLiveTraffic`.
    private func revealDisplayEndpoint(_ row: RequestListRow?) {
        let workspace = activeWorkspace
        guard let row,
              let entry = workspace.trafficSelectionIndex[row.id],
              workspace.filteredRows.indices.contains(entry.rowIndex),
              workspace.filteredRows[entry.rowIndex].id == row.id else
        {
            return
        }
        selectedTransactionIDs = [entry.transaction.id]
        selectTransaction(entry.transaction)
        workspace.publishTrafficRevealRequest(for: entry.transaction.id)
    }
}
