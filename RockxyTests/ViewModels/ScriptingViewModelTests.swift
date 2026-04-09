import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ScriptingViewModel` in the view models layer.

@MainActor
struct ScriptingViewModelTests {
    @Test("Script templates dictionary has exactly six entries")
    func scriptTemplatesHasSixEntries() {
        #expect(ScriptingViewModel.scriptTemplates.count == 6)
    }

    @Test("Script templates contains Modify Headers with onRequest")
    func scriptTemplatesContainsModifyHeaders() throws {
        let template = ScriptingViewModel.scriptTemplates["Modify Headers"]
        #expect(template != nil)
        #expect(try #require(template?.contains("onRequest")))
    }

    @Test("Script templates contains Log Requests")
    func scriptTemplatesContainsLogRequests() {
        #expect(ScriptingViewModel.scriptTemplates["Log Requests"] != nil)
    }

    @Test("Script templates contains Block Pattern with analytics")
    func scriptTemplatesContainsBlockPattern() throws {
        let template = ScriptingViewModel.scriptTemplates["Block Pattern"]
        #expect(template != nil)
        #expect(try #require(template?.contains("analytics")))
    }

    @Test("Script templates contains Custom Response with statusCode")
    func scriptTemplatesContainsCustomResponse() throws {
        let template = ScriptingViewModel.scriptTemplates["Custom Response"]
        #expect(template != nil)
        #expect(try #require(template?.contains("statusCode")))
    }

    @Test("Script templates contains Rewrite URL")
    func scriptTemplatesContainsRewriteURL() {
        #expect(ScriptingViewModel.scriptTemplates["Rewrite URL"] != nil)
    }

    @Test("Script templates contains Conditional Mock JSON")
    func scriptTemplatesContainsConditionalMockJSON() throws {
        let template = ScriptingViewModel.scriptTemplates["Conditional Mock JSON"]
        #expect(template != nil)
        #expect(try #require(template?.contains("featureA")))
    }

    @Test("applyTemplate sets scriptContent to matching template source")
    func applyTemplateReplacesContent() {
        let vm = ScriptingViewModel()
        vm.applyTemplate("Modify Headers")
        #expect(vm.scriptContent == ScriptingViewModel.scriptTemplates["Modify Headers"])
    }

    @Test("applyTemplate with invalid name leaves scriptContent unchanged")
    func applyTemplateWithInvalidNameDoesNothing() {
        let vm = ScriptingViewModel()
        vm.scriptContent = "original"
        vm.applyTemplate("NonExistent")
        #expect(vm.scriptContent == "original")
    }

    @Test("clearConsole removes all entries without error")
    func clearConsoleRemovesAllEntries() {
        let vm = ScriptingViewModel()
        #expect(vm.consoleOutput.isEmpty)
        vm.clearConsole()
        #expect(vm.consoleOutput.isEmpty)
    }

    @Test("Default scriptContent is empty")
    func defaultScriptContentIsEmpty() {
        let vm = ScriptingViewModel()
        #expect(vm.scriptContent.isEmpty)
    }

    @Test("Default selectedPluginID is nil")
    func defaultSelectedPluginIDIsNil() {
        let vm = ScriptingViewModel()
        #expect(vm.selectedPluginID == nil)
    }

    @Test("Default runStatus is idle")
    func defaultRunStatusIsIdle() {
        let vm = ScriptingViewModel()
        #expect(vm.runStatus == .idle)
        #expect(vm.runStatusMessage == nil)
    }

    @Test("selectedPlugin returns nil when plugins list is empty")
    func selectedPluginReturnsNilWhenNoPlugins() {
        let vm = ScriptingViewModel()
        vm.selectedPluginID = "some-id"
        #expect(vm.selectedPlugin == nil)
    }

    @Test("Default consoleOutput is empty")
    func defaultConsoleOutputIsEmpty() {
        let vm = ScriptingViewModel()
        #expect(vm.consoleOutput.isEmpty)
    }

    @Test("runTest without selected plugin updates failure status")
    func runTestWithoutSelectionFails() async {
        let vm = ScriptingViewModel()
        await vm.runTest()
        #expect(vm.runStatus == .failure)
        #expect(vm.runStatusMessage == "No script selected")
    }

    @Test("All templates contain module.exports")
    func allTemplatesContainModuleExports() {
        for (name, source) in ScriptingViewModel.scriptTemplates {
            #expect(source.contains("module.exports"), "Template '\(name)' should contain module.exports")
        }
    }
}
