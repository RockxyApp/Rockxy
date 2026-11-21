import Foundation

// Extends `MainContentCoordinator` with the error-response counter shown in the status bar.

// MARK: - MainContentCoordinator + ErrorCount

extension MainContentCoordinator {
    /// Rebuilds the count from the whole retained capture.
    ///
    /// Use this only where rows left the history -- eviction, Clear Session, deleting a
    /// domain or an app's traffic -- because a removal is the one change whose effect on
    /// the count cannot be derived from the rows handed to us. Everything that adds or
    /// refreshes rows goes through `updateErrorCount(for:)` instead.
    func recomputeErrorCount() {
        erroredTransactionIDs = Set(
            transactions.lazy.filter(Self.isErrorResponse).map(\.id)
        )
        errorCount = erroredTransactionIDs.count
        rebuildTLSFailureTransactionIDs()
        // This is the removal path, so a favourites list cached from the previous
        // contents of the history may now name a row that is gone. The cache key no
        // longer carries `transactions.count`, so this is what retires such a list.
        invalidateSidebarFavoriteCache()
        recomputeTrafficSignalCounts()
    }

    /// Folds just the rows that arrived or changed into the count.
    ///
    /// Costs the size of the batch rather than the size of the capture, which matters
    /// because live rows refresh at display cadence for as long as a stream stays open.
    /// Tracking identities also makes a repeated delivery harmless: a WebSocket is
    /// delivered once when it opens and again when it closes, and the old `+=` counted
    /// such a row twice if both deliveries carried an error response.
    func updateErrorCount(for updatedTransactions: some Sequence<HTTPTransaction>) {
        for transaction in updatedTransactions {
            if Self.isErrorResponse(transaction) {
                erroredTransactionIDs.insert(transaction.id)
            } else {
                erroredTransactionIDs.remove(transaction.id)
            }
            // A row's TLS disposition is stamped on the same deliveries that carry its
            // response, so the set that the status bar's "available" count subtracts is
            // maintained here rather than at its own call sites, for the same reason the
            // signal badges are: separate call sites are what would let them drift.
            if transaction.isTLSFailure {
                tlsFailureTransactionIDs.insert(transaction.id)
            } else {
                tlsFailureTransactionIDs.remove(transaction.id)
            }
        }
        errorCount = erroredTransactionIDs.count
        // The signal badges are derived from the retained rows exactly as this count is,
        // so they are maintained from the same two points. Giving them their own call
        // sites is what would let the two drift apart.
        updateTrafficSignalCounts(for: updatedTransactions)
    }

    /// Rebuilds `tlsFailureTransactionIDs` from the whole retained capture.
    ///
    /// Lives beside the error count because it is maintained with it, and is reachable on
    /// its own for one reason: Clear Session empties the history without going through
    /// `recomputeErrorCount()` -- it resets the error and signal state inline -- and a set
    /// left describing cleared rows would be subtracted from a history that no longer
    /// holds them, under-reporting the status bar's "available" count for the rest of the
    /// session. `resetTrafficMetrics()` is the point on that path this file can reach.
    func rebuildTLSFailureTransactionIDs() {
        tlsFailureTransactionIDs = Set(
            transactions.lazy.filter(\.isTLSFailure).map(\.id)
        )
    }

    static func isErrorResponse(_ transaction: HTTPTransaction) -> Bool {
        (transaction.response?.statusCode ?? 0) >= 400
    }
}
