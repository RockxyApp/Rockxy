import Foundation
import os

// Extends `MainContentCoordinator` with workspaces behavior for the main workspace.

// MARK: - MainContentCoordinator + Workspaces

extension MainContentCoordinator {
    func closeWorkspace(id: UUID) {
        cancelDebugAssistantTask(for: id)
        if let pane = workspaceStore.splitCompanion(for: id) {
            cancelDebugAssistantTask(for: pane.id)
        }
        workspaceStore.closeWorkspace(id: id)
    }

    /// Closable tabs other than `id`, in tab order.
    func closableWorkspaceIDs(otherThan id: UUID) -> [UUID] {
        workspaceStore.workspaces.filter { $0.id != id && $0.isClosable }.map(\.id)
    }

    /// Closable tabs after `id` in the tab strip.
    func closableWorkspaceIDs(rightOf id: UUID) -> [UUID] {
        guard let index = workspaceStore.workspaces.firstIndex(where: { $0.id == id }) else {
            return []
        }
        return workspaceStore.workspaces[(index + 1)...].filter(\.isClosable).map(\.id)
    }

    /// Closes several tabs; `keeping` stays selected when the active tab is among them.
    func closeWorkspaces(_ ids: [UUID], keeping kept: UUID) {
        if ids.contains(workspaceStore.activeWorkspaceID) {
            workspaceStore.selectWorkspace(id: kept)
        }
        for id in ids {
            closeWorkspace(id: id)
        }
    }

    // MARK: - All-Workspace Updates

    func recomputeAllWorkspaces() {
        for workspace in workspaceStore.allWorkspaces {
            recomputeFilteredTransactions(for: workspace)
        }
    }

    func clearAllWorkspaces() {
        for workspace in workspaceStore.allWorkspaces {
            workspace.reset()
        }
        TrafficDomainSnapshot.shared.update(appNodes: [], domainTree: [])
    }

