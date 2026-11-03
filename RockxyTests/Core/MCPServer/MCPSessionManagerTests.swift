import Foundation
@testable import Rockxy
import Testing

// MARK: - MCPSessionManagerTests

@Suite("MCP Session Manager")
struct MCPSessionManagerTests {
    @Test("Create session returns non-nil ID")
    func createSession() throws {
        let manager = MCPSessionManager()
        let id = manager.createSession()
        #expect(id != nil)
        #expect(try !#require(id?.isEmpty))
    }

    @Test("Validate existing session returns true")
    func validateExisting() throws {
        let manager = MCPSessionManager()
        let id = try #require(manager.createSession())
        #expect(manager.validateSession(id))
    }

    @Test("Validate unknown session returns false")
    func validateUnknown() {
        let manager = MCPSessionManager()
        #expect(!manager.validateSession("nonexistent-session-id"))
    }

    @Test("Remove session invalidates it")
    func removeInvalidates() throws {
        let manager = MCPSessionManager()
        let id = try #require(manager.createSession())
        #expect(manager.validateSession(id))

        manager.removeSession(id)
        #expect(!manager.validateSession(id))
    }

    @Test("Session limit enforcement")
    func sessionLimit() throws {
        let manager = MCPSessionManager()
        var ids: [String] = []
        for _ in 0 ..< MCPLimits.maxConcurrentSessions {
            let id = manager.createSession()
            #expect(id != nil)
            try ids.append(#require(id))
        }
        #expect(manager.createSession() == nil)
        #expect(manager.activeSessions == MCPLimits.maxConcurrentSessions)
    }

    @Test("Expired sessions are cleaned up")
    func expiredCleanup() throws {
        let manager = MCPSessionManager()
        let sessionID = try #require(manager.createSession())
        #expect(manager.activeSessions == 1)

        manager.setSessionTimestamp(
            Date().addingTimeInterval(-(MCPLimits.sessionTimeout + 5)),
            for: sessionID
        )
        manager.removeExpiredSessions()
        #expect(manager.activeSessions == 0)
    }

    @Test("Validating a session refreshes its idle deadline")
    func useRefreshesIdleDeadline() throws {
        let manager = MCPSessionManager()
        let sessionID = try #require(manager.createSession())

        // Just short of the idle deadline: the session is still valid, and that use
        // has to move the deadline, or a client working past it would be cut off.
        manager.setSessionTimestamp(
            Date().addingTimeInterval(-(MCPLimits.sessionTimeout - 5)),
            for: sessionID
        )
        #expect(manager.validateSession(sessionID))

        manager.removeExpiredSessions()
        #expect(manager.activeSessions == 1)
        #expect(manager.validateSession(sessionID))
    }

    @Test("Idle session is dropped once the idle interval passes")
    func idleSessionExpires() throws {
        let manager = MCPSessionManager()
        let sessionID = try #require(manager.createSession())

        manager.setSessionTimestamp(
            Date().addingTimeInterval(-(MCPLimits.sessionTimeout + 5)),
            for: sessionID
        )
        #expect(!manager.validateSession(sessionID))
        #expect(manager.activeSessions == 0)
    }

    @Test("Absolute lifetime still caps a continuously used session")
    func maxLifetimeCapsRefreshedSession() throws {
        let manager = MCPSessionManager()
        let sessionID = try #require(manager.createSession())

        // Freshly used, so only the absolute cap can end it.
        manager.setSessionCreation(Date().addingTimeInterval(-(24 * 60 * 60)), for: sessionID)
        #expect(!manager.validateSession(sessionID))
        #expect(manager.activeSessions == 0)
    }

    @Test("Active session count is accurate")
    func activeCount() throws {
        let manager = MCPSessionManager()
        #expect(manager.activeSessions == 0)

        let id1 = try #require(manager.createSession())
        #expect(manager.activeSessions == 1)

        let id2 = try #require(manager.createSession())
        #expect(manager.activeSessions == 2)

        manager.removeSession(id1)
        #expect(manager.activeSessions == 1)

        manager.removeSession(id2)
        #expect(manager.activeSessions == 0)
    }

    @Test("Created session IDs are unique")
    func uniqueIds() throws {
        let manager = MCPSessionManager()
        let id1 = try #require(manager.createSession())
        let id2 = try #require(manager.createSession())
        #expect(id1 != id2)
    }

    @Test("Removing nonexistent session is safe")
    func removeNonexistent() {
        let manager = MCPSessionManager()
        manager.removeSession("does-not-exist")
        #expect(manager.activeSessions == 0)
    }

    @Test("Freeing a slot allows new session")
    func freeSlotAllowsNew() throws {
        let manager = MCPSessionManager()
        var ids: [String] = []
        for _ in 0 ..< MCPLimits.maxConcurrentSessions {
            try ids.append(#require(manager.createSession()))
        }
        #expect(manager.createSession() == nil)

        manager.removeSession(ids[0])
        let newId = manager.createSession()
        #expect(newId != nil)
        #expect(manager.activeSessions == MCPLimits.maxConcurrentSessions)
    }

    @Test("Session IDs are cryptographically unique")
    func sessionIdUniqueness() {
        let manager = MCPSessionManager()
        var ids = Set<String>()
        for _ in 0 ..< 100 {
            if let id = manager.createSession() {
                ids.insert(id)
                manager.removeSession(id)
            }
        }
        #expect(ids.count == 100)
    }
}
