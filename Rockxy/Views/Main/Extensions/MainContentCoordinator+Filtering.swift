import Foundation

// Extends `MainContentCoordinator` with filtering behavior for the main workspace.

// MARK: - MainContentCoordinator + Filtering

/// Coordinator extension for transaction filtering. Provides both a full recompute
/// and an incremental append path for batch delivery without user filters active.
/// Incremental paths intentionally append visible rows via `appendDerivedRows(_:to:)`
/// and may skip bumping `refreshToken` when a batch contributes no non-TLS-failure rows.
extension MainContentCoordinator {
    // MARK: - Row Derivation (single path for table-facing refresh)

    func deriveFilteredRows() {
        deriveFilteredRows(for: activeWorkspace)
    }

    func deriveFilteredRows(for workspace: WorkspaceState, reusingRetainedRows: Bool = false) {
        let locale = RockxyLocalization.bundle.bundleURL.absoluteString + RockxyLocalization.locale.identifier
        let canReuse = reusingRetainedRows && workspace.rowProjectionLocale == locale
        let previousRows = canReuse ? workspace.filteredRows : []
        let previousIndex = canReuse ? workspace.trafficSelectionIndex : [:]
        var rows: [RequestListRow] = []
        rows.reserveCapacity(workspace.filteredTransactions.count)
        for transaction in workspace.filteredTransactions {
            if let entry = previousIndex[transaction.id],
               previousRows.indices.contains(entry.rowIndex),
               previousRows[entry.rowIndex].id == transaction.id
            {
                let row = previousRows[entry.rowIndex]
                if row.canReuseProjection(of: transaction) {
                    rows.append(row)
                    continue
                }
            }
            rows.append(RequestListRow(from: transaction, sslState: sslState(for: transaction)))
        }
        workspace.rowProjectionLocale = locale
        if !workspace.activeSortDescriptors.isEmpty {
            let statusOrder = workspace.activeSortDescriptors.contains { $0.key == "state" }
                ? RequestListRow.StatusSortOrder() : nil
            rows.sort { lhs, rhs in
                RequestListRow.compare(lhs, rhs, using: workspace.activeSortDescriptors, statusOrder: statusOrder)
            }
        }
        workspace.filteredRows = rows
        var selectionIndex: [UUID: TrafficSelectionIndexEntry] = [:]
        selectionIndex.reserveCapacity(rows.count)
        for (index, row) in rows.enumerated() {
            if let transaction = row.source {
                selectionIndex[row.id] = TrafficSelectionIndexEntry(transaction: transaction, rowIndex: index)
            }
        }
        if selectionIndex.count != rows.count {
            // Preserve the existing latest-source rule for duplicate UUIDs even if sorting
            // moved a different object with that UUID to the final displayed position.
            let transactionsByID = Dictionary(
                workspace.filteredTransactions.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            for (index, row) in rows.enumerated() {
                if let transaction = transactionsByID[row.id] {
                    selectionIndex[row.id] = TrafficSelectionIndexEntry(transaction: transaction, rowIndex: index)
                }
            }
        }
        workspace.trafficSelectionIndex = selectionIndex
        workspace.selectedTransactionIDs = workspace.selectedTransactionIDs.filter { selectionIndex[$0] != nil }
        if let selected = workspace.selectedTransaction, selectionIndex[selected.id] == nil {
            // The primary row was filtered out. Promote the top-most surviving selected row,
            // matching `selectTransactions(_:primaryID:)`, so the inspector never reads
            // "No Selection" beside a table and footer that still show a selected row.
            let survivingPrimary = rows.first { workspace.selectedTransactionIDs.contains($0.id) }
            workspace.selectedTransaction = survivingPrimary.flatMap {
                workspace.trafficSelectionIndex[$0.id]?.transaction
            }
        }
        // A full derivation replaces the entire row set, so any in-flight append chain is
        // void: clear both the append-only signal and its provenance token before bumping the
        // token. Scattered callers that set lastDeriveWasAppendOnly = false rely on this so a
        // stale append signal can never survive a recompute.
        workspace.lastDeriveWasAppendOnly = false
        workspace.appendChainOriginToken = nil
        workspace.refreshToken += 1
        reconcileFollowLiveSelection(for: workspace)
    }

    private func appendDerivedRows(_ batch: [HTTPTransaction], to workspace: WorkspaceState) {
        let visibleTransactions = batch.filter { !$0.isTLSFailure }
        let appendedRows = visibleTransactions
            .map { RequestListRow(from: $0, sslState: sslState(for: $0)) }

        guard !appendedRows.isEmpty else {
            return
        }

        // Record the base token this append chain builds on. The first append of a chain
        // captures the current (pre-append) token; later coalesced appends preserve it so the
        // table can still prove its displayed prefix matches the grown row set.
        if workspace.appendChainOriginToken == nil {
            workspace.appendChainOriginToken = workspace.refreshToken
        }
        if workspace.filteredRows.isEmpty {
            workspace.rowProjectionLocale = RockxyLocalization.bundle.bundleURL.absoluteString
                + RockxyLocalization.locale.identifier
        }
        let firstAppendedIndex = workspace.filteredRows.count
        workspace.filteredRows.append(contentsOf: appendedRows)
        for (offset, transaction) in visibleTransactions.enumerated() {
            workspace.trafficSelectionIndex[transaction.id] = TrafficSelectionIndexEntry(
                transaction: transaction,
                rowIndex: firstAppendedIndex + offset
            )
        }
        workspace.refreshToken += 1
    }

    func sslState(for transaction: HTTPTransaction) -> RequestListRow.SSLState {
        guard let scheme = transaction.request.url.scheme?.lowercased(),
              scheme == "https" || scheme == "wss" else
        {
            return .insecure
        }

        // Capture truth wins over current policy: a CONNECT tunnel that was passed through raw
        // stays tunneled even after the host's rule is later enabled, and genuinely decrypted
        // traffic stays intercepted.
        if let capture = transaction.sslCapture {
            return capture == .intercepted ? .secureIntercepted : .secureTunneled
        }

        // Legacy / reloaded / imported rows carry no recorded disposition. Derive it from the
        // record's own shape — never from current host policy, which would make a historical row
        // flip meaning when a rule is toggled. A secure CONNECT row is a tunnel record and stays
        // tunneled; any captured non-CONNECT HTTPS/WSS transaction is decrypted application
        // traffic (a raw tunnel never yields per-request records) and is intercepted.
        return transaction.request.method == "CONNECT" ? .secureTunneled : .secureIntercepted
    }

    // MARK: - Filtered Transactions

    /// Reveals the compound filter editor on first use, then appends one rule per invocation.
    func addAdvancedFilterRule() {
        if isFilterBarVisible {
            filterRules.append(FilterRule())
        } else {
            if filterRules.isEmpty {
                filterRules = [FilterRule()]
            }
            isFilterBarVisible = true
        }
        recomputeFilteredTransactions()
    }

    /// Adds a context-menu filter through the same rule collection used by the visible filter editor.
    func applyContextFilter(_ suggestion: ContextFilterSuggestion, excluding: Bool = false) {
        var rule = FilterRule(
            field: suggestion.field,
            filterOperator: excluding ? suggestion.excludeOperator : suggestion.includeOperator,
            value: suggestion.value
        )
        if let placeholderIndex = filterRules.firstIndex(where: {
            $0.isEnabled && $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            rule.id = filterRules[placeholderIndex].id
            rule.connector = filterRules[placeholderIndex].connector
            filterRules[placeholderIndex] = rule
        } else {
            filterRules.append(rule)
        }
        isFilterBarVisible = true
        recomputeFilteredTransactions()
    }

    /// True when any workspace-level filter narrows the visible traffic: search/method/status/etc.
    /// via `FilterCriteria`, an active advanced rule, a Traffic Signal, a Focus Set, or muted sources.
    /// A merely-visible but empty advanced editor is intentionally not treated as active.
    var hasActiveWorkspaceFilters: Bool {
        !filterCriteria.isEmpty
            || !FilterRuleEvaluator.activeRules(in: filterRules, isFilterBarVisible: isFilterBarVisible).isEmpty
            || activeWorkspace.activeTrafficSignal != nil
            || activeWorkspace.activeFocusSet != nil
            || !activeWorkspace.mutedTrafficSources.isEmpty
    }

    /// Full reset of every workspace filter, scope, and focus/noise dimension back to "All Traffic",
    /// then recompute. Single source of truth for the filter-summary "Clear All" chip and the
    /// request-list empty-state recovery actions so they cannot drift apart.
    func clearAllWorkspaceFilters() {
        resetFilters(in: activeWorkspace)
        recomputeFilteredTransactions()
    }

    /// Session-level reset used by "Clear Session and Filters". Session data spans every
    /// workspace, so leaving an inactive workspace's visibility lenses behind would silently
    /// hide newly captured traffic when the user returns to it.
    func clearFiltersAcrossAllWorkspaces() {
        for workspace in workspaceStore.allWorkspaces {
            resetFilters(in: workspace)
        }
        recomputeAllWorkspaces()
    }

    private func resetFilters(in workspace: WorkspaceState) {
        workspace.filterCriteria = .empty
        workspace.filterCriteria.sidebarScope = .allTraffic
        workspace.sidebarSelection = nil
        workspace.isFilterBarVisible = false
        workspace.filterRules = [FilterRule()]
        workspace.activeTrafficSignal = nil
        workspace.activeFocusSetID = nil
        workspace.mutedTrafficSources.removeAll()
    }

    /// The status bar's "available" count: how many rows the current scope could show.
    ///
    /// `.allTraffic` is answered from the maintained TLS-failure set rather than by
    /// counting `!isTLSFailure` across the capture. The status bar sits in the centre
    /// pane's `body`, so that count ran once per render and, worse, registered an
    /// observation dependency on every retained row -- the next arriving response
    /// invalidated the pane and the count ran again, which is what made a long capture
    /// lag. The three favourite scopes keep counting: their lists are the cached
    /// favourites, bounded by how many rows the user pinned, saved, or annotated rather
    /// than by how long capture has run.
    var availableTransactionCountForCurrentScope: Int {
        switch filterCriteria.sidebarScope {
        case .saved:
            allSavedTransactions.count { !$0.isTLSFailure }
        case .pinned:
            allPinnedTransactions.count { !$0.isTLSFailure }
        case .notes:
            allNotesTransactions.count { !$0.isTLSFailure }
        case .allTraffic:
            transactions.count - tlsFailureTransactionIDs.count
        }
    }

    func appendFilteredTransactions(_ batch: [HTTPTransaction]) {
        let activeRules = FilterRuleEvaluator.activeRules(in: filterRules, isFilterBarVisible: isFilterBarVisible)
        if filterCriteria.sidebarScope == .allTraffic, filterCriteria.isEmpty, activeRules.isEmpty,
           activeSortDescriptors.isEmpty, !hasWorkspaceVisibilityRules(activeWorkspace)
        {
            filteredTransactions.append(contentsOf: batch.filter { !$0.isTLSFailure })
            activeWorkspace.lastDeriveWasAppendOnly = true
            appendDerivedRows(batch, to: activeWorkspace)
        } else {
            recomputeFilteredTransactions()
            return
        }
    }

    /// Applies a search-field edit at once and schedules the filter pass behind a short
    /// debounce. The text has to land immediately so the field stays responsive; what
    /// costs real time is the pass below, which walks every captured transaction. After
    /// a long capture that list is large enough that one pass per keystroke is itself
    /// the typing lag.
    func searchTextDidChange(_ text: String) {
        filterCriteria.searchText = text
        searchRecomputeTask?.cancel()
        searchRecomputeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(for: self.searchRecomputeDebounce)
            } catch {
                // Cancelled by a newer keystroke: coalesced into the later pass.
                return
            }
            guard !Task.isCancelled else {
                return
            }
            // Cleared before the pass so the supersede below does not cancel this
            // very task while it is the one running.
            self.searchRecomputeTask = nil
            self.recomputeFilteredTransactions()
        }
    }

