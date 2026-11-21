import AppKit
import Foundation
@testable import Rockxy
import Testing

// Regression tests for the redesigned Script Editor: dirty-draft tracking,
// the three-way unsaved-changes switch flow, save preflight, mock
// normalization, rule-test outcomes, and bounded console behavior.

@MainActor
@Suite(.serialized)
struct ScriptEditorViewModelTests {
    // MARK: Internal

    // MARK: - Dirty draft + baseline

    @Test("Editor draft equality reflects every tracked field")
    func editorDraftEqualityTracksEveryField() {
        var draft = ScriptEditorDraft.initialDefault
        var other = ScriptEditorDraft.initialDefault
        #expect(draft == other)

        other.name = "Changed"
        #expect(draft != other)
        other = draft
        other.method = .post
        #expect(draft != other)
        other = draft
        other.runAsMock.toggle()
        #expect(draft != other)
        other = draft
        other.code += "// tail"
        #expect(draft != other)

        draft.includeSubpaths.toggle()
        #expect(draft != ScriptEditorDraft.initialDefault)
    }

    @Test("Fresh editor is awaiting an intent and reports no unsaved changes")
    func freshEditorAwaitsIntentAndIsClean() {
        let vm = ScriptEditorViewModel()
        #expect(vm.contentState == .awaitingIntent)
        #expect(vm.isDirty == false)
        #expect(vm.hasUnsavedBoundChanges == false)
        #expect(vm.statusMessage.isEmpty)
    }

    @Test("Loading an existing script establishes a clean baseline and editing dirties it")
    func loadEstablishesBaselineAndEditingDirties() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "editor.baseline.\(UUID().uuidString)"
        try makeScriptPlugin(id: pluginID, name: "Baseline", in: env)
        await env.manager.loadAllPlugins()

        let vm = makeEditor(env)
        await vm.load(intent: .edit(pluginID: pluginID))

        #expect(vm.contentState == .editing)
        #expect(vm.isDirty == false)
        #expect(vm.hasUnsavedBoundChanges == false)

