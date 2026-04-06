import Foundation
import os

/// Append-only buffer for log entries with a default cap of 100k entries.
/// When capacity is exceeded, the oldest 10% of entries are discarded to maintain
/// bounded memory usage while preserving recent context. Older entries should be
/// persisted to `SessionStore` (SQLite) before eviction if long-term retention is needed.
actor InMemoryLogBuffer {
    // MARK: Lifecycle

    init(maxCapacity: Int = 100_000) {
        self.maxCapacity = maxCapacity
    }

    // MARK: Internal

    var count: Int {
        entries.count
    }

    func append(_ entry: LogEntry) {
        entries.append(entry)
        evictIfNeeded()
    }

    func allEntries() -> [LogEntry] {
        entries
    }

    func clear() {
        entries.removeAll()
        Self.logger.info("Log buffer cleared")
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "InMemoryLogBuffer")

    private var entries: [LogEntry] = []
    private let maxCapacity: Int

    private func evictIfNeeded() {
        guard entries.count > maxCapacity else {
            return
        }
        let evictCount = maxCapacity / 10
        entries.removeFirst(evictCount)
        Self.logger.info("Evicted \(evictCount) log entries from buffer")
    }
}