    func recomputeFilteredTransactions() {
        // Any immediate recompute, from any call site, supersedes a debounced one.
        searchRecomputeTask?.cancel()
        searchRecomputeTask = nil
        activeWorkspace.lastDeriveWasAppendOnly = false
        let baseList: [HTTPTransaction] = switch filterCriteria.sidebarScope {
        case .saved:
            allSavedTransactions
        case .pinned:
            allPinnedTransactions
        case .notes:
            allNotesTransactions
        case .allTraffic:
            transactions
        }

        let activeRules = FilterRuleEvaluator.activeRules(in: filterRules, isFilterBarVisible: isFilterBarVisible)
        guard !filterCriteria.isEmpty || !activeRules.isEmpty || hasWorkspaceVisibilityRules(activeWorkspace) else {
            filteredTransactions = baseList.filter { !$0.isTLSFailure }
            // Filtering never mutates a transaction, so every surviving row can be
            // reused instead of reprojected. The reuse guard is complete for what a row
            // carries: `canReuseProjection(of:)` requires the same object identity and an
            // unchanged `listPresentationRevision`, and every field the row projects --
            // status, sizes, headers, duration, badges, SSL state -- comes from a property
            // whose `didSet` bumps that revision. The one field that cannot (frame count
            // mutates inside the `WebSocketConnection` reference, so the property's own
            // `didSet` never fires) is compared explicitly by the same guard. Without this,
            // one filter pass over a long capture reprojects every row, which is the
            // after-a-long-capture lag itself.
            deriveFilteredRows(for: activeWorkspace, reusingRetainedRows: true)
            return
        }
        let smartFilter = SmartTrafficFilter.parse(filterCriteria.searchText)
        filteredTransactions = baseList.filter { transaction in
            if transaction.isTLSFailure {
                return false
            }
            if !isVisibleInWorkspaceScope(transaction, workspace: activeWorkspace) {
                return false
            }
            if let exactTransactionID = filterCriteria.exactTransactionID,
               transaction.id != exactTransactionID
            {
                return false
            }
            if let sidebarDomain = filterCriteria.sidebarDomain {
                guard DomainGrouping.host(transaction.request.host, matchesDomain: sidebarDomain) else {
                    return false
                }
            }
            if !DomainGrouping.path(transaction.request.path, matchesPrefix: filterCriteria.sidebarPathPrefix) {
                return false
            }
            if let sidebarApp = filterCriteria.sidebarApp {
                guard transaction.clientApp == sidebarApp else {
                    return false
                }
            }
            if filterCriteria.isSearchEnabled, !filterCriteria.searchText.isEmpty {
                guard smartFilter.matches(transaction) else {
                    return false
                }
                let searchText = smartFilter.remainingSearchText.lowercased()
                if !searchText.isEmpty {
                    let targetValue = fieldValue(for: filterCriteria.searchField, in: transaction)
                    guard targetValue.lowercased().contains(searchText) else {
                        return false
                    }
                }
            }
            if !filterCriteria.methods.isEmpty {
                guard filterCriteria.methods.contains(transaction.request.method) else {
                    return false
                }
            }
            if !filterCriteria.statusCodes.isEmpty {
                guard let status = transaction.response?.statusCode,
                      filterCriteria.statusCodes.contains(status) else
                {
                    return false
                }
            }
            if !filterCriteria.contentTypes.isEmpty {
                let requestType = transaction.request.contentType
                let responseType = transaction.response?.contentType
                guard requestType.map(filterCriteria.contentTypes.contains) == true
                    || responseType.map(filterCriteria.contentTypes.contains) == true else
                {
                    return false
                }
            }
            if !filterCriteria.domains.isEmpty {
                guard filterCriteria.domains.contains(where: {
                    DomainGrouping.host(transaction.request.host, matchesDomain: $0)
                }) else {
                    return false
                }
            }
            if !filterCriteria.activeProtocolFilters.isEmpty {
                let contentFilters = filterCriteria.activeProtocolFilters.filter { !$0.isStatusFilter }
                let statusFilters = filterCriteria.activeProtocolFilters.filter(\.isStatusFilter)

                if !contentFilters.isEmpty {
                    guard contentFilters.contains(where: { $0.matches(transaction) }) else {
                        return false
                    }
                }
                if !statusFilters.isEmpty {
                    guard statusFilters.contains(where: { $0.matches(transaction) }) else {
                        return false
                    }
                }
            }
            if !activeRules.isEmpty, !FilterRuleEvaluator.matches(transaction, rules: activeRules) {
                return false
            }
            return true
        }
        // Filtering never mutates a transaction, so every surviving row can be
        // reused instead of reprojected. The reuse guard is complete for what a row
        // carries: `canReuseProjection(of:)` requires the same object identity and an
        // unchanged `listPresentationRevision`, and every field the row projects --
        // status, sizes, headers, duration, badges, SSL state -- comes from a property
        // whose `didSet` bumps that revision. The one field that cannot (frame count
        // mutates inside the `WebSocketConnection` reference, so the property's own
        // `didSet` never fires) is compared explicitly by the same guard. Without this,
        // one filter pass over a long capture reprojects every row, which is the
        // after-a-long-capture lag itself.
        deriveFilteredRows(for: activeWorkspace, reusingRetainedRows: true)
    }

