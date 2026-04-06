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
        // Find the closest transaction within the time window
        let matchingTransaction = transactions
            .filter { abs($0.timestamp.timeIntervalSince(logEntry.timestamp)) < timeWindow }
            .min {
                abs($0.timestamp.timeIntervalSince(logEntry.timestamp)) <
                    abs($1.timestamp.timeIntervalSince(logEntry.timestamp))
            }
        return matchingTransaction?.id
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "LogCorrelator")
}
