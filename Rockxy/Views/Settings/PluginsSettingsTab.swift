import SwiftUI

// Renders the plugins settings interface for the settings experience.

// MARK: - PluginsSettingsTab

struct PluginsSettingsTab: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                pluginListPanel
                    .frame(width: settingsMetrics.fieldWidth(240))

                Divider()

                if let plugin = viewModel.selectedPlugin {
                    PluginDetailView(plugin: plugin, viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            bottomBar
        }
        .font(settingsMetrics.font())
        .task { await viewModel.loadPlugins() }
        .alert(
            String(localized: "Plugin Error"),
            isPresented: Binding(
                get: { viewModel.lastEnableError != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.lastEnableError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK")) { viewModel.lastEnableError = nil }
        } message: {
            Text(viewModel.lastEnableError ?? "")
        }
    }

    // MARK: Private

    @State private var viewModel = PluginSettingsViewModel()
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var pluginListPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search Plugins"), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(settingsMetrics.font())
                    .frame(minHeight: settingsMetrics.controlHeight)
            }
            .padding(8)

            Divider()

            categoryFilterBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            Divider()

            List(viewModel.filteredPlugins, selection: $viewModel.selectedPluginID) { plugin in
                PluginListRow(
                    plugin: plugin,
                    isSelected: viewModel.selectedPluginID == plugin.id
                ) { _ in
                    Task { await viewModel.togglePlugin(id: plugin.id) }
                }
                .tag(plugin.id)
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.sidebar)
        }
    }

    private var categoryFilterBar: some View {
        HStack(spacing: 4) {
            categoryPill(String(localized: "All"), category: nil)
            categoryPill(String(localized: "Inspector"), category: .inspector)
            categoryPill(String(localized: "Exporter"), category: .exporter)
            categoryPill(String(localized: "Script"), category: .script)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Plugin Selected"), systemImage: "puzzlepiece.extension")
        } description: {
            Text("Select a plugin from the list to view its details and configuration.")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.openPluginsFolder()
            } label: {
                Label(String(localized: "Open Plugins Folder"), systemImage: "folder")
            }

            Button {
                viewModel.installFromFile()
            } label: {
                Label(String(localized: "Install from File…"), systemImage: "plus")
            }

            Spacer()

            Text(String(localized: "\(viewModel.plugins.count) plugins"))
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: settingsMetrics.footerHeight)
    }

    private func categoryPill(_ title: String, category: PluginType?) -> some View {
        let isActive = viewModel.selectedCategory == category
        return Button {
            viewModel.selectedCategory = category
        } label: {
            Text(title)
                .font(settingsMetrics.secondaryFont(weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
