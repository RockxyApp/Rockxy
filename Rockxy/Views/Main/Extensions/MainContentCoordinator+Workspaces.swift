import Foundation
import os

// Extends `MainContentCoordinator` with workspaces behavior for the main workspace.

// MARK: - MainContentCoordinator + Workspaces

extension MainContentCoordinator {
    // MARK: - All-Workspace Updates

    func recomputeAllWorkspaces() {
        for workspace in workspaceStore.workspaces {
            recomputeFilteredTransactions(for: workspace)
        }
    }

    func clearAllWorkspaces() {
        for workspace in workspaceStore.workspaces {
            workspace.reset()
        }
        TrafficDomainSnapshot.shared.update(appNodes: [], domainTree: [])
    }

    func updateAllWorkspaces(with batch: [HTTPTransaction]) {
        for workspace in workspaceStore.workspaces {
            for transaction in batch {
                updateDomainGroupingIndex(for: transaction, in: workspace)
                updateAppNodes(for: transaction, in: workspace)
            }
            refreshDomainTree(for: workspace)
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
            if !DomainGrouping.path(transaction.request.path, matchesPrefix: workspace.filterCriteria.sidebarPathPrefix) {
                return
            }
        }

        workspace.domainGroupingIndex.add(transaction)
    }

    func refreshDomainTree(for workspace: WorkspaceState, alphabetical: Bool = false) {
        workspace.domainTree = workspace.domainGroupingIndex.makeTree(alphabetical: alphabetical)
        workspace.domainIndexMap.removeAll(keepingCapacity: true)
        for (index, node) in workspace.domainTree.enumerated() {
            workspace.domainIndexMap[node.selectionDomain] = index
        }
    }

    func updateAppNodes(for transaction: HTTPTransaction, in workspace: WorkspaceState) {
        let appName = transaction.clientApp ?? String(localized: "Unknown")
        let host = transaction.request.host

        if let sidebarApp = workspace.filterCriteria.sidebarApp {
            guard appName == sidebarApp else {
                return
            }
        }

        if let index = workspace.appNodeIndexMap[appName] {
            workspace.appNodes[index].requestCount += 1
            if !host.isEmpty, !workspace.appNodes[index].domains.contains(host) {
                workspace.appNodes[index].domains.append(host)
                workspace.appNodes[index].domains.sort()
            }
        } else {
            let info = AppInfo(name: appName, domains: host.isEmpty ? [] : [host], requestCount: 1)
            workspace.appNodeIndexMap[appName] = workspace.appNodes.count
            workspace.appNodes.append(info)
        }
    }

    func rebuildSidebarIndexes(for workspace: WorkspaceState) {
        workspace.domainTree.removeAll()
        workspace.domainIndexMap.removeAll()
        workspace.domainGroupingIndex.removeAll()
        workspace.appNodes.removeAll()
        workspace.appNodeIndexMap.removeAll()
        for transaction in transactions {
            updateDomainGroupingIndex(for: transaction, in: workspace)
            updateAppNodes(for: transaction, in: workspace)
        }
        refreshDomainTree(for: workspace)
        pruneSidebarSelectionIfNeeded(in: workspace)
        TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)
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
        case .allApps,
             .allDomains,
             .allPinned,
             .allSaved:
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

    // MARK: - Eviction Across Workspaces

    func evictFromAllWorkspaces(removedIDs: Set<UUID>) {
        for workspace in workspaceStore.workspaces {
            workspace.filteredTransactions.removeAll { removedIDs.contains($0.id) }
            if workspace.selectedTransaction.map({ removedIDs.contains($0.id) }) == true {
                workspace.selectedTransaction = nil
            }
            rebuildSidebarIndexes(for: workspace)
            workspace.lastDeriveWasAppendOnly = false
            deriveFilteredRows(for: workspace)
        }
    }
}