    func fieldValue(for field: FilterField, in transaction: HTTPTransaction) -> String {
        FilterRuleEvaluator.fieldValue(for: field, in: transaction)
    }

    func activeInspectorHighlightContext() -> InspectorHighlightContext {
        var literalTerms: [String] = []
        var regexPatterns: [String] = []

        func appendLiteral(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !literalTerms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else
            {
                return
            }
            literalTerms.append(trimmed)
        }

        if filterCriteria.isSearchEnabled {
            appendLiteral(filterCriteria.searchText)
        }

        let activeRules = FilterRuleEvaluator.activeRules(in: filterRules, isFilterBarVisible: isFilterBarVisible)
        for rule in activeRules where rule.filterOperator.contributesHighlight {
            let trimmed = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if rule.filterOperator == .regex {
                regexPatterns.append(trimmed)
            } else {
                appendLiteral(trimmed)
            }
        }

        return InspectorHighlightContext(
            literalTerms: Array(literalTerms.prefix(20)),
            regexPatterns: Array(regexPatterns.prefix(10))
        )
    }

    // MARK: - Per-Workspace Filtering

    func appendFilteredTransactions(_ batch: [HTTPTransaction], to workspace: WorkspaceState) {
        let activeRules = FilterRuleEvaluator.activeRules(
            in: workspace.filterRules,
            isFilterBarVisible: workspace.isFilterBarVisible
        )
        if workspace.filterCriteria.sidebarScope == .allTraffic,
           workspace.filterCriteria.isEmpty, activeRules.isEmpty, workspace.activeSortDescriptors.isEmpty,
           !hasWorkspaceVisibilityRules(workspace)
        {
            workspace.filteredTransactions.append(contentsOf: batch.filter { !$0.isTLSFailure })
            workspace.lastDeriveWasAppendOnly = true
            appendDerivedRows(batch, to: workspace)
        } else {
            recomputeFilteredTransactions(for: workspace)
            return
        }
    }

