import Foundation
@testable import Rockxy
import Testing

// MARK: - SettingsWindowReadabilityTests

/// Contracts for the native sidebar/content Settings shell: the navigation model,
/// safe fallback for invalid persisted selection, and the resizable window shell.
struct SettingsWindowReadabilityTests {
    // MARK: Internal

    @Test("Settings navigation model is stable and complete")
    func settingsNavigationModelIsStableAndComplete() {
        // All nine categories are preserved, in order, with their persisted raw values.
        #expect(RockxySettingsTab.allCases.count == 9)
        #expect(RockxySettingsTab.allCases.map(\.rawValue) == [
            "general",
            "appearance",
            "privacy",
            "assistant",
            "tools",
            "github",
            "plugins",
            "mcp",
            "advanced",
        ])

        for tab in RockxySettingsTab.allCases {
            #expect(tab.id == tab)
            #expect(!tab.title.isEmpty)
            #expect(!tab.symbol.isEmpty)
            #expect(!tab.paneDescription.isEmpty)
        }
    }

    @Test("Invalid persisted selection resolves to general")
    func invalidPersistedSelectionResolvesToGeneral() {
        #expect(RockxySettingsTab.resolve("not-a-tab") == .general)
        #expect(RockxySettingsTab.resolve("") == .general)
        for tab in RockxySettingsTab.allCases {
            #expect(RockxySettingsTab.resolve(tab.rawValue) == tab)
        }
    }

    @Test("Programmatic selection writes the namespaced defaults key")
    func programmaticSelectionWritesNamespacedDefaultsKey() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "SettingsWindowReadabilityTests.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RockxySettingsTab.select(.assistant, defaults: defaults)
        #expect(defaults.string(forKey: RockxySettingsTab.defaultsKey) == "assistant")
        #expect(RockxySettingsTab.resolve(
            defaults.string(forKey: RockxySettingsTab.defaultsKey) ?? ""
        ) == .assistant)

        RockxySettingsTab.select(.general, defaults: defaults)
        #expect(defaults.string(forKey: RockxySettingsTab.defaultsKey) == "general")
    }

    @Test("Settings shell clones the native Developer Setup window contract")
    func settingsShellIsResizableNativeSidebarContentWindow() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/SettingsView.swift")
        let appSource = try readProjectFile("Rockxy/RockxyApp.swift")
        let sceneSource = try readProjectFile("Rockxy/Views/Settings/SettingsWindowScene.swift")

        // Settings uses the same fully native split-view structure as Developer
        // Setup. The system owns its sidebar toggle and unified title bar.
        #expect(source.contains("NavigationSplitView {"))
        #expect(source.contains("List(selection: selectionBinding)"))
        #expect(source.contains("Binding<RockxySettingsTab?>"))
        #expect(source.contains("RockxySettingsSidebarSection.allCases"))
        #expect(source.contains("Section(section.title)"))
        #expect(source.contains("min: settingsMetrics.sidebarMinWidth"))
        #expect(source.contains("ideal: settingsMetrics.sidebarIdealWidth"))
        #expect(source.contains("max: settingsMetrics.sidebarMaxWidth"))
        #expect(source.contains(".navigationTitle(selectedTab.title)"))
        #expect(source.contains(".scrollEdgeEffectStyle(.soft, for: .vertical)"))
        #expect(!source.contains("settingsToolbarContent"))
        #expect(!source.contains("Settings Category"))
        #expect(!source.contains("ToolbarItem(placement: .principal)"))
        #expect(!source.contains(".safeAreaBar(edge: .top"))
        #expect(!source.contains("SettingsWindowToolbarInstaller"))
        #expect(!source.contains("NSToolbarDelegate"))

        // Font scaling belongs to pane content. Applying it at the split root
        // also scales native toolbar controls and can create a second toolbar row.
        #expect(source.contains(".font(settingsMetrics.font(weight: selectedTab == tab ? .semibold : .regular))"))
        #expect(!source.contains(".listStyle(.sidebar)\n            .font(settingsMetrics.font())"))
        #expect(source.contains("detailContent(for: selectedTab)\n                .font(settingsMetrics.font())"))

        // Visited panes remain mounted so local drafts survive sidebar navigation.
        #expect(source.contains("@State private var loadedTabs: Set<RockxySettingsTab> = []"))
        #expect(source.contains("private var persistentPaneStack: some View"))
        #expect(source.contains("ForEach(loadedPaneTabs)"))
        #expect(source.contains(".allowsHitTesting(isSelected)"))
        #expect(source.contains(".accessibilityHidden(!isSelected)"))

        // Pane types stay explicit without type erasure.
        #expect(source.contains("switch tab {"))
        #expect(!source.contains("AnyView"))

        // Category title belongs to native navigation chrome, not to a second
        // picker or hand-built bar floating above every pane.
        #expect(!source.contains("private func paneHeader(for tab: RockxySettingsTab)"))

        // The fixed 820x600 shell is gone; geometry is adaptive and resizable.
        #expect(!source.contains(".frame(width: settingsMetrics.windowWidth, height: settingsMetrics.windowHeight)"))
        #expect(source.contains("minWidth: settingsMetrics.windowMinWidth"))
        #expect(source.contains("idealWidth: settingsMetrics.windowIdealWidth"))
        #expect(source.contains("minHeight: settingsMetrics.windowMinHeight"))
        #expect(source.contains("maxWidth: .infinity"))

        // Settings is a normal Window scene just like Developer Setup. This is
        // what keeps the automatic sidebar toggle inside the unified title bar.
        #expect(appSource.contains("SettingsWindowScene()"))
        #expect(appSource.contains("CommandGroup(replacing: .appSettings)"))
        #expect(appSource.contains("openWindow(id: \"settings\")"))
        #expect(!appSource.contains("Settings {"))
        #expect(sceneSource.contains("struct SettingsWindowScene: Scene"))
        #expect(sceneSource
            .contains("Window(String(localized: \"Settings\", bundle: RockxyLocalization.bundle), id: \"settings\")"))
        #expect(sceneSource.contains(".defaultSize(width: 1_000, height: 640)"))
        #expect(sceneSource.contains(".defaultPosition(.center)"))
        #expect(sceneSource.contains(".windowResizability(.contentMinSize)"))
        #expect(sceneSource.contains(".windowToolbarStyle(.unified(showsTitle: true))"))
    }

    @Test("Settings panes share one outer layout contract")
    func settingsPanesShareOuterLayoutContract() throws {
        let componentSource = try readProjectFile("Rockxy/Views/Settings/SettingsSectionComponents.swift")
        #expect(componentSource.contains("struct SettingsPane<Content: View>: View"))
        #expect(componentSource.contains(".padding(.horizontal, settingsMetrics.contentPadding)"))
        #expect(componentSource.contains(".padding(.vertical, settingsMetrics.paneContentPadding)"))
        #expect(componentSource.contains("settingsMetrics.contentMaxWidth"))
        #expect(componentSource.contains("Color(nsColor: .windowBackgroundColor)"))
        #expect(componentSource.contains("ViewThatFits(in: .horizontal)"))
        #expect(componentSource.contains("settingsMetrics.fieldSpacing"))
        #expect(!componentSource.contains("GroupBox"))
        #expect(!componentSource.contains("Color.clear.frame(width: settingsMetrics.rowLeading)"))
        #expect(componentSource.contains(".padding(.leading, settingsMetrics.rowLeading)"))

        let githubSource = try readProjectFile("Rockxy/Views/Settings/GitHubSettingsTab.swift")
        #expect(githubSource.contains("? String(localized: \"Reconnect...\", bundle: RockxyLocalization.bundle)"))
        #expect(githubSource.contains(": String(localized: \"Authorize...\", bundle: RockxyLocalization.bundle)"))
        #expect(!githubSource.contains("String(localized: viewModel.isConnected ?"))

        let standardPanePaths = [
            "Rockxy/Views/Settings/GeneralSettingsTab.swift",
            "Rockxy/Views/Settings/AppearanceSettingsTab.swift",
            "Rockxy/Views/Settings/PrivacySettingsTab.swift",
            "Rockxy/Views/Settings/AssistantSettingsTab.swift",
            "Rockxy/Views/Settings/ToolsSettingsTab.swift",
            "Rockxy/Views/Settings/GitHubSettingsTab.swift",
            "Rockxy/Views/Settings/MCPSettingsTab.swift",
            "Rockxy/Views/Settings/AdvancedSettingsTab.swift",
        ]

        for path in standardPanePaths {
            let paneSource = try readProjectFile(path)
            #expect(
                paneSource.contains("SettingsPane {"),
                "Expected \(path) to use the shared Settings pane scaffold"
            )
        }

        let privacySource = try readProjectFile("Rockxy/Views/Settings/PrivacySettingsTab.swift")
        #expect(!privacySource.contains("Form {"))

        let appearanceSource = try readProjectFile("Rockxy/Views/Settings/AppearanceSettingsTab.swift")
        #expect(!appearanceSource.contains(".padding(.horizontal, 18)"))

        let advancedSource = try readProjectFile("Rockxy/Views/Settings/AdvancedSettingsTab.swift")
        #expect(!advancedSource
            .contains("settingsRow(label: String(localized: \"Software Update:\", bundle: RockxyLocalization.bundle))"))
        #expect(advancedSource
            .contains("SettingsFieldRow(String(localized: \"Check Frequency\", bundle: RockxyLocalization.bundle))"))
        #expect(advancedSource.contains(".labelsHidden()"))

        // Plugins intentionally keeps a full-bleed master/detail surface with
        // a native resizable content split and a compact menu fallback.
        let pluginsSource = try readProjectFile("Rockxy/Views/Settings/PluginsSettingsTab.swift")
        #expect(pluginsSource.contains("VStack(spacing: 0)"))
        #expect(pluginsSource.contains("pluginListPanel"))
        #expect(pluginsSource.contains("HSplitView"))
        #expect(pluginsSource.contains("ViewThatFits(in: .horizontal)"))
        #expect(pluginsSource.contains(".pickerStyle(.menu)"))
        #expect(pluginsSource.contains(".listStyle(.inset)"))
        #expect(!pluginsSource.contains(".padding(.horizontal, settingsMetrics.contentPadding)"))
    }

    @Test("Assistant local model library uses the available Settings width")
    func assistantModelLibraryUsesAvailableWidth() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/AssistantSettingsTab.swift")

        #expect(source.contains(".frame(maxWidth: settingsMetrics.fieldWidth(680), alignment: .leading)"))
        #expect(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(source.components(separatedBy: "settingsMetrics.fieldWidth(520)").count - 1 == 1)
        #expect(source.components(separatedBy: ".layoutPriority(1)").count - 1 >= 3)
        #expect(source.contains("VStack(alignment: .leading, spacing: 12)"))
        #expect(!source.contains("SettingsIndentedContent {\n            VStack(alignment: .leading, spacing: 12)"))
        #expect(source
            .contains("modelAction(model)\n                    .fixedSize(horizontal: true, vertical: false)"))
    }

    @Test("MCP configuration remains readable without wrapping long paths")
    func mcpConfigurationUsesScrollableCodeSurface() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/MCPSettingsTab.swift")

        #expect(source
            .contains(
                "SettingsSection(String(localized: \"Client Configuration\", bundle: RockxyLocalization.bundle))"
            ))
        #expect(source.contains("ScrollView(.horizontal)"))
        #expect(source.contains(".fixedSize(horizontal: true, vertical: true)"))
        #expect(source.contains(".textSelection(.enabled)"))
        #expect(source.contains("Client Activity"))
        #expect(source.contains("Last validated method:"))
        #expect(source.contains("Redaction is active for MCP tool results."))
    }

    @Test("Assistant local runtimes keep the native settings hierarchy readable")
    func assistantLocalRuntimeCatalogUsesAdaptiveRows() throws {
        let source = try readProjectFile("Rockxy/Views/Settings/AssistantSettingsTab.swift")

        #expect(source.contains("AssistantLocalRuntimePreset.all"))
        #expect(source.contains("SettingsFieldRow(String(localized: \"Local Runtime\""))
        #expect(source.contains("String(localized: \"Recommended For\""))
        #expect(source.contains(".frame(maxWidth: settingsMetrics.fieldWidth(680), alignment: .leading)"))
        #expect(source.contains("localModelFitTitle"))
        #expect(!source.contains("LazyVGrid("))
    }

    @Test("Appearance settings changes the bundle-driven app language without restarting")
    func appearanceSettingsChangesAppLanguageImmediately() throws {
        let appearance = try readProjectFile("Rockxy/Views/Settings/AppearanceSettingsTab.swift")
        let general = try readProjectFile("Rockxy/Views/Settings/GeneralSettingsTab.swift")
        let metricsProvider = try readProjectFile("Rockxy/Models/UI/AppUIDisplayMetrics.swift")

        #expect(appearance
            .contains("SettingsSection(String(localized: \"Language\", bundle: RockxyLocalization.bundle))"))
        #expect(appearance.contains("languageController.availableOptions"))
        #expect(appearance.contains(".pickerStyle(.menu)"))
        #expect(appearance.contains("languageController.select(optionID: newValue)"))
        #expect(metricsProvider.contains(".environment(\\.locale, RockxyLocalization.locale)"))
        #expect(!appearance.contains("requestQuitForRequiredReopen"))
        #expect(!general.contains("AppLanguageController"))
    }

    // MARK: Private

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
