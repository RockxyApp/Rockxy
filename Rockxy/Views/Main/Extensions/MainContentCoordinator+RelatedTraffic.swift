import Foundation

// Extends `MainContentCoordinator` with the bounded same-host neighbour query the
// inspector's Details tab reads.

// MARK: - MainContentCoordinator + RelatedTraffic

extension MainContentCoordinator {
    /// The `limit` retained requests to the same host as `transaction` that are closest to
    /// it in time, nearest first, excluding `transaction` itself.
    ///
    /// A bounded selection rather than a sort, because every caller wants a handful of
    /// neighbours. The Details tab built this by filtering the whole capture and then
    /// sorting the same-host slice by distance -- three times per render, in the `body` of
    /// the Context Dock's default tab -- so reading six neighbours cost a full comparison
    /// sort, and touching each candidate's response registered an observation dependency
    /// on it, which let the next arriving response invalidate the pane and start the sorts
    /// again.
    func nearestTransactions(toSameHostAs transaction: HTTPTransaction, limit: Int) -> [HTTPTransaction] {
        guard limit > 0 else {
            return []
        }
        let host = transaction.request.host
        let pivot = transaction.timestamp
        var nearest: [(distance: TimeInterval, transaction: HTTPTransaction)] = []
        nearest.reserveCapacity(limit)
        for candidate in transactions
            where candidate.id != transaction.id && candidate.request.host == host
        {
            let distance = abs(candidate.timestamp.timeIntervalSince(pivot))
            if nearest.count == limit {
                guard let worst = nearest.last, distance < worst.distance else {
                    continue
                }
                nearest.removeLast()
            }
            // `limit` is 20 at most, so the insertion walk is bounded by it rather than by
            // how long capture has run, which is the whole point of selecting here.
            let insertion = nearest.firstIndex { distance < $0.distance } ?? nearest.count
            nearest.insert((distance: distance, transaction: candidate), at: insertion)
        }
        return nearest.map(\.transaction)
    }
}
