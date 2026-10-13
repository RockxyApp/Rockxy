import Foundation
@testable import Rockxy
import Testing

// MARK: - ScriptStarterTemplateTests

// Every starter template must be valid as shipped and do what its title says when the real
// runtime executes it.

struct ScriptStarterTemplateTests {
    // MARK: Internal

    @Test("Six starter templates are offered, each with a distinct title")
    func templateCatalog() {
        let titles = ScriptStarterTemplate.allCases.map(\.title)
        #expect(titles.count == 6)
        #expect(Set(titles).count == titles.count)
    }

    @Test("Every starter template passes validation with its own behavior", arguments: ScriptStarterTemplate.allCases)
    func templatesValidate(template: ScriptStarterTemplate) {
        let behavior = template.behavior
        let result = ScriptSourceValidator.validate(
            source: template.source,
            runOnRequest: behavior.runOnRequest,
            runOnResponse: behavior.runOnResponse,
            runAsMock: behavior.runAsMock
        )
        #expect(result == .valid)
    }

    @Test("Mock templates run as mock; the others forward requests")
    func mockFlags() {
        #expect(ScriptStarterTemplate.customResponse.behavior.runAsMock)
        #expect(ScriptStarterTemplate.conditionalMockJSON.behavior.runAsMock)
        #expect(!ScriptStarterTemplate.modifyHeaders.behavior.runAsMock)
        #expect(!ScriptStarterTemplate.blockPattern.behavior.runAsMock)
    }

    @Test("Modify Headers adds its header")
    func modifyHeaders() async throws {
        let outcome = try await run(.modifyHeaders, url: "https://api.example.com/users")
        guard case let .forward(request) = outcome else {
            Issue.record("Expected .forward, got \(outcome)")
            return
        }
        #expect(request.headers.contains { $0.name == "X-Debug-Client" && $0.value == "Rockxy" })
    }

    @Test("Log Requests forwards the request unchanged")
    func logRequests() async throws {
        let outcome = try await run(.logRequests, url: "https://api.example.com/users")
        guard case let .forward(request) = outcome else {
            Issue.record("Expected .forward, got \(outcome)")
            return
        }
        #expect(request.url.absoluteString == "https://api.example.com/users")
    }

    @Test("Block Pattern blocks matching URLs and forwards the rest")
    func blockPattern() async throws {
        let blocked = try await run(.blockPattern, url: "https://cdn.example.com/analytics/track")
        guard case .blockLocally = blocked else {
            Issue.record("Expected .blockLocally, got \(blocked)")
            return
        }
        let allowed = try await run(.blockPattern, url: "https://api.example.com/users")
        guard case .forward = allowed else {
            Issue.record("Expected .forward, got \(allowed)")
            return
        }
    }

    @Test("Custom Response answers locally with JSON")
    func customResponse() async throws {
        let outcome = try await run(.customResponse, url: "https://api.example.com/users")
        guard case let .mock(response) = outcome else {
            Issue.record("Expected .mock, got \(outcome)")
            return
        }
        #expect(response.statusCode == 200)
        let body = try #require(response.body.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("/users"))
    }

    @Test("Rewrite URL changes the path and keeps the host")
    func rewriteURL() async throws {
        let outcome = try await run(.rewriteURL, url: "https://api.example.com/v1/users")
        guard case let .forward(request) = outcome else {
            Issue.record("Expected .forward, got \(outcome)")
            return
        }
        #expect(request.url.path == "/v2/users")
        #expect(request.url.host == "api.example.com")
    }

    @Test("Conditional Mock JSON mocks listed paths and reports the rest as missing")
    func conditionalMock() async throws {
        let listed = try await run(.conditionalMockJSON, url: "https://api.example.com/api/user")
        guard case let .mock(user) = listed else {
            Issue.record("Expected .mock, got \(listed)")
            return
        }
        #expect(user.statusCode == 200)
        #expect(user.body.flatMap { String(data: $0, encoding: .utf8) }?.contains("Ada") == true)

        let missing = try await run(.conditionalMockJSON, url: "https://api.example.com/api/other")
        guard case let .mock(notFound) = missing else {
            Issue.record("Expected .mock, got \(missing)")
            return
        }
        #expect(notFound.statusCode == 404)
    }

    // MARK: Private

    private func run(_ template: ScriptStarterTemplate, url: String) async throws -> RequestHookOutcome {
        let runtime = ScriptRuntime()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTemplateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try template.source.write(to: directory.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
        let id = "test.template.\(template.rawValue)"
        let manifest = PluginManifest(
            id: id,
            name: template.title,
            version: "1.0.0",
            author: PluginAuthor(name: "Test", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "index.js"],
            capabilities: []
        )
        try await runtime.loadPlugin(PluginInfo(
            id: id,
            manifest: manifest,
            bundlePath: directory,
            isEnabled: true,
            status: .active
        ))
        let request = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: url)),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Accept", value: "*/*")],
            body: nil
        )
        return try await runtime.callOnRequest(
            pluginID: id,
            context: ScriptRequestContext(from: request),
            behavior: template.behavior,
            originalRequest: request
        )
    }
}
