import Foundation
@testable import Rockxy
import Testing

// MARK: - ScriptQuotaTests

/// Serialized: mutates shared plugin directory and UserDefaults plugin-enabled keys.
@Suite(.serialized)
struct ScriptQuotaTests {
    @Test("ScriptPolicyGate reads limit from AppPolicy")
    @MainActor
    func gateLimitFromPolicy() {
        let gate = ScriptPolicyGate(policy: TinyScriptPolicy())
        #expect(gate.policy.maxEnabledScripts == 2)
    }

    @Test("ScriptQuotaError provides description")
    func quotaErrorDescription() {
        let error = ScriptQuotaError.limitReached(max: 5)
        #expect(error.localizedDescription.contains("5"))
    }

    @Test("ScriptPluginError.pluginNotFound provides description")
    func pluginNotFoundDescription() {
        let error = ScriptPluginError.pluginNotFound("test-id")
        #expect(error.localizedDescription.contains("test-id"))
    }

    // MARK: - Missing Plugin Errors

    @Test("enablePluginIfAllowed throws for missing plugin ID")
    func enableMissingPluginThrows() async {
        let manager = ScriptPluginManager()
        do {
            _ = try await manager.enablePluginIfAllowed(id: "nonexistent", maxEnabled: 10)
            Issue.record("Expected ScriptPluginError.pluginNotFound")
        } catch is ScriptPluginError {
            // Expected
        } catch {
            Issue.record("Expected ScriptPluginError, got \(error)")
        }
    }

