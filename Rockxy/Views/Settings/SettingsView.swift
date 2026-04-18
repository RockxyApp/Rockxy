import SwiftUI

// Root settings window using macOS native tab-based layout.
// Each tab is a self-contained settings pane with its own `@AppStorage` bindings.

// MARK: - SettingsView

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gear")
                }

            AppearanceSettingsTab()
                .tabItem {
                    Label(String(localized: "Appearance"), systemImage: "sparkles")
                }

            PrivacySettingsTab()
                .tabItem {
                    Label(String(localized: "Privacy"), systemImage: "person.badge.shield.checkmark")
                }

            ToolsSettingsTab()
                .tabItem {
                    Label(String(localized: "Tools"), systemImage: "wrench.and.screwdriver")
                }

            PluginsSettingsTab()
                .tabItem {
                    Label(String(localized: "Plugins"), systemImage: "puzzlepiece.extension")
                }

            MCPSettingsTab()
                .tabItem {
                    Label(String(localized: "MCP"), systemImage: "network")
                }

            AdvancedSettingsTab()
                .tabItem {
                    Label(String(localized: "Advanced"), systemImage: "ellipsis.circle")
                }
        }
        .frame(width: 820, height: 600)
    }
}
