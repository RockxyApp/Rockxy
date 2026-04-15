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
}
