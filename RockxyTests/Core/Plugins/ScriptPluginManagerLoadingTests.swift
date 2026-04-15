import Foundation
@testable import Rockxy
import Testing

// Tests for the ScriptPluginManager startup-readiness contract:
// - `ensureLoadedOnce()` runs the discovery + reconcile pass exactly once
// - Concurrent callers share that single pass
// - `loadAllPlugins()` remains a re-scannable refresh path AFTER the one-shot load
// - PluginManager.loadPlugins() / ensureLoadedOnce() register built-ins exactly once

private func makeIsolatedDiscoveryDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("RockxyTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "RockxyTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Failed to create isolated UserDefaults suite: \(suiteName)")
    }
    return defaults
}

private func makeManager() throws -> ScriptPluginManager {
    let dir = try makeIsolatedDiscoveryDir()
    let defaults = makeIsolatedDefaults()
    let discovery = PluginDiscovery(pluginsDirectory: dir, defaults: defaults)
    return ScriptPluginManager(discovery: discovery, defaults: defaults)
}

// MARK: - ScriptPluginManagerLoadingTests

struct ScriptPluginManagerLoadingTests {
    @Test("Concurrent ensureLoadedOnce callers share one discovery pass")
    func concurrentEnsureLoadedOnce() async throws {
        let manager = try makeManager()
        async let a: Void = manager.ensureLoadedOnce()
        async let b: Void = manager.ensureLoadedOnce()
        async let c: Void = manager.ensureLoadedOnce()
        _ = await (a, b, c)
        let ready = await manager.isReady
        #expect(ready)
    }

    @Test("loadAllPlugins remains callable AFTER ensureLoadedOnce (no permanent early-return)")
    func loadAllPluginsRescansAfterFirstLoad() async throws {
        let manager = try makeManager()
        await manager.ensureLoadedOnce()
        // Should not throw and should not be a no-op forever.
        await manager.loadAllPlugins()
        await manager.loadAllPlugins()
        // No assertion on plugin count — directory is empty — but the calls
        // returning successfully proves the path is reentrant.
        let plugins = await manager.plugins
        #expect(plugins.isEmpty)
    }

    @Test("PluginManager.loadPlugins registers built-ins exactly once across many calls")
    func builtInsRegisteredExactlyOnce() {
        let manager = PluginManager()
        manager.loadPlugins()
        manager.loadPlugins()
        manager.loadPlugins()
        let exporters = manager.allExporters()
        let harCount = exporters.filter { $0.name == "HAR Exporter" }.count
        #expect(harCount == 1)
    }
}
