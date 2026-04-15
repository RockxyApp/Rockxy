import Foundation
@testable import Rockxy
import Testing

// Verifies the runtime dispatches by JS function arity:
// - 3-arg `onRequest(context, url, request)`
// - 4-arg `onResponse(context, url, request, response)` with bodyFilePath support
// while keeping the single-arg `onRequest(ctx)` / `onResponse(ctx)` path working.

struct ScriptMultiArgRuntimeTests {
    // MARK: Internal

    // MARK: Multi-arg request

    @Test("Multi-arg onRequest mutates headers via dictionary assignment")
    func multiArgRequestMutatesHeaders() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          request.headers["X-Multi"] = "yes";
          return request;
        }
        """
        let plugin = try makeTempPlugin(id: "test.multiarg.req", script: script)
        try await runtime.loadPlugin(plugin)

        let req = makeRequest()
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: req),
            behavior: ScriptBehavior.defaults(),
            originalRequest: req
        )
        guard case let .forward(modified) = outcome else {
            Issue.record("expected .forward, got \(outcome)")
            return
        }
        #expect(modified.headers.contains(where: { $0.name == "X-Multi" && $0.value == "yes" }))
    }

    @Test("Multi-arg onRequest path mutation reaches the forwarded URL")
    func multiArgRequestMutatesPath() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          request.path = "/v2/x";
          return request;
        }
        """
        let plugin = try makeTempPlugin(id: "test.multiarg.path", script: script)
        try await runtime.loadPlugin(plugin)

        let req = makeRequest(url: "https://example.com/v1/x")
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: req),
            behavior: ScriptBehavior.defaults(),
            originalRequest: req
        )
        guard case let .forward(modified) = outcome else {
            Issue.record("expected .forward")
            return
        }
        #expect(modified.url.path == "/v2/x")
        #expect(modified.url.host == "example.com")
    }

    @Test("Multi-arg onRequest preserves duplicate query parameter values")
    func multiArgRequestPreservesDuplicateQueries() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          request.queries["tag"] = ["1", "2", "3"];
          return request;
        }
        """
        let plugin = try makeTempPlugin(id: "test.multiarg.queries", script: script)
        try await runtime.loadPlugin(plugin)

        let req = makeRequest(url: "https://example.com/v1/x?tag=1&tag=2")
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: req),
            behavior: ScriptBehavior.defaults(),
            originalRequest: req
        )
        guard case let .forward(modified) = outcome else {
            Issue.record("expected .forward")
            return
        }
        let queryItems = URLComponents(url: modified.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(queryItems.filter { $0.name == "tag" }.compactMap(\.value) == ["1", "2", "3"])
    }

    @Test("Multi-arg onRequest host mutation is dropped (security boundary)")
    func multiArgRequestHostMutationDropped() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(context, url, request) {
          request.host = "evil.example.com";
          return request;
        }
        """
        let plugin = try makeTempPlugin(id: "test.multiarg.host", script: script)
        try await runtime.loadPlugin(plugin)

        let req = makeRequest(url: "https://example.com/x")
        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: ScriptRequestContext(from: req),
            behavior: ScriptBehavior.defaults(),
            originalRequest: req
        )
        guard case let .forward(modified) = outcome else {
            Issue.record("expected .forward")
            return
        }
        #expect(modified.url.host == "example.com")
    }

    // MARK: Multi-arg response

    @Test("Multi-arg onResponse mutates statusCode and body")
    func multiArgResponseMutates() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onResponse(context, url, request, response) {
          response.statusCode = 418;
          response.body = "teapot";
          return response;
        }
        """
        let plugin = try makeTempPlugin(id: "test.multiarg.resp", script: script)
        try await runtime.loadPlugin(plugin)

        let req = makeRequest()
        let resp = makeResponse()
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: req, response: resp),
            originalRequest: req,
            originalResponse: resp
        )
        #expect(mutated.statusCode == 418)
        #expect(String(data: mutated.body ?? Data(), encoding: .utf8) == "teapot")
    }

    // MARK: bodyFilePath

    @Test("bodyFilePath loads a file under ~ and uses it as the response body")
    func bodyFilePathLoadsFile() async throws {
        let tmpName = "rockxy-test-\(UUID().uuidString).txt"
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(tmpName)
        let payload = "hello-from-disk"
        try payload.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let runtime = ScriptRuntime()
        let script = """
        function onResponse(context, url, request, response) {
          response.bodyFilePath = "~/\(tmpName)";
          return response;
        }
        """
        let plugin = try makeTempPlugin(id: "test.multiarg.body-file", script: script)
        try await runtime.loadPlugin(plugin)

        let req = makeRequest()
        let resp = makeResponse()
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: req, response: resp),
            originalRequest: req,
            originalResponse: resp
        )
        #expect(String(data: mutated.body ?? Data(), encoding: .utf8) == payload)
    }

    @Test("bodyFilePath outside $HOME is rejected and original body retained")
    func bodyFilePathOutsideHomeRejected() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onResponse(context, url, request, response) {
          response.bodyFilePath = "/etc/hosts";
          return response;
        }
        """
        let plugin = try makeTempPlugin(id: "test.multiarg.body-file-outside", script: script)
        try await runtime.loadPlugin(plugin)

        let req = makeRequest()
        let resp = makeResponse()
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: req, response: resp),
            originalRequest: req,
            originalResponse: resp
        )
        // Loader rejects → original body retained
        #expect(String(data: mutated.body ?? Data(), encoding: .utf8) == "original")
    }

    // MARK: Private

    // MARK: Helpers

    private func makeTempPlugin(id: String, script: String) throws -> PluginInfo {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptFile = tempDir.appendingPathComponent("main.js")
        try script.write(to: scriptFile, atomically: true, encoding: .utf8)
        let manifest = PluginManifest(
            id: id,
            name: "MultiArg",
            version: "1.0.0",
            author: PluginAuthor(name: "Test", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "main.js"],
            capabilities: []
        )
        return PluginInfo(id: id, manifest: manifest, bundlePath: tempDir, isEnabled: true, status: .active)
    }

    private func makeRequest(method: String = "GET", url: String = "https://example.com/v1/x?a=1") -> HTTPRequestData {
        HTTPRequestData(
            method: method,
            // swiftlint:disable:next force_unwrapping
            url: URL(string: url)!,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Accept", value: "*/*")],
            body: nil
        )
    }

    private func makeResponse() -> HTTPResponseData {
        HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain")],
            body: "original".data(using: .utf8)
        )
    }
}
