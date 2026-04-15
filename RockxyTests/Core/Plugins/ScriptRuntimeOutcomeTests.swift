import Foundation
@testable import Rockxy
import Testing

// New behavior tests for ScriptRuntime: CommonJS, null→block, mock outcomes,
// response mutation apply-back.

struct ScriptRuntimeOutcomeTests {
    // MARK: Internal

    // MARK: - CommonJS

    @Test("CommonJS module.exports = { onRequest } resolves and runs")
    func commonJSExportsAreResolved() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function handle(ctx) {
            ctx.setHeader('X-Common', 'js');
            return ctx;
        }
        module.exports = { onRequest: handle };
        """
        let (plugin, tempDir) = try makeTempPlugin(id: "test.commonjs", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: makeRequest()),
            behavior: ScriptBehavior.defaults(),
            originalRequest: makeRequest()
        )

        guard case let .forward(req) = outcome else {
            Issue.record("expected .forward outcome")
            return
        }
        #expect(req.headers.contains(where: { $0.name == "X-Common" && $0.value == "js" }))
    }

    @Test("Direct global onRequest still works alongside CommonJS support")
    func directGlobalsStillWork() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(ctx) {
            ctx.setHeader('X-Direct', 'global');
            return ctx;
        }
        """
        let (plugin, tempDir) = try makeTempPlugin(id: "test.directglobal", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: makeRequest()),
            behavior: ScriptBehavior.defaults(),
            originalRequest: makeRequest()
        )
        guard case let .forward(req) = outcome else {
            Issue.record("expected .forward")
            return
        }
        #expect(req.headers.contains(where: { $0.name == "X-Direct" }))
    }

    // MARK: - Outcomes

    @Test("Returning null from onRequest produces .blockLocally outcome")
    func nullReturnBlocks() async throws {
        let runtime = ScriptRuntime()
        let script = "function onRequest(ctx) { return null; }"
        let (plugin, tempDir) = try makeTempPlugin(id: "test.null", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: makeRequest()),
            behavior: ScriptBehavior.defaults(),
            originalRequest: makeRequest()
        )
        guard case .blockLocally = outcome else {
            Issue.record("expected .blockLocally, got \(outcome)")
            return
        }
    }

    @Test("runAsMock=true with valid response object produces .mock outcome")
    func mockValidResponse() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(ctx) {
          return { statusCode: 200, headers: { "X-Mock": "yes" }, body: '{"hello":"world"}' };
        }
        """
        let (plugin, tempDir) = try makeTempPlugin(id: "test.mockok", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let mockBehavior = ScriptBehavior(
            matchCondition: nil,
            runOnRequest: true,
            runOnResponse: false,
            runAsMock: true
        )
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: makeRequest()),
            behavior: mockBehavior,
            originalRequest: makeRequest()
        )
        guard case let .mock(resp) = outcome else {
            Issue.record("expected .mock, got \(outcome)")
            return
        }
        #expect(resp.statusCode == 200)
        #expect(resp.headers.contains(where: { $0.name == "X-Mock" && $0.value == "yes" }))
        #expect(resp.body != nil)
    }

    @Test("runAsMock=true with garbage return produces .mockFailure")
    func mockFailureOnGarbage() async throws {
        let runtime = ScriptRuntime()
        let script = "function onRequest(ctx) { return 'not an object'; }"
        let (plugin, tempDir) = try makeTempPlugin(id: "test.mockbad", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let mockBehavior = ScriptBehavior(
            matchCondition: nil,
            runOnRequest: true,
            runOnResponse: false,
            runAsMock: true
        )
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: makeRequest()),
            behavior: mockBehavior,
            originalRequest: makeRequest()
        )
        guard case .mockFailure = outcome else {
            Issue.record("expected .mockFailure, got \(outcome)")
            return
        }
    }

    @Test("runAsMock=true with invalid status produces .mockFailure")
    func mockFailureOnInvalidStatus() async throws {
        let runtime = ScriptRuntime()
        let script = "function onRequest(ctx) { return { statusCode: 9999 }; }"
        let (plugin, tempDir) = try makeTempPlugin(id: "test.mockbadstatus", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let mockBehavior = ScriptBehavior(
            matchCondition: nil,
            runOnRequest: true,
            runOnResponse: false,
            runAsMock: true
        )
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: makeRequest()),
            behavior: mockBehavior,
            originalRequest: makeRequest()
        )
        guard case .mockFailure = outcome else {
            Issue.record("expected .mockFailure, got \(outcome)")
            return
        }
    }

    @Test("runAsMock=true with null produces .mockFailure (not blockLocally)")
    func mockFailureOnNull() async throws {
        let runtime = ScriptRuntime()
        let script = "function onRequest(ctx) { return null; }"
        let (plugin, tempDir) = try makeTempPlugin(id: "test.mocknull", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let mockBehavior = ScriptBehavior(
            matchCondition: nil,
            runOnRequest: true,
            runOnResponse: false,
            runAsMock: true
        )
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: makeRequest()),
            behavior: mockBehavior,
            originalRequest: makeRequest()
        )
        guard case .mockFailure = outcome else {
            Issue.record("expected .mockFailure (not blockLocally) when runAsMock=true, got \(outcome)")
            return
        }
    }

    // MARK: - Response hook

    @Test("onResponse can mutate status, headers, and body via setters")
    func responseHookMutates() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onResponse(ctx) {
          ctx.setStatus(418);
          ctx.setHeader('X-Mutated', 'true');
          ctx.setBody('replaced');
          return ctx;
        }
        """
        let (plugin, tempDir) = try makeTempPlugin(id: "test.responsemut", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let request = makeRequest()
        let response = makeResponse(status: 200, body: "original".data(using: .utf8))
        let context = ScriptResponseContext(request: request, response: response)
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: context,
            originalRequest: request,
            originalResponse: response
        )
        #expect(mutated.statusCode == 418)
        #expect(mutated.headers.contains(where: { $0.name == "X-Mutated" && $0.value == "true" }))
        #expect(String(data: mutated.body ?? Data(), encoding: .utf8) == "replaced")
    }

    @Test("onResponse missing on plugin returns original response unchanged")
    func responseHookMissingPassthrough() async throws {
        let runtime = ScriptRuntime()
        let script = "function onRequest(ctx) { return ctx; }"
        let (plugin, tempDir) = try makeTempPlugin(id: "test.noresponse", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let request = makeRequest()
        let response = makeResponse(status: 200, body: "kept".data(using: .utf8))
        let context = ScriptResponseContext(request: request, response: response)
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: context,
            originalRequest: request,
            originalResponse: response
        )
        #expect(mutated.statusCode == 200)
        #expect(String(data: mutated.body ?? Data(), encoding: .utf8) == "kept")
    }

    // MARK: - Host/port/scheme drop

    @Test("Host/port/scheme mutations from request hook are discarded")
    func hostMutationDropped() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(ctx) {
          ctx.setURL('https://evil.example.com:9999/path');
          return ctx;
        }
        """
        let (plugin, tempDir) = try makeTempPlugin(id: "test.hostmut", script: script)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runtime.loadPlugin(plugin)

        let original = makeRequest(url: "https://example.com/api")
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: original),
            behavior: ScriptBehavior.defaults(),
            originalRequest: original
        )
        guard case let .forward(forwardReq) = outcome else {
            Issue.record("expected .forward")
            return
        }
        #expect(forwardReq.url.host == "example.com")
        #expect(forwardReq.url.port == nil)
        #expect(forwardReq.url.scheme == "https")
        // Path SHOULD update
        #expect(forwardReq.url.path == "/path")
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeTempPlugin(id: String, script: String) throws -> (PluginInfo, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptFile = tempDir.appendingPathComponent("main.js")
        try script.write(to: scriptFile, atomically: true, encoding: .utf8)

        let manifest = PluginManifest(
            id: id,
            name: "Test",
            version: "1.0.0",
            author: PluginAuthor(name: "Tester", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "main.js"],
            capabilities: []
        )
        return (
            PluginInfo(id: id, manifest: manifest, bundlePath: tempDir, isEnabled: true, status: .active),
            tempDir
        )
    }

    private func makeRequest(method: String = "GET", url: String = "https://example.com/api") -> HTTPRequestData {
        HTTPRequestData(
            method: method,
            // swiftlint:disable:next force_unwrapping
            url: URL(string: url)!,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: nil
        )
    }

    private func makeResponse(status: Int = 200, body: Data? = nil) -> HTTPResponseData {
        HTTPResponseData(
            statusCode: status,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain")],
            body: body,
            bodyTruncated: false,
            contentType: nil
        )
    }
}
