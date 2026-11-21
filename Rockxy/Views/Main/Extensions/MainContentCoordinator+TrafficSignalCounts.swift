import Foundation

// Extends `MainContentCoordinator` with the Traffic Signal badge counts the sidebar shows.

// MARK: - MainContentCoordinator + TrafficSignalCounts

extension MainContentCoordinator {
    /// Rebuilds every signal count from the whole retained capture.
    ///
    /// Use this only where rows left the history, for the same reason
    /// `recomputeErrorCount()` does: a removal is the one change whose effect cannot be
    /// derived from the rows handed to us, because the deleted rows are already gone.
    func recomputeTrafficSignalCounts() {
        signalMaskByTransactionID.removeAll(keepingCapacity: true)
        signalMaskByTransactionID.reserveCapacity(transactions.count)
        var counts: [TrafficSignal: Int] = [:]
        for transaction in transactions {
            let mask = Self.trafficSignalMask(for: transaction)
            guard mask != 0 else {
                continue
            }
            signalMaskByTransactionID[transaction.id] = mask
            for (index, signal) in TrafficSignal.allCases.enumerated() where mask & (1 << UInt8(index)) != 0 {
                counts[signal, default: 0] += 1
            }
        }
        trafficSignalCounts = counts
    }

    /// Folds just the rows that arrived or changed into the counts.
    ///
    /// The badges used to be computed inside the sidebar's own `body`, once per signal,
    /// each pass counting the whole retained capture. That cost grew with how long
    /// capture had run, and it was self-sustaining: evaluating the predicates inside a
    /// view body registers an observation dependency on nearly every property of every
    /// retained row, so the next arriving response invalidated the sidebar and the five
    /// scans ran again.
    func updateTrafficSignalCounts(for updatedTransactions: some Sequence<HTTPTransaction>) {
        var counts = trafficSignalCounts
        for transaction in updatedTransactions {
            let previousMask = signalMaskByTransactionID[transaction.id] ?? 0
            let mask = Self.trafficSignalMask(for: transaction)
            guard previousMask != mask else {
                continue
            }
            if mask == 0 {
                signalMaskByTransactionID.removeValue(forKey: transaction.id)
            } else {
                signalMaskByTransactionID[transaction.id] = mask
            }
            for (index, signal) in TrafficSignal.allCases.enumerated() {
                let bit: UInt8 = 1 << UInt8(index)
                let wasCounted = previousMask & bit != 0
                let isCounted = mask & bit != 0
                guard wasCounted != isCounted else {
                    continue
                }
                counts[signal, default: 0] += isCounted ? 1 : -1
            }
        }
        trafficSignalCounts = counts
    }

    /// Which signals a row currently belongs to, one bit per `TrafficSignal.allCases`
    /// position. Remembering it is what lets a refresh adjust the counts from the batch
    /// alone: a row acquires and loses signals as its response and timing arrive.
    static func trafficSignalMask(for transaction: HTTPTransaction) -> UInt8 {
        guard !transaction.isTLSFailure else {
            return 0
        }
        var mask: UInt8 = 0
        for (index, signal) in TrafficSignal.allCases.enumerated() where signal.matches(transaction) {
            mask |= 1 << UInt8(index)
        }
        return mask
    }
}