    @Test("ScriptPolicyGate.enablePlugin propagates pluginNotFound")
    @MainActor
    func gatePropagatesPluginNotFound() async {
        let manager = ScriptPluginManager()
        let gate = ScriptPolicyGate(policy: DefaultAppPolicy())
        do {
            try await gate.enablePlugin(id: "ghost", using: manager)
            Issue.record("Expected error")
        } catch is ScriptPluginError {
            // Expected
        } catch is ScriptQuotaError {
            Issue.record("Should have thrown ScriptPluginError, not quota error")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Concurrent Enables

    @Test("Concurrent enables against shared manager are serialized by actor")
    func concurrentEnablesAreSerialized() async throws {
        let pluginsDir = TestFixtures.makeIsolatedPluginDir()
        defer { TestFixtures.cleanupIsolatedPluginDir(pluginsDir) }

        var pluginIDs: [String] = []
        for i in 0 ..< 5 {
            let id = "concurrent-\(i)-\(UUID().uuidString.prefix(8))"
            _ = try TestFixtures.createTempPlugin(id: id, enabled: false, in: pluginsDir)
            pluginIDs.append(id)
        }
        defer {
            for id in pluginIDs {
                TestFixtures.cleanupTempPlugin(id: id, bundlePath: pluginsDir.appendingPathComponent(id))
            }
        }

        let manager = TestFixtures.makeIsolatedPluginManager(pluginsDir: pluginsDir)
        await manager.loadAllPlugins()

        // Try to enable all 5 concurrently with maxEnabled = 2
        await withTaskGroup(of: Bool.self) { group in
            for id in pluginIDs {
                group.addTask {
                    do {
                        return try await manager.enablePluginIfAllowed(id: id, maxEnabled: 2)
                    } catch {
                        return false
                    }
                }
            }
            var successes = 0
            for await result in group where result {
                successes += 1
            }
            #expect(successes == 2)
        }
    }

    // MARK: - Real Plugin Enable/Disable Path

    @Test("Enable and disable through shared manager round-trips correctly")
    func enableDisableRoundTrip() async throws {
        let pluginsDir = TestFixtures.makeIsolatedPluginDir()
        defer { TestFixtures.cleanupIsolatedPluginDir(pluginsDir) }

        let id = "roundtrip-test-\(UUID().uuidString.prefix(8))"
        _ = try TestFixtures.createTempPlugin(id: id, enabled: false, in: pluginsDir)

        let manager = TestFixtures.makeIsolatedPluginManager(pluginsDir: pluginsDir)
        await manager.loadAllPlugins()
        let initial = await manager.plugins
        #expect(initial.contains { $0.id == id })
        #expect(initial.first { $0.id == id }?.isEnabled == false)

        // Enable through the quota-checked path
        let accepted = try await manager.enablePluginIfAllowed(id: id, maxEnabled: 10)
        #expect(accepted)
        let afterEnable = await manager.plugins
        #expect(afterEnable.first { $0.id == id }?.isEnabled == true)

        // Disable
        await manager.disablePlugin(id: id)
        let afterDisable = await manager.plugins
        #expect(afterDisable.first { $0.id == id }?.isEnabled == false)
    }

    @Test("Both ViewModels observe shared manager enable/disable")
    @MainActor
    func sharedManagerObservation() async throws {
        let pluginsDir = TestFixtures.makeIsolatedPluginDir()
        defer { TestFixtures.cleanupIsolatedPluginDir(pluginsDir) }

        let id = "shared-obs-\(UUID().uuidString.prefix(8))"
        _ = try TestFixtures.createTempPlugin(id: id, enabled: false, in: pluginsDir)

        let manager = TestFixtures.makeIsolatedPluginManager(pluginsDir: pluginsDir)
        let settings = PluginSettingsViewModel(pluginManager: manager)
        let scripting = ScriptingViewModel(pluginManager: manager)

        await settings.loadPlugins()
        scripting.plugins = await manager.plugins

        #expect(settings.plugins.contains { $0.id == id })
        #expect(scripting.plugins.contains { $0.id == id })

        // Enable through gate
        let gate = ScriptPolicyGate(policy: DefaultAppPolicy())
        try await gate.enablePlugin(id: id, using: manager)

        // Both VMs refresh from the same manager and see the change
        settings.plugins = await manager.plugins
        scripting.plugins = await manager.plugins
        #expect(settings.plugins.first { $0.id == id }?.isEnabled == true)
        #expect(scripting.plugins.first { $0.id == id }?.isEnabled == true)
    }

    // MARK: - Stale Cross-Window Re-Enable

    @Test("Re-enabling an already-enabled plugin is a no-op success")
    func reEnableIsNoOp() async throws {
        let pluginsDir = TestFixtures.makeIsolatedPluginDir()
        defer { TestFixtures.cleanupIsolatedPluginDir(pluginsDir) }

        let id = "reenable-\(UUID().uuidString.prefix(8))"
        _ = try TestFixtures.createTempPlugin(id: id, enabled: false, in: pluginsDir)

        let manager = TestFixtures.makeIsolatedPluginManager(pluginsDir: pluginsDir)
        await manager.loadAllPlugins()

        // First window enables the plugin
        let first = try await manager.enablePluginIfAllowed(id: id, maxEnabled: 1)
        #expect(first)
        let afterFirst = await manager.plugins
        #expect(afterFirst.first { $0.id == id }?.isEnabled == true)
        #expect(afterFirst.first { $0.id == id }?.status == .active)

        // Second window has stale local state and issues enable again.
        // This must succeed as a no-op — no runtime reload, no quota rejection.
        let second = try await manager.enablePluginIfAllowed(id: id, maxEnabled: 1)
        #expect(second)

        // State remains stable
        let afterSecond = await manager.plugins
        #expect(afterSecond.first { $0.id == id }?.isEnabled == true)
        #expect(afterSecond.first { $0.id == id }?.status == .active)
    }

    // MARK: - Policy Injection

    @Test("Custom policy takes effect through .shared assignment")
    @MainActor
    func customPolicyInjectable() {
        let saved = ScriptPolicyGate.shared
        defer { ScriptPolicyGate.shared = saved }

        ScriptPolicyGate.shared = ScriptPolicyGate(policy: TinyScriptPolicy())
        #expect(ScriptPolicyGate.shared.policy.maxEnabledScripts == 2)

        ScriptPolicyGate.shared = ScriptPolicyGate(policy: DefaultAppPolicy())
        #expect(ScriptPolicyGate.shared.policy.maxEnabledScripts == 10)
    }

    @Test("Coordinator construction does not pollute shared script gate")
    @MainActor
    func coordinatorDoesNotPolluteScriptGate() {
        let saved = ScriptPolicyGate.shared
        defer { ScriptPolicyGate.shared = saved }

        ScriptPolicyGate.shared = ScriptPolicyGate(policy: TinyScriptPolicy())
        _ = MainContentCoordinator(policy: DefaultAppPolicy())
        #expect(ScriptPolicyGate.shared.policy.maxEnabledScripts == 2)
    }

    // MARK: - Default Wiring

    @Test("Settings and scripting VMs backed by same manager discover same plugin")
    @MainActor
    func sharedManagerBothVMsDiscover() async throws {
        let pluginsDir = TestFixtures.makeIsolatedPluginDir()
        defer { TestFixtures.cleanupIsolatedPluginDir(pluginsDir) }

        let id = "default-wiring-\(UUID().uuidString.prefix(8))"
        _ = try TestFixtures.createTempPlugin(id: id, enabled: false, in: pluginsDir)

        let manager = TestFixtures.makeIsolatedPluginManager(pluginsDir: pluginsDir)
        let settings = PluginSettingsViewModel(pluginManager: manager)
        let scripting = ScriptingViewModel(pluginManager: manager)

        await settings.loadPlugins()
        await scripting.loadPlugins()

        #expect(settings.plugins.contains { $0.id == id })
        #expect(scripting.plugins.contains { $0.id == id })
        #expect(settings.plugins.count == scripting.plugins.count)
    }

    @Test("PluginManager.shared returns same instance")
    func pluginManagerSingletonIdentity() {
        let first = PluginManager.shared
        let second = PluginManager.shared
        #expect(first === second)
    }

    @Test("Concurrent enable of 2 real plugins both succeed at high limit")
    func concurrentRealPluginSuccess() async throws {
        let pluginsDir = TestFixtures.makeIsolatedPluginDir()
        defer { TestFixtures.cleanupIsolatedPluginDir(pluginsDir) }

        var pluginIDs: [String] = []
        for i in 0 ..< 2 {
            let id = "concurrent-real-\(i)-\(UUID().uuidString.prefix(8))"
            _ = try TestFixtures.createTempPlugin(id: id, enabled: false, in: pluginsDir)
            pluginIDs.append(id)
        }

        let manager = TestFixtures.makeIsolatedPluginManager(pluginsDir: pluginsDir)
        await manager.loadAllPlugins()

        await withTaskGroup(of: Bool.self) { group in
            for id in pluginIDs {
                group.addTask {
                    do {
                        return try await manager.enablePluginIfAllowed(id: id, maxEnabled: 10)
                    } catch {
                        return false
                    }
                }
            }
            var successes = 0
            for await result in group where result {
                successes += 1
            }
            #expect(successes == 2)
        }

        // Verify postcondition: both plugins are actually enabled in the shared manager
        let finalPlugins = await manager.plugins
        for id in pluginIDs {
            let plugin = finalPlugins.first { $0.id == id }
            #expect(plugin?.isEnabled == true)
        }
    }
}

// MARK: - TinyScriptPolicy

private struct TinyScriptPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 2
    let maxLiveHistoryEntries = 1_000
}
