import Dispatch
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

        // Taken before the removal, because the ledgers below are subtracted from rather
        // than rebuilt and the rows they describe have to still be in hand.
        let removed = transactions.filter { removedIDs.contains($0.id) }
        transactions.removeAll { removedIDs.contains($0.id) }
        transactionsByProjectID[projectStore.activeProjectID] = transactions
        retainObservedDomainsByApp(removing: removed, appending: [])
        retainErrorAndSignalCounts(removing: removed, appending: [])
        // Evicted rows have to leave the byte total as well, or the footer keeps
        // counting traffic the user can no longer see.
        rebuildTrafficTotals(from: transactions)
        evictFromAllWorkspaces(removedIDs: removedIDs, removed: removed)

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
                      includesImported || !transaction.isImported else
                {
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

    // MARK: - Memory pressure

    /// Starts responding to system memory pressure while capture runs.
    ///
    /// `evictOldestTransactions(count:)` is the only path that can reclaim imported rows,
    /// which the live cap never trims, and until now nothing in the app could reach it:
    /// its only trigger was `.bufferEvictionRequested`, which the shipping app never
    /// posts (`TrafficSessionManager.reportAcceptedCount` has no caller outside tests, so
    /// its overflow accounting never runs). The live cap in the capture path kept history
    /// bounded, but a long session that also imported or received rows had no reclamation
    /// at all and the app ignored system pressure entirely.
    ///
    /// Installing it here, rather than once per coordinator, keeps it to sessions that
    /// actually capture: that is the long-running case, and it keeps a pressure event from
    /// discarding rows in a coordinator that is only displaying an imported file.
    func installMemoryPressureEviction() {
        memoryPressureSource?.cancel()
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        // The handler reads the event through the stored property rather than capturing
        // `source`: a dispatch source retains its handler, so capturing the source inside
        // its own handler is a cycle that `cancel()` does not break. The queue is `.main`,
        // so this runs on the main thread already -- a `Task` hop would delay the response
        // until after whatever is already queued, which under pressure is the wrong end.
        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let isCritical = memoryPressureSource?.data.contains(.critical) ?? false
            MainActor.assumeIsolated {
                self.evictForMemoryPressure(isCritical: isCritical)
            }
        }
        source.activate()
        memoryPressureSource = source
    }

    func cancelMemoryPressureEviction() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    /// Drops a bounded slice of the oldest rows, imported ones included.
    ///
    /// Two guards matter more than the slice size. The floor keeps a small session intact:
    /// pressure caused by something else on the machine must not cost the user the handful
    /// of rows they are reading. The interval keeps the response from becoming the problem:
    /// the kernel can deliver pressure events in bursts, and each eviction still rebuilds
    /// every workspace's sidebar indexes over the whole history, so an unthrottled handler
    /// would stall the main thread exactly when the machine is already struggling.
    func evictForMemoryPressure(isCritical: Bool, now: Date = Date()) {
        guard transactions.count > Self.memoryPressureHistoryFloor else {
            return
        }
        if let last = lastMemoryPressureEvictionAt,
           now.timeIntervalSince(last) < Self.memoryPressureEvictionInterval
        {
            return
        }
        let share = isCritical ? 4 : 10
        let minimum = isCritical ? 250 : 100
        let count = min(transactions.count, max(minimum, transactions.count / share))
        lastMemoryPressureEvictionAt = now
        Self.logger.info(
            "Memory pressure (\(isCritical ? "critical" : "warning", privacy: .public)): evicting \(count)"
        )
        evictOldestTransactions(count: count)
    }

    /// Below this many rows a pressure event reclaims nothing: the win would be negligible
    /// and the cost is the user's visible session.
    static let memoryPressureHistoryFloor = 200
    static let memoryPressureEvictionInterval: TimeInterval = 5
}
