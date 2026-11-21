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
        TrafficDomainSnapshot.shared.update(appNodes: [], domains: [])
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
        publishTrafficDomainSnapshot()
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

    /// Publishes the workspace's domain tree, patching only what changed.
    ///
    /// Everything here used to be proportional to the number of distinct hosts and paths
    /// in the capture -- the tree was rebuilt and re-sorted wholesale, the total was
    /// reduced over the roots, and the index map was rebuilt -- and it ran once per open
    /// Traffic Tab on every 100 ms delivery batch. That collection is not bounded by the
    /// history cap: it only grows for as long as capture runs, so evicting rows never made
    /// this cheaper. The index now maintains all three, and the map is rebuilt only when
    /// the root list it describes actually changed.
    ///
    /// `alphabetical` is the one-shot sidebar sort command: it publishes an order the
    /// index does not maintain, so the map is rebuilt unconditionally and the recorded
    /// revision is cleared so the next ordinary refresh rebuilds it again.
    func refreshDomainTree(for workspace: WorkspaceState, alphabetical: Bool = false) {
        workspace.domainTree = workspace.domainGroupingIndex.makeTree(alphabetical: alphabetical)
        workspace.totalDomainCount = workspace.domainGroupingIndex.rootRequestTotal
        let revision = workspace.domainGroupingIndex.rootOrderRevision
        guard alphabetical || workspace.domainIndexRevision != revision else {
            return
        }
        workspace.domainIndexMap.removeAll(keepingCapacity: true)
        for (index, node) in workspace.domainTree.enumerated() {
            workspace.domainIndexMap[node.selectionDomain] = index
        }
        workspace.domainIndexRevision = alphabetical ? nil : revision
    }

    /// Republishes the read-only snapshot secondary windows read traffic context from.
    ///
    /// Reads the domain list the active workspace's index already keeps in order, rather
    /// than flattening and re-collating the published tree on every batch.
    func publishTrafficDomainSnapshot() {
        TrafficDomainSnapshot.shared.update(
            appNodes: appNodes,
            domains: activeWorkspace.domainGroupingIndex.sortedSelectionDomains
        )
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
        publishTrafficDomainSnapshot()
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
                patchSidebarIndexes(
                    for: workspace,
                    removing: removed,
                    previousTransactionCount: transactions.count + removed.count - batch.count
                )
            }
            CaptureRetentionProfiler.measure(.filteredRows) {
                recomputeFilteredTransactions(for: workspace, reusingRetainedRows: true)
            }
        }
        publishTrafficDomainSnapshot()
    }

    /// Brings one workspace's sidebar indexes up to date with a history that lost `removed`
    /// (and may have gained rows the index has not seen), without rebuilding them.
    ///
    /// The patch is only sound when the index describes exactly the history as it was a
    /// moment ago, so every precondition is checked and any miss falls back to the
    /// authoritative rebuild: a different sidebar scope or language, a revision ledger
    /// whose size is not the previous history's, or an index that saw a duplicate object.
    /// Shared by capture retention and by eviction, which are the same operation.
    private func patchSidebarIndexes(
        for workspace: WorkspaceState,
        removing removed: [HTTPTransaction],
        previousTransactionCount oldCount: Int
    ) {
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
        var appGroupingChanged = false
        for transaction in updates {
            if reconcileSidebarContribution(
                transaction,
                domains: &domains,
                apps: &apps,
                workspace: workspace,
                unknown: unknown
            ) {
                appGroupingChanged = true
            }
            workspace.sidebarTransactionRevisions[ObjectIdentifier(transaction)] = transaction.listPresentationRevision
        }
        // `reconcileRetainedOrder` is the one piece of full-capture work in an otherwise
        // batch-sized refresh, and what it produces is a pure function of the retained
        // order and the stored app memberships. A refresh that changed no membership --
        // the common case while a WebSocket or SSE stream ticks for hours -- cannot have
        // changed either input, so the pass would recompute the state the index already
        // holds. Rows captured since the last pass were appended at the end of both the
        // history and `insertionOrder`, so skipping it cannot reorder them, and eviction
        // reconciles on its own path.
        if appGroupingChanged {
            apps.reconcileRetainedOrder(transactions)
        }
        workspace.domainGroupingIndex = domains
        workspace.appGroupingIndex = apps
        refreshDomainTree(for: workspace)
        refreshAppNodes(for: workspace)
        // A refresh can move a row to another host or app, which adds and retires nodes.
        // The snapshot secondary windows read is a projection of the active tab's index, so
        // leaving it alone served the previous batch's domains until the next capture batch.
        if workspace === activeWorkspace {
            publishTrafficDomainSnapshot()
        }
    }

    /// Reconciles one row's sidebar contributions and reports whether the app grouping
    /// changed, so a caller can skip the retained-order pass that depends on it.
    @discardableResult
    private func reconcileSidebarContribution(
        _ transaction: HTTPTransaction, domains: inout DomainGroupingIndex,
        apps: inout AppGroupingIndex, workspace: WorkspaceState, unknown: String
    )
        -> Bool
    {
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
            return apps.upsert(transaction, appName: name)
        }
        return apps.remove([transaction])
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

    /// Drops evicted rows from every Traffic Tab.
    ///
    /// `removed` is the rows themselves, already taken out of `transactions`: the sidebar
    /// indexes are keyed by object identity, so subtracting them needs the objects and not
    /// only their ids. With it, each tab patches its domain and app trees and reuses the
    /// row projections it already holds. Without it (callers that only kept ids) a tab
    /// falls back to the authoritative rebuild, which is what this always did.
    func evictFromAllWorkspaces(removedIDs: Set<UUID>, removed: [HTTPTransaction]? = nil) {
        for workspace in workspaceStore.allWorkspaces {
            workspace.filteredTransactions.removeAll { removedIDs.contains($0.id) }
            workspace.selectedTransactionIDs.subtract(removedIDs)
            if workspace.selectedTransaction.map({ removedIDs.contains($0.id) }) == true {
                workspace.selectedTransaction = nil
            }
            guard let removed else {
                rebuildSidebarIndexes(for: workspace)
                workspace.lastDeriveWasAppendOnly = false
                deriveFilteredRows(for: workspace)
                continue
            }
            let selectionBefore = workspace.sidebarSelection
            patchSidebarIndexes(
                for: workspace,
                removing: removed,
                previousTransactionCount: transactions.count + removed.count
            )
            if workspace.sidebarSelection != selectionBefore {
                // Pruning widened the tab's scope, so its row set is no longer the one
                // the criteria describe.
                recomputeFilteredTransactions(for: workspace, reusingRetainedRows: true)
            } else {
                workspace.lastDeriveWasAppendOnly = false
                deriveFilteredRows(for: workspace, reusingRetainedRows: true)
            }
        }
        publishTrafficDomainSnapshot()
    }
}
