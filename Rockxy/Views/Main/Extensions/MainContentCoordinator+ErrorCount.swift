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
        }
        errorCount = erroredTransactionIDs.count
        // The signal badges are derived from the retained rows exactly as this count is,
        // so they are maintained from the same two points. Giving them their own call
        // sites is what would let the two drift apart.
        updateTrafficSignalCounts(for: updatedTransactions)
    }

    static func isErrorResponse(_ transaction: HTTPTransaction) -> Bool {
        (transaction.response?.statusCode ?? 0) >= 400
    }
}
