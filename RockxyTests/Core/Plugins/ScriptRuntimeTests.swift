import Foundation
import JavaScriptCore
@testable import Rockxy
import Testing

// MARK: - ScriptRuntimeTests

// Regression tests for `ScriptRuntime` in the core plugins layer.

/// Serialized because one test here still evaluates a deliberately long-running script to
/// prove the 5 s hook watchdog fires, and JavaScriptCore cannot be interrupted once an
/// evaluation is running. Run in parallel several such scripts pin several cores at once,
/// which is what starved the cooperative pool and stalled the run on 2026-11-02 and again
/// on 2026-11-03. Serialized, at most one core is burning at a time. The two load-path
/// tests no longer spin: they hold the evaluation on a semaphore through
/// `setSourceEvaluationHook` instead.
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
    /// for the rest of the test process: with Swift Testing running suites in parallel
    /// such scripts starved the cooperative pool and stalled the run on 2026-11-03. This
    /// is the one test left that needs a spinning script, because a hook call has no
    /// evaluation seam to park on; the load-path tests hold the evaluation on a semaphore.
    ///
    /// A bounded loop proves the same thing, because the assertion is that the 5 s
    /// watchdog fires while the evaluation is still going. 3e9 is around
    /// 12 s on this machine (1e9 is 3.9 s, 3e8 is 1.1 s), over twice the 5 s watchdog, and a loaded machine only makes
    /// it longer -- the safe direction. The
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

    /// The evaluation is held on a semaphore rather than spun in a JavaScript loop. The
    /// property is that the watchdog retires a load whose evaluation is still going, and
    /// a held evaluation is exactly that, without burning a core for 12 s or depending on
    /// how fast JavaScriptCore happens to count. The evaluation runs off the actor, so
    /// the second half of this test, loading an unrelated plugin afterwards and calling
    /// it, is the actual assertion that a stuck load cannot take the runtime down.
    @Test(
        "A script whose top-level code never returns fails its load and leaves the runtime usable",
        .timeLimit(.minutes(1))
    )
    func runawayTopLevelSourceFailsTheLoadWithoutWedgingTheRuntime() async throws {
        let runtime = ScriptRuntime()
        let runaway = try makeTempPlugin(
            id: "com.test.runaway-toplevel",
            script: "function onRequest(ctx) { return ctx; }"
        )
        let handshake = EvaluationHandshake()
        await runtime.setSourceEvaluationHook(handshake.hook)

        do {
            try await runtime.loadPlugin(runaway)
            Issue.record("a load whose evaluation never finishes must fail")
        } catch let error as ScriptRuntimeError {
            guard case .runawayScript = error else {
                Issue.record("expected runawayScript from the watchdog, got \(error)")
                handshake.release()
                return
            }
        }
        // Let the held evaluation finish and stop holding later ones.
        await runtime.setSourceEvaluationHook(nil)
        handshake.release()

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
    /// The interleaving is decided by a two-way handshake, not by timing. The evaluation
    /// hook fires on the plugin's queue after the load has claimed its token, so when the
    /// test hears it, the load is provably in flight; the hook then parks on a semaphore
    /// until the test has finished unloading. Only after that does the evaluation return,
    /// so the finishing load meets a superseded token every time, on any machine, with no
    /// CPU-bound script and no deadline in the success path. The time limit is only a
    /// backstop against a hang if a regression stops the hook from ever firing.
    @Test("An unload during a load wins, and the finishing load does not register", .timeLimit(.minutes(1)))
    func unloadDuringLoadSupersedesIt() async throws {
        let runtime = ScriptRuntime()
        let slow = try makeTempPlugin(
            id: "com.test.slow-load",
            script: "function onRequest(ctx) { return ctx; }"
        )
        let handshake = EvaluationHandshake()
        await runtime.setSourceEvaluationHook(handshake.hook)

        let load = Task { try await runtime.loadPlugin(slow) }
        await handshake.waitUntilEvaluating()
        await runtime.unloadPlugin(id: slow.id)
        handshake.release()

        do {
            try await load.value
            Issue.record("a load superseded by an unload must not succeed")
        } catch let error as ScriptRuntimeError {
            guard case let .pluginNotLoaded(id) = error, id == slow.id else {
                Issue.record("expected the superseded-load error, got \(error)")
                return
            }
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

// MARK: - EvaluationHandshake

/// Both directions of the handshake with a load's source evaluation. `hook` is installed
/// through `ScriptRuntime.setSourceEvaluationHook`; it runs on the plugin's Dispatch queue,
/// announces that evaluation began, then parks on a semaphore until `release()`. Blocking
/// a Dispatch thread is fine; the test side only ever awaits the stream, so no cooperative
/// thread is held.
private final class EvaluationHandshake: @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        (began, beganContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    // MARK: Internal

    var hook: @Sendable () -> Void {
        { [self] in
            beganContinuation.yield()
            released.wait()
        }
    }

    func waitUntilEvaluating() async {
        for await _ in began {
            return
        }
    }

    func release() {
        released.signal()
    }

    // MARK: Private

    private let began: AsyncStream<Void>
    private let beganContinuation: AsyncStream<Void>.Continuation
    private let released = DispatchSemaphore(value: 0)
}
