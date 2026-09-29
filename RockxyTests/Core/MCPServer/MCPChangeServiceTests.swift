import Foundation
@testable import Rockxy
import Testing

// MARK: - MCPChangeServiceTests

@MainActor
@Suite("MCP Change Tools")
struct MCPChangeServiceTests {
    // MARK: Internal

    @Test("Every change tool is refused while changes are off, before anything is written")
    func refusedWhileChangesAreOff() async throws {
        let fixture = try Fixture(allowChanges: false)
        defer { fixture.cleanUp() }

        for name in MCPChangeService.toolNames {
            let result = await fixture.service.call(name, arguments: ["url": "https://api.example.com/*"])
            #expect(result.isError == true)
            let json = try decode(result)
            #expect(json["error"] as? String == "Changes from MCP clients are turned off")
            #expect(json["tool"] as? String == name)
        }
        #expect(await fixture.mutator.addedRules.isEmpty)
        #expect(fixture.control.enabledDomains.isEmpty)
        #expect(fixture.control.clearCount == 0)
        #expect(fixture.defaults.object(forKey: NoCacheHeaderMutator.userDefaultsKey) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    @Test("Map Local writes the body file and compiles the wildcard like the editor")
    func mapLocalCreatesRuleAndBodyFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let result = await fixture.service.call("create_map_local", arguments: [
            "url": "https://api.example.com/v1/users*",
            "method": "get",
            "status_code": 404,
            "headers": ["Content-Type": "application/json"],
            "body": "{\"error\":\"missing\"}",
            "graphql_operation": "GetUser",
        ])

        #expect(result.isError != true)
        let rule = try #require(await fixture.mutator.addedRules.first)
        #expect(rule.matchCondition.sourceURLPattern == "https://api.example.com/v1/users*")
        #expect(rule.matchCondition.urlPattern == RulePatternBuilder.regexSource(
            rawPattern: "https://api.example.com/v1/users*",
            matchType: .wildcard,
            includeSubpaths: true
        ))
        #expect(rule.matchCondition.method == "GET")
        #expect(rule.matchCondition.graphQLOperationName == "GetUser")
        guard case let .mapLocal(filePath, statusCode, isDirectory, _, headers) = rule.action else {
            Issue.record("Expected a Map Local action")
            return
        }
        #expect(statusCode == 404)
        #expect(!isDirectory)
        #expect(headers == [HTTPHeader(name: "Content-Type", value: "application/json")])
        #expect(try String(contentsOfFile: filePath, encoding: .utf8) == "{\"error\":\"missing\"}")
        #expect(filePath.hasPrefix(fixture.directory.path))
        let json = try decode(result)
        #expect(json["rule_id"] as? String == rule.id.uuidString)
    }

    @Test("A refused Map Local rule leaves no body file behind")
    func mapLocalQuotaRemovesBodyFile() async throws {
        let fixture = try Fixture(addResult: .quotaExceeded)
        defer { fixture.cleanUp() }

        let result = await fixture.service.call("create_map_local", arguments: [
            "url": "https://api.example.com/users",
            "body": "{}",
        ])

        #expect(result.isError == true)
        #expect(try decode(result)["error"] as? String
            == "The active rule limit for this tool was reached. Disable another rule first.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    @Test(
        "Invalid rule arguments are rejected before a rule is added",
        arguments: [
            ("create_breakpoint", ["phase": MCPJSONValue.string("request")]),
            ("create_breakpoint", ["url": "https://x.test/*", "phase": "sometimes"]),
            ("create_breakpoint", ["url": "(unclosed", "match_type": "regex"]),
            ("create_map_local", ["url": "https://x.test/*", "status_code": 42]),
            ("create_map_local", ["url": "https://x.test/*", "headers": ["Bad\r\nName": "v"]]),
            ("create_map_local", ["url": "https://x.test/*", "headers": ["X-Test": "a\r\nInjected: 1"]]),
            ("create_map_remote", ["from_url": "https://x.test/*", "to_url": "ftp://files.test"]),
            ("create_map_remote", ["from_url": "https://x.test/*"]),
            ("create_block_rule", ["url": "https://x.test/*", "action": "explode"]),
            ("create_block_rule", ["url": "https://x.test/*", "method": "GET /evil"]),
        ] as [(String, [String: MCPJSONValue])]
    )
    func invalidArgumentsAreRejected(tool: String, arguments: [String: MCPJSONValue]) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let result = await fixture.service.call(tool, arguments: arguments)

        #expect(result.isError == true)
        #expect(try decode(result)["param"] != nil)
        #expect(await fixture.mutator.addedRules.isEmpty)
    }

    @Test("Map Remote keeps the destination scheme, host, port, and path")
    func mapRemoteParsesDestination() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let result = await fixture.service.call("create_map_remote", arguments: [
            "from_url": "https://api.example.com/*",
            "to_url": "http://localhost:3000/api",
        ])

        #expect(result.isError != true)
        let rule = try #require(await fixture.mutator.addedRules.first)
        guard case let .mapRemote(configuration) = rule.action else {
            Issue.record("Expected a Map Remote action")
            return
        }
        #expect(configuration.scheme == "http")
        #expect(configuration.host == "localhost")
        #expect(configuration.port == 3_000)
        #expect(configuration.path == "/api")
    }

    @Test("Block rule maps drop to a closed connection")
    func blockRuleDropsConnection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        _ = await fixture.service.call("create_block_rule", arguments: [
            "url": "https://ads.example.com/*",
            "action": "drop",
        ])

        let rule = try #require(await fixture.mutator.addedRules.first)
        guard case let .block(statusCode) = rule.action else {
            Issue.record("Expected a Block action")
            return
        }
        #expect(statusCode == BlockActionType.dropConnection.statusCode)
    }

    @Test("set_rule_enabled refuses unknown rules and reports the quota")
    func setRuleEnabledValidatesTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let unknown = await fixture.service.call("set_rule_enabled", arguments: [
            "rule_id": .string(UUID().uuidString),
            "enabled": true,
        ])
        #expect(unknown.isError == true)

        let existing = ProxyRule(
            name: "Existing",
            matchCondition: RuleMatchCondition(),
            action: .block(statusCode: 403)
        )
        await fixture.mutator.seed(existing, enableAllowed: false)
        let refused = await fixture.service.call("set_rule_enabled", arguments: [
            "rule_id": .string(existing.id.uuidString),
            "enabled": true,
        ])
        #expect(refused.isError == true)
    }

    @Test("HTTPS decryption accepts host names only and goes through the workspace")
    func decryptionValidatesDomain() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        for bad in ["", "https://api.example.com", "api example.com", "*.", "a..b", "host/path"] {
            let result = await fixture.service.call("enable_ssl_proxying", arguments: ["domain": .string(bad)])
            #expect(result.isError == true)
        }
        #expect(fixture.control.enabledDomains.isEmpty)

        let result = await fixture.service.call("enable_ssl_proxying", arguments: ["domain": " API.Example.com "])
        #expect(result.isError != true)
        #expect(fixture.control.enabledDomains == ["api.example.com"])
        #expect(MCPChangeService.isValidDecryptionDomain("*.example.com"))
    }

    @Test("Recording needs a running proxy; No Caching and Clear Session apply")
    func captureControls() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.control.isProxyRunning = false
        let stopped = await fixture.service.call("set_recording", arguments: ["recording": false])
        #expect(stopped.isError == true)

        fixture.control.isProxyRunning = true
        let paused = await fixture.service.call("set_recording", arguments: ["recording": false])
        #expect(paused.isError != true)
        #expect(fixture.control.recording == false)

        _ = await fixture.service.call("set_no_caching", arguments: ["enabled": true])
        #expect(fixture.defaults.bool(forKey: NoCacheHeaderMutator.userDefaultsKey))

        _ = await fixture.service.call("clear_session", arguments: [:])
        #expect(fixture.control.clearCount == 1)
    }

    @Test("Registry lists change tools only when a change service is attached")
    func registryListsChangeTools() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let coordinator = MCPServerCoordinator()
        let readOnly = MCPToolRegistry(
            flowService: MCPFlowQueryService(
                serverCoordinator: coordinator,
                redactionPolicy: MCPRedactionPolicy(isEnabled: false)
            ),
            statusService: MCPStatusService(serverCoordinator: coordinator),
            ruleService: MCPRuleQueryService(ruleEngine: RuleEngine())
        )
        var writable = readOnly
        writable.changeService = fixture.service

        let readOnlyNames = Set(readOnly.listTools().tools.map { $0.name })
        let writableNames = Set(writable.listTools().tools.map { $0.name })
        #expect(readOnlyNames.isDisjoint(with: MCPChangeService.toolNames))
        #expect(MCPChangeService.toolNames.isSubset(of: writableNames))
        #expect(Set(MCPChangeToolDefinitions.allTools.map(\.name)) == MCPChangeService.toolNames)
    }

    // MARK: Private

    private func decode(_ result: MCPToolCallResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}

