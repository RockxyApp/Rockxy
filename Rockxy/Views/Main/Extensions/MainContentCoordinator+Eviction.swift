import Foundation
import os

// Extends `MainContentCoordinator` with eviction behavior for the main workspace.

// MARK: - MainContentCoordinator + Eviction

extension MainContentCoordinator {
    func evictOldestTransactions(count: Int) {
        guard count > 0, !transactions.isEmpty else {
            return
        }
        let removedIDs = Self.evictionCandidateIDs(in: transactions, count: count, includesImported: true)
        let removeCount = removedIDs.count

        transactions.removeAll { removedIDs.contains($0.id) }
        transactionsByProjectID[projectStore.activeProjectID] = transactions
        rebuildObservedDomainsByApp()
        recomputeErrorCount()
        evictFromAllWorkspaces(removedIDs: removedIDs)

        Self.logger.info("Evicted \(removeCount) oldest transactions (remaining: \(self.transactions.count))")
    }

    /// The rows to drop when history is over its cap, oldest first: finished rows before
    /// connections and streams that are still open, so an open WebSocket, SSE stream, or
    /// pending request is not dropped while ordinary requests captured after it remain.
    /// Imported rows are only chosen when `includesImported` is set (memory pressure).
    static func evictionCandidateIDs(
        in history: [HTTPTransaction],
        count: Int,
        includesImported: Bool
    )
        -> Set<UUID>
    {
        guard count > 0 else {
            return []
        }
        var selected = Set<UUID>()
        for takesOpenRows in [false, true] {
            for transaction in history {
                if selected.count >= count {
                    return selected
                }
                let isOpen = transaction.state == .pending || transaction.isRunning
                guard isOpen == takesOpenRows,
                      includesImported || !transaction.isImported
                else {
                    continue
                }
                selected.insert(transaction.id)
            }
        }
        return selected
    }

    func rebuildSidebarIndexes() {
        rebuildSidebarIndexes(for: activeWorkspace)
    }
}
