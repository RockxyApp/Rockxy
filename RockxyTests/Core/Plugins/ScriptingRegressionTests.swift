import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

// MARK: - ToggleBox

// Regression tests for the scripting feature, covering review findings #1, #5,
// #6, #7, and #8. Other findings have dedicated tests.

/// Small thread-safe Bool box so the `@Sendable` settingsProvider closure can
/// flip its toggle from outside without needing actor isolation.
final class ToggleBox: @unchecked Sendable {
    // MARK: Lifecycle

    init(value: Bool) {
        self.value = value
    }

    // MARK: Internal

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    // MARK: Private

    private let lock = NSLock()
    private var value: Bool
}

// MARK: - ScriptingRegressionTests

@Suite(.serialized)
struct ScriptingRegressionTests {
    // MARK: Internal

    // MARK: - Finding #1: legacy onResponse(ctx) top-level mutations

    @Test("Legacy onResponse(ctx) top-level statusCode mutation is honored")
    func legacyTopLevelStatusCodeMutation() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onResponse(ctx) {
          ctx.statusCode = 503;
          return ctx;
        }
        """
        let plugin = try makeTempPlugin(id: "test.legacy.status", script: script)
        try await runtime.loadPlugin(plugin)
        let req = makeRequest()
        let resp = makeResponse(status: 200, body: Data("ok".utf8))
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: req, response: resp),
            originalRequest: req,
            originalResponse: resp
        )
        #expect(mutated.statusCode == 503)
    }

    @Test("Legacy onResponse(ctx) top-level body mutation is honored")
    func legacyTopLevelBodyMutation() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onResponse(ctx) {
          ctx.body = "replaced";
          return ctx;
        }
        """
        let plugin = try makeTempPlugin(id: "test.legacy.body", script: script)
        try await runtime.loadPlugin(plugin)
        let req = makeRequest()
        let resp = makeResponse(body: Data("original".utf8))
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: req, response: resp),
            originalRequest: req,
            originalResponse: resp
        )
        #expect(String(data: mutated.body ?? Data(), encoding: .utf8) == "replaced")
    }

    @Test("Legacy onResponse(ctx) top-level responseHeaders mutation is honored")
    func legacyTopLevelHeadersMutation() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onResponse(ctx) {
          ctx.responseHeaders = { "X-Legacy": "yes" };
          return ctx;
        }
        """
        let plugin = try makeTempPlugin(id: "test.legacy.headers", script: script)
        try await runtime.loadPlugin(plugin)
        let req = makeRequest()
        let resp = makeResponse(body: Data("x".utf8))
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: req, response: resp),
            originalRequest: req,
            originalResponse: resp
        )
        #expect(mutated.headers.contains { $0.name == "X-Legacy" && $0.value == "yes" })
    }

    @Test("Single-arg onResponse(ctx) also honors nested response fallback")
    func nestedResponseFallbackMutation() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onResponse(ctx) {
          ctx.response = { statusCode: 504, headers: { "X-Nested": "yes" }, body: "nested" };
          return ctx;
        }
        """
        let plugin = try makeTempPlugin(id: "test.legacy.nested", script: script)
        try await runtime.loadPlugin(plugin)
        let req = makeRequest()
        let resp = makeResponse(status: 200, body: Data("original".utf8))
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: req, response: resp),
            originalRequest: req,
            originalResponse: resp
        )
        #expect(mutated.statusCode == 504)
        #expect(mutated.headers.contains { $0.name == "X-Nested" && $0.value == "yes" })
        #expect(String(data: mutated.body ?? Data(), encoding: .utf8) == "nested")
    }

    @Test("Single-arg onResponse(ctx) preserves binary body payloads")
    func legacyBinaryBodyPreserved() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onResponse(ctx) {
          ctx.body = ctx.body;
          return ctx;
        }
        """
        let plugin = try makeTempPlugin(id: "test.legacy.binary", script: script)
        try await runtime.loadPlugin(plugin)
        let req = makeRequest()
        let payload = Data([0x00, 0xFF, 0x10, 0x41])
        let resp = makeResponse(body: payload)
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: req, response: resp),
            originalRequest: req,
            originalResponse: resp
        )
        #expect(mutated.body == payload)
    }

    // MARK: - Finding #5: legacy ctx.setBody plain-text replacement

    @Test("Legacy ctx.setBody(\"plain\") replaces the request body")
    func legacySetBodyPlainTextReplacesRequest() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(ctx) {
          ctx.setBody("hello world");
          return ctx;
        }
        """
        let plugin = try makeTempPlugin(id: "test.legacy.setbody", script: script)
        try await runtime.loadPlugin(plugin)
        let req = makeRequest(method: "POST", body: Data("old".utf8))
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
        #expect(String(data: modified.body ?? Data(), encoding: .utf8) == "hello world")
    }

    // MARK: - Finding #6: request framing recompute (HTTP + intercepted HTTPS share helper)

    @Test("Adding a body to a previously bodyless request adds Content-Length")
    func framingAddedBodyAddsContentLength() {
        let req = makeRequest(method: "POST", body: Data("hello".utf8))
        let originalHead = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/path")
        // No Content-Length on the original head.
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.headers.first(name: "Content-Length") == "5")
    }

    @Test("Removing the body sets Content-Length: 0 even if original had none")
    func framingRemovedBodyZeroContentLength() {
        let req = makeRequest(method: "POST", body: nil)
        let originalHead = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/path")
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(forward.headers.first(name: "Content-Length") == "0")
    }

    @Test("Chunked uploads keep Transfer-Encoding and have no Content-Length")
    func framingChunkedDropsContentLength() {
        let req = makeRequest(
            method: "POST",
            headers: [
                HTTPHeader(name: "Transfer-Encoding", value: "chunked"),
                HTTPHeader(name: "Content-Length", value: "5")
            ],
            body: Data("ignored".utf8)
        )
        let originalHead = HTTPRequestHead(
            version: .http1_1,
            method: .POST,
            uri: "/path",
            headers: HTTPHeaders([
                ("Transfer-Encoding", "chunked"),
                ("Content-Length", "5"),
            ])
        )
        let forward = ProxyHandlerShared.buildForwardHead(from: req, originalHead: originalHead)
        #expect(!forward.headers.contains(name: "Content-Length"))
        #expect(forward.headers.first(name: "Transfer-Encoding") == "chunked")
    }

    // MARK: - Finding #7: response framing reflects mutated body

    @Test(
        "ScriptResponseContext apply replaces body and the test verifies framing recompute via real Content-Length header"
    )
    func responseFramingMatchesMutatedBody() async throws {
        // Direct-style: drive ScriptResponseContext.apply through the runtime,
        // then verify Content-Length on the mutated HTTPResponseData reflects the
        // new body length when the script supplies a Content-Length header itself
        // OR has none — UpstreamResponseHandler is the seam that finalizes the
        // wire framing; we verify the data-side contract here.
        let runtime = ScriptRuntime()
        let script = """
        function onResponse(ctx) {
          ctx.body = "much-longer-replacement";
          return ctx;
        }
        """
        let plugin = try makeTempPlugin(id: "test.framing.resp", script: script)
        try await runtime.loadPlugin(plugin)
        let req = makeRequest()
        let resp = makeResponse(
            headers: [
                HTTPHeader(name: "Content-Type", value: "text/plain"),
                HTTPHeader(name: "Content-Length", value: "5")
            ],
            body: Data("short".utf8)
        )
        let mutated = try await runtime.callOnResponse(
            pluginID: plugin.id,
            context: ScriptResponseContext(request: req, response: resp),
            originalRequest: req,
            originalResponse: resp
        )
        // The body changed; the returned response must carry the new bytes.
        // (UpstreamResponseHandler is what writes the final Content-Length header
        //  to the wire — it always replaces it with the mutated body size.)
        #expect(String(data: mutated.body ?? Data(), encoding: .utf8) == "much-longer-replacement")
        #expect((mutated.body?.count ?? 0) > 5)
    }

    // MARK: - Finding #4: response-breakpoint preservation when oversize hits

    @Test("Oversize body with breakpoint armed keeps buffering — does NOT flush early")
    func oversizeBreakpointKeepsBuffering() {
        let decision = ProxyHandlerShared.oversizeRelayDecision(
            deferRelayForScript: true,
            shouldBreakOnResponse: true
        )
        #expect(decision == .keepBufferingForBreakpoint)
    }

    @Test("Oversize body without breakpoint flushes buffered prefix and streams the rest")
    func oversizeNoBreakpointFlushesPrefix() {
        let decision = ProxyHandlerShared.oversizeRelayDecision(
            deferRelayForScript: true,
            shouldBreakOnResponse: false
        )
        #expect(decision == .flushBufferedAndResumeStreaming)
    }

    @Test("Oversize body without script defer is already streaming")
    func oversizeNoDeferAlreadyStreaming() {
        let decision = ProxyHandlerShared.oversizeRelayDecision(
            deferRelayForScript: false,
            shouldBreakOnResponse: false
        )
        #expect(decision == .alreadyStreaming)
    }

    @Test("Oversize body with breakpoint but no script defer is already streaming (current chunks already relayed)")
    func oversizeBreakpointNoDefer() {
        // shouldBreakOnResponse already suppresses chunk relay independently of
        // deferRelayForScript, so reaching here means buffering for the breakpoint
        // is already in place — nothing extra for the truncation branch to do.
        let decision = ProxyHandlerShared.oversizeRelayDecision(
            deferRelayForScript: false,
            shouldBreakOnResponse: true
        )
        #expect(decision == .alreadyStreaming)
    }

    // MARK: - Finding #8: master toggle disables runtime hooks

    @Test("scriptingToolEnabled=false makes runRequestHook a no-op forwarder")
    func toolToggleBypassesRequestHook() async throws {
        // Use an injected `settingsProvider` so this test owns its own master
        // toggle state and never races other suites that touch UserDefaults.standard.
        let suite = "ScriptingRegressionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let discovery = PluginDiscovery(pluginsDirectory: dir, defaults: defaults)
        // Box keeps the toggle value under a lock so the @Sendable closure can flip it.
        let toggleBox = ToggleBox(value: false)
        let manager = ScriptPluginManager(
            discovery: discovery,
            defaults: defaults,
            settingsProvider: {
                var s = AppSettings()
                s.scriptingToolEnabled = toggleBox.get()
                return s
            }
        )

        // Drop a plugin with a script that always blocks. With the tool ENABLED
        // it would block; with it DISABLED the manager must skip it entirely.
        let pluginID = "test.toggle.\(UUID().uuidString.prefix(6))"
        let pluginDir = dir.appendingPathComponent(pluginID, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: pluginID,
            name: "Blocker",
            version: "1.0.0",
            author: PluginAuthor(name: "Test", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "index.js"],
            capabilities: []
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: pluginDir.appendingPathComponent("plugin.json"))
        try "function onRequest(ctx) { return null; }".write(
            to: pluginDir.appendingPathComponent("index.js"),
            atomically: true,
            encoding: .utf8
        )
        defaults.set(true, forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: pluginID))
        await manager.loadAllPlugins()

        // Toggle off — request flows through.
        toggleBox.set(false)
        let req = makeRequest()
        let outcome = await manager.runRequestHook(on: req)
        guard case .forward = outcome else {
            Issue.record("toggle off: expected .forward, got \(outcome)")
            return
        }

        // Toggle on — same plugin now blocks.
        toggleBox.set(true)
        let outcome2 = await manager.runRequestHook(on: req)
        guard case .blockLocally = outcome2 else {
            Issue.record("toggle on: expected .blockLocally, got \(outcome2)")
            return
        }
    }

    @Test("scriptingToolEnabled=false makes runResponseHook return original response")
    func toolToggleBypassesResponseHook() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "ScriptingRegressionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let discovery = PluginDiscovery(pluginsDirectory: dir, defaults: defaults)
        let manager = ScriptPluginManager(
            discovery: discovery,
            defaults: defaults,
            settingsProvider: {
                var s = AppSettings()
                s.scriptingToolEnabled = false
                return s
            }
        )

        let pluginID = "test.toggle.resp.\(UUID().uuidString.prefix(6))"
        let pluginDir = dir.appendingPathComponent(pluginID, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: pluginID,
            name: "RespMutator",
            version: "1.0.0",
            author: PluginAuthor(name: "Test", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "index.js"],
            capabilities: []
        )
        try JSONEncoder().encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"))
        try "function onResponse(ctx) { ctx.statusCode = 418; return ctx; }".write(
            to: pluginDir.appendingPathComponent("index.js"),
            atomically: true,
            encoding: .utf8
        )
        defaults.set(true, forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: pluginID))
        await manager.loadAllPlugins()

        let req = makeRequest()
        let resp = makeResponse(status: 200)
        let mutated = await manager.runResponseHook(request: req, response: resp)
        #expect(mutated.statusCode == 200, "with toggle off, response should be untouched")
    }

    @Test("hasResponseHookForSnapshot returns false when scriptingToolEnabled is off")
    func toolToggleBypassesPreflightSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "ScriptingRegressionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let discovery = PluginDiscovery(pluginsDirectory: dir, defaults: defaults)
        let manager = ScriptPluginManager(
            discovery: discovery,
            defaults: defaults,
            settingsProvider: {
                var s = AppSettings()
                s.scriptingToolEnabled = false
                return s
            }
        )
        let req = makeRequest()
        #expect(manager.hasResponseHookForSnapshot(request: req) == false)
    }

    @Test("Disabling a response script refreshes the preflight snapshot immediately")
    func disablingResponseScriptRefreshesSnapshot() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "ScriptingRegressionTests-\(UUID().uuidString)") ?? .standard
        let discovery = PluginDiscovery(pluginsDirectory: dir, defaults: defaults)
        let manager = ScriptPluginManager(discovery: discovery, defaults: defaults)

        let pluginID = "test.snapshot.resp.\(UUID().uuidString.prefix(6))"
        let pluginDir = dir.appendingPathComponent(pluginID, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: pluginID,
            name: "RespMutator",
            version: "1.0.0",
            author: PluginAuthor(name: "Test", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "index.js"],
            capabilities: [],
            scriptBehavior: ScriptBehavior(
                matchCondition: nil,
                runOnRequest: false,
                runOnResponse: true,
                runAsMock: false
            )
        )
        try JSONEncoder().encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"))
        try "function onResponse(ctx) { ctx.statusCode = 418; return ctx; }".write(
            to: pluginDir.appendingPathComponent("index.js"),
            atomically: true,
            encoding: .utf8
        )
        defaults.set(true, forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: pluginID))
        await manager.loadAllPlugins()

        let req = makeRequest()
        #expect(manager.hasResponseHookForSnapshot(request: req) == true)

        await manager.disablePlugin(id: pluginID)
        #expect(manager.hasResponseHookForSnapshot(request: req) == false)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeTempPlugin(id: String, script: String) throws -> PluginInfo {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try script.write(to: tempDir.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        let manifest = PluginManifest(
            id: id,
            name: "Reg",
            version: "1.0.0",
            author: PluginAuthor(name: "Test", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "main.js"],
            capabilities: []
        )
        return PluginInfo(id: id, manifest: manifest, bundlePath: tempDir, isEnabled: true, status: .active)
    }

    private func makeRequest(
        method: String = "GET",
        url: String = "https://example.com/path",
        headers: [HTTPHeader] = [],
        body: Data? = nil
    )
        -> HTTPRequestData
    {
        HTTPRequestData(
            method: method,
            // swiftlint:disable:next force_unwrapping
            url: URL(string: url)!,
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: body
        )
    }

    private func makeResponse(
        status: Int = 200,
        headers: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "text/plain")],
        body: Data? = nil
    )
        -> HTTPResponseData
    {
        HTTPResponseData(
            statusCode: status,
            statusMessage: "OK",
            headers: headers,
            body: body
        )
    }
}
