import AppKit
import Foundation
@testable import Rockxy
import Testing

// Regression tests for the scripting viewmodels: default template text, editor
// view model state, and list view model construction.

@MainActor
@Suite(.serialized)
struct ScriptingViewModelTests {
    // MARK: Internal

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
        #expect(pattern == RulePatternBuilder.regexSource(
            rawPattern: "api.example.com/v1/*",
            matchType: .wildcard,
            includeSubpaths: false
        ))
        let sub = ScriptEditorViewModel.wildcardToRegex("api.example.com/v1/*", includeSubpaths: true)
        #expect(sub == RulePatternBuilder.regexSource(
            rawPattern: "api.example.com/v1/*",
            matchType: .wildcard,
            includeSubpaths: true
        ))
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

    @Test("Script code highlighting uses supplied editor font size")
    func scriptCodeHighlightingUsesEditorFontSize() throws {
        let settings = InspectorTextEditorSettings(fontSize: 20, tabWidth: 4, useMonospacedFont: true)
        let highlighted = ScriptCodeHighlighting.highlightedString(
            "const value = 1",
            spans: [],
            editorSettings: settings
        )
        let font = try #require(highlighted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(font.pointSize == 20)
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
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

    @Test("Runtime status mapping is typed for every plugin state")
    func runtimeStatusMappingCoversEveryPluginState() {
        #expect(ScriptListRuntimeStatus(.active) == .active)
        #expect(ScriptListRuntimeStatus(.disabled) == .disabled)
        #expect(ScriptListRuntimeStatus(.loading) == .loading)
        #expect(ScriptListRuntimeStatus(.error("boom")) == .error)
        #expect(ScriptListRuntimeStatus(.error("boom")).title == "Error")
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
                runtimeStatus: .active
            ),
            PluginInfoSnapshot(
                id: "script-post",
                name: "Post Script",
                isEnabled: true,
                method: "POST",
                urlPattern: nil,
                runtimeStatus: .active
            ),
        ]
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
                runtimeStatus: .active
            )
        ]
        vm.filterText = "token"
        vm.filterColumn = .name

        let rows = vm.filteredDisplayRows
        #expect(rows.count == 2)
        #expect(rows.first?.id == .folder(folderID))
        #expect(rows.last?.id == .script("script-1"))
    }

    @Test("Whitespace-only search preserves the unfiltered rows")
    func whitespaceSearchPreservesRows() {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        folderStore.reconcile(with: ["script-1"])
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        vm.plugins = [
            PluginInfoSnapshot(
                id: "script-1",
                name: "Auth Script",
                isEnabled: true,
                method: "GET",
                urlPattern: "/auth",
                runtimeStatus: .active
            ),
        ]

        vm.filterText = "   \n"

        #expect(vm.filteredDisplayRows.map(\.id) == [.script("script-1")])
    }

    @Test("Creating a folder clears search so inline rename stays visible")
    func createFolderClearsSearch() {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        vm.filterText = "does-not-match"
        vm.filterColumn = .method

        vm.createNewFolder()

        #expect(vm.filterText.isEmpty)
        #expect(vm.filterColumn == .name)
        #expect(vm.filteredDisplayRows.contains { $0.id == vm.selectedRowID })
    }

    @Test("Renaming a folder reconciles selection against the active name filter")
    func renameFolderClearsHiddenSelection() {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        let folderID = folderStore.createFolder(name: "Auth")
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        vm.filterColumn = .name
        vm.filterText = "Auth"
        vm.selectedRowID = .folder(folderID)
        vm.beginRenameSelectedFolder()
        vm.renamingFolderText = "Other"

        vm.commitFolderRename()

        #expect(vm.filteredDisplayRows.isEmpty)
        #expect(vm.selectedRowID == nil)
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
                runtimeStatus: .active
            ),
            PluginInfoSnapshot(
                id: "script-child",
                name: "Child Script",
                isEnabled: true,
                method: "GET",
                urlPattern: "/auth",
                runtimeStatus: .active
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
                runtimeStatus: .active
            ),
        ]
        vm.selectedRowID = .folder(folderID)

        await vm.deleteSelection()

        #expect(vm.selectedRowID == nil)
        #expect(folderStore.index.folders.isEmpty)
        #expect(folderStore.index.rootOrder == [.script("script-1")])
        #expect(vm.plugins.count == 1)
    }

    @Test("refresh clears a script selection removed by another surface")
    func refreshClearsMissingSelection() async {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: ScriptFolderStore(defaults: env.defaults)
        )
        vm.plugins = [
            PluginInfoSnapshot(
                id: "removed-script",
                name: "Removed Script",
                isEnabled: true,
                method: nil,
                urlPattern: nil,
                runtimeStatus: .active
            ),
        ]
        vm.selectedRowID = .script("removed-script")

        await vm.refresh()

        #expect(vm.plugins.isEmpty)
        #expect(vm.selectedRowID == nil)
    }

    @Test("refresh clears a selected script hidden by the active filter")
    func refreshClearsFilteredSelection() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "script.filtered.\(UUID().uuidString)"
        try makeScriptPlugin(
            id: pluginID,
            name: "Visible Script",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: false
        )
        await env.manager.loadAllPlugins()

        let vm = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: ScriptFolderStore(defaults: env.defaults)
        )
        await vm.refresh()
        vm.selectedRowID = .script(pluginID)
        vm.filterText = "does-not-match"

        await vm.refresh()

        #expect(vm.plugins.map(\.id) == [pluginID])
        #expect(vm.filteredDisplayRows.isEmpty)
        #expect(vm.selectedRowID == nil)
    }

    @Test("collapsing a folder clears its hidden child selection")
    func collapsingFolderClearsChildSelection() {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = ScriptFolderStore(defaults: defaults)
        let folderID = folderStore.createFolder(name: "Auth")
        folderStore.addScript("script-child", toFolder: folderID)
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(pluginManager: env.manager, folderStore: folderStore)
        vm.plugins = [
            PluginInfoSnapshot(
                id: "script-child",
                name: "Child",
                isEnabled: false,
                method: nil,
                urlPattern: nil,
                runtimeStatus: .disabled
            ),
        ]
        vm.selectedRowID = .script("script-child")

        vm.toggleFolder(id: folderID)

        #expect(folderStore.index.folders.first(where: { $0.id == folderID })?.expanded == false)
        #expect(vm.selectedRowID == nil)
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

    @Test("Creating from a template writes its name, source, and mock behavior")
    func createNewScriptFromTemplate() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: ScriptFolderStore(defaults: env.defaults),
            pluginsDirectory: env.pluginsDir
        )
        _ = ScriptEditorSession.shared.consumePending()

        let pluginID = try #require(await vm.createNewScript(from: .conditionalMockJSON))
        _ = ScriptEditorSession.shared.consumePending()

        let pluginDir = env.pluginsDir.appendingPathComponent(pluginID, isDirectory: true)
        let manifest = try JSONDecoder().decode(
            PluginManifest.self,
            from: Data(contentsOf: pluginDir.appendingPathComponent("plugin.json"))
        )
        let source = try String(contentsOf: pluginDir.appendingPathComponent("index.js"), encoding: .utf8)
        #expect(manifest.name == ScriptStarterTemplate.conditionalMockJSON.title)
        #expect(manifest.scriptBehavior == ScriptStarterTemplate.conditionalMockJSON.behavior)
        #expect(manifest.scriptBehavior?.runAsMock == true)
        #expect(source == ScriptStarterTemplate.conditionalMockJSON.source)
    }

    @Test("createNewScript clears search so its selected row stays visible")
    func createNewScriptClearsActiveSearch() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: ScriptFolderStore(defaults: env.defaults),
            pluginsDirectory: env.pluginsDir
        )
        vm.filterText = "does-not-match"
        vm.filterColumn = .urlPattern

        let createdID = try #require(await vm.createNewScript())

        #expect(vm.filterText.isEmpty)
        #expect(vm.filterColumn == .name)
        #expect(vm.selectedRowID == .script(createdID))
        #expect(vm.filteredDisplayRows.contains { $0.id == .script(createdID) })
    }

    @Test("Concurrent create requests are gated to one coherent discovery result")
    func concurrentCreateRequestsAreGated() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let vm = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: ScriptFolderStore(defaults: env.defaults),
            pluginsDirectory: env.pluginsDir
        )

        async let first = vm.createNewScript()
        async let second = vm.createNewScript()
        let (firstResult, secondResult) = await (first, second)
        let results = [firstResult, secondResult].compactMap(\.self)

        #expect(results.count == 1)
        #expect(vm.plugins.map(\.id) == results)
        #expect(await env.manager.plugins.map(\.id) == results)
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

    @Test("duplicateSelection surfaces an operation error when the source bundle is missing")
    func duplicateSelectionSurfacesOperationError() async {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let folderStore = ScriptFolderStore(defaults: env.defaults)
        let vm = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: folderStore,
            pluginsDirectory: env.pluginsDir
        )
        let missingID = "script.missing.\(UUID().uuidString)"
        vm.plugins = [
            PluginInfoSnapshot(
                id: missingID,
                name: "Ghost",
                isEnabled: false,
                method: nil,
                urlPattern: nil,
                runtimeStatus: .disabled
            ),
        ]
        vm.selectedRowID = .script(missingID)
        #expect(vm.operationError == nil)

        await vm.duplicateSelection()

        // Copying a bundle that does not exist on disk fails and is surfaced to
        // the user via `operationError`; selection and plugin list are untouched.
        #expect(vm.operationError != nil)
        #expect(vm.selectedRowID == .script(missingID))
        #expect(vm.plugins.map(\.id) == [missingID])
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

    @Test("Reload marks a missing script bundle as errored instead of leaving a false active state")
    func reloadMissingBundleMarksRuntimeError() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "script.reload.missing.\(UUID().uuidString)"
        let bundle = try makeScriptPlugin(
            id: pluginID,
            name: "Missing During Reload",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: true
        )
        await env.manager.loadAllPlugins()
        #expect(await env.manager.plugins.first(where: { $0.id == pluginID })?.status == .active)
        try FileManager.default.removeItem(at: bundle)

        do {
            try await env.manager.reloadPlugin(id: pluginID)
            Issue.record("Expected reload to fail when the bundle disappeared")
        } catch {
            #expect(error is ScriptPluginError)
        }

        let snapshot = await env.manager.plugins.first(where: { $0.id == pluginID })
        guard case .error = snapshot?.status else {
            Issue.record("Expected the missing bundle to leave an explicit runtime error")
            return
        }
        #expect(snapshot?.lastError != nil)
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
            urlPattern: "https://api.example.com/v1/*",
            matchType: .wildcard,
            includeSubpaths: true,
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
        #expect(vm.urlPattern == "https://api.example.com/v1/*")
        #expect(vm.patternMode == .wildcard)
        #expect(vm.includeSubpaths == true)
        #expect(vm.method == .post)
        #expect(vm.runOnRequest == false)
        #expect(vm.runOnResponse == true)
        #expect(vm.runAsMock == true)
        #expect(vm.code == source)
    }

    @Test("List duplicate and editor handoff honor an imported bundle path")
    func importedBundlePathSupportsDuplicateAndEditorLoad() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "script.imported.\(UUID().uuidString)"
        let source = "async function onRequest(context, url, request) { return request; }"
        let originalDirectory = try makeScriptPlugin(
            id: pluginID,
            name: "Imported Script",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: false,
            source: source
        )
        let importedDirectory = env.pluginsDir.appendingPathComponent("user-folder-name", isDirectory: true)
        try FileManager.default.moveItem(at: originalDirectory, to: importedDirectory)
        await env.manager.loadAllPlugins()

        let editor = ScriptEditorViewModel(
            pluginManager: env.manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: env.pluginsDir
        )
        await editor.load(intent: .edit(pluginID: pluginID))
        #expect(editor.name == "Imported Script")
        #expect(editor.code == source)

        let list = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: ScriptFolderStore(defaults: env.defaults),
            pluginsDirectory: env.pluginsDir
        )
        await list.refresh()
        list.selectedRowID = .script(pluginID)
        await list.duplicateSelection()

        #expect(list.operationError == nil)
        #expect(list.plugins.count == 2)
    }

    @Test("testRule handles matches misses and invalid regex")
    func testRulePreviewCases() {
        let vm = ScriptEditorViewModel()
        vm.urlPattern = "https://api.example.com/v1/*"
        vm.patternMode = .wildcard
        #expect(vm.testRule(against: "https://api.example.com/v1/users"))
        #expect(!vm.testRule(against: "https://api.example.com/v2/users"))

        vm.urlPattern = "127.0.0.1:43210/rockxy-demo/pricing-experiment"
        #expect(vm.testRule(against: "http://127.0.0.1:43210/rockxy-demo/pricing-experiment"))

        vm.patternMode = .regex
        vm.urlPattern = "["
        #expect(!vm.testRule(against: "https://api.example.com/v1/users"))

        vm.patternMode = .advanced
        vm.urlPattern = #"api\.example\.com/v1/.+"#
        #expect(vm.testRule(against: "https://api.example.com/v1/users"))
    }

    @Test("Validate updates status tone for valid and invalid scripts")
    func validateUpdatesStatusTone() {
        let vm = ScriptEditorViewModel()
        vm.runOnRequest = false
        vm.runOnResponse = true
        vm.code = """
        function onResponse(response) {
          if (response.request.headers["X-Rockxy-Scenario-Id"] !== "scripted-mock") {
            return response;
          }
          response.headers["Content-Type"] = "application/json";
          return response;
        }
        """

        vm.validateScript()

        #expect(vm.statusTone == .success)
        #expect(vm.statusMessage == "Script is valid")

        vm.code = "function onResponse(response) {"
        vm.validateScript()

        #expect(vm.statusTone == .error)
        #expect(vm.statusMessage == "Validation failed")
        #expect(vm.consoleEntries.contains { $0.level == .errors && $0.message.contains("Validation failed") })
    }

    @Test("Script editor unwraps previously generated wildcard regex for display")
    func legacyGeneratedWildcardLoadsAsRawUserPattern() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let pluginID = "script.legacy-pattern.\(UUID().uuidString)"
        try makeScriptPlugin(
            id: pluginID,
            name: "Legacy Pattern",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: true,
            urlPattern: #"127\.0\.0\.1:43210\/rockxy-demo\/pricing-experiment($|[?#])"#
        )
        await env.manager.loadAllPlugins()

        let vm = ScriptEditorViewModel(
            pluginManager: env.manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: env.pluginsDir
        )
        await vm.load(intent: .edit(pluginID: pluginID))

        #expect(vm.urlPattern == "127.0.0.1:43210/rockxy-demo/pricing-experiment")
        #expect(vm.patternMode == .wildcard)
        #expect(vm.includeSubpaths == false)
        #expect(vm.testRule(against: "http://127.0.0.1:43210/rockxy-demo/pricing-experiment"))
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
        // A valid Mock configuration: mock scripts must run on Request (and not
        // Response), and the source must define the onRequest hook.
        let updatedSource = "async function onRequest(context, url, request) { return request; }"
        vm.name = "Persisted Script"
        vm.urlPattern = "https://api.example.com/v1/*"
        vm.includeSubpaths = true
        vm.patternMode = .wildcard
        vm.method = .post
        vm.runOnRequest = true
        vm.runOnResponse = false
        vm.runAsMock = true
        vm.code = updatedSource

        let saved = await vm.saveAndActivate()
        #expect(saved)

        let pluginDir = env.pluginsDir.appendingPathComponent(pluginID, isDirectory: true)
        let manifest = try JSONDecoder().decode(
            PluginManifest.self,
            from: Data(contentsOf: pluginDir.appendingPathComponent("plugin.json"))
        )
        let source = try String(contentsOf: pluginDir.appendingPathComponent("index.js"), encoding: .utf8)
        #expect(manifest.name == "Persisted Script")
        #expect(manifest.scriptBehavior?.matchCondition?.method == "POST")
        #expect(manifest.scriptBehavior?.matchCondition?.urlPattern == "https://api.example.com/v1/*")
        #expect(manifest.scriptBehavior?.matchCondition?.matchType == .wildcard)
        #expect(manifest.scriptBehavior?.matchCondition?.includeSubpaths == true)
        #expect(manifest.scriptBehavior?.runOnRequest == true)
        #expect(manifest.scriptBehavior?.runOnResponse == false)
        #expect(manifest.scriptBehavior?.runAsMock == true)
        #expect(source == updatedSource)

        let postSnap = await env.manager.plugins.first(where: { $0.id == pluginID })
        #expect(postSnap?.manifest.name == "Persisted Script")
        #expect(postSnap?.manifest.scriptBehavior?.matchCondition?.urlPattern == "https://api.example.com/v1/*")
        #expect(postSnap?.manifest.scriptBehavior?.matchCondition?.matchType == .wildcard)
    }

    @Test("Save & Activate updates scripting list matching rule snapshot")
    func saveAndActivateUpdatesListMatchingRuleSnapshot() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let folderStore = ScriptFolderStore(defaults: env.defaults)
        let pluginID = "script.list-refresh.\(UUID().uuidString)"
        try makeScriptPlugin(
            id: pluginID,
            name: "List Refresh",
            in: env.pluginsDir,
            defaults: env.defaults,
            enabled: false
        )
        await env.manager.loadAllPlugins()

        let listVM = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: folderStore,
            pluginsDirectory: env.pluginsDir
        )
        await listVM.refresh()
        #expect(listVM.plugins.first(where: { $0.id == pluginID })?.urlPattern == nil)

        let editorVM = ScriptEditorViewModel(
            pluginManager: env.manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: env.pluginsDir
        )
        await editorVM.load(intent: .edit(pluginID: pluginID))
        editorVM.urlPattern = "127.0.0.1:43210/rockxy-demo/pricing-experiment"
        editorVM.patternMode = .wildcard

        await editorVM.saveAndActivate()
        await listVM.refresh()

        let updated = listVM.plugins.first(where: { $0.id == pluginID })
        #expect(updated?.urlPattern == "127.0.0.1:43210/rockxy-demo/pricing-experiment")
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

    // MARK: Private

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
        matchType: RuleMatchType? = nil,
        includeSubpaths: Bool? = nil,
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
                matchCondition: RuleMatchCondition(
                    urlPattern: urlPattern,
                    method: method,
                    matchType: matchType,
                    includeSubpaths: includeSubpaths
                ),
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
