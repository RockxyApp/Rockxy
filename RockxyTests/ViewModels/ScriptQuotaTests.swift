import Foundation
@testable import Rockxy
import Testing

// MARK: - ScriptQuotaTests

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
    func concurrentEnablesAreSerialized() async {
        let manager = ScriptPluginManager()
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 10 {
                group.addTask {
                    do {
                        return try await manager.enablePluginIfAllowed(id: "test", maxEnabled: 2)
                    } catch {
                        return false
                    }
                }
            }
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            // All fail — plugin not found
            #expect(results.allSatisfy { !$0 })
        }
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
        // Coordinator init no longer overwrites shared gates
        #expect(ScriptPolicyGate.shared.policy.maxEnabledScripts == 2)
    }

    // MARK: - Shared Manager Observation

    @Test("Both ViewModels observe same ScriptPluginManager state")
    @MainActor
    func sharedManagerState() async {
        let manager = ScriptPluginManager()
        let settings = PluginSettingsViewModel(pluginManager: manager)
        let scripting = ScriptingViewModel(pluginManager: manager)

        await settings.loadPlugins()
        await scripting.loadPlugins()

        let managerPlugins = await manager.plugins
        #expect(settings.plugins.count == managerPlugins.count)
        #expect(scripting.plugins.count == managerPlugins.count)
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