    func recomputeFilteredTransactions(for workspace: WorkspaceState, reusingRetainedRows: Bool = false) {
        workspace.lastDeriveWasAppendOnly = false
        let baseList: [HTTPTransaction] = switch workspace.filterCriteria.sidebarScope {
        case .saved:
            allSavedTransactions
        case .pinned:
            allPinnedTransactions
        case .notes:
            allNotesTransactions
        case .allTraffic:
            transactions
        }

        let activeRules = FilterRuleEvaluator.activeRules(
            in: workspace.filterRules,
            isFilterBarVisible: workspace.isFilterBarVisible
        )
        guard !workspace.filterCriteria.isEmpty || !activeRules.isEmpty || hasWorkspaceVisibilityRules(workspace) else {
            workspace.filteredTransactions = baseList.filter { !$0.isTLSFailure }
            deriveFilteredRows(for: workspace, reusingRetainedRows: reusingRetainedRows)
            return
        }
        let smartFilter = SmartTrafficFilter.parse(workspace.filterCriteria.searchText)
        workspace.filteredTransactions = baseList.filter {
            matchesActiveWorkspaceFilters($0, in: workspace, activeRules: activeRules, smartFilter: smartFilter)
        }
        deriveFilteredRows(for: workspace, reusingRetainedRows: reusingRetainedRows)
    }