        vm.name += " Edited"
        #expect(vm.isDirty)
        #expect(vm.hasUnsavedBoundChanges)
    }

    @Test("A successful save rebaselines the draft so it is no longer dirty")
    func successfulSaveRebaselinesDraft() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "editor.rebaseline.\(UUID().uuidString)"
        try makeScriptPlugin(id: pluginID, name: "Rebaseline", in: env)
        await env.manager.loadAllPlugins()

        let vm = makeEditor(env)
        await vm.load(intent: .edit(pluginID: pluginID))
        vm.name = "Rebaselined"
        #expect(vm.isDirty)

        let saved = await vm.saveAndActivate()
        #expect(saved)
        #expect(vm.isDirty == false)

        vm.code += "\n// later edit"
        #expect(vm.isDirty)
    }

    @Test("Save persists the captured draft; a later edit stays dirty against that baseline")
    func saveBaselinesCapturedDraftNotLaterEdits() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "editor.captured.\(UUID().uuidString)"
        try makeScriptPlugin(id: pluginID, name: "Captured", in: env)
        await env.manager.loadAllPlugins()

        let vm = makeEditor(env)
        await vm.load(intent: .edit(pluginID: pluginID))
        vm.name = "Captured Save"
        let savedCode = vm.code

        let saved = await vm.saveAndActivate()
        #expect(saved)
        #expect(vm.isDirty == false)

        let pluginDir = env.pluginsDir.appendingPathComponent(pluginID, isDirectory: true)
        let onDisk = try String(contentsOf: pluginDir.appendingPathComponent("index.js"), encoding: .utf8)
        #expect(onDisk == savedCode)

        vm.code = savedCode + "\n// appended"
        #expect(vm.isDirty)
    }

    // MARK: - Request-load flow (three-way switch)

    @Test("Switching scripts while clean loads immediately without prompting")
    func cleanSwitchLoadsWithoutPrompt() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let idA = "editor.switch.a.\(UUID().uuidString)"
        let idB = "editor.switch.b.\(UUID().uuidString)"
        try makeScriptPlugin(id: idA, name: "Alpha", in: env)
        try makeScriptPlugin(id: idB, name: "Bravo", in: env)
        await env.manager.loadAllPlugins()

        let vm = makeEditor(env)
        await vm.requestLoad(intent: .edit(pluginID: idA))
        #expect(vm.pluginID == idA)
        #expect(vm.isShowingUnsavedSwitchPrompt == false)

        await vm.requestLoad(intent: .edit(pluginID: idB))
        #expect(vm.pluginID == idB)
        #expect(vm.isShowingUnsavedSwitchPrompt == false)
        #expect(vm.name == "Bravo")
    }

    @Test("Cancelling the unsaved switch keeps the current draft and clears the pending intent")
    func cancelUnsavedSwitchKeepsDraftClearsPending() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let idA = "editor.cancel.a.\(UUID().uuidString)"
        let idB = "editor.cancel.b.\(UUID().uuidString)"
        try makeScriptPlugin(id: idA, name: "Alpha", in: env)
        try makeScriptPlugin(id: idB, name: "Bravo", in: env)
        await env.manager.loadAllPlugins()

        let vm = makeEditor(env)
        await vm.load(intent: .edit(pluginID: idA))
        vm.name = "Alpha Edited"

        await vm.requestLoad(intent: .edit(pluginID: idB))
        #expect(vm.isShowingUnsavedSwitchPrompt)
        #expect(vm.pendingIntent == .edit(pluginID: idB))
        #expect(vm.pluginID == idA)

        await vm.resolveUnsavedSwitch(.cancel)
        #expect(vm.isShowingUnsavedSwitchPrompt == false)
        #expect(vm.pendingIntent == nil)
        #expect(vm.pluginID == idA)
        #expect(vm.name == "Alpha Edited")
        #expect(vm.isDirty)
    }

    @Test("Discarding the unsaved switch loads the pending intent and drops edits")
    func discardUnsavedSwitchLoadsPending() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let idA = "editor.discard.a.\(UUID().uuidString)"
        let idB = "editor.discard.b.\(UUID().uuidString)"
        try makeScriptPlugin(id: idA, name: "Alpha", in: env)
        try makeScriptPlugin(id: idB, name: "Bravo", in: env)
        await env.manager.loadAllPlugins()

        let vm = makeEditor(env)
        await vm.load(intent: .edit(pluginID: idA))
        vm.name = "Alpha Edited"

        await vm.requestLoad(intent: .edit(pluginID: idB))
        await vm.resolveUnsavedSwitch(.discard)

        #expect(vm.pendingIntent == nil)
        #expect(vm.pluginID == idB)
        #expect(vm.name == "Bravo")
        #expect(vm.isDirty == false)

        let alphaManifest = try JSONDecoder().decode(
            PluginManifest.self,
            from: Data(contentsOf: env.pluginsDir.appendingPathComponent(idA).appendingPathComponent("plugin.json"))
        )
        #expect(alphaManifest.name == "Alpha")
    }

    @Test("Save & Switch persists the current script before loading the pending intent")
    func saveAndSwitchPersistsThenLoadsPending() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let idA = "editor.saveswitch.a.\(UUID().uuidString)"
        let idB = "editor.saveswitch.b.\(UUID().uuidString)"
        try makeScriptPlugin(id: idA, name: "Alpha", in: env)
        try makeScriptPlugin(id: idB, name: "Bravo", in: env)
        await env.manager.loadAllPlugins()

        let vm = makeEditor(env)
        await vm.load(intent: .edit(pluginID: idA))
        vm.name = "Alpha Saved"

        await vm.requestLoad(intent: .edit(pluginID: idB))
        await vm.resolveUnsavedSwitch(.saveAndSwitch)

        #expect(vm.pendingIntent == nil)
        #expect(vm.pluginID == idB)
        #expect(vm.name == "Bravo")

        let alphaManifest = try JSONDecoder().decode(
            PluginManifest.self,
            from: Data(contentsOf: env.pluginsDir.appendingPathComponent(idA).appendingPathComponent("plugin.json"))
        )
        #expect(alphaManifest.name == "Alpha Saved")
    }

    @Test("Reopening the same dirty script prompts before discarding edits")
    func sameScriptWhileDirtyPrompts() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "editor.same.\(UUID().uuidString)"
        try makeScriptPlugin(id: pluginID, name: "Same", in: env)
        await env.manager.loadAllPlugins()

        let vm = makeEditor(env)
        await vm.load(intent: .edit(pluginID: pluginID))
        vm.name = "Same Edited"

        await vm.requestLoad(intent: .edit(pluginID: pluginID))
        #expect(vm.isShowingUnsavedSwitchPrompt)
        #expect(vm.pendingIntent == .edit(pluginID: pluginID))

        await vm.resolveUnsavedSwitch(.discard)
        #expect(vm.name == "Same")
        #expect(vm.isDirty == false)
    }

    // MARK: - Save preflight

    @Test("Save with no bound script reports a truthful failure")
    func saveWithoutBoundScriptReportsFailure() async {
        let vm = ScriptEditorViewModel()
        await vm.load(intent: .createNew)
        #expect(vm.pluginID == nil)

        let saved = await vm.saveAndActivate()
        #expect(saved == false)
        #expect(vm.statusTone == .warning)
        #expect(vm.statusMessage.isEmpty == false)
    }

    @Test("Preflight blocks a blank name and never touches the plugin files")
    func preflightBlocksBlankName() async throws {
        try await assertPreflightBlocksSave { $0.name = "   " }
    }

    @Test("Preflight blocks an invalid regex pattern and never touches the plugin files")
    func preflightBlocksInvalidRegex() async throws {
        try await assertPreflightBlocksSave { vm in
            vm.patternMode = .regex
            vm.urlPattern = "["
        }
    }

    @Test("Preflight blocks disabling both phases and never touches the plugin files")
    func preflightBlocksBothPhasesOff() async throws {
        try await assertPreflightBlocksSave { vm in
            vm.runOnRequest = false
            vm.runOnResponse = false
        }
    }

    @Test("Preflight blocks a Mock script that does not run on Request")
    func preflightBlocksMockWithoutRequest() async throws {
        try await assertPreflightBlocksSave { vm in
            vm.runOnResponse = true
            vm.runOnRequest = false
            vm.runAsMock = true
        }
    }

    @Test("Sequential saves both succeed and clear the in-flight flag")
    func sequentialSavesSucceedAndClearFlag() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "editor.double.\(UUID().uuidString)"
        try makeScriptPlugin(id: pluginID, name: "Double", in: env)
        await env.manager.loadAllPlugins()

        let vm = makeEditor(env)
        await vm.load(intent: .edit(pluginID: pluginID))
        vm.name = "Double One"
        let first = await vm.saveAndActivate()
        #expect(vm.isSaving == false)
        vm.name = "Double Two"
        let second = await vm.saveAndActivate()

        #expect(first)
        #expect(second)
        #expect(vm.isSaving == false)
    }

    // MARK: - Mock normalization

    @Test("Enabling Mock normalizes phases; disabling Request clears Mock")
    func mockNormalizationKeepsPhasesConsistent() {
        let vm = ScriptEditorViewModel()
        vm.runOnRequest = false
        vm.runOnResponse = true

        vm.setRunAsMock(true)
        #expect(vm.runAsMock)
        #expect(vm.runOnRequest)
        #expect(vm.runOnResponse == false)

        vm.setRunOnRequest(false)
        #expect(vm.runOnRequest == false)
        #expect(vm.runAsMock == false)
    }

    // MARK: - Rule test outcome

    @Test("Rule evaluation separates invalid patterns from genuine misses")
    func ruleEvaluationSeparatesInvalidFromMiss() {
        let vm = ScriptEditorViewModel()
        vm.patternMode = .regex
        vm.urlPattern = "api\\.example\\.com/v1/.+"
        #expect(vm.evaluateRule(against: "https://api.example.com/v1/users") == .match)
        #expect(vm.evaluateRule(against: "https://other.example.com") == .noMatch)

        vm.urlPattern = "["
        #expect(vm.evaluateRule(against: "https://api.example.com/v1/users") == .invalidPattern)

        vm.runRuleTest()
        #expect(vm.testRulePreview.contains("not a valid"))
    }

    // MARK: - Console bounding + filter state

    @Test("Editor console is bounded to the newest entries and evicts the oldest")
    func consoleBoundedToNewestEntries() async {
        let vm = ScriptEditorViewModel()
        // A distinguishable oldest entry, then enough churn to overflow the cap.
        await vm.validateScript()
        #expect(vm.consoleEntries.contains { $0.message.contains("Validation passed") })

        for _ in 0 ..< 520 {
            vm.beautify()
        }

        #expect(vm.consoleEntries.count == 500)
        #expect(!vm.consoleEntries.contains { $0.message.contains("Validation passed") })
        #expect(vm.consoleEntries.allSatisfy { $0.message.contains("beautified") })
    }

    @Test("Console empty state distinguishes truly empty from filtered-empty")
    func consoleEmptyStateDistinguishesFilteredFromEmpty() async {
        let vm = ScriptEditorViewModel()
        #expect(vm.consoleEmptyState == .empty)

        await vm.validateScript()
        #expect(vm.consoleEmptyState == .populated)
        #expect(vm.visibleConsoleEntries.isEmpty == false)

        // The validation entry is a `.system` message; hide that level.
        vm.consoleFilter = [.errors]
        #expect(vm.visibleConsoleEntries.isEmpty)
        #expect(vm.consoleEmptyState == .filtered)
    }

    // MARK: Private

    private func makeEditor(_ env: TestFixtures.IsolatedPluginEnv) -> ScriptEditorViewModel {
        ScriptEditorViewModel(
            pluginManager: env.manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: env.pluginsDir
        )
    }

    /// Create a disabled script plugin bundle with the default template source.
    private func makeScriptPlugin(
        id: String,
        name: String,
        in env: TestFixtures.IsolatedPluginEnv
    )
        throws
    {
        let pluginDir = env.pluginsDir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: id,
            name: name,
            version: "1.0.0",
            author: PluginAuthor(name: "User", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "index.js"],
            capabilities: ["modifyRequest", "modifyResponse"],
            scriptBehavior: ScriptBehavior.defaults()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"))
        try ScriptTemplates.defaultSource.write(
            to: pluginDir.appendingPathComponent("index.js"),
            atomically: true,
            encoding: .utf8
        )
        env.defaults.removeObject(forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
    }

    /// Loads a fresh plugin, applies an invalid mutation, saves, and asserts the
    /// save is rejected without altering the persisted manifest or source.
    private func assertPreflightBlocksSave(
        mutate: (ScriptEditorViewModel) -> Void
    )
        async throws
    {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "editor.preflight.\(UUID().uuidString)"
        try makeScriptPlugin(id: pluginID, name: "Preflight", in: env)
        await env.manager.loadAllPlugins()

        let pluginDir = env.pluginsDir.appendingPathComponent(pluginID, isDirectory: true)
        let manifestURL = pluginDir.appendingPathComponent("plugin.json")
        let scriptURL = pluginDir.appendingPathComponent("index.js")
        let manifestBefore = try Data(contentsOf: manifestURL)
        let sourceBefore = try Data(contentsOf: scriptURL)

        let vm = makeEditor(env)
        await vm.load(intent: .edit(pluginID: pluginID))
        vm.code = "// no hooks here"
        mutate(vm)

        let saved = await vm.saveAndActivate()
        #expect(saved == false)
        #expect(vm.statusTone == .error)
        #expect(vm.consoleEntries.contains { $0.level == .errors })

        #expect(try Data(contentsOf: manifestURL) == manifestBefore)
        #expect(try Data(contentsOf: scriptURL) == sourceBefore)
    }
}
