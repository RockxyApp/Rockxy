import Foundation
import NIOCore
import NIOEmbedded
import NIOHTTP1
@testable import Rockxy
import Testing

// MARK: - MCPClientActivityStoreTests

@Suite("MCP Client Activity Store")
struct MCPClientActivityStoreTests {
    @Test("Method activity is ignored until a client initializes")
    func methodBeforeInitializeIsIgnored() {
        let store = MCPClientActivityStore()
        var activity = MCPClientActivity(clientName: "Client", clientVersion: "1", initializedAt: .now)
        activity.recordMethod("tools/list", at: .now)
        // A method snapshot is meaningful only when it carries the connection identity.
        // The handler enforces this by never publishing before initialize.
        #expect(store.latest == nil)
    }

    @Test("Initialize records identity; later methods update only method and timestamp")
    func initializeThenMethod() throws {
        let store = MCPClientActivityStore()
        let initializedAt = Date(timeIntervalSince1970: 1_000)
        let laterAt = Date(timeIntervalSince1970: 1_500)

        store.recordInitialize(clientName: "Desktop MCP Client", clientVersion: "1.2.3", at: initializedAt)
        let initial = store.latest
        #expect(initial?.clientName == "Desktop MCP Client")
        #expect(initial?.clientVersion == "1.2.3")
        #expect(initial?.initializedAt == initializedAt)
        #expect(initial?.lastMethod == "initialize")
        #expect(initial?.lastActivityAt == initializedAt)

        var methodActivity = try #require(store.latest)
        methodActivity.recordMethod("tools/call", at: laterAt)
        store.record(methodActivity)
        let updated = store.latest
        #expect(updated?.clientName == "Desktop MCP Client")
        #expect(updated?.clientVersion == "1.2.3")
        #expect(updated?.initializedAt == initializedAt)
        #expect(updated?.lastMethod == "tools/call")
        #expect(updated?.lastActivityAt == laterAt)
    }

    @Test("Client identifiers are trimmed and bounded")
    func identifiersAreBounded() {
        let store = MCPClientActivityStore()
        let oversized = String(repeating: "n", count: MCPClientActivity.maxIdentifierLength + 50)
        store.recordInitialize(clientName: "  \(oversized)  ", clientVersion: " 9.9 \n")

        #expect(store.latest?.clientName.count == MCPClientActivity.maxIdentifierLength)
        #expect(store.latest?.clientVersion == "9.9")
    }

    @Test("Reset clears activity and notifies only when something was recorded")
    func resetClearsAndNotifies() throws {
        let store = MCPClientActivityStore()
        let notifications = MCPActivityNotificationCounter()
        store.onChange = { notifications.increment() }

        store.reset()
        #expect(notifications.value == 0)

        store.recordInitialize(clientName: "Client", clientVersion: "1")
        var pingActivity = try #require(store.latest)
        pingActivity.recordMethod("ping", at: .now)
        store.record(pingActivity)
        #expect(notifications.value == 2)

        store.reset()
        #expect(store.latest == nil)
        #expect(notifications.value == 3)

        // A stale connection may publish a complete snapshot after another client.
        // The snapshot must retain that connection's own identity.
        var staleClient = MCPClientActivity(
            clientName: "Earlier Client",
            clientVersion: "0.9",
            initializedAt: Date(timeIntervalSince1970: 500)
        )
        staleClient.recordMethod("ping", at: Date(timeIntervalSince1970: 2_000))
        store.record(staleClient)
        #expect(store.latest?.clientName == "Earlier Client")
        #expect(store.latest?.initializedAt == Date(timeIntervalSince1970: 500))
        #expect(notifications.value == 4)
    }
}

// MARK: - MCPClientActivityHandlerTests

@Suite("MCP Client Activity Handler")
struct MCPClientActivityHandlerTests {
    // MARK: Internal

