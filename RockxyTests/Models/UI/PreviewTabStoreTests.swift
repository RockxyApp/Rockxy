import Foundation
@testable import Rockxy
import Testing

// Regression tests for `PreviewTabStore` in the models ui layer.

@MainActor
struct PreviewTabStoreTests {
    // MARK: Internal

    // MARK: - Initialization

    @Test("Store initializes with empty tabs")
    func defaultInit() {
        clearDefaultsKey("previewTabs", fallback: TestIdentity.previewTabStorageKey)
        clearDefaultsKey("previewAutoBeautify", fallback: TestIdentity.previewTabBeautifyKey)
        let freshStore = PreviewTabStore()
        #expect(freshStore.requestTabs.isEmpty)
        #expect(freshStore.responseTabs.isEmpty)
        #expect(freshStore.autoBeautify == true)
    }

    // MARK: - Enable/Disable

    @Test("Enable tab adds to correct panel")
    func enableTab() {
        let store = makeCleanStore()
        let tab = store.enableTab(renderMode: .jsonTree, panel: .request)
        #expect(store.requestTabs.count == 1)
        #expect(store.responseTabs.isEmpty)
        #expect(tab.renderMode == .jsonTree)
        #expect(tab.panel == .request)
        #expect(tab.name == "JSON Treeview")
        #expect(tab.isBuiltIn == true)
    }

    @Test("Enable same tab twice does not duplicate")
    func enableTabNoDuplicate() {
        let store = makeCleanStore()
        store.enableTab(renderMode: .hex, panel: .response)
        store.enableTab(renderMode: .hex, panel: .response)
        #expect(store.responseTabs.count == 1)
    }

    @Test("Disable tab removes from panel")
    func disableTab() {
        let store = makeCleanStore()
        store.enableTab(renderMode: .html, panel: .request)
        #expect(store.requestTabs.count == 1)
        store.disableTab(renderMode: .html, panel: .request)
        #expect(store.requestTabs.isEmpty)
    }

    @Test("Disable non-existent tab is no-op")
    func disableNonExistent() {
        let store = makeCleanStore()
        store.disableTab(renderMode: .hex, panel: .request)
        #expect(store.requestTabs.isEmpty)
    }

    // MARK: - Toggle

    @Test("Toggle enables then disables")
    func toggleTab() {
        let store = makeCleanStore()
        store.toggleTab(renderMode: .css, panel: .response)
        #expect(store.isEnabled(renderMode: .css, panel: .response))
        store.toggleTab(renderMode: .css, panel: .response)
        #expect(!store.isEnabled(renderMode: .css, panel: .response))
    }

    // MARK: - isEnabled

    @Test("isEnabled returns correct state")
    func isEnabledCheck() {
        let store = makeCleanStore()
        #expect(!store.isEnabled(renderMode: .json, panel: .request))
        store.enableTab(renderMode: .json, panel: .request)
        #expect(store.isEnabled(renderMode: .json, panel: .request))
        #expect(!store.isEnabled(renderMode: .json, panel: .response))
    }

    // MARK: - Multiple Tabs

    @Test("Multiple tabs in both panels")
    func multipleTabs() {
        let store = makeCleanStore()
        store.enableTab(renderMode: .json, panel: .request)
        store.enableTab(renderMode: .hex, panel: .request)
        store.enableTab(renderMode: .jsonTree, panel: .response)
        store.enableTab(renderMode: .html, panel: .response)
        store.enableTab(renderMode: .raw, panel: .response)
        #expect(store.requestTabs.count == 2)
        #expect(store.responseTabs.count == 3)
    }

    // MARK: - Panel Independence

    @Test("Same render mode can be in both panels independently")
    func panelIndependence() {
        let store = makeCleanStore()
        store.enableTab(renderMode: .hex, panel: .request)
        store.enableTab(renderMode: .hex, panel: .response)
        #expect(store.requestTabs.count == 1)
        #expect(store.responseTabs.count == 1)
        store.disableTab(renderMode: .hex, panel: .request)
        #expect(store.requestTabs.isEmpty)
        #expect(store.responseTabs.count == 1)
    }

    @Test("Persisted custom raw tabs are ignored")
    func persistedCustomTabsIgnored() throws {
        clearDefaultsKey("previewAutoBeautify", fallback: TestIdentity.previewTabBeautifyKey)
        let tabs = [
            PreviewTab(name: "Legacy Raw", renderMode: .raw, panel: .response, isBuiltIn: false),
            PreviewTab(renderMode: .raw, panel: .response),
        ]
        UserDefaults.standard.set(try JSONEncoder().encode(tabs), forKey: currentDefaultsKey("previewTabs"))

        let store = PreviewTabStore()

        #expect(store.responseTabs.count == 1)
        #expect(store.responseTabs.first?.isBuiltIn == true)
        #expect(store.responseTabs.first?.name == "Raw")
    }

    @Test("Auto beautify preference persists when toggled")
    func autoBeautifyPersistsWhenToggled() {
        let store = makeCleanStore()
        store.autoBeautify = false

        let freshStore = PreviewTabStore()

        #expect(freshStore.autoBeautify == false)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeCleanStore() -> PreviewTabStore {
        clearDefaultsKey("previewTabs", fallback: TestIdentity.previewTabStorageKey)
        clearDefaultsKey("previewAutoBeautify", fallback: TestIdentity.previewTabBeautifyKey)
        return PreviewTabStore()
    }

    private func clearDefaultsKey(_ key: String, fallback: String) {
        let currentKey = currentDefaultsKey(key)
        UserDefaults.standard.removeObject(forKey: currentKey)
        if currentKey != fallback {
            UserDefaults.standard.removeObject(forKey: fallback)
        }
    }

    private func currentDefaultsKey(_ key: String) -> String {
        RockxyIdentity.current.defaultsKey(key)
    }
}
