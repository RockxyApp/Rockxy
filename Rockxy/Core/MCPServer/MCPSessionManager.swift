import Foundation
import os

/// Logger must be nonisolated(unsafe) because MCPSessionManager is accessed
/// from NIO event loop threads outside Swift's structured concurrency.
nonisolated(unsafe) private let mcpSessionLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "MCPSessionManager"
)

// MARK: - MCPSessionManager

/// Thread-safe session manager for MCP connections. Uses `NSLock` because
/// this is accessed from NIO event loop threads, not Swift actors.
final class MCPSessionManager: @unchecked Sendable {
    // MARK: Internal

    var activeSessions: Int {
        lock.lock()
        defer { lock.unlock() }
        return sessions.count
    }

    func createSession() -> String? {
        lock.lock()
        defer { lock.unlock() }

        _ = removeExpiredSessionsLocked(now: Date())

        guard sessions.count < MCPLimits.maxConcurrentSessions else {
            mcpSessionLogger.warning(
                "Session limit reached (\(MCPLimits.maxConcurrentSessions)), rejecting new session"
            )
            return nil
        }

        let id = UUID().uuidString
        sessions[id] = Date()
        mcpSessionLogger.info("Created MCP session \(id, privacy: .private(mask: .hash))")
        return id
    }

    func validateSession(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let created = sessions[id] else {
            return false
        }
        let elapsed = Date().timeIntervalSince(created)
        if elapsed > MCPLimits.sessionTimeout {
            sessions.removeValue(forKey: id)
            mcpSessionLogger.info("Session \(id, privacy: .private(mask: .hash)) expired after \(Int(elapsed))s")
            return false
        }
        return true
    }

    func removeSession(_ id: String) {
        lock.lock()
        defer { lock.unlock() }

        if sessions.removeValue(forKey: id) != nil {
            mcpSessionLogger.info("Removed MCP session \(id, privacy: .private(mask: .hash))")
        }
    }

    func removeExpiredSessions() {
        lock.lock()
        defer { lock.unlock() }

        _ = removeExpiredSessionsLocked(now: Date())
    }

    #if DEBUG
    func setSessionTimestamp(_ date: Date, for id: String) {
        lock.lock()
        defer { lock.unlock() }

        guard sessions[id] != nil else {
            return
        }
        sessions[id] = date
    }
    #endif

    // MARK: Private

    private let lock = NSLock()
    private var sessions: [String: Date] = [:]

    private func removeExpiredSessionsLocked(now: Date) -> Int {
        var expiredIDs: [String] = []
        for (id, created) in sessions where now.timeIntervalSince(created) > MCPLimits.sessionTimeout {
            expiredIDs.append(id)
        }
        for id in expiredIDs {
            sessions.removeValue(forKey: id)
        }
        if !expiredIDs.isEmpty {
            mcpSessionLogger.info("Evicted \(expiredIDs.count) expired MCP session(s)")
        }
        return expiredIDs.count
    }
}
