import Foundation
import os

// Tells an open Script Editor how the script's latest run went, without flooding the main thread.

// MARK: - ScriptRunReport

struct ScriptRunReport: Equatable, Sendable {
    enum Phase: String, Sendable {
        case request
        case response
    }

    enum Outcome: Equatable, Sendable {
        case succeeded
        case failed(String)
    }

    let pluginID: String
    let phase: Phase
    let outcome: Outcome
    let timestamp: Date
}

// MARK: - ScriptRunReporter

/// Publishes `ScriptRunReport`s for the editor's status line. Successes and repeated identical
/// failures are coalesced to at most one per script and phase per interval, because a busy script
/// can run hundreds of times a second; a new failure reason always publishes at once.
final class ScriptRunReporter: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        successInterval: TimeInterval = 1,
        now: @escaping @Sendable () -> Date = Date.init,
        sink: @escaping @Sendable (ScriptRunReport) -> Void = { report in
            NotificationCenter.default.post(name: .scriptRunDidFinish, object: report)
        }
    ) {
        self.successInterval = successInterval
        self.now = now
        self.sink = sink
    }

    // MARK: Internal

    func reportSuccess(pluginID: String, phase: ScriptRunReport.Phase) {
        let timestamp = now()
        let key = "\(pluginID)|\(phase.rawValue)"
        let shouldPublish = state.withLock { lastSuccess -> Bool in
            if let last = lastSuccess[key], timestamp.timeIntervalSince(last) < successInterval {
                return false
            }
            lastSuccess[key] = timestamp
            return true
        }
        guard shouldPublish else {
            return
        }
        sink(ScriptRunReport(pluginID: pluginID, phase: phase, outcome: .succeeded, timestamp: timestamp))
    }

    /// Failures publish at once when the reason changes, and otherwise at most once per interval,
    /// so a script that fails on every request cannot flood the main thread either.
    func reportFailure(pluginID: String, phase: ScriptRunReport.Phase, reason: String) {
        let timestamp = now()
        let key = "\(pluginID)|\(phase.rawValue)"
        let shouldPublish = failures.withLock { last -> Bool in
            if let previous = last[key], previous.reason == reason,
               timestamp.timeIntervalSince(previous.at) < successInterval
            {
                return false
            }
            last[key] = (reason, timestamp)
            return true
        }
        // A failure resets success coalescing so the next success is shown right away.
        state.withLock { lastSuccess in
            lastSuccess[key] = nil
        }
        guard shouldPublish else {
            return
        }
        sink(ScriptRunReport(pluginID: pluginID, phase: phase, outcome: .failed(reason), timestamp: timestamp))
    }

    // MARK: Private

    private let successInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let sink: @Sendable (ScriptRunReport) -> Void
    private let state = OSAllocatedUnfairLock<[String: Date]>(initialState: [:])
    private let failures = OSAllocatedUnfairLock<[String: (reason: String, at: Date)]>(initialState: [:])
}
