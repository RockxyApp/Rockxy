import Foundation
@testable import Rockxy
import Testing

// Regression tests for the scripting viewmodels: default template text, editor
// view model state, and list view model construction.

@MainActor
@Suite(.serialized)
struct ScriptingViewModelTests {
    @Test("ScriptTemplates.defaultSource contains the multi-arg onRequest signature")
    func defaultTemplateContainsMultiArgRequest() {
        #expect(ScriptTemplates.defaultSource.contains("function onRequest(context, url, request)"))
    }

    @Test("ScriptTemplates.defaultSource contains the multi-arg onResponse signature")
    func defaultTemplateContainsMultiArgResponse() {
        #expect(ScriptTemplates.defaultSource.contains("function onResponse(context, url, request, response)"))
    }

    @Test("ScriptTemplates.defaultSource documents response.bodyFilePath comment")
    func defaultTemplateContainsBodyFilePath() {
        #expect(ScriptTemplates.defaultSource.contains("response.bodyFilePath"))
    }

    @Test("ScriptEditorViewModel starts with defaults (match-all, req/resp on, mock off)")
    func editorDefaults() {
        let vm = ScriptEditorViewModel()
        #expect(vm.runOnRequest == true)
        #expect(vm.runOnResponse == true)
        #expect(vm.runAsMock == false)
        #expect(vm.method == .any)
        #expect(vm.patternMode == .wildcard)
        #expect(vm.code == ScriptTemplates.defaultSource)
        #expect(vm.sampleURL == "https://api.example.com/path")
    }

    @Test("Wildcard-to-regex helper escapes specials and anchors when no subpath")
    func wildcardHelper() {
        let pattern = ScriptEditorViewModel.wildcardToRegex("api.example.com/v1/*")
        #expect(pattern == "^api\\.example\\.com/v1/.*$")
        let sub = ScriptEditorViewModel.wildcardToRegex("api.example.com/v1/*", includeSubpaths: true)
        #expect(sub == "api\\.example\\.com/v1/.*")
    }

    @Test("Beautify normalizes indentation on a dedented JS block")
    func beautifyIndents() {
        let src = """
        function outer() {
        var x = 1;
        if (x) {
        console.log(x);
        }
        }
        """
        let out = ScriptEditorViewModel.beautifyJavaScript(src)
        // All opening braces should increase indent by 2 spaces.
        #expect(out.contains("  var x = 1;"))
        #expect(out.contains("  if (x) {"))
        #expect(out.contains("    console.log(x);"))
    }

    @Test("ScriptingListViewModel starts with no plugins and no selection")
    func listDefaults() {
        let vm = ScriptingListViewModel()
        #expect(vm.plugins.isEmpty)
        #expect(vm.selectedRowID == nil)
    }