// MARK: - Fixture

@MainActor
private struct Fixture {
    // MARK: Lifecycle

    init(allowChanges: Bool = true, addResult: RuleMutationResult = .persisted(.saved)) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-change-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "mcp-change-tests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        mutator = RecordingMutator(addResult: addResult)
        control = FakeControl()
        coordinator = MCPServerCoordinator()
        coordinator.attachProviders(flow: FakeFlow(), state: control, control: control)
        service = MCPChangeService(
            serverCoordinator: coordinator,
            ruleMutations: MCPRuleMutationService(mutator: mutator, mapLocalDirectory: directory),
            permission: MCPChangePermission { allowChanges },
            defaults: defaults
        )
    }

    // MARK: Internal

    let directory: URL
    let suiteName: String
    let defaults: UserDefaults
    let mutator: RecordingMutator
    let control: FakeControl
    let coordinator: MCPServerCoordinator
    let service: MCPChangeService

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - RecordingMutator

private actor RecordingMutator: MCPRuleMutating {
    // MARK: Lifecycle

    init(addResult: RuleMutationResult) {
        self.addResult = addResult
    }

    // MARK: Internal

    private(set) var addedRules: [ProxyRule] = []

    func seed(_ rule: ProxyRule, enableAllowed: Bool) {
        seeded[rule.id] = rule
        self.enableAllowed = enableAllowed
    }

    func addRule(_ rule: ProxyRule) async -> RuleMutationResult {
        if case .persisted(.saved) = addResult {
            addedRules.append(rule)
        }
        return addResult
    }

    func setRuleEnabled(id: UUID, enabled: Bool) async -> Bool {
        enableAllowed
    }

    func rule(id: UUID) async -> ProxyRule? {
        seeded[id]
    }

    // MARK: Private

    private let addResult: RuleMutationResult
    private var seeded: [UUID: ProxyRule] = [:]
    private var enableAllowed = true
}

// MARK: - FakeControl

@MainActor
private final class FakeControl: MCPProxyStateProvider, MCPCaptureControlProvider {
    var isProxyRunning = true
    var recording = true
    var enabledDomains: [String] = []
    var clearCount = 0

    var activeProxyPort: Int {
        9_090
    }

    var isRecording: Bool {
        recording
    }

    var isSystemProxyConfigured: Bool {
        false
    }

    var transactionCount: Int {
        0
    }

    func mcpEnableHTTPSDecryption(for domain: String) -> MCPDecryptionChange {
        enabledDomains.append(domain)
        return .enabled(domain: domain)
    }

    func mcpSetRecording(_ isRecording: Bool) -> Bool {
        guard isProxyRunning else {
            return false
        }
        recording = isRecording
        return true
    }

    func mcpClearSession() async {
        clearCount += 1
    }
}

// MARK: - FakeFlow

@MainActor
private final class FakeFlow: MCPLiveFlowProvider {
    var liveTransactions: [HTTPTransaction] {
        []
    }

    var liveTransactionCount: Int {
        0
    }

    func liveTransaction(for id: UUID) -> HTTPTransaction? {
        nil
    }
}
