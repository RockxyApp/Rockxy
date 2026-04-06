import Foundation
import os
import OSLog

/// Streams entries from the macOS unified logging system (OSLog) by polling `OSLogStore`.
///
/// Uses `scope: .currentProcessIdentifier` because `OSLogStore.system` requires the
/// `com.apple.logging.read` entitlement, which is not available to third-party apps.
/// Polls every 500ms, advancing the position cursor to avoid re-delivering entries.
enum OSLogSource {
    nonisolated static func startStreaming(
        subsystem: String?,
        since: Date,
        handler: @Sendable @escaping (LogEntry) -> Void
    )
        -> Task<Void, Never>
    {
        let startDate = since
        let subsystemFilter = subsystem

        return Task.detached {
            let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "OSLogSource")

            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                var lastPosition = store.position(date: startDate)

                while !Task.isCancelled {
                    do {
                        let predicate = subsystemFilter.map {
                            NSPredicate(format: "subsystem == %@", $0)
                        }
                        let entries = try store.getEntries(at: lastPosition, matching: predicate)

                        for entry in entries {
                            guard !Task.isCancelled else {
                                return
                            }
                            guard let logEntry = entry as? OSLogEntryLog else {
                                continue
                            }

                            let level: LogLevel = switch logEntry.level {
                            case .debug: .debug
                            case .info: .info
                            case .notice: .notice
                            case .error: .error
                            case .fault: .fault
                            case .undefined: .debug
                            @unknown default: .info
                            }

                            let mapped = LogEntry(
                                id: UUID(),
                                timestamp: logEntry.date,
                                level: level,
                                message: logEntry.composedMessage,
                                source: .oslog(subsystem: logEntry.subsystem),
                                processName: logEntry.process,
                                subsystem: logEntry.subsystem,
                                category: logEntry.category,
                                metadata: [:],
                                correlatedTransactionId: nil
                            )
                            handler(mapped)
                        }

                        lastPosition = store.position(date: Date())
                    } catch {
                        logger.error("Failed to fetch log entries: \(error.localizedDescription)")
                    }

                    try? await Task.sleep(for: .milliseconds(500))
                }
            } catch {
                logger.error("Failed to create OSLogStore: \(error.localizedDescription)")
            }
        }
    }
}
