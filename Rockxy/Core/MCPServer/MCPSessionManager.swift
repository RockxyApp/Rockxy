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
///
/// A session expires after `MCPLimits.sessionTimeout` of being *idle*, not of
/// existing: a client working through a long investigation would otherwise be cut
/// off mid-request while an abandoned session kept its slot until the same fixed
/// deadline. `MCPLimits.maxSessionLifetime` still caps a session that is kept warm forever,
/// because refreshing on use alone would leave the lifetime unbounded.
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
        let now = Date()
        sessions[id] = Session(createdAt: now, lastUsedAt: now)
        mcpSessionLogger.info("Created MCP session \(id, privacy: .private(mask: .hash))")
        return id
    }

    /// Validating is the only evidence of use the manager gets — the handler calls it
    /// on every request that carries a session id — so it doubles as the idle refresh.
    func validateSession(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let session = sessions[id] else {
            return false
        }
        let now = Date()
        if let reason = Self.expiry(of: session, now: now) {
            sessions.removeValue(forKey: id)
            mcpSessionLogger.info("Session \(id, privacy: .private(mask: .hash)) expired (\(reason, privacy: .public))")
            return false
        }
        sessions[id]?.lastUsedAt = now
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
    /// Ages both timestamps, so a test can drive either expiry rule to its deadline.
    func setSessionTimestamp(_ date: Date, for id: String) {
        lock.lock()
        defer { lock.unlock() }

        guard sessions[id] != nil else {
            return
        }
        sessions[id] = Session(createdAt: date, lastUsedAt: date)
    }

    /// Ages creation only, leaving the session freshly used, so a test can reach the
    /// absolute cap without also crossing the idle deadline.
    func setSessionCreation(_ date: Date, for id: String) {
        lock.lock()
        defer { lock.unlock() }

        sessions[id]?.createdAt = date
    }
    #endif

    // MARK: Private

    private struct Session {
        var createdAt: Date
        var lastUsedAt: Date
    }

    private let lock = NSLock()
    private var sessions: [String: Session] = [:]

    /// The reason this session is over, or `nil` while it is still valid. The string is
    /// a fixed label, never session data.
    private static func expiry(of session: Session, now: Date) -> String? {
        if now.timeIntervalSince(session.lastUsedAt) > MCPLimits.sessionTimeout {
            return "idle"
        }
        if now.timeIntervalSince(session.createdAt) > MCPLimits.maxSessionLifetime {
            return "max lifetime"
        }
        return nil
    }

    private func removeExpiredSessionsLocked(now: Date) -> Int {
        var expiredIDs: [String] = []
        for (id, session) in sessions where Self.expiry(of: session, now: now) != nil {
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
