import Foundation
import JavaScriptCore
@testable import Rockxy
import Testing

// Regression tests for `ScriptRuntime` in the core plugins layer.

/// Serialized because three tests here evaluate a deliberately long-running script to
/// prove the 5 s watchdog fires, and JavaScriptCore cannot be interrupted once an
/// evaluation is running. Run in parallel they pin three cores at once, which is what
/// starved the cooperative pool and stalled the run on 2026-11-02 and again on
/// 2026-11-03. Serialized, at most one core is burning at a time.
@Suite(.serialized)
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

    /// The loop is long rather than infinite, and that is deliberate.
    /// `workItem.cancel()` is a no-op for work already running and JavaScriptCore
    /// exposes no public way to interrupt a running evaluation, so the thread spins for
    /// the whole loop whatever the watchdog does. A `while (true)` therefore pins a core
    /// for the rest of the test process, and this file needs three such scripts: with
    /// Swift Testing running suites in parallel that starved the cooperative pool and
    /// stalled the run on 2026-11-03.
    ///
    /// A bounded loop proves the same thing, because the assertion is that the 5 s
    /// watchdog fires while the evaluation is still going. Sized as in
    /// `unloadDuringLoadSupersedesIt`: 3e9 is around 12 s on this machine, over twice the
    /// watchdog, and a loaded machine only makes it longer -- the safe direction. The
    /// thread then exits and gives the core back.
    @Test("A plugin whose script never returns is retired, and a reload revives it")
    func runawayScriptRetiresThePluginAndReloadRevivesIt() async throws {
        let runtime = ScriptRuntime()
        let runaway = "function onRequest(ctx) { for (let i = 0; i < 3e9; i++) {} }"
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

    /// Bounded for the reason the hook test above explains. It covers a different
    /// failure: the loop here is at TOP LEVEL, so it runs inside `evaluateScript` during
    /// the load itself, where no hook is ever called. Evaluated on the actor that would
    /// hang `ScriptRuntime` permanently -- so the second half of this test, loading an
    /// unrelated plugin afterwards and calling it, is the actual assertion.
    @Test("A script whose top-level code never returns fails its load and leaves the runtime usable")
    func runawayTopLevelSourceFailsTheLoadWithoutWedgingTheRuntime() async throws {
        let runtime = ScriptRuntime()
        let runaway = try makeTempPlugin(
            id: "com.test.runaway-toplevel",
            script: "for (let i = 0; i < 3e9; i++) {}\nfunction onRequest(ctx) { return ctx; }"
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
    /// Waiting for `inFlightLoadCount` is what makes this honest rather than a coin flip:
    /// both calls have to reach the actor, so an unload issued right after the load task
    /// can arrive first, correctly supersede nothing, and let the later load register --
    /// which would fail every assertion here against a product that behaved correctly.
    ///
    /// Timing alone cannot close the rest of the gap. Tests run in parallel, so the hop
    /// that carries `unloadPlugin` onto the actor waits on a cooperative pool other suites
    /// are using, while the evaluation runs on its own Dispatch queue and is not slowed by
    /// any of it. A 3e8 loop lost that race on 2026-11-02: it finished, registered, and
    /// only then did the unload land, so `loadPlugin` returned normally.
    ///
    /// What makes the outcome deterministic is that both remaining paths prove the same
    /// thing. If the unload lands first the load is superseded; if the pool stalls long
    /// enough the watchdog retires the evaluation instead. Either way `loadPlugin` throws
    /// a `ScriptRuntimeError` and the plugin is never registered, which is the invariant
    /// the user actually depends on: a script they switched off must not end up loaded and
    /// callable.
    ///
    /// So the loop is sized against the 5 s watchdog, not against the hop: outrunning the
    /// hop cannot be guaranteed at any size, while exceeding the watchdog can. Measured
    /// with JavaScriptCore on this machine, idle: 3e8 takes 1.1 s, 1e9 takes 3.9 s. 3e9 is
    /// therefore around 12 s, and a loaded machine only makes it longer, which is the safe
    /// direction. It must also not be far larger than that: `workItem.cancel()` is a no-op
    /// for work already running, so the thread spins for the whole loop whatever the
    /// watchdog does. A 1e10 loop measured ~39 s, and the full suite stalled on
    /// 2026-11-02 with three CPU-bound threads of an 11-core box held at once.
    @Test("An unload during a load wins, and the finishing load does not register")
    func unloadDuringLoadSupersedesIt() async throws {
        let runtime = ScriptRuntime()
        let slow = try makeTempPlugin(
            id: "com.test.slow-load",
            script: "for (let i = 0; i < 3e9; i++) {}\nfunction onRequest(ctx) { return ctx; }"
        )

        let load = Task { try await runtime.loadPlugin(slow) }
        let deadline = ContinuousClock.now + .seconds(10)
        while await runtime.inFlightLoadCount == 0, ContinuousClock.now < deadline {
            await Task.yield()
        }
        try #require(
            await runtime.inFlightLoadCount == 1,
            "the load never began evaluating, so there was nothing for the unload to supersede"
        )
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
