import Foundation
@testable import Rockxy
import Testing

// MARK: - MockProxyStateProvider

@MainActor
final class MockProxyStateProvider: MCPProxyStateProvider {
    var isProxyRunning = true
    var activeProxyPort = 9_090
    var isRecording = true
    var isSystemProxyConfigured = false
    var transactionCount = 42
}

// MARK: - MCPStatusServiceTests

@MainActor
@Suite("MCP Status Service")
struct MCPStatusServiceTests {
    // MARK: Internal

    // MARK: - get_version

    @Test("Get version returns app info")
    func getVersion() {
        let service = makeService()
        let result = service.getVersion()

        expectNoError(result)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("app_version"))
        #expect(text.contains("build_number"))
        #expect(text.contains("mcp_protocol_version"))
        #expect(text.contains("app_name"))
        #expect(text.contains(MCPProtocolVersion.current))
    }

    @Test("Get version result is valid JSON")
    func getVersionValidJSON() throws {
        let service = makeService()
        let result = service.getVersion()

        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["mcp_protocol_version"] as? String == MCPProtocolVersion.current)
    }

    // MARK: - get_proxy_status

    @Test("Get proxy status with no provider attached")
    func proxyStatusNilProvider() async {
        let service = makeService()
        let result = await service.getProxyStatus()

        expectNoError(result)
        let json = try? decodeJSONObject(from: result)
        #expect(json?["is_running"] as? Bool == false)
        #expect(json?["has_provider"] as? Bool == false)
        #expect(json?["status_reason"] as? String == "Proxy window not active")
    }

    @Test("Get proxy status with active provider")
    func proxyStatusActive() async {
        let provider = MockProxyStateProvider()
        provider.isProxyRunning = true
        provider.activeProxyPort = 8_888
        provider.isRecording = true
        provider.isSystemProxyConfigured = true
        provider.transactionCount = 100

        let service = makeService(stateProvider: provider)

        let result = await service.getProxyStatus()

        expectNoError(result)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("\"is_running\":true") || text.contains("\"is_running\": true"))
        #expect(text.contains("8888"))
        #expect(text.contains("\"is_recording\":true") || text.contains("\"is_recording\": true"))
        #expect(text.contains("\"is_system_proxy\":true") || text.contains("\"is_system_proxy\": true"))
        #expect(text.contains("100"))
    }

    @Test("Get proxy status reads MainContentCoordinator runtime state")
    func proxyStatusReadsMainContentCoordinator() async throws {
        let mainCoordinator = MainContentCoordinator()
        mainCoordinator.isProxyRunning = true
        mainCoordinator.activeProxyPort = 7_777
        mainCoordinator.isRecording = false
        mainCoordinator.isSystemProxyConfigured = true
        mainCoordinator.transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/live/1"),
            TestFixtures.makeTransaction(url: "https://api.example.com/live/2"),
            TestFixtures.makeTransaction(url: "https://api.example.com/live/3"),
        ]

        let coordinator = MCPServerCoordinator()
        coordinator.attachProviders(flow: mainCoordinator, state: mainCoordinator)
        let service = MCPStatusService(serverCoordinator: coordinator)

        let result = await service.getProxyStatus()
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["is_running"] as? Bool == true)
        #expect(json["port"] as? Int == 7_777)
        #expect(json["is_recording"] as? Bool == false)
        #expect(json["is_system_proxy"] as? Bool == true)
        #expect(json["transaction_count"] as? Int == 3)
    }

    @Test("Get proxy status with stopped proxy")
    func proxyStatusStopped() async {
        let provider = MockProxyStateProvider()
        provider.isProxyRunning = false
        provider.activeProxyPort = 0
        provider.isRecording = false
        provider.isSystemProxyConfigured = false
        provider.transactionCount = 0

        let service = makeService(stateProvider: provider)

        let result = await service.getProxyStatus()

        expectNoError(result)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("\"is_running\":false") || text.contains("\"is_running\": false"))
        #expect(!text.contains("\"port\""))
    }

    @Test("Get proxy status result is valid JSON")
    func proxyStatusValidJSON() async throws {
        let provider = MockProxyStateProvider()
        let service = makeService(stateProvider: provider)

        let result = await service.getProxyStatus()
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["is_running"] as? Bool == true)
        #expect(json?["transaction_count"] as? Int == 42)
    }

    @Test("Get proxy status port only included when running")
    func proxyStatusPortWhenRunning() async throws {
        let provider = MockProxyStateProvider()
        provider.isProxyRunning = true
        provider.activeProxyPort = 9_090

        let service = makeService(stateProvider: provider)

        let result = await service.getProxyStatus()
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["port"] as? Int == 9_090)
    }

    // MARK: Private

    private func makeService(stateProvider: MockProxyStateProvider? = nil) -> MCPStatusService {
        let coordinator = MCPServerCoordinator()
        if let stateProvider {
            coordinator.attachProviders(
                flow: MockFlowProvider(),
                state: stateProvider
            )
        }
        return MCPStatusService(serverCoordinator: coordinator)
    }

    private func expectNoError(_ result: MCPToolCallResult) {
        #expect(result.isError != true)
    }

    private func decodeJSONObject(from result: MCPToolCallResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        let data = Data(text.utf8)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
