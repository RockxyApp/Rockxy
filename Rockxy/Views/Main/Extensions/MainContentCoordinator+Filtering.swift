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
        // lastDeriveWasAppendOnly is NOT reset here — it persists until the table
        // reads it in updateNSView and the next derive cycle overwrites it.
        workspace.refreshToken += 1
    }

    private func appendDerivedRows(_ batch: [HTTPTransaction], to workspace: WorkspaceState) {
        let appendedRows = batch
            .filter { !$0.isTLSFailure }
            .map { RequestListRow(from: $0, sslState: sslState(for: $0)) }

        guard !appendedRows.isEmpty else {
            return
        }

        workspace.filteredRows.append(contentsOf: appendedRows)
        workspace.refreshToken += 1
    }

    func sslState(for transaction: HTTPTransaction) -> RequestListRow.SSLState {
        guard let scheme = transaction.request.url.scheme?.lowercased(),
              scheme == "https" || scheme == "wss" else
        {
            return .insecure
        }

        let host = transaction.request.host
        guard !host.isEmpty else {
            return .secureTunneled
        }

        return SSLProxyingManager.shared.shouldIntercept(host) ? .secureIntercepted : .secureTunneled
    }

    // MARK: - Filtered Transactions

    func appendFilteredTransactions(_ batch: [HTTPTransaction]) {
        let activeRules = FilterRuleEvaluator.activeRules(in: filterRules, isFilterBarVisible: isFilterBarVisible)
        if filterCriteria.sidebarScope == .allTraffic, filterCriteria.isEmpty, activeRules.isEmpty,
           activeSortDescriptors.isEmpty
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
        case .allTraffic:
            transactions
        }

        let activeRules = FilterRuleEvaluator.activeRules(in: filterRules, isFilterBarVisible: isFilterBarVisible)
        guard !filterCriteria.isEmpty || !activeRules.isEmpty else {
            filteredTransactions = baseList.filter { !$0.isTLSFailure }
            deriveFilteredRows()
            return
        }
        filteredTransactions = baseList.filter { transaction in
            if transaction.isTLSFailure {
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
                let searchText = filterCriteria.searchText.lowercased()
                let targetValue = fieldValue(for: filterCriteria.searchField, in: transaction)
                guard targetValue.lowercased().contains(searchText) else {
                    return false
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
           workspace.filterCriteria.isEmpty, activeRules.isEmpty, workspace.activeSortDescriptors.isEmpty
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
        case .allTraffic:
            transactions
        }

        let activeRules = FilterRuleEvaluator.activeRules(
            in: workspace.filterRules,
            isFilterBarVisible: workspace.isFilterBarVisible
        )
        guard !workspace.filterCriteria.isEmpty || !activeRules.isEmpty else {
            workspace.filteredTransactions = baseList.filter { !$0.isTLSFailure }
            deriveFilteredRows(for: workspace)
            return
        }
        workspace.filteredTransactions = baseList.filter { transaction in
            if transaction.isTLSFailure {
                return false
            }
            if let sidebarDomain = workspace.filterCriteria.sidebarDomain {
                guard DomainGrouping.host(transaction.request.host, matchesDomain: sidebarDomain) else {
                    return false
                }
            }
            if !DomainGrouping.path(transaction.request.path, matchesPrefix: workspace.filterCriteria.sidebarPathPrefix) {
                return false
            }
            if let sidebarApp = workspace.filterCriteria.sidebarApp {
                guard transaction.clientApp == sidebarApp else {
                    return false
                }
            }
            if workspace.filterCriteria.isSearchEnabled, !workspace.filterCriteria.searchText.isEmpty {
                let searchText = workspace.filterCriteria.searchText.lowercased()
                let targetValue = fieldValue(for: workspace.filterCriteria.searchField, in: transaction)
                guard targetValue.lowercased().contains(searchText) else {
                    return false
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
}