    @Test("Successful initialize records the client and validated methods update the activity")
    @MainActor
    func initializeAndMethodsRecordActivity() throws {
        let store = MCPClientActivityStore()
        let channel = try makeChannel(store: store)
        defer { _ = try? channel.finish() }

        let initialize = try performRequest(
            through: channel,
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Activity Client","version":"4.2"}}}
            """
        )
        #expect(initialize.status == .ok)
        let sessionID = try #require(initialize.headers.first(name: "Mcp-Session-Id"))

        let activity = try #require(store.latest)
        #expect(activity.clientName == "Activity Client")
        #expect(activity.clientVersion == "4.2")
        #expect(activity.lastMethod == "initialize")

        let ping = try performRequest(
            through: channel,
            body: #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#,
            sessionID: sessionID
        )
        #expect(ping.status == .ok)
        #expect(store.latest?.lastMethod == "ping")
        #expect(store.latest?.clientName == "Activity Client")
        #expect(store.latest?.initializedAt == activity.initializedAt)

        let tools = try performRequest(
            through: channel,
            body: #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#,
            sessionID: sessionID
        )
        #expect(tools.status == .ok)
        #expect(store.latest?.lastMethod == "tools/list")
    }

    @Test("Each connection keeps its own identity when clients interleave methods")
    @MainActor
    func interleavedClientsKeepConnectionIdentity() throws {
        let store = MCPClientActivityStore()
        let earlierChannel = try makeChannel(store: store)
        let laterChannel = try makeChannel(store: store)
        defer {
            _ = try? earlierChannel.finish()
            _ = try? laterChannel.finish()
        }

        let earlierInitialize = try performRequest(
            through: earlierChannel,
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Earlier Client","version":"1.0"}}}
            """
        )
        let earlierSessionID = try #require(earlierInitialize.headers.first(name: "Mcp-Session-Id"))
        let earlierInitializedAt = try #require(store.latest?.initializedAt)

        let laterInitialize = try performRequest(
            through: laterChannel,
            body: """
            {"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Later Client","version":"2.0"}}}
            """
        )
        #expect(laterInitialize.status == .ok)
        #expect(store.latest?.clientName == "Later Client")

        let earlierPing = try performRequest(
            through: earlierChannel,
            body: #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#,
            sessionID: earlierSessionID
        )
        #expect(earlierPing.status == .ok)
        #expect(store.latest?.clientName == "Earlier Client")
        #expect(store.latest?.clientVersion == "1.0")
        #expect(store.latest?.initializedAt == earlierInitializedAt)
        #expect(store.latest?.lastMethod == "ping")
    }

    @Test("Rejected requests never touch the activity")
    @MainActor
    func rejectedRequestsDoNotRecordActivity() throws {
        let store = MCPClientActivityStore()
        let channel = try makeChannel(store: store)
        defer { _ = try? channel.finish() }

        let unauthorized = try performRequest(
            through: channel,
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Intruder","version":"1"}}}
            """,
            includeAuthorization: false
        )
        #expect(unauthorized.status == .unauthorized)
        #expect(store.latest == nil)

        let unsupported = try performRequest(
            through: channel,
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01","capabilities":{},"clientInfo":{"name":"Old Client","version":"1"}}}
            """
        )
        #expect(unsupported.status == .ok)
        #expect(unsupported.body.contains("Unsupported MCP protocol version"))
        #expect(store.latest == nil)

        let initialize = try performRequest(
            through: channel,
            body: """
            {"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Activity Client","version":"4.2"}}}
            """
        )
        let sessionID = try #require(initialize.headers.first(name: "Mcp-Session-Id"))
        #expect(store.latest?.lastMethod == "initialize")

        let missingSession = try performRequest(
            through: channel,
            body: #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#
        )
        #expect(missingSession.status == .badRequest)
        #expect(store.latest?.lastMethod == "initialize")

        let unknownMethod = try performRequest(
            through: channel,
            body: #"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#,
            sessionID: sessionID
        )
        #expect(unknownMethod.body.contains("Method not found"))
        #expect(store.latest?.lastMethod == "initialize")
    }

    // MARK: Private

    @MainActor
    private func makeChannel(store: MCPClientActivityStore) throws -> EmbeddedChannel {
        let coordinator = MCPServerCoordinator()
        let flowService = MCPFlowQueryService(
            serverCoordinator: coordinator,
            redactionPolicy: MCPRedactionPolicy(isEnabled: false)
        )
        let statusService = MCPStatusService(serverCoordinator: coordinator)
        let ruleService = MCPRuleQueryService(ruleEngine: RuleEngine())
        let registry = MCPToolRegistry(
            flowService: flowService,
            statusService: statusService,
            ruleService: ruleService
        )
        let handler = MCPServerHandler(
            configuration: .default,
            sessionManager: MCPSessionManager(),
            toolRegistry: registry,
            storedToken: "test-token",
            activityStore: store
        )
        return EmbeddedChannel(handler: handler)
    }