    /// The single membership test behind the visible row set. `recomputeFilteredTransactions`
    /// folds it over the retained capture; the live-row path evaluates it for the handful of
    /// rows a flush changed. Sharing one predicate is what makes the cheap path provably
    /// equivalent -- a second copy of these rules could drift and show the wrong rows.
    ///
    /// Every clause reads only the row and the workspace's own filter state, so the result
    /// for one row never depends on any other row.
    func matchesActiveWorkspaceFilters(
        _ transaction: HTTPTransaction,
        in workspace: WorkspaceState,
        activeRules: [FilterRule],
        smartFilter: SmartTrafficFilter
    )
        -> Bool
    {
        if transaction.isTLSFailure {
            return false
        }
        if !isVisibleInWorkspaceScope(transaction, workspace: workspace) {
            return false
        }
        if let exactTransactionID = workspace.filterCriteria.exactTransactionID,
           transaction.id != exactTransactionID
        {
            return false
        }
        if let sidebarDomain = workspace.filterCriteria.sidebarDomain {
            guard DomainGrouping.host(transaction.request.host, matchesDomain: sidebarDomain) else {
                return false
            }
        }
        if !DomainGrouping.path(
            transaction.request.path,
            matchesPrefix: workspace.filterCriteria.sidebarPathPrefix
        ) {
            return false
        }
        if let sidebarApp = workspace.filterCriteria.sidebarApp {
            guard transaction.clientApp == sidebarApp else {
                return false
            }
        }
        if workspace.filterCriteria.isSearchEnabled, !workspace.filterCriteria.searchText.isEmpty {
            guard smartFilter.matches(transaction) else {
                return false
            }
            let searchText = smartFilter.remainingSearchText.lowercased()
            if !searchText.isEmpty {
                let targetValue = fieldValue(for: workspace.filterCriteria.searchField, in: transaction)
                guard targetValue.lowercased().contains(searchText) else {
                    return false
                }
            }
        }
        if !workspace.filterCriteria.methods.isEmpty {
            guard workspace.filterCriteria.methods.contains(transaction.request.method) else {
                return false
            }
        }
        if !workspace.filterCriteria.statusCodes.isEmpty {
            guard let status = transaction.response?.statusCode,
                  workspace.filterCriteria.statusCodes.contains(status) else
            {
                return false
            }
        }
        if !workspace.filterCriteria.contentTypes.isEmpty {
            let requestType = transaction.request.contentType
            let responseType = transaction.response?.contentType
            guard requestType.map(workspace.filterCriteria.contentTypes.contains) == true
                || responseType.map(workspace.filterCriteria.contentTypes.contains) == true else
            {
                return false
            }
        }
        if !workspace.filterCriteria.domains.isEmpty {
            guard workspace.filterCriteria.domains.contains(where: {
                DomainGrouping.host(transaction.request.host, matchesDomain: $0)
            }) else {
                return false
            }
        }
        if !workspace.filterCriteria.activeProtocolFilters.isEmpty {
            let contentFilters = workspace.filterCriteria.activeProtocolFilters.filter { !$0.isStatusFilter }
            let statusFilters = workspace.filterCriteria.activeProtocolFilters.filter(\.isStatusFilter)

            if !contentFilters.isEmpty {
                guard contentFilters.contains(where: { $0.matches(transaction) }) else {
                    return false
                }
            }
            if !statusFilters.isEmpty {
                guard statusFilters.contains(where: { $0.matches(transaction) }) else {
                    return false
                }
            }
        }
        if !activeRules.isEmpty, !FilterRuleEvaluator.matches(transaction, rules: activeRules) {
            return false
        }
        return true
    }

