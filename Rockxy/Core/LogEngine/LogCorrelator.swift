import Foundation
import os

/// Associates log entries with network transactions based on temporal proximity.
/// A log entry is linked to the closest transaction whose timestamp falls within the
/// configured time window (default 1 second). This heuristic works well when a single
/// app is being debugged; multi-app scenarios may need process-based correlation.
enum LogCorrelator {
    // MARK: Internal

    static func correlate(
        logEntry: LogEntry,
        with transactions: [HTTPTransaction],
        timeWindow: TimeInterval = 1.0
    )
        -> UUID?
    {
        // Capture completion order is not timestamp order: a long request can arrive
        // after newer ones. Scan once without allocating a matching-history array.
        var closest: UUID?
        var closestDistance = timeWindow
        for transaction in transactions {
            let distance = abs(transaction.timestamp.timeIntervalSince(logEntry.timestamp))
            guard distance < closestDistance else {
                continue
            }
            closest = transaction.id
            closestDistance = distance
            if distance == 0 {
                break
            }
        }
        return closest
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "LogCorrelator")
}
