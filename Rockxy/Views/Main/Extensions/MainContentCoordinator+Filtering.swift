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

    func deriveFilteredRows(for workspace: WorkspaceState) {
        var rows = workspace.filteredTransactions.map { transaction in
            RequestListRow(from: transaction, sslState: sslState(for: transaction))
        }
        if !workspace.activeSortDescriptors.isEmpty {
            rows.sort { lhs, rhs in
                RequestListRow.compare(lhs, rhs, using: workspace.activeSortDescriptors)
            }
        }
        workspace.filteredRows = rows
        let transactionsByID = Dictionary(
            workspace.filteredTransactions.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        workspace.trafficSelectionIndex = Dictionary(
            rows.enumerated().compactMap { index, row in
                transactionsByID[row.id].map {
                    (row.id, TrafficSelectionIndexEntry(transaction: $0, rowIndex: index))
                }
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let visibleIDs = Set(workspace.filteredTransactions.map(\.id))
        workspace.selectedTransactionIDs.formIntersection(visibleIDs)
        if let selected = workspace.selectedTransaction, !visibleIDs.contains(selected.id) {
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

    var availableTransactionCountForCurrentScope: Int {
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
        return baseList.count { !$0.isTLSFailure }
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

    func recomputeFilteredTransactions() {
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
            deriveFilteredRows()
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
        deriveFilteredRows()
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

    func recomputeFilteredTransactions(for workspace: WorkspaceState) {
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
            deriveFilteredRows(for: workspace)
            return
        }
        let smartFilter = SmartTrafficFilter.parse(workspace.filterCriteria.searchText)
        workspace.filteredTransactions = baseList.filter { transaction in
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
        deriveFilteredRows(for: workspace)
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