    private func performRequest(
        through channel: EmbeddedChannel,
        body: String,
        sessionID: String? = nil,
        includeAuthorization: Bool = true
    )
        throws -> (status: HTTPResponseStatus, headers: HTTPHeaders, body: String)
    {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        if includeAuthorization {
            headers.add(name: "Authorization", value: "Bearer test-token")
        }
        if let sessionID {
            headers.add(name: "Mcp-Session-Id", value: sessionID)
        }

        let head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/mcp", headers: headers)
        try channel.writeInbound(HTTPServerRequestPart.head(head))
        var buffer = channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        try channel.writeInbound(HTTPServerRequestPart.body(buffer))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        let headPart = try #require(try channel.readOutbound(as: HTTPServerResponsePart.self))
        guard case let .head(responseHead) = headPart else {
            Issue.record("Expected HTTP response head")
            throw CocoaError(.coderInvalidValue)
        }

        var bodyText = ""
        while let part = try channel.readOutbound(as: HTTPServerResponsePart.self) {
            switch part {
            case let .body(.byteBuffer(buffer)):
                bodyText += String(bytes: buffer.readableBytesView, encoding: .utf8) ?? ""
            case .body(.fileRegion):
                Issue.record("Unexpected file region in HTTP response body")
                throw CocoaError(.coderInvalidValue)
            case .end:
                return (responseHead.status, responseHead.headers, bodyText)
            case .head:
                Issue.record("Unexpected extra response head")
                throw CocoaError(.coderInvalidValue)
            }
        }

        Issue.record("Expected response end")
        throw CocoaError(.coderInvalidValue)
    }
}

// MARK: - MCPClientActivityCoordinatorTests

@MainActor
@Suite("MCP Client Activity Coordinator", .serialized)
struct MCPClientActivityCoordinatorTests {
    // MARK: Internal

    @Test("Coordinator mirrors store activity on the main actor and clears it on stop")
    func coordinatorMirrorsAndResets() async throws {
        let coordinator = MCPServerCoordinator()
        #expect(coordinator.latestClientActivity == nil)

        coordinator.clientActivityStore.recordInitialize(clientName: "Client", clientVersion: "1.0")
        var activity = try #require(coordinator.clientActivityStore.latest)
        activity.recordMethod("tools/list", at: .now)
        coordinator.clientActivityStore.record(activity)
        try await waitUntil { coordinator.latestClientActivity?.lastMethod == "tools/list" }
        #expect(coordinator.latestClientActivity?.clientName == "Client")

        await coordinator.stop()
        #expect(coordinator.latestClientActivity == nil)
        #expect(coordinator.clientActivityStore.latest == nil)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(coordinator.latestClientActivity == nil)
    }

    @Test("Starting a new run clears activity from the previous run")
    func startClearsPreviousActivity() async throws {
        // Injected settings: other suites write AppSettingsManager.shared in parallel.
        var settings = AppSettingsManager.shared.settings
        settings.mcpServerEnabled = false
        let coordinator = MCPServerCoordinator(settingsProvider: { settings })
        coordinator.clientActivityStore.recordInitialize(clientName: "Client", clientVersion: "1.0")
        try await waitUntil { coordinator.latestClientActivity != nil }

        // Disabled start returns before the run boundary, so stale activity must survive it.
        await coordinator.startIfEnabled()
        #expect(coordinator.latestClientActivity != nil)

        settings.mcpServerEnabled = true
        settings.mcpServerPort = 1
        await coordinator.startIfEnabled()

        #expect(!coordinator.isRunning)
        #expect(coordinator.latestClientActivity == nil)
        #expect(coordinator.clientActivityStore.latest == nil)
    }

    // MARK: Private

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 500 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Condition was not met in time")
    }
}

// MARK: - MCPActivityNotificationCounter

private final class MCPActivityNotificationCounter: @unchecked Sendable {
    // MARK: Internal

    private(set) var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
}
