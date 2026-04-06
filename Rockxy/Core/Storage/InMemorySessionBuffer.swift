import Foundation
import os

/// Ring buffer holding active HTTP transactions in memory (default cap: 50k).
/// Uses a dictionary for O(1) lookups by ID and a parallel ordered-ID array to
/// preserve insertion order for the request list UI. When capacity is exceeded,
/// the oldest 10% of entries are evicted to keep memory bounded.
actor InMemorySessionBuffer {
    // MARK: Lifecycle

    init(maxCapacity: Int = 50000) {
        self.maxCapacity = maxCapacity
    }

    // MARK: Internal

    var count: Int {
        transactions.count
    }

    func append(_ transaction: HTTPTransaction) {
        transactions[transaction.id] = transaction
        orderedIds.append(transaction.id)
        evictIfNeeded()
    }

    func transaction(for id: UUID) -> HTTPTransaction? {
        transactions[id]
    }

    func allTransactions() -> [HTTPTransaction] {
        orderedIds.compactMap { transactions[$0] }
    }

    func clear() {
        transactions.removeAll()
        orderedIds.removeAll()
        Self.logger.info("Session buffer cleared")
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "InMemorySessionBuffer")

    private var transactions: [UUID: HTTPTransaction] = [:]
    private var orderedIds: [UUID] = []
    private let maxCapacity: Int

    private func evictIfNeeded() {
        guard transactions.count > maxCapacity else {
            return
        }
        let evictCount = maxCapacity / 10
        let idsToRemove = Array(orderedIds.prefix(evictCount))
        for id in idsToRemove {
            transactions.removeValue(forKey: id)
        }
        orderedIds.removeFirst(evictCount)
        Self.logger.info("Evicted \(evictCount) transactions from buffer")
    }
}