    func updateAllWorkspaces(with batch: [HTTPTransaction]) {
        for workspace in workspaceStore.allWorkspaces {
            let initializesIndex = workspace.sidebarTransactionRevisions.isEmpty && transactions.count == batch.count
            for transaction in batch {
                workspace.sidebarTransactionRevisions[ObjectIdentifier(transaction)] = transaction
                    .listPresentationRevision
                updateDomainGroupingIndex(for: transaction, in: workspace)
                addToAppGroupingIndex(transaction, in: workspace)
            }
            if initializesIndex, workspace.sidebarTransactionRevisions.count == transactions.count {
                workspace.sidebarIndexSignature = sidebarIndexSignature(for: workspace)
            }
            refreshDomainTree(for: workspace)
            refreshAppNodes(for: workspace)
            appendFilteredTransactions(batch, to: workspace)
        }
        TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)
    }

    // MARK: - Per-Workspace Sidebar

    func updateDomainTree(for transaction: HTTPTransaction, in workspace: WorkspaceState) {
        updateDomainGroupingIndex(for: transaction, in: workspace)
        refreshDomainTree(for: workspace)
    }

    func updateDomainGroupingIndex(for transaction: HTTPTransaction, in workspace: WorkspaceState) {
        let domain = transaction.request.host
        guard !domain.isEmpty else {
            return
        }

        if let sidebarDomain = workspace.filterCriteria.sidebarDomain {
            guard DomainGrouping.host(domain, matchesDomain: sidebarDomain) else {
                return
            }
            if !DomainGrouping.path(
                transaction.request.path,
                matchesPrefix: workspace.filterCriteria.sidebarPathPrefix
            ) {
                return
            }
        }

        workspace.domainGroupingIndex.add(transaction)
    }

    func refreshDomainTree(for workspace: WorkspaceState, alphabetical: Bool = false) {
        workspace.domainTree = workspace.domainGroupingIndex.makeTree(alphabetical: alphabetical)
        workspace.totalDomainCount = workspace.domainTree.reduce(0) { $0 + $1.requestCount }
        workspace.domainIndexMap.removeAll(keepingCapacity: true)
        for (index, node) in workspace.domainTree.enumerated() {
            workspace.domainIndexMap[node.selectionDomain] = index
        }
    }

    func updateAppNodes(for transaction: HTTPTransaction, in workspace: WorkspaceState) {
        addToAppGroupingIndex(transaction, in: workspace)
        refreshAppNodes(for: workspace)
    }

    func rebuildSidebarIndexes(for workspace: WorkspaceState) {
        // Reuse storage locally and publish the finished trees once. Mutating an
        // observable workspace cache for every retained row amplifies full-history work.
        var domains = DomainGroupingIndex()
        var apps = AppGroupingIndex()
        swap(&domains, &workspace.domainGroupingIndex)
        swap(&apps, &workspace.appGroupingIndex)
        domains.removeAll()
        apps.removeAll()
        let signature = sidebarIndexSignature(for: workspace)
        var revisions: [ObjectIdentifier: UInt64] = [:]
        revisions.reserveCapacity(transactions.count)
        let criteria = workspace.filterCriteria
        let unknown = String(localized: "Unknown", bundle: RockxyLocalization.bundle)
        for transaction in transactions {
            revisions[ObjectIdentifier(transaction)] = transaction.listPresentationRevision
            let host = transaction.request.host
            let matchesDomain = criteria.sidebarDomain.map {
                DomainGrouping.host(host, matchesDomain: $0)
                    && DomainGrouping.path(transaction.request.path, matchesPrefix: criteria.sidebarPathPrefix)
            } ?? true
            if !host.isEmpty, matchesDomain {
                domains.add(transaction)
            }
            let appName = transaction.clientApp ?? unknown
            if criteria.sidebarApp == nil || criteria.sidebarApp == appName {
                let normalizedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
                apps.add(transaction, appName: normalizedName.isEmpty ? unknown : appName)
            }
        }
        workspace.domainGroupingIndex = domains
        workspace.appGroupingIndex = apps
        workspace.sidebarIndexSignature = signature
        workspace.sidebarTransactionRevisions = revisions
        refreshDomainTree(for: workspace)
        refreshAppNodes(for: workspace)
        pruneSidebarSelectionIfNeeded(in: workspace)
        if signature != sidebarIndexSignature(for: workspace) {
            rebuildSidebarIndexes(for: workspace)
            return
        }
        TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)
    }

    /// A different sidebar scope or language requires an authoritative rebuild.
    private func sidebarIndexSignature(for workspace: WorkspaceState) -> [String?] {
        [
            workspace.filterCriteria.sidebarDomain,
            workspace.filterCriteria.sidebarPathPrefix,
            workspace.filterCriteria.sidebarApp,
            RockxyLocalization.bundle.bundleURL.absoluteString,
            RockxyLocalization.locale.identifier
        ]
    }

    /// Removes stored contributions before reading mutable models, then reconciles only
    /// rows whose projection changed. Duplicate object aliases use the full rebuild path.
    func retainAllWorkspaces(removing removed: [HTTPTransaction], appending batch: [HTTPTransaction]) {
        for workspace in workspaceStore.allWorkspaces {
            CaptureRetentionProfiler.measure(.sidebarIndexes) {
                let oldCount = transactions.count + removed.count - batch.count
                guard workspace.sidebarIndexSignature == sidebarIndexSignature(for: workspace),
                      workspace.sidebarTransactionRevisions.count == oldCount,
                      workspace.domainGroupingIndex.supportsIncrementalRemoval,
                      workspace.appGroupingIndex.supportsIncrementalRemoval else
                {
                    rebuildSidebarIndexes(for: workspace)
                    return
                }
                var domains = DomainGroupingIndex()
                var apps = AppGroupingIndex()
                swap(&domains, &workspace.domainGroupingIndex)
                swap(&apps, &workspace.appGroupingIndex)
                domains.remove(removed)
                apps.remove(removed)
                var revisions = workspace.sidebarTransactionRevisions
                for transaction in removed {
                    revisions.removeValue(forKey: ObjectIdentifier(transaction))
                }
                let unknown = String(localized: "Unknown", bundle: RockxyLocalization.bundle)
                for transaction in transactions {
                    let id = ObjectIdentifier(transaction)
                    guard revisions[id] != transaction.listPresentationRevision else {
                        continue
                    }
                    reconcileSidebarContribution(
                        transaction,
                        domains: &domains,
                        apps: &apps,
                        workspace: workspace,
                        unknown: unknown
                    )
                    revisions[id] = transaction.listPresentationRevision
                }
                apps.reconcileRetainedOrder(transactions)
                workspace.domainGroupingIndex = domains
                workspace.appGroupingIndex = apps
                workspace.sidebarTransactionRevisions = revisions
                refreshDomainTree(for: workspace)
                refreshAppNodes(for: workspace)
                pruneSidebarSelectionIfNeeded(in: workspace)
                if workspace.sidebarIndexSignature != sidebarIndexSignature(for: workspace) {
                    rebuildSidebarIndexes(for: workspace)
                }
            }
            CaptureRetentionProfiler.measure(.filteredRows) {
                recomputeFilteredTransactions(for: workspace, reusingRetainedRows: true)
            }
        }
        TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)
    }

    func refreshSidebarContributions(_ updates: [HTTPTransaction], in workspace: WorkspaceState) {
        guard workspace.sidebarIndexSignature == sidebarIndexSignature(for: workspace),
              workspace.domainGroupingIndex.supportsIncrementalRemoval,
              workspace.appGroupingIndex.supportsIncrementalRemoval else
        {
            rebuildSidebarIndexes(for: workspace)
            return
        }
        var domains = DomainGroupingIndex()
        var apps = AppGroupingIndex()
        swap(&domains, &workspace.domainGroupingIndex)
        swap(&apps, &workspace.appGroupingIndex)
        let unknown = String(localized: "Unknown", bundle: RockxyLocalization.bundle)
        for transaction in updates {
            reconcileSidebarContribution(
                transaction,
                domains: &domains,
                apps: &apps,
                workspace: workspace,
                unknown: unknown
            )
            workspace.sidebarTransactionRevisions[ObjectIdentifier(transaction)] = transaction.listPresentationRevision
        }
        apps.reconcileRetainedOrder(transactions)
        workspace.domainGroupingIndex = domains
        workspace.appGroupingIndex = apps
        refreshDomainTree(for: workspace)
        refreshAppNodes(for: workspace)
    }

    private func reconcileSidebarContribution(
        _ transaction: HTTPTransaction, domains: inout DomainGroupingIndex,
        apps: inout AppGroupingIndex, workspace: WorkspaceState, unknown: String
    ) {
        let criteria = workspace.filterCriteria
        let host = transaction.request.host
        let matchesDomain = criteria.sidebarDomain.map {
            DomainGrouping.host(host, matchesDomain: $0)
                && DomainGrouping.path(transaction.request.path, matchesPrefix: criteria.sidebarPathPrefix)
        } ?? true
        if !host.isEmpty, matchesDomain {
            domains.update([transaction])
        } else {
            domains.remove([transaction])
        }
        let name = transaction.clientApp ?? unknown
        if criteria.sidebarApp == nil || criteria.sidebarApp == name {
            apps.upsert(transaction, appName: name)
        } else {
            apps.remove([transaction])
        }
    }

    func pruneSidebarSelectionIfNeeded(in workspace: WorkspaceState) {
        guard let selection = workspace.sidebarSelection else {
            return
        }

        let isValid: Bool = switch selection {
        case let .domainNode(domain):
            workspace.domainTree.contains { $0.selectionDomain == domain }
        case let .domainPath(domain, pathPrefix):
            workspace.domainTree.contains { nodeContainsPath($0, domain: domain, pathPrefix: pathPrefix) }
        case let .app(name, _):
            workspace.appNodeIndexMap[name] != nil
        case let .pinnedTransaction(id):
            allPinnedTransactions.contains { $0.id == id }
        case let .savedTransaction(id):
            allSavedTransactions.contains { $0.id == id }
        case let .noteTransaction(id):
            allNotesTransactions.contains { $0.id == id }
        case .allApps,
             .allDomains,
             .allPinned,
             .allSaved,
             .allNotes,
             .insights:
            true
        case .filter,
             .ruleGroup,
             .savedSession,
             .logStream:
            true
        }

        guard !isValid else {
            return
        }
        workspace.sidebarSelection = nil
        workspace.filterCriteria.sidebarDomain = nil
        workspace.filterCriteria.sidebarPathPrefix = nil
        workspace.filterCriteria.sidebarApp = nil
        workspace.filterCriteria.sidebarScope = .allTraffic
    }

    private func nodeContainsPath(_ node: DomainNode, domain: String, pathPrefix: String) -> Bool {
        if node.selectionDomain == domain, node.pathPrefix == pathPrefix {
            return true
        }
        return node.children.contains { nodeContainsPath($0, domain: domain, pathPrefix: pathPrefix) }
    }

    func addToAppGroupingIndex(_ transaction: HTTPTransaction, in workspace: WorkspaceState) {
        let appName = transaction.clientApp ?? String(localized: "Unknown", bundle: RockxyLocalization.bundle)
        if let sidebarApp = workspace.filterCriteria.sidebarApp, appName != sidebarApp {
            return
        }
        workspace.appGroupingIndex.add(transaction, appName: appName)
    }

    func refreshAppNodes(for workspace: WorkspaceState) {
        workspace.appNodes = workspace.appGroupingIndex.makeNodes()
        workspace.appNodeIndexMap.removeAll(keepingCapacity: true)
        for (index, node) in workspace.appNodes.enumerated() {
            workspace.appNodeIndexMap[node.name] = index
        }
    }

    // MARK: - Eviction Across Workspaces

    func evictFromAllWorkspaces(removedIDs: Set<UUID>) {
        for workspace in workspaceStore.allWorkspaces {
            workspace.filteredTransactions.removeAll { removedIDs.contains($0.id) }
            workspace.selectedTransactionIDs.subtract(removedIDs)
            if workspace.selectedTransaction.map({ removedIDs.contains($0.id) }) == true {
                workspace.selectedTransaction = nil
            }
            rebuildSidebarIndexes(for: workspace)
            workspace.lastDeriveWasAppendOnly = false
            deriveFilteredRows(for: workspace)
        }
    }
}
