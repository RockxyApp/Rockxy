import Foundation
@testable import Rockxy
import Testing

// Regression tests for issue #416: a multi-arg `onRequest` begins a flow's
// `context.sharedState`, and only a multi-arg `onResponse` on a forwarded request
// ever consumes it. Every other ending has to release it, or a long capture keeps
// the store full of flows nothing will end.

@Suite(.serialized)
struct ScriptFlowStateLeakTests {
    // MARK: Internal

    @Test("Blocked request releases the flow state its request hook began")
    func blockedRequestReleasesFlowState() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          context.sharedState.seen = true;
          return null;
        }
        function onResponse(context, url, request, response) {
          return response;
        }
        """
        let plugin = try makeTempPlugin(id: "test.flowleak.blocked", script: script)
        try await runtime.loadPlugin(plugin)

        let outcome = try await callRequest(on: runtime, pluginID: plugin.id)
        guard case .blockLocally = outcome else {
            Issue.record("expected .blockLocally outcome, got \(outcome)")
            return
        }
        #expect(await runtime.pendingFlowStateCount(pluginID: plugin.id) == 0)
    }

    @Test("Mocked request releases the flow state its request hook began")
    func mockedRequestReleasesFlowState() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          context.sharedState.seen = true;
          return { statusCode: 200, body: "mocked" };
        }
        function onResponse(context, url, request, response) {
          return response;
        }
        """
        let plugin = try makeTempPlugin(id: "test.flowleak.mocked", script: script)
        try await runtime.loadPlugin(plugin)

        let outcome = try await callRequest(
            on: runtime,
            pluginID: plugin.id,
            behavior: ScriptBehavior(runAsMock: true)
        )
        guard case .mock = outcome else {
            Issue.record("expected .mock outcome, got \(outcome)")
            return
        }
        #expect(await runtime.pendingFlowStateCount(pluginID: plugin.id) == 0)
    }

    @Test("Failed request hook releases the flow state it began")
    func throwingRequestReleasesFlowState() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          context.sharedState.seen = true;
          throw new Error('boom');
        }
        function onResponse(context, url, request, response) {
          return response;
        }
        """
        let plugin = try makeTempPlugin(id: "test.flowleak.throwing", script: script)
        try await runtime.loadPlugin(plugin)

        await #expect(throws: ScriptRuntimeError.self) {
            _ = try await self.callRequest(on: runtime, pluginID: plugin.id)
        }
        #expect(await runtime.pendingFlowStateCount(pluginID: plugin.id) == 0)
    }

    @Test("Forwarded request releases flow state when no response hook can consume it")
    func forwardWithoutStateCarryingResponseReleasesFlowState() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          context.sharedState.seen = true;
          return request;
        }
        function onResponse(ctx) {
          return ctx;
        }
        """
        let plugin = try makeTempPlugin(id: "test.flowleak.legacyresponse", script: script)
        try await runtime.loadPlugin(plugin)

        // Repeated to show this is the per-request leak, not a single stale entry.
        for _ in 0 ..< 5 {
            let outcome = try await callRequest(on: runtime, pluginID: plugin.id)
            guard case .forward = outcome else {
                Issue.record("expected .forward outcome, got \(outcome)")
                return
            }
        }
        #expect(await runtime.pendingFlowStateCount(pluginID: plugin.id) == 0)
    }

    @Test("Forwarded request releases flow state when the response hook is switched off")
    func forwardWithResponseHookDisabledReleasesFlowState() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          context.sharedState.seen = true;
          return request;
        }
        function onResponse(context, url, request, response) {
          return response;
        }
        """
        let plugin = try makeTempPlugin(id: "test.flowleak.responseoff", script: script)
        try await runtime.loadPlugin(plugin)

        let outcome = try await callRequest(
            on: runtime,
            pluginID: plugin.id,
            behavior: ScriptBehavior(runOnResponse: false)
        )
        guard case .forward = outcome else {
            Issue.record("expected .forward outcome, got \(outcome)")
            return
        }
        #expect(await runtime.pendingFlowStateCount(pluginID: plugin.id) == 0)
    }

    @Test("Forwarded request keeps flow state for a multi-arg response hook")
    func forwardKeepsFlowStateForMultiArgResponse() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          context.sharedState.token = 'carried';
          return request;
        }
        function onResponse(context, url, request, response) {
          response.headers['X-Shared'] = String(context.sharedState.token);
          return response;
        }
        """
        let plugin = try makeTempPlugin(id: "test.flowleak.carried", script: script)
        try await runtime.loadPlugin(plugin)

        let request = makeRequest()
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: request),
            behavior: ScriptBehavior.defaults(),
            originalRequest: request
        )
        guard case .forward = outcome else {
            Issue.record("expected .forward outcome, got \(outcome)")
            return
        }
        #expect(await runtime.pendingFlowStateCount(pluginID: plugin.id) == 1)

        let response = makeResponse()
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: request, response: response),
            originalRequest: request,
            originalResponse: response
        )
        #expect(mutated.headers.contains { $0.name == "X-Shared" && $0.value == "carried" })
        #expect(await runtime.pendingFlowStateCount(pluginID: plugin.id) == 0)
    }

    // MARK: Private

    private func callRequest(
        on runtime: ScriptRuntime,
        pluginID: String,
        behavior: ScriptBehavior = ScriptBehavior.defaults()
    )
        async throws -> RequestHookOutcome
    {
        let request = makeRequest()
        return try await runtime.callOnRequest(
            pluginID: pluginID,
            context: ScriptRequestContext(from: request),
            behavior: behavior,
            originalRequest: request
        )
    }

    private func makeTempPlugin(id: String, script: String) throws -> PluginInfo {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let scriptFile = tempDir.appendingPathComponent("main.js")
        try script.write(to: scriptFile, atomically: true, encoding: .utf8)

        let manifest = PluginManifest(
            id: id,
            name: "Test Plugin",
            version: "1.0.0",
            author: PluginAuthor(name: "Test", url: nil),
            description: "Test plugin",
            types: [.script],
            entryPoints: ["script": "main.js"],
            capabilities: ["modifyRequest"]
        )

        return PluginInfo(
            id: id,
            manifest: manifest,
            bundlePath: tempDir,
            isEnabled: true,
            status: .active
        )
    }

    private func makeRequest() -> HTTPRequestData {
        HTTPRequestData(
            method: "GET",
            url: URL(string: "https://example.com/path")!,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: nil
        )
    }

    private func makeResponse() -> HTTPResponseData {
        HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain")],
            body: Data("ok".utf8)
        )
    }
}
