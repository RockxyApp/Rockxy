import Foundation
import os

// Extends `MainContentCoordinator` with logs behavior for the main workspace.

// MARK: - MainContentCoordinator + Logs

/// Coordinator extension for OSLog and process log capture lifecycle. Incoming log entries
/// are correlated with network transactions by timestamp and process, then appended to the
/// in-memory buffer with overflow eviction based on `maxLogBufferSize`.
extension MainContentCoordinator {
    // MARK: - Log Capture Lifecycle

    func startLogCapture() {
        Self.logger.info("Starting log capture")
        let contextStore = captureContextStore
        let recordingGate = captureRecordingGate
        Task {
            await logEngine.setOnLogEntry { [weak self] entry in
                guard let self else {
                    return
                }
                guard recordingGate.allowsCapture() else {
                    return
                }
                let captureContext = contextStore.snapshot()
                Task { @MainActor in
                    self.addLogEntry(entry, captureContext: captureContext)
                }
            }

            await logEngine.startCapture()
            Self.logger.info("Log capture started")
        }
    }

    func stopLogCapture() {
        Task {
            await logEngine.stopCapture()
            Self.logger.info("Log capture stopped")
        }
    }

    // MARK: - Log Entry Processing

    func addLogEntry(_ entry: LogEntry) {
        addLogEntry(entry, captureContext: activeCaptureContext)
    }

    /// Routes and correlates a log using the Project ownership captured when the
    /// log engine delivered it, not whichever Project is active after the main-
    /// actor hop. Stale, deleted, or cleared Project generations fail closed.
    func addLogEntry(_ entry: LogEntry, captureContext: TrafficCaptureContext?) {
        guard let captureContext,
              captureContext.sessionID == captureContext.projectID,
              projectStore.projects.contains(where: { $0.id == captureContext.projectID }),
              captureContext.generation
                == captureGenerationByProjectID[captureContext.projectID, default: 0] else
        {
            Self.logger.debug("Dropped log entry with stale or unknown Project ownership")
            return
        }

        var mutableEntry = entry
        let settings = AppSettingsStorage.load()
        let projectID = captureContext.projectID
        let projectTransactions = if projectID == projectStore.activeProjectID {
            transactions
        } else {
            transactionsByProjectID[projectID] ?? []
        }
        if let correlatedId = LogCorrelator.correlate(
            logEntry: entry,
            with: projectTransactions
        ) {
            mutableEntry.correlatedTransactionId = correlatedId
        }

        if projectID == projectStore.activeProjectID {
            logEntries.append(mutableEntry)
            if logEntries.count > settings.maxLogBufferSize {
                let excess = logEntries.count - settings.maxLogBufferSize
                logEntries.removeFirst(excess)
                Self.logger.debug("Evicted \(excess) oldest log entries")
            }
        } else {
            var projectLogs = logEntriesByProjectID[projectID] ?? []
            projectLogs.append(mutableEntry)
            if projectLogs.count > settings.maxLogBufferSize {
                let excess = projectLogs.count - settings.maxLogBufferSize
                projectLogs.removeFirst(excess)
                Self.logger.debug("Evicted \(excess) oldest log entries")
            }
            logEntriesByProjectID[projectID] = projectLogs
        }
    }
}