    @Test("Script editor menus match native grouped order")
    func editorMenuContentOrder() {
        #expect(ScriptEditorMenuContent.methodSections == [
            [.any],
            [.get, .post, .put, .delete, .patch],
            [.head, .options, .trace],
        ])
        #expect(ScriptEditorMenuContent.patternModeSections == [
            [.wildcard, .regex],
            [.advanced],
        ])
    }

    @Test("Script code highlighting recognizes JavaScript syntax roles")
    func scriptCodeHighlightingSpans() {
        let spans = ScriptCodeHighlighting.spans(for: #"async function run() { return "ok"; // done"#)
        #expect(spans.contains { $0.role == .keyword })
        #expect(spans.contains { $0.role == .function })
        #expect(spans.contains { $0.role == .string })
        #expect(spans.contains { $0.role == .comment })
        #expect(spans.contains { $0.role == .punctuation })
    }

    @Test("Method enum round-trips via persistedValue")
    func methodRoundTrip() {
        for m in ScriptMatchMethod.allCases {
            let persisted = m.persistedValue
            let reparsed = ScriptMatchMethod(persisted: persisted)
            #expect(reparsed == m)
        }
    }

    @Test("Folder index Codable round-trips")
    func folderIndexCodable() throws {
        let folder = ScriptFolder(name: "Auth", expanded: true, scriptIDs: ["a", "b"])
        let index = ScriptFolderIndex(folders: [folder], rootOrder: [.folder(folder.id), .script("c")])
        let data = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(ScriptFolderIndex.self, from: data)
        #expect(decoded == index)
    }

    @Test("Method filter treats missing persisted method as ANY")
    func methodFilterMatchesAnyFallback() {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        folderStore.reconcile(with: ["script-any", "script-post"])

        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        vm.plugins = [
            PluginInfoSnapshot(
                id: "script-any",
                name: "Any Script",
                isEnabled: true,
                method: nil,
                urlPattern: nil,
                statusText: "Active"
            ),
            PluginInfoSnapshot(
                id: "script-post",
                name: "Post Script",
                isEnabled: true,
                method: "POST",
                urlPattern: nil,
                statusText: "Active"
            ),
        ]
        vm.isFilterVisible = true
        vm.filterColumn = .method
        vm.filterText = "any"

        let rows = vm.filteredDisplayRows
        #expect(rows.count == 1)
        #expect(rows.first?.id == .script("script-any"))
    }

    @Test("Folder index entry decode rejects payloads containing both folder and script")
    func folderIndexRejectsAmbiguousEntry() throws {
        let data = Data(
            #"{"folders":[],"rootOrder":[{"folder":"00000000-0000-0000-0000-000000000001","script":"abc"}]}"#
                .utf8
        )
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ScriptFolderIndex.self, from: data)
        }
    }

    @Test("Filtered rows include collapsed folder ancestors for matching scripts")
    func filteredRowsIncludeCollapsedFolderAncestors() {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        let folderID = folderStore.createFolder(name: "Auth")
        folderStore.addScript("script-1", toFolder: folderID)
        folderStore.setExpanded(folderID: folderID, expanded: false)

        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        vm.plugins = [
            PluginInfoSnapshot(
                id: "script-1",
                name: "Token Refresh",
                isEnabled: true,
                method: "GET",
                urlPattern: "/token",
                statusText: "Active"
            )
        ]
        vm.isFilterVisible = true
        vm.filterText = "token"
        vm.filterColumn = .name

        let rows = vm.filteredDisplayRows
        #expect(rows.count == 2)
        #expect(rows.first?.id == .folder(folderID))
        #expect(rows.last?.id == .script("script-1"))
    }

    @Test("Display rows preserve root order and hide collapsed folder children")
    func displayRowsPreserveRootOrderAndCollapsedState() {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        let folderID = folderStore.createFolder(name: "Auth")
        folderStore.addScript("script-child", toFolder: folderID)
        folderStore.reconcile(with: ["script-root", "script-child"])

        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        vm.plugins = [
            PluginInfoSnapshot(
                id: "script-root",
                name: "Root Script",
                isEnabled: true,
                method: nil,
                urlPattern: nil,
                statusText: "Active"
            ),
            PluginInfoSnapshot(
                id: "script-child",
                name: "Child Script",
                isEnabled: true,
                method: "GET",
                urlPattern: "/auth",
                statusText: "Active"
            ),
        ]

        #expect(vm.displayRows.map(\.id) == [.folder(folderID), .script("script-child"), .script("script-root")])
        #expect(vm.displayRows.first(where: { $0.id == .script("script-child") })?.indent == 1)
        #expect(vm.displayRows.first(where: { $0.id == .script("script-root") })?.indent == 0)

        folderStore.setExpanded(folderID: folderID, expanded: false)

        #expect(vm.displayRows.map(\.id) == [.folder(folderID), .script("script-root")])
    }

    @Test("deleteSelection removes selected script and clears selection")
    func deleteSelectionRemovesScriptAndClearsSelection() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let folderStore = ScriptFolderStore(defaults: env.defaults)
        let pluginID = "script.delete.\(UUID().uuidString)"
        try makeScriptPlugin(
            id: pluginID,
            name: "Delete Me",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: true
        )
        await env.manager.loadAllPlugins()

        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        await vm.refresh()
        vm.selectedRowID = .script(pluginID)

        await vm.deleteSelection()

        #expect(vm.selectedRowID == nil)
        #expect(vm.plugins.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: env.pluginsDir.appendingPathComponent(pluginID).path))
    }

    @Test("deleteSelection removes selected folder but preserves its scripts")
    func deleteSelectionRemovesFolderAndPreservesChildren() async {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        let folderID = folderStore.createFolder(name: "Auth")
        folderStore.addScript("script-1", toFolder: folderID)
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        vm.plugins = [
            PluginInfoSnapshot(
                id: "script-1",
                name: "Token",
                isEnabled: true,
                method: "GET",
                urlPattern: "/token",
                statusText: "Active"
            ),
        ]
        vm.selectedRowID = .folder(folderID)

        await vm.deleteSelection()

        #expect(vm.selectedRowID == nil)
        #expect(folderStore.index.folders.isEmpty)
        #expect(folderStore.index.rootOrder == [.script("script-1")])
        #expect(vm.plugins.count == 1)
    }

    @Test("open editor actions publish edit intent only for script selections")
    func openEditorActionsPublishScriptIntent() {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        let folderID = folderStore.createFolder(name: "Auth")
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        _ = ScriptEditorSession.shared.consumePending()

        vm.selectedRowID = .folder(folderID)
        vm.openEditorForSelection()
        #expect(ScriptEditorSession.shared.consumePending() == nil)

        vm.selectedRowID = .script("script-1")
        vm.openEditorForSelection()
        #expect(ScriptEditorSession.shared.consumePending() == .edit(pluginID: "script-1"))

        vm.openEditor(for: "script-2")
        #expect(ScriptEditorSession.shared.consumePending() == .edit(pluginID: "script-2"))
    }

    @Test("createNewScript writes default files selects the script and opens editor intent")
    func createNewScriptCreatesFilesSelectionAndEditorIntent() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let folderStore = ScriptFolderStore(defaults: env.defaults)
        let vm = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: folderStore,
            pluginsDirectory: env.pluginsDir
        )
        _ = ScriptEditorSession.shared.consumePending()

        let pluginID = await vm.createNewScript()

        guard let pluginID else {
            Issue.record("Expected createNewScript to return a plugin id")
            return
        }
        let pluginDir = env.pluginsDir.appendingPathComponent(pluginID, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: pluginDir.appendingPathComponent("plugin.json").path))
        #expect(FileManager.default.fileExists(atPath: pluginDir.appendingPathComponent("index.js").path))
        #expect(vm.selectedRowID == .script(pluginID))
        #expect(vm.plugins.map(\.id) == [pluginID])
        #expect(ScriptEditorSession.shared.consumePending() == .edit(pluginID: pluginID))

        let manifest = try JSONDecoder().decode(
            PluginManifest.self,
            from: Data(contentsOf: pluginDir.appendingPathComponent("plugin.json"))
        )
        let source = try String(contentsOf: pluginDir.appendingPathComponent("index.js"), encoding: .utf8)
        #expect(manifest.id == pluginID)
        #expect(manifest.name == "Untitled Script 1")
        #expect(manifest.scriptBehavior == ScriptBehavior.defaults())
        #expect(source == ScriptTemplates.defaultSource)
    }

    @Test("duplicateSelection copies source script manifest and selects the copy")
    func duplicateSelectionCopiesManifestAndSource() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let folderStore = ScriptFolderStore(defaults: env.defaults)
        let source = "async function onRequest(context, url, request) { return request; }"
        let originalID = "script.duplicate.\(UUID().uuidString)"
        try makeScriptPlugin(
            id: originalID,
            name: "Original Script",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: true,
            method: "PATCH",
            urlPattern: "/v1/items",
            runOnRequest: true,
            runOnResponse: false,
            runAsMock: true,
            source: source
        )
        await env.manager.loadAllPlugins()

        let vm = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: folderStore,
            pluginsDirectory: env.pluginsDir
        )
        await vm.refresh()
        vm.selectedRowID = .script(originalID)

        await vm.duplicateSelection()

        guard case let .script(copyID) = vm.selectedRowID else {
            Issue.record("Expected duplicateSelection to select the copied script")
            return
        }
        #expect(copyID != originalID)
        #expect(Set(vm.plugins.map(\.id)) == Set([originalID, copyID]))

        let copyDir = env.pluginsDir.appendingPathComponent(copyID, isDirectory: true)
        let manifest = try JSONDecoder().decode(
            PluginManifest.self,
            from: Data(contentsOf: copyDir.appendingPathComponent("plugin.json"))
        )
        let copiedSource = try String(contentsOf: copyDir.appendingPathComponent("index.js"), encoding: .utf8)
        #expect(manifest.id == copyID)
        #expect(manifest.name == "Original Script (Copy)")
        #expect(manifest.scriptBehavior?.matchCondition?.method == "PATCH")
        #expect(manifest.scriptBehavior?.matchCondition?.urlPattern == "/v1/items")
        #expect(manifest.scriptBehavior?.runOnResponse == false)
        #expect(manifest.scriptBehavior?.runAsMock == true)
        #expect(copiedSource == source)
    }

    @Test("folder actions create rename cancel toggle and begin rename selected folder")
    func folderActionsCreateRenameCancelToggleAndBeginRename() {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)

        vm.createNewFolder()

        guard case let .folder(folderID) = vm.selectedRowID else {
            Issue.record("Expected createNewFolder to select the new folder")
            return
        }
        #expect(vm.renamingFolderID == folderID)
        #expect(vm.renamingFolderText == "Untitled")

        vm.renamingFolderText = "  Auth Scripts  "
        vm.commitFolderRename()

        #expect(vm.renamingFolderID == nil)
        #expect(vm.renamingFolderText.isEmpty)
        #expect(folderStore.index.folders.first(where: { $0.id == folderID })?.name == "Auth Scripts")

        vm.toggleFolder(id: folderID)
        #expect(folderStore.index.folders.first(where: { $0.id == folderID })?.expanded == false)
        vm.toggleFolder(id: folderID)
        #expect(folderStore.index.folders.first(where: { $0.id == folderID })?.expanded == true)

        vm.beginRenameSelectedFolder()
        #expect(vm.renamingFolderID == folderID)
        #expect(vm.renamingFolderText == "Auth Scripts")
        vm.cancelFolderRename()
        #expect(vm.renamingFolderID == nil)
        #expect(vm.renamingFolderText.isEmpty)
    }

    @Test("folder child toggle enables and disables only requested scripts")
    func setScriptsEnabledTogglesOnlyRequestedScripts() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let folderStore = ScriptFolderStore(defaults: env.defaults)
        let firstID = "script.toggle.first.\(UUID().uuidString)"
        let secondID = "script.toggle.second.\(UUID().uuidString)"
        try makeScriptPlugin(id: firstID, name: "First", in: env.pluginsDir, defaults: env.defaults, enabled: false)
        try makeScriptPlugin(id: secondID, name: "Second", in: env.pluginsDir, defaults: env.defaults, enabled: false)
        await env.manager.loadAllPlugins()

        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        await vm.refresh()

        await vm.setScriptsEnabled(ids: [firstID], enabled: true)
        var snapshots = await env.manager.plugins
        #expect(snapshots.first(where: { $0.id == firstID })?.isEnabled == true)
        #expect(snapshots.first(where: { $0.id == secondID })?.isEnabled == false)

        await vm.setScriptsEnabled(ids: [firstID, secondID], enabled: false)
        snapshots = await env.manager.plugins
        #expect(snapshots.first(where: { $0.id == firstID })?.isEnabled == false)
        #expect(snapshots.first(where: { $0.id == secondID })?.isEnabled == false)
    }

    @Test("toggleScript flips the clicked script enabled state")
    func toggleScriptFlipsEnabledState() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let folderStore = ScriptFolderStore(defaults: env.defaults)
        let pluginID = "script.toggle.clicked.\(UUID().uuidString)"
        try makeScriptPlugin(id: pluginID, name: "Clicked", in: env.pluginsDir, defaults: env.defaults, enabled: false)
        await env.manager.loadAllPlugins()

        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        await vm.refresh()

        await vm.toggleScript(id: pluginID)
        var snapshots = await env.manager.plugins
        #expect(snapshots.first(where: { $0.id == pluginID })?.isEnabled == true)

        await vm.toggleScript(id: pluginID)
        snapshots = await env.manager.plugins
        #expect(snapshots.first(where: { $0.id == pluginID })?.isEnabled == false)
    }

    @Test("Scripting advanced toggles persist through AppSettingsStorage")
    func advancedTogglesPersist() async {
        await RuleTestLock.shared.acquire()
        let original = AppSettingsStorage.load()
        var reset = original
        reset.scriptingToolEnabled = true
        reset.allowSystemEnvVars = false
        reset.allowMultipleScriptsPerRequest = false
        AppSettingsStorage.save(reset)

        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: ScriptFolderStore(defaults: env.defaults)
        )

        vm.setToolEnabled(false)
        vm.setAdvanceAllowSystemEnvVars(true)
        vm.setAdvanceAllowChaining(true)

        let persisted = AppSettingsStorage.load()
        #expect(persisted.scriptingToolEnabled == false)
        #expect(persisted.allowSystemEnvVars == true)
        #expect(persisted.allowMultipleScriptsPerRequest == true)

        AppSettingsStorage.save(original)
        await RuleTestLock.shared.release()
    }

    @Test("Script editor session increments even for same plugin intent")
    func editorSessionReopeningSamePluginAdvancesVersion() {
        _ = ScriptEditorSession.shared.consumePending()
        let before = ScriptEditorSession.shared.contextVersion

        ScriptEditorSession.shared.setPending(.edit(pluginID: "script-1"))
        let firstVersion = ScriptEditorSession.shared.contextVersion
        let firstIntent = ScriptEditorSession.shared.consumePending()
        ScriptEditorSession.shared.setPending(.edit(pluginID: "script-1"))
        let secondVersion = ScriptEditorSession.shared.contextVersion
        let secondIntent = ScriptEditorSession.shared.consumePending()

        #expect(firstVersion == before &+ 1)
        #expect(secondVersion == firstVersion &+ 1)
        #expect(firstIntent == .edit(pluginID: "script-1"))
        #expect(secondIntent == .edit(pluginID: "script-1"))
    }

    @Test("ScriptEditorViewModel loads persisted manifest, behavior, and source")
    func editorLoadsExistingScriptFields() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "script.load.\(UUID().uuidString)"
        let source = "async function onRequest(context, url, request) { return request; }"
        try makeScriptPlugin(
            id: pluginID,
            name: "Loaded Script",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: true,
            method: "POST",
            urlPattern: #"https:\/\/api\.example\.com\/v1\/.*"#,
            runOnRequest: false,
            runOnResponse: true,
            runAsMock: true,
            source: source
        )
        await env.manager.loadAllPlugins()

        let vm = ScriptEditorViewModel(
            pluginManager: env.manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: env.pluginsDir
        )
        await vm.load(intent: .edit(pluginID: pluginID))

        #expect(vm.name == "Loaded Script")
        #expect(vm.urlPattern == #"https:\/\/api\.example\.com\/v1\/.*"#)
        #expect(vm.method == .post)
        #expect(vm.runOnRequest == false)
        #expect(vm.runOnResponse == true)
        #expect(vm.runAsMock == true)
        #expect(vm.code == source)
    }

    @Test("testRule handles matches misses and invalid regex")
    func testRulePreviewCases() {
        let vm = ScriptEditorViewModel()
        vm.urlPattern = "https://api.example.com/v1/*"
        vm.patternMode = .wildcard
        #expect(vm.testRule(against: "https://api.example.com/v1/users"))
        #expect(!vm.testRule(against: "https://api.example.com/v2/users"))

        vm.patternMode = .regex
        vm.urlPattern = "["
        #expect(!vm.testRule(against: "https://api.example.com/v1/users"))

        vm.patternMode = .advanced
        vm.urlPattern = #"api\.example\.com/v1/.+"#
        #expect(vm.testRule(against: "https://api.example.com/v1/users"))
    }

    @Test("Save & Activate persists matching rule run options and source")
    func saveAndActivatePersistsEditorFields() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "script.persist.\(UUID().uuidString)"
        try makeScriptPlugin(
            id: pluginID,
            name: "Before",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: false
        )
        await env.manager.loadAllPlugins()

        let vm = ScriptEditorViewModel(
            pluginManager: env.manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: env.pluginsDir
        )
        await vm.load(intent: .edit(pluginID: pluginID))
        let updatedSource = "async function onResponse(context, url, request, response) { return response; }"
        vm.name = "Persisted Script"
        vm.urlPattern = "https://api.example.com/v1/*"
        vm.includeSubpaths = true
        vm.patternMode = .wildcard
        vm.method = .post
        vm.runOnRequest = false
        vm.runOnResponse = true
        vm.runAsMock = true
        vm.code = updatedSource

        await vm.saveAndActivate()

        let pluginDir = env.pluginsDir.appendingPathComponent(pluginID, isDirectory: true)
        let manifest = try JSONDecoder().decode(
            PluginManifest.self,
            from: Data(contentsOf: pluginDir.appendingPathComponent("plugin.json"))
        )
        let source = try String(contentsOf: pluginDir.appendingPathComponent("index.js"), encoding: .utf8)
        #expect(manifest.name == "Persisted Script")
        #expect(manifest.scriptBehavior?.matchCondition?.method == "POST")
        #expect(manifest.scriptBehavior?.matchCondition?.urlPattern == #"https://api\.example\.com/v1/.*"#)
        #expect(manifest.scriptBehavior?.runOnRequest == false)
        #expect(manifest.scriptBehavior?.runOnResponse == true)
        #expect(manifest.scriptBehavior?.runAsMock == true)
        #expect(source == updatedSource)
    }

    @Test("Script editor footer actions update code console visibility and shared state")
    func editorFooterActionsUpdateCodeConsoleAndSharedState() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "script.footer.\(UUID().uuidString)"
        try makeScriptPlugin(
            id: pluginID,
            name: "Footer Script",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: true
        )
        await env.manager.loadAllPlugins()

        let vm = ScriptEditorViewModel(
            pluginManager: env.manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: env.pluginsDir
        )
        await vm.load(intent: .edit(pluginID: pluginID))
        vm.code = """
        function run() {
        console.log("ok");
        }
        """

        vm.beautify()
        #expect(vm.code.contains(#"  console.log("ok");"#))
        #expect(vm.consoleEntries.contains { $0.level == .system && $0.message.contains("beautified") })

        vm.insertSnippet("// request.headers[\"X-Debug\"] = \"1\";")
        #expect(vm.code.hasSuffix("// request.headers[\"X-Debug\"] = \"1\";"))

        #expect(vm.consolePanelVisible == true)
        vm.toggleConsolePanel()
        #expect(vm.consolePanelVisible == false)
        vm.toggleConsolePanel()
        #expect(vm.consolePanelVisible == true)

        let storageKey = RockxyIdentity.current.pluginStoragePrefix(pluginID: pluginID) + "token"
        UserDefaults.standard.set("cached", forKey: storageKey)
        defer { UserDefaults.standard.removeObject(forKey: storageKey) }
        vm.resetSharedState()
        #expect(UserDefaults.standard.string(forKey: storageKey) == nil)
        #expect(vm.consoleEntries.contains { $0.message == "Shared state cleared." })

        vm.clearConsole()
        #expect(vm.consoleEntries.isEmpty)
    }

    @Test("Save & Activate enables a freshly-created script and reports active")
    func saveAndActivateEnablesNewScript() async throws {
        // Isolated plugin environment.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "ScriptingViewModelTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Failed to create isolated UserDefaults suite: \(suite)")
            return
        }
        let discovery = PluginDiscovery(pluginsDirectory: dir, defaults: defaults)
        let manager = ScriptPluginManager(discovery: discovery, defaults: defaults)

        // Hand-create a disabled plugin on disk with the default template.
        let pluginID = "test.save-and-activate.\(UUID().uuidString.prefix(6))"
        let pluginDir = dir.appendingPathComponent(pluginID, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: pluginID,
            name: "Untitled Script",
            version: "1.0.0",
            author: PluginAuthor(name: "User", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "index.js"],
            capabilities: [],
            scriptBehavior: ScriptBehavior.defaults()
        )
        try JSONEncoder().encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"))
        try ScriptTemplates.defaultSource.write(
            to: pluginDir.appendingPathComponent("index.js"),
            atomically: true,
            encoding: .utf8
        )
        // Plugin starts disabled (no key set).
        await manager.loadAllPlugins()
        let preSnap = await manager.plugins.first(where: { $0.id == pluginID })
        #expect(preSnap?.isEnabled == false, "plugin should start disabled")

        // Editor VM saves & activates with an isolated policy gate so this test
        // doesn't share quota state with concurrent suites.
        let vm = ScriptEditorViewModel(
            pluginManager: manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: dir
        )
        await vm.load(intent: .edit(pluginID: pluginID))
        await vm.saveAndActivate()

        let postSnap = await manager.plugins.first(where: { $0.id == pluginID })
        #expect(
            postSnap?.isEnabled == true,
            "Save & Activate should enable the plugin (status: \(String(describing: postSnap?.status)), msg: \(vm.statusMessage))"
        )
        #expect(
            postSnap?.status == .active,
            "plugin should be active after save (status: \(String(describing: postSnap?.status)))"
        )
        #expect(
            vm.savedAndActive == true,
            "VM must report savedAndActive=true when actually active (msg: \(vm.statusMessage))"
        )
    }

    // MARK: - Helpers

    @discardableResult
    private func makeScriptPlugin(
        id: String,
        name: String,
        in pluginsDir: URL,
        defaults: UserDefaults,
        enabled: Bool,
        method: String? = nil,
        urlPattern: String? = nil,
        runOnRequest: Bool = true,
        runOnResponse: Bool = true,
        runAsMock: Bool = false,
        source: String = ScriptTemplates.defaultSource
    )
        throws -> URL
    {
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        let pluginDir = pluginsDir.appendingPathComponent(id, isDirectory: true)
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
            configuration: nil,
            minRockxyVersion: nil,
            homepage: nil,
            license: nil,
            scriptBehavior: ScriptBehavior(
                matchCondition: RuleMatchCondition(urlPattern: urlPattern, method: method),
                runOnRequest: runOnRequest,
                runOnResponse: runOnResponse,
                runAsMock: runAsMock
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"))
        try source.write(to: pluginDir.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)

        let key = RockxyIdentity.current.pluginEnabledKey(pluginID: id)
        if enabled {
            defaults.set(true, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }

        return pluginDir
    }
}