    /// True when a live flush can be shown by rewriting the changed rows in place: none of
    /// them crosses the visible-set boundary, and no active sort depends on what changed.
    ///
    /// The expensive alternative re-filters the whole retained capture and reprojects every
    /// surviving row, which at a hundred thousand rows costs tens of milliseconds per flush
    /// per workspace -- and flushes arrive about ten times a second while a stream is open.
    /// Anything this cannot prove falls back to that full recompute, so a row that really
    /// does enter or leave the filter is still placed by the authoritative path.
    func liveUpdatesPreserveRowMembership(
        _ updates: [HTTPTransaction],
        in workspace: WorkspaceState
    )
        -> Bool
    {
        // A finished response can change a sort key, and the table draws rows in sorted
        // order, so these columns need the row set reordered rather than rewritten.
        if workspace.activeSortDescriptors
            .contains(where: { RequestListRow.requiresResortAfterLiveUpdate(columnID: $0.key ?? "") })
        {
            return false
        }
        let activeRules = FilterRuleEvaluator.activeRules(
            in: workspace.filterRules,
            isFilterBarVisible: workspace.isFilterBarVisible
        )
        let narrowsRows = !workspace.filterCriteria.isEmpty || !activeRules.isEmpty
            || hasWorkspaceVisibilityRules(workspace)
        let smartFilter = SmartTrafficFilter.parse(workspace.filterCriteria.searchText)
        for transaction in updates {
            // Only `.allTraffic` draws from the retained history. The pinned, saved, and
            // notes scopes have their own base lists, and absence from those lists is not
            // something the filter predicate can see, so treat any currently visible row in
            // those scopes as unprovable and let the recompute decide.
            let shouldBeVisible = workspace.filterCriteria.sidebarScope == .allTraffic
                && !transaction.isTLSFailure
                && (!narrowsRows || matchesActiveWorkspaceFilters(
                    transaction,
                    in: workspace,
                    activeRules: activeRules,
                    smartFilter: smartFilter
                ))
            // `trafficSelectionIndex` holds one entry per derived row, so it answers
            // "is this row on screen right now" without scanning the row set.
            guard (workspace.trafficSelectionIndex[transaction.id] != nil) == shouldBeVisible else {
                return false
            }
        }
        return true
    }

    private func hasWorkspaceVisibilityRules(_ workspace: WorkspaceState) -> Bool {
        workspace.activeFocusSet != nil
            || workspace.activeTrafficSignal != nil
            || !workspace.mutedTrafficSources.isEmpty
    }

    private func isVisibleInWorkspaceScope(_ transaction: HTTPTransaction, workspace: WorkspaceState) -> Bool {
        // Shared Focus/Noise gate (mute + Focus Set), then the request-list-only Traffic Signal lens.
        guard isWithinFocusNoiseScope(transaction, workspace: workspace) else {
            return false
        }
        if let signal = workspace.activeTrafficSignal, !signal.matches(transaction) {
            return false
        }
        return true
    }
}
