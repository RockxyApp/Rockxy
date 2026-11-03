import Foundation

// Extends `MainContentCoordinator` with incremental upkeep for the maintained indexes
// that a retention step used to rebuild from the whole retained history.

// MARK: - MainContentCoordinator + EvictionMaintenance

extension MainContentCoordinator {
    /// Folds one retention step into the observed-domain ledger.
    ///
    /// The ledger records the app and host each row was actually counted under, which is
    /// what makes a removal derivable: `rebuildObservedDomainsByApp()` had to read the
    /// mutable client of every retained row to answer the same question. It is already the
    /// authority the enrichment path (`moveObservedDomainsFromUnknown(for:)`) moves rows
    /// with, so subtracting the entries of the rows that left leaves exactly the state a
    /// rebuild from the remaining history would.
    ///
    /// Appends are applied first so a row that arrived and was evicted in the same step
    /// nets out, as it would in a rebuild from the post-eviction history.
    func retainObservedDomainsByApp(
        removing removed: [HTTPTransaction],
        appending appended: [HTTPTransaction]
    ) {
        appendObservedDomainsByApp(from: appended)
        guard !removed.isEmpty else {
            return
        }
        var changedApps: Set<String> = []
        for transaction in removed {
            // Keyed by object, and removed rather than read, so a row delivered under two
            // aliases of the same id is subtracted once rather than twice.
            guard let old = observedDomainContributions.removeValue(forKey: ObjectIdentifier(transaction)) else {
                continue
            }
            let remaining = (observedDomainCountsByApp[old.app]?[old.host] ?? 0) - old.count
            if remaining <= 0 {
                observedDomainCountsByApp[old.app]?.removeValue(forKey: old.host)
            } else {
                observedDomainCountsByApp[old.app]?[old.host] = remaining
            }
            if observedDomainCountsByApp[old.app]?.isEmpty == true {
                observedDomainCountsByApp.removeValue(forKey: old.app)
            }
            changedApps.insert(old.app)
        }
        publishObservedDomains(for: changedApps)
    }

    /// Folds one retention step into the Assistant's host index.
    ///
    /// `rebuildDebugAssistantTrafficIndex()` allocated a fresh `transactions +
    /// persistedFavorites` array, a set of every id, and a dictionary of arrays over the
    /// whole history, on every batch once the cap was reached. The guard is the one
    /// `appendToDebugAssistantTrafficIndex(_:)` uses: if the index does not describe the
    /// history this step started from, there is nothing to patch and the rebuild is the
    /// only correct answer.
    func retainDebugAssistantTrafficIndex(
        removing removed: [HTTPTransaction],
        appending appended: [HTTPTransaction]
    ) {
        let expectedPreviousLiveCount = transactions.count + removed.count - appended.count
        guard debugAssistantIndexedLiveCount == expectedPreviousLiveCount,
              debugAssistantIndexedFavoriteCount == persistedFavorites.count else
        {
            rebuildDebugAssistantTrafficIndex()
            return
        }
        for transaction in appended where debugAssistantIndexedTransactionIDs.insert(transaction.id).inserted {
            let host = transaction.request.host
            debugAssistantTransactionsByHost[host, default: []].append(transaction)
            debugAssistantIndexedHostByID[transaction.id] = host
        }
        let favoritesByID: [UUID: HTTPTransaction] = removed.isEmpty ? [:] : Dictionary(
            persistedFavorites.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for transaction in removed {
            let id = transaction.id
            // The bucket the row was filed under, not the one its request names now: a
            // rule rewrite or a replay can change `request` after indexing, and looking up
            // the current host would leave the evicted row in the index -- holding the last
            // strong reference to a row the user can no longer see.
            guard let host = debugAssistantIndexedHostByID.removeValue(forKey: id) else {
                continue
            }
            debugAssistantTransactionsByHost[host]?.removeAll { $0.id == id }
            if debugAssistantTransactionsByHost[host]?.isEmpty == true {
                debugAssistantTransactionsByHost.removeValue(forKey: host)
            }
            debugAssistantIndexedTransactionIDs.remove(id)
            // A saved request keeps its place when the live row behind it is evicted,
            // because a rebuild indexes `transactions + persistedFavorites` and would
            // still find it -- under the saved copy rather than the evicted object.
            guard let favorite = favoritesByID[id] else {
                continue
            }
            let favoriteHost = favorite.request.host
            debugAssistantTransactionsByHost[favoriteHost, default: []].append(favorite)
            debugAssistantIndexedHostByID[id] = favoriteHost
            debugAssistantIndexedTransactionIDs.insert(id)
        }
        debugAssistantIndexedLiveCount = transactions.count
        debugAssistantIndexedFavoriteCount = persistedFavorites.count
        debugAssistantTrafficIndexGeneration &+= 1
        debugAssistantRelatedCache = nil
    }

    /// Folds one retention step into the error count, the TLS-failure set, and the
    /// sidebar's Traffic Signal badges.
    ///
    /// This is the third sanctioned maintenance point for those, beside
    /// `recomputeErrorCount()` and `updateErrorCount(for:)`, and exists for the same
    /// reason the other two are split: a removal is the one change whose effect cannot be
    /// derived from the rows handed to us -- unless the rows that left are handed over
    /// too, which a retention step does. It costs the step rather than the two O(history)
    /// passes `recomputeErrorCount()` made, plus the one in `recomputeTrafficSignalCounts()`.
    ///
    /// Everything `recomputeErrorCount()` does besides counting still happens here:
    /// `erroredTransactionIDs` and `tlsFailureTransactionIDs` are maintained by id instead
    /// of rebuilt (eviction removes every row carrying an id, so no retained row can share
    /// one), and the sidebar favourites cache is still retired -- a list cached from the
    /// previous contents of the history can name a row that is now gone, and the cache key
    /// no longer carries `transactions.count`, so this is what retires it.
    func retainErrorAndSignalCounts(
        removing removed: [HTTPTransaction],
        appending appended: [HTTPTransaction]
    ) {
        updateErrorCount(for: appended)
        guard !removed.isEmpty else {
            return
        }
        var counts = trafficSignalCounts
        for transaction in removed {
            let id = transaction.id
            erroredTransactionIDs.remove(id)
            tlsFailureTransactionIDs.remove(id)
            guard let mask = signalMaskByTransactionID.removeValue(forKey: id) else {
                continue
            }
            for (index, signal) in TrafficSignal.allCases.enumerated() where mask & (1 << UInt8(index)) != 0 {
                counts[signal, default: 0] -= 1
            }
        }
        trafficSignalCounts = counts
        errorCount = erroredTransactionIDs.count
        invalidateSidebarFavoriteCache()
    }
}
