import Foundation
import JavaScriptCore
@testable import Rockxy
import Testing

// Regression tests for `ScriptRuntime` in the core plugins layer.

struct ScriptRuntimeTests {
    // MARK: Internal

    @Test("Load plugin with onRequest that adds header, verify header reaches forwarded request")
    func onRequestAddsHeader() async throws {
        let runtime = ScriptRuntime()
        let script = """
        function onRequest(ctx) {
            ctx.setHeader('X-Test-Plugin', 'injected');
            return ctx;
        }
        """

        let plugin = try makeTempPlugin(id: "com.test.header-adder", script: script)
        try await runtime.loadPlugin(plugin)

        let requestContext = makeRequestContext()
        let originalRequest = makeHTTPRequestData()

        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: requestContext,
            behavior: ScriptBehavior.defaults(),
            originalRequest: originalRequest
        )

        guard case let .forward(modifiedRequest) = outcome else {
            Issue.record("expected .forward outcome, got \(outcome)")
            return
        }
        #expect(modifiedRequest.headers.contains(where: { $0.name == "X-Test-Plugin" && $0.value == "injected" }))
        #expect(modifiedRequest.headers
            .contains(where: { $0.name == "Content-Type" && $0.value == "application/json" }))
    }

    @Test("callOnRequest on unloaded plugin throws pluginNotLoaded")
    func callOnUnloadedPluginThrows() async throws {
        let runtime = ScriptRuntime()
        let requestContext = makeRequestContext()
        let originalRequest = makeHTTPRequestData()

        await #expect(throws: ScriptRuntimeError.self) {
            try await runtime.callOnRequest(
                pluginID: "com.test.nonexistent",
                context: requestContext,
                behavior: ScriptBehavior.defaults(),
                originalRequest: originalRequest
            )
        }
    }

    @Test("unloadPlugin removes plugin so subsequent call throws")
    func unloadRemovesPlugin() async throws {
        let runtime = ScriptRuntime()
        let script = "function onRequest(ctx) { return ctx; }"

        let plugin = try makeTempPlugin(id: "com.test.unload-test", script: script)
        try await runtime.loadPlugin(plugin)

        #expect(await runtime.hasPlugin(id: plugin.id) == true)

        await runtime.unloadPlugin(id: plugin.id)

        #expect(await runtime.hasPlugin(id: plugin.id) == false)

        let requestContext = makeRequestContext()
        let originalRequest = makeHTTPRequestData()

        await #expect(throws: ScriptRuntimeError.self) {
            try await runtime.callOnRequest(
                pluginID: plugin.id,
                context: requestContext,
                behavior: ScriptBehavior.defaults(),
                originalRequest: originalRequest
            )
        }
    }

    /// Costs the test process one spinning thread for its remaining lifetime: the
    /// script below never returns and JavaScriptCore exposes no public way to
    /// interrupt a running evaluation. That is the defect under test, so one leaked
    /// thread is the price of covering it — do not add a second runaway test.
    @Test("A plugin whose script never returns is retired, and a reload revives it")
    func runawayScriptRetiresThePluginAndReloadRevivesIt() async throws {
        let runtime = ScriptRuntime()
        let runaway = "function onRequest(ctx) { while (true) {} }"
        let plugin = try makeTempPlugin(id: "com.test.runaway", script: runaway)
        try await runtime.loadPlugin(plugin)

        await #expect(throws: ScriptRuntimeError.self) {
            try await runtime.callOnRequest(
                pluginID: plugin.id,
                context: makeRequestContext(),
                behavior: ScriptBehavior.defaults(),
                originalRequest: makeHTTPRequestData()
            )
        }

        // The whole point of retiring it: the second call must NOT pay the timeout
        // again behind a loop that will never end.
        let startedAt = ContinuousClock.now
        await #expect(throws: ScriptRuntimeError.self) {
            try await runtime.callOnRequest(
                pluginID: plugin.id,
                context: makeRequestContext(),
                behavior: ScriptBehavior.defaults(),
                originalRequest: makeHTTPRequestData()
            )
        }
        #expect(startedAt.duration(to: .now) < .seconds(1))

        // Reloading a corrected script must revive the plugin; without clearing the
        // retired flag it would stay dead for the rest of the app's life.
        await runtime.unloadPlugin(id: plugin.id)
        let fixed = try makeTempPlugin(id: plugin.id, script: "function onRequest(ctx) { return ctx; }")
        try await runtime.loadPlugin(fixed)

        let outcome = try await runtime.callOnRequest(
            pluginID: plugin.id,
            context: makeRequestContext(),
            behavior: ScriptBehavior.defaults(),
            originalRequest: makeHTTPRequestData()
        )
        guard case .forward = outcome else {
            Issue.record("a reloaded plugin must forward again, got \(outcome)")
            return
        }
    }

    /// Costs the test process a second spinning thread for its remaining lifetime, for
    /// the same reason the hook test above does. It earns it by covering a different
    /// failure: the loop here is at TOP LEVEL, so it runs inside `evaluateScript` during
    /// the load itself, where no hook is ever called. Evaluated on the actor that would
    /// hang `ScriptRuntime` permanently -- so the second half of this test, loading an
    /// unrelated plugin afterwards and calling it, is the actual assertion.
    @Test("A script whose top-level code never returns fails its load and leaves the runtime usable")
    func runawayTopLevelSourceFailsTheLoadWithoutWedgingTheRuntime() async throws {
        let runtime = ScriptRuntime()
        let runaway = try makeTempPlugin(
            id: "com.test.runaway-toplevel",
            script: "while (true) {}\nfunction onRequest(ctx) { return ctx; }"
        )

        await #expect(throws: ScriptRuntimeError.self) {
            try await runtime.loadPlugin(runaway)
        }

        // Nothing was registered for it, so a call must fail at once rather than wait
        // behind an evaluation that will never finish.
        let startedAt = ContinuousClock.now
        await #expect(throws: ScriptRuntimeError.self) {
            try await runtime.callOnRequest(
                pluginID: runaway.id,
                context: makeRequestContext(),
                behavior: ScriptBehavior.defaults(),
                originalRequest: makeHTTPRequestData()
            )
        }
        #expect(startedAt.duration(to: .now) < .seconds(1))

        // The point of evaluating off the actor: a runaway load must not take the
        // runtime down with it. Another plugin still loads and still runs.
        let healthy = try makeTempPlugin(
            id: "com.test.after-runaway",
            script: "function onRequest(ctx) { ctx.setHeader('X-After', 'ok'); return ctx; }"
        )
        try await runtime.loadPlugin(healthy)
        let outcome = try await runtime.callOnRequest(
            pluginID: healthy.id,
            context: makeRequestContext(),
            behavior: ScriptBehavior.defaults(),
            originalRequest: makeHTTPRequestData()
        )
        guard case let .forward(request) = outcome else {
            Issue.record("a healthy plugin loaded after a runaway load must forward, got \(outcome)")
            return
        }
        #expect(
            request.headers.contains { $0.name == "X-After" && $0.value == "ok" }
        )
    }

    /// Evaluating the source off the actor means `loadPlugin` suspends, so an unload can
    /// now interleave with it. If the finishing load still registered itself, disabling a
    /// script while it was loading would leave it running on captured traffic.
    ///
    /// The top-level loop below terminates, so no thread leaks; it only has to outlast the
    /// single actor hop `unloadPlugin` needs, which it does by orders of magnitude. The
    /// assertions hold whether the load was superseded or hit the watchdog first.
    @Test("An unload during a load wins, and the finishing load does not register")
    func unloadDuringLoadSupersedesIt() async throws {
        let runtime = ScriptRuntime()
        let slow = try makeTempPlugin(
            id: "com.test.slow-load",
            script: "for (let i = 0; i < 3e8; i++) {}\nfunction onRequest(ctx) { return ctx; }"
        )

        let load = Task { try await runtime.loadPlugin(slow) }
        await runtime.unloadPlugin(id: slow.id)

        await #expect(throws: ScriptRuntimeError.self) {
            try await load.value
        }
        let isLoaded = await runtime.hasPlugin(id: slow.id)
        #expect(!isLoaded)

        await #expect(throws: ScriptRuntimeError.self) {
            try await runtime.callOnRequest(
                pluginID: slow.id,
                context: makeRequestContext(),
                behavior: ScriptBehavior.defaults(),
                originalRequest: makeHTTPRequestData()
            )
        }
    }

    // MARK: Private

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

    private func makeRequestContext(
        method: String = "GET",
        url: String = "https://example.com/api",
        headers: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")]
    )
        -> ScriptRequestContext
    {
        let request = makeHTTPRequestData(method: method, url: url, headers: headers)
        return ScriptRequestContext(from: request)
    }

    private func makeHTTPRequestData(
        method: String = "GET",
        url: String = "https://example.com/api",
        headers: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")]
    )
        -> HTTPRequestData
    {
        HTTPRequestData(
            method: method,
            // swiftlint:disable:next force_unwrapping
            url: URL(string: url)!,
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: nil
        )
    }
}
