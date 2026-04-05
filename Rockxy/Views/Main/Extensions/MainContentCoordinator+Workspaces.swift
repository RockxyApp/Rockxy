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
    }

    func updateAllWorkspaces(with batch: [HTTPTransaction]) {
        for workspace in workspaceStore.workspaces {
            for transaction in batch {
                updateDomainTree(for: transaction, in: workspace)
                updateAppNodes(for: transaction, in: workspace)
            }
            appendFilteredTransactions(batch, to: workspace)
        }
    }

    // MARK: - Per-Workspace Sidebar

    func updateDomainTree(for transaction: HTTPTransaction, in workspace: WorkspaceState) {
        let domain = transaction.request.host
        guard !domain.isEmpty else {
            return
        }

        if let sidebarDomain = workspace.filterCriteria.sidebarDomain {
            guard domain.hasSuffix(sidebarDomain) || domain == sidebarDomain else {
                return
            }
        }

        if let index = workspace.domainIndexMap[domain] {
            workspace.domainTree[index].requestCount += 1
        } else {
            let node = DomainNode(id: domain, domain: domain, requestCount: 1, children: [])
            workspace.domainIndexMap[domain] = workspace.domainTree.count
            workspace.domainTree.append(node)
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
        workspace.appNodes.removeAll()
        workspace.appNodeIndexMap.removeAll()
        for transaction in transactions {
            updateDomainTree(for: transaction, in: workspace)
            updateAppNodes(for: transaction, in: workspace)
        }
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
