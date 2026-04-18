import Darwin
import Foundation
@testable import Rockxy
import Testing

// MARK: - MCPIntegrationTests

@MainActor
@Suite("MCP Integration Tests", .serialized)
struct MCPIntegrationTests {
    // MARK: Internal

    @Test("Launch-time enablement starts server")
    func launchTimeStart() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let wasEnabled = AppSettingsManager.shared.settings.mcpServerEnabled
        let wasPort = AppSettingsManager.shared.settings.mcpServerPort
        let port = Self.testPort(offset: 0)

        AppSettingsManager.shared.updateMCPServerEnabled(true)
        AppSettingsManager.shared.updateMCPServerPort(port)
        defer {
            AppSettingsManager.shared.updateMCPServerEnabled(wasEnabled)
            AppSettingsManager.shared.updateMCPServerPort(wasPort)
        }

        await MCPServerCoordinator.shared.startIfEnabled()

        #expect(MCPServerCoordinator.shared.isRunning)
        #expect(MCPServerCoordinator.shared.activePort == port)

        await MCPServerCoordinator.shared.stop()
        #expect(!MCPServerCoordinator.shared.isRunning)
    }

    @Test("Disabled setting prevents start")
    func disabledSetting() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let wasEnabled = AppSettingsManager.shared.settings.mcpServerEnabled

        AppSettingsManager.shared.updateMCPServerEnabled(false)
        defer {
            AppSettingsManager.shared.updateMCPServerEnabled(wasEnabled)
        }
        await MCPServerCoordinator.shared.startIfEnabled()
        #expect(!MCPServerCoordinator.shared.isRunning)
    }

    @Test("Provider attach and detach")
    func providerAttachDetach() throws {
        try Self.ensureSuiteLock()

        let flowProvider = MockFlowProvider()
        let stateProvider = MockProxyStateProvider()

        MCPServerCoordinator.shared.attachProviders(flow: flowProvider, state: stateProvider)
        MCPServerCoordinator.shared.detachProviders()
    }

    @Test("Handshake file created on start, deleted on stop")
    func handshakeLifecycle() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let wasEnabled = AppSettingsManager.shared.settings.mcpServerEnabled
        let wasPort = AppSettingsManager.shared.settings.mcpServerPort
        let port = Self.testPort(offset: 1)

        AppSettingsManager.shared.updateMCPServerEnabled(true)
        AppSettingsManager.shared.updateMCPServerPort(port)
        defer {
            AppSettingsManager.shared.updateMCPServerEnabled(wasEnabled)
            AppSettingsManager.shared.updateMCPServerPort(wasPort)
        }

        await MCPServerCoordinator.shared.startIfEnabled()

        guard MCPServerCoordinator.shared.isRunning else {
            Issue.record("Server failed to start — port \(port) likely in use")
            return
        }

        let exists = FileManager.default.fileExists(
            atPath: MCPHandshakeStore.handshakeFilePath.path
        )
        #expect(exists)

        if exists {
            let handshake = try? MCPHandshakeStore.read()
            #expect(handshake?.port == port)
            #expect(handshake?.token.isEmpty == false)
        }

        await MCPServerCoordinator.shared.stop()

        let stillExists = FileManager.default.fileExists(
            atPath: MCPHandshakeStore.handshakeFilePath.path
        )
        #expect(!stillExists)
    }

    @Test("RuleEngine.shared used for list_rules")
    func rulesUseSharedEngine() async throws {
        try Self.ensureSuiteLock()

        let service = MCPRuleQueryService(ruleEngine: RuleEngine.shared)
        let result = await service.listRules()
        #expect(result.isError == nil || result.isError == false)
    }

    @Test("Initialize, notification, and tools list work over HTTP")
    func initializeNotificationAndToolsList() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let port = Self.testPort(offset: 2)
        let saved = saveMCPSettings(enabled: true, port: port)
        defer { restoreMCPSettings(saved) }

        await MCPServerCoordinator.shared.startIfEnabled()

        let handshake = try MCPHandshakeStore.read()
        let initialize = try await sendJsonRpc(
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"RockxyTests","version":"1.0"}}}
            """,
            token: handshake.token,
            port: port
        )

        #expect(initialize.response.statusCode == 200)
        let sessionId = try #require(initialize.response.value(forHTTPHeaderField: "Mcp-Session-Id"))
        let initializeText = try #require(String(bytes: initialize.data, encoding: .utf8))
        #expect(initializeText.contains("\"protocolVersion\":\"2025-11-25\""))

        let notification = try await sendJsonRpc(
            body: """
            {"jsonrpc":"2.0","method":"notifications/initialized"}
            """,
            token: handshake.token,
            port: port,
            sessionId: sessionId,
            protocolVersion: "2025-11-25"
        )

        #expect(notification.response.statusCode == 202)
        #expect(notification.data.isEmpty)

        let tools = try await sendJsonRpc(
            body: """
            {"jsonrpc":"2.0","id":2,"method":"tools/list"}
            """,
            token: handshake.token,
            port: port,
            sessionId: sessionId,
            protocolVersion: "2025-11-25"
        )

        #expect(tools.response.statusCode == 200)
        let toolsText = try #require(String(bytes: tools.data, encoding: .utf8))
        #expect(toolsText.contains("get_version"))
        #expect(toolsText.contains("filter_flows"))

        await MCPServerCoordinator.shared.stop()
    }

    @Test("Initialize rejects unsupported MCP protocol version")
    func initializeRejectsUnsupportedProtocolVersion() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let port = Self.testPort(offset: 8)
        let saved = saveMCPSettings(enabled: true, port: port)
        defer { restoreMCPSettings(saved) }

        await MCPServerCoordinator.shared.startIfEnabled()
        let handshake = try MCPHandshakeStore.read()

        let result = try await sendJsonRpc(
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-01-01","capabilities":{},"clientInfo":{"name":"RockxyTests","version":"1.0"}}}
            """,
            token: handshake.token,
            port: port
        )

        #expect(result.response.statusCode == 200)
        let text = try #require(String(bytes: result.data, encoding: .utf8))
        #expect(text.contains("Unsupported MCP protocol version"))

        await MCPServerCoordinator.shared.stop()
    }

    @Test("HTTP transport returns recent flows from attached app state")
    func httpRecentFlowsFromMainCoordinator() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let port = Self.testPort(offset: 6)
        let saved = saveMCPSettings(enabled: true, port: port)
        defer { restoreMCPSettings(saved) }

        let mainCoordinator = MainContentCoordinator()
        mainCoordinator.transactions = [
            TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/live/1", statusCode: 200),
            TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/live/2", statusCode: 201),
        ]
        mainCoordinator.isProxyRunning = true
        mainCoordinator.activeProxyPort = 9_090
        MCPServerCoordinator.shared.attachProviders(flow: mainCoordinator, state: mainCoordinator)

        await MCPServerCoordinator.shared.startIfEnabled()

        let handshake = try MCPHandshakeStore.read()
        let initialize = try await sendJsonRpc(
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"RockxyTests","version":"1.0"}}}
            """,
            token: handshake.token,
            port: port
        )
        let sessionId = try #require(initialize.response.value(forHTTPHeaderField: "Mcp-Session-Id"))

        let flows = try await sendJsonRpc(
            body: """
            {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_recent_flows","arguments":{"limit":10,"filter_host":"api.example.com"}}}
            """,
            token: handshake.token,
            port: port,
            sessionId: sessionId,
            protocolVersion: "2025-11-25"
        )

        #expect(flows.response.statusCode == 200)
        let responseEnvelope = try #require(JSONSerialization.jsonObject(with: flows.data) as? [String: Any])
        let result = try #require(responseEnvelope["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let payloadText = try #require(content.first?["text"] as? String)
        let payloadData = Data(payloadText.utf8)
        let payload = try #require(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let returnedFlows = try #require(payload["flows"] as? [[String: Any]])

        #expect(returnedFlows.count == 2)
        #expect(returnedFlows.contains { ($0["path"] as? String) == "/live/1" })
        #expect(returnedFlows.contains { ($0["path"] as? String) == "/live/2" })
        #expect(payload["total_count"] as? Int == 2)

        await MCPServerCoordinator.shared.stop()
        MCPServerCoordinator.shared.detachProviders()
    }

    @Test("rockxy-mcp bridge handles initialize, initialized notification, and tools list")
    func stdioBridgeInitializeAndToolsList() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let port = Self.testPort(offset: 5)
        let saved = saveMCPSettings(enabled: true, port: port)
        defer { restoreMCPSettings(saved) }

        await MCPServerCoordinator.shared.startIfEnabled()
        try waitForHandshake(port: port)

        let binaryURL = try rockxyMCPBinaryURL()
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = binaryURL
        process.environment = bridgeEnvironment()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        defer {
            try? stdinPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        try writeLine(
            """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"RockxyTests","version":"1.0"}}}
            """,
            to: stdinPipe.fileHandleForWriting
        )
        let initializeResponse = try readLine(
            from: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading,
            process: process
        )
        #expect(initializeResponse.contains("\"protocolVersion\":\"2025-11-25\""))

        try writeLine(
            """
            {"jsonrpc":"2.0","method":"notifications/initialized"}
            """,
            to: stdinPipe.fileHandleForWriting
        )
        try writeLine(
            """
            {"jsonrpc":"2.0","id":2,"method":"tools/list"}
            """,
            to: stdinPipe.fileHandleForWriting
        )

        let toolsResponse = try readLine(
            from: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading,
            process: process
        )
        #expect(toolsResponse.contains("get_version"))
        #expect(toolsResponse.contains("filter_flows"))
        #expect(!toolsResponse.contains("empty response from Rockxy MCP server"))

        try stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        let stderr = String(bytes: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            Issue.record("rockxy-mcp stderr: \(stderr)")
        }
        #expect(process.terminationStatus == 0)
        #expect(stderr.isEmpty)

        await MCPServerCoordinator.shared.stop()
    }

    @Test("rockxy-mcp bridge handles multiple requests in one stdin chunk")
    func stdioBridgeHandlesChunkedInput() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let port = Self.testPort(offset: 7)
        let saved = saveMCPSettings(enabled: true, port: port)
        defer { restoreMCPSettings(saved) }

        await MCPServerCoordinator.shared.startIfEnabled()
        try waitForHandshake(port: port)

        let binaryURL = try rockxyMCPBinaryURL()
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = binaryURL
        process.environment = bridgeEnvironment()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        defer {
            try? stdinPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        let chunk = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"RockxyTests","version":"1.0"}}}
        {"jsonrpc":"2.0","method":"notifications/initialized"}
        {"jsonrpc":"2.0","id":2,"method":"tools/list"}
        """
        stdinPipe.fileHandleForWriting.write(Data(chunk.utf8))
        stdinPipe.fileHandleForWriting.write(Data("\n".utf8))

        let initializeResponse = try readLine(
            from: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading,
            process: process
        )
        let toolsResponse = try readLine(
            from: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading,
            process: process
        )

        #expect(initializeResponse.contains("\"protocolVersion\":\"2025-11-25\""))
        #expect(toolsResponse.contains("get_recent_flows"))
        #expect(toolsResponse.contains("get_ssl_proxying_list"))

        try stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        let stderr = String(bytes: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0)
        #expect(stderr.isEmpty)

        await MCPServerCoordinator.shared.stop()
    }

    @Test("rockxy-mcp bridge handles split stdin lines across multiple writes")
    func stdioBridgeHandlesSplitStdinLines() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let port = Self.testPort(offset: 9)
        let saved = saveMCPSettings(enabled: true, port: port)
        defer { restoreMCPSettings(saved) }

        await MCPServerCoordinator.shared.startIfEnabled()
        try waitForHandshake(port: port)

        let binaryURL = try rockxyMCPBinaryURL()
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = binaryURL
        process.environment = bridgeEnvironment()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        defer {
            try? stdinPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        stdinPipe.fileHandleForWriting.write(
            Data(
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"clientInfo\":{\"name\":\"Rockxy"
                    .utf8
            )
        )
        stdinPipe.fileHandleForWriting.write(
            Data("Tests\",\"version\":\"1.0\"}}}\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}\n".utf8)
        )

        let initializeResponse = try readLine(
            from: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading,
            process: process
        )
        let toolsResponse = try readLine(
            from: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading,
            process: process
        )

        #expect(initializeResponse.contains("\"protocolVersion\":\"2025-11-25\""))
        #expect(toolsResponse.contains("Missing Mcp-Session-Id") == false)
        #expect(toolsResponse.contains("get_recent_flows"))

        try stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        let stderr = String(bytes: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0)
        #expect(stderr.isEmpty)

        await MCPServerCoordinator.shared.stop()
    }

    @Test("Rejects disallowed origin")
    func rejectsDisallowedOrigin() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let port = Self.testPort(offset: 3)
        let saved = saveMCPSettings(enabled: true, port: port)
        defer { restoreMCPSettings(saved) }

        await MCPServerCoordinator.shared.startIfEnabled()

        let handshake = try MCPHandshakeStore.read()
        let result = try await sendJsonRpc(
            body: """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"RockxyTests","version":"1.0"}}}
            """,
            token: handshake.token,
            port: port,
            origin: "https://evil.example.com"
        )

        #expect(result.response.statusCode == 403)
        let text = try #require(String(bytes: result.data, encoding: .utf8))
        #expect(text.contains("Origin not allowed"))

        await MCPServerCoordinator.shared.stop()
    }

    @Test("Rejects oversized request body")
    func rejectsOversizedBody() async throws {
        try Self.ensureSuiteLock()
        await resetSharedCoordinator()

        let port = Self.testPort(offset: 4)
        let saved = saveMCPSettings(enabled: true, port: port)
        defer { restoreMCPSettings(saved) }

        await MCPServerCoordinator.shared.startIfEnabled()

        let handshake = try MCPHandshakeStore.read()
        let oversize = String(repeating: "a", count: MCPLimits.maxRequestBodySize + 128)
        let result = try await sendRawRequest(
            body: Data(oversize.utf8),
            token: handshake.token,
            port: port
        )

        #expect(result.response.statusCode == 413)
        let text = try #require(String(bytes: result.data, encoding: .utf8))
        #expect(text.contains("Request body too large"))

        await MCPServerCoordinator.shared.stop()
    }

    // MARK: Private

    private final class CrossProcessLock {
        // MARK: Lifecycle

        init(fileDescriptor: Int32) {
            self.fileDescriptor = fileDescriptor
        }

        deinit {
            flock(fileDescriptor, LOCK_UN)
            close(fileDescriptor)
        }

        // MARK: Private

        private let fileDescriptor: Int32
    }

    private typealias SavedSettings = (enabled: Bool, port: Int, redact: Bool)

    private static let suiteLockResult: Result<CrossProcessLock, Error> = Result {
        try acquireTestLock()
    }

    /// Derives a stable, process-scoped port range so parallel test workers do not collide.
    private static func testPort(offset: Int) -> Int {
        let slotWidth = 20
        precondition(offset < slotWidth, "offset must be less than \(slotWidth)")
        let processBucket = Int(ProcessInfo.processInfo.processIdentifier % 100)
        return 40_000 + (processBucket * slotWidth) + offset
    }

    private static func acquireTestLock() throws -> CrossProcessLock {
        let lockURL = URL(fileURLWithPath: "/tmp/rockxy-mcp-integration.lock", isDirectory: false)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        guard flock(fd, LOCK_EX) == 0 else {
            close(fd)
            throw CocoaError(.fileReadUnknown)
        }
        return CrossProcessLock(fileDescriptor: fd)
    }

    private static func ensureSuiteLock() throws {
        _ = try suiteLockResult.get()
    }

    private func saveMCPSettings(enabled: Bool, port: Int) -> SavedSettings {
        let settings = AppSettingsManager.shared.settings
        AppSettingsManager.shared.updateMCPServerEnabled(enabled)
        AppSettingsManager.shared.updateMCPServerPort(port)
        AppSettingsManager.shared.updateMCPRedactSensitiveData(settings.mcpRedactSensitiveData)
        return (settings.mcpServerEnabled, settings.mcpServerPort, settings.mcpRedactSensitiveData)
    }

    private func restoreMCPSettings(_ saved: SavedSettings) {
        AppSettingsManager.shared.updateMCPServerEnabled(saved.enabled)
        AppSettingsManager.shared.updateMCPServerPort(saved.port)
        AppSettingsManager.shared.updateMCPRedactSensitiveData(saved.redact)
    }

    private func sendJsonRpc(
        body: String,
        token: String,
        port: Int,
        sessionId: String? = nil,
        protocolVersion: String? = nil,
        origin: String? = nil
    )
        async throws -> (data: Data, response: HTTPURLResponse)
    {
        try await sendRawRequest(
            body: Data(body.utf8),
            token: token,
            port: port,
            sessionId: sessionId,
            protocolVersion: protocolVersion,
            origin: origin
        )
    }

    private func sendRawRequest(
        body: Data,
        token: String,
        port: Int,
        sessionId: String? = nil,
        protocolVersion: String? = nil,
        origin: String? = nil
    )
        async throws -> (data: Data, response: HTTPURLResponse)
    {
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/mcp"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        if let protocolVersion {
            request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        }
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        return try (data, #require(response as? HTTPURLResponse))
    }

    private func rockxyMCPBinaryURL() throws -> URL {
        let binaryURL = Bundle(for: AppDelegate.self).bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("rockxy-mcp")
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return binaryURL
    }

    private func bridgeEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let appSupportDirectory = RockxyIdentity.current.appSupportDirectory()
        let testRootName = appSupportDirectory.deletingLastPathComponent().lastPathComponent
        let prefix = "rockxy-tests-"
        if testRootName.hasPrefix(prefix) {
            environment["ROCKXY_TEST_RUN_TOKEN"] = String(testRootName.dropFirst(prefix.count))
        }
        environment["ROCKXY_TEST_APP_SUPPORT_DIRECTORY"] = appSupportDirectory.path
        return environment
    }

    private func writeLine(_ line: String, to handle: FileHandle) throws {
        handle.write(Data(line.utf8))
        handle.write(Data("\n".utf8))
    }

    private func readLine(
        from handle: FileHandle,
        stderr: FileHandle? = nil,
        process: Process? = nil,
        timeout: TimeInterval = 5
    )
        throws -> String
    {
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()

        while Date() < deadline {
            if let chunk = try handle.read(upToCount: 1), let byte = chunk.first {
                if byte == UInt8(ascii: "\n") {
                    let line = String(bytes: buffer, encoding: .utf8) ?? ""
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        return line
                    }
                    continue
                }
                buffer.append(byte)
                continue
            }

            Thread.sleep(forTimeInterval: 0.01)
        }

        if let process, !process.isRunning,
           let stderr,
           let stderrData = try? stderr.readToEnd(),
           let stderrText = String(data: stderrData, encoding: .utf8),
           !stderrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileReadUnknown.rawValue,
                userInfo: [NSLocalizedDescriptionKey: stderrText]
            )
        }

        throw CocoaError(.fileReadUnknown)
    }

    private func waitForHandshake(port: Int, timeout: TimeInterval = 2) throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let handshake = try? MCPHandshakeStore.read(), handshake.port == port, !handshake.token.isEmpty {
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        throw CocoaError(.fileReadUnknown)
    }

    private func resetSharedCoordinator() async {
        await MCPServerCoordinator.shared.stop()
        MCPServerCoordinator.shared.detachProviders()
    }
}
