import SwiftUI

// Root settings window using macOS native tab-based layout.
// Each tab is a self-contained settings pane with its own `@AppStorage` bindings.

// MARK: - RockxySettingsTab

enum RockxySettingsTab: String {
    case general
    case appearance
    case privacy
    case tools
    case github
    case plugins
    case mcp
    case advanced

    // MARK: Internal

    static let defaultsKey = RockxyIdentity.current.defaultsKey("selectedSettingsTab")

    static func select(_ tab: RockxySettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: defaultsKey)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    var body: some View {
        TabView(selection: $selectedTabID) {
            GeneralSettingsTab()
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gear")
                }
                .tag(RockxySettingsTab.general.rawValue)

            AppearanceSettingsTab()
                .tabItem {
                    Label(String(localized: "Appearance"), systemImage: "sparkles")
                }
                .tag(RockxySettingsTab.appearance.rawValue)

            PrivacySettingsTab()
                .tabItem {
                    Label(String(localized: "Privacy"), systemImage: "person.badge.shield.checkmark")
                }
                .tag(RockxySettingsTab.privacy.rawValue)

            ToolsSettingsTab()
                .tabItem {
                    Label(String(localized: "Tools"), systemImage: "wrench.and.screwdriver")
                }
                .tag(RockxySettingsTab.tools.rawValue)

            GitHubSettingsTab()
                .tabItem {
                    Label(String(localized: "GitHub"), systemImage: "link")
                }
                .tag(RockxySettingsTab.github.rawValue)

            PluginsSettingsTab()
                .tabItem {
                    Label(String(localized: "Plugins"), systemImage: "puzzlepiece.extension")
                }
                .tag(RockxySettingsTab.plugins.rawValue)

            MCPSettingsTab()
                .tabItem {
                    Label(String(localized: "MCP"), systemImage: "network")
                }
                .tag(RockxySettingsTab.mcp.rawValue)

            AdvancedSettingsTab()
                .tabItem {
                    Label(String(localized: "Advanced"), systemImage: "ellipsis.circle")
                }
                .tag(RockxySettingsTab.advanced.rawValue)
        }
        .frame(width: 820, height: 600)
    }

    // MARK: Private

    @AppStorage(RockxySettingsTab.defaultsKey) private var selectedTabID = RockxySettingsTab.general.rawValue
}
