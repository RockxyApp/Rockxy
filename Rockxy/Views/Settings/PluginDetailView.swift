import SwiftUI

// Renders the plugin detail interface for the settings experience.

// MARK: - PluginDetailView

struct PluginDetailView: View {
    // MARK: Internal

    let plugin: PluginInfo
    let viewModel: PluginSettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Text(plugin.manifest.description)
                    .font(settingsMetrics.font())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                badgesSection

                if let configuration = plugin.manifest.configuration, !configuration.isEmpty {
                    Divider()
                    configurationSection(configuration)
                }

                Divider()
                actionsSection
            }
            .padding(20)
        }
        .font(settingsMetrics.font())
    }

    // MARK: Private

    @State private var showUninstallConfirmation = false
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            pluginIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.manifest.name)
                    .font(.system(size: max(16, settingsMetrics.bodyFontSize + 3), weight: .semibold))
                Text("v\(plugin.manifest.version)")
                    .font(settingsMetrics.font())
                    .foregroundStyle(.secondary)
                if let urlString = plugin.manifest.author.url, let url = URL(string: urlString) {
                    Link(plugin.manifest.author.name, destination: url)
                        .font(settingsMetrics.font())
                } else {
                    Text(plugin.manifest.author.name)
                        .font(settingsMetrics.font())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pluginIcon: some View {
        let sfSymbol = plugin.manifest.types.first.map { Theme.Plugin.sfSymbol(for: $0) } ?? "shippingbox"
        let badgeColor = plugin.manifest.types.first.map { Theme.Plugin.badgeColor(for: $0) } ?? .gray
        return RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [badgeColor, badgeColor.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: sfSymbol)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
    }

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(plugin.manifest.types, id: \.rawValue) { type in
                    Text(type.rawValue.capitalized)
                        .font(settingsMetrics.secondaryFont(weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Plugin.badgeColor(for: type).opacity(0.15))
                        .foregroundStyle(Theme.Plugin.badgeColor(for: type))
                        .clipShape(Capsule())
                }
            }

            if !plugin.manifest.capabilities.isEmpty {
                HStack(spacing: 6) {
                    ForEach(plugin.manifest.capabilities, id: \.self) { capability in
                        Text(capability)
                            .font(settingsMetrics.secondaryFont())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.gray.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.revealInFinder(plugin: plugin)
            } label: {
                Label(String(localized: "Reveal in Finder"), systemImage: "folder")
            }

            Button {
                Task { await viewModel.reloadPlugin(id: plugin.id) }
            } label: {
                Label(String(localized: "Reload"), systemImage: "arrow.clockwise")
            }

            if !plugin.isBuiltIn {
                Button {
                    Task { await viewModel.reinstallPlugin(id: plugin.id) }
                } label: {
                    Label(String(localized: "Reinstall"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
            }

            if !plugin.isBuiltIn {
                Button(role: .destructive) {
                    showUninstallConfirmation = true
                } label: {
                    Label(String(localized: "Uninstall"), systemImage: "trash")
                }
                .alert(
                    String(localized: "Uninstall Plugin"),
                    isPresented: $showUninstallConfirmation
                ) {
                    Button(String(localized: "Cancel"), role: .cancel) {}
                    Button(String(localized: "Uninstall"), role: .destructive) {
                        Task { await viewModel.uninstallPlugin(id: plugin.id) }
                    }
                } message: {
                    Text("Are you sure you want to uninstall \(plugin.manifest.name)?")
                }
            }
        }
    }

    private func configurationSection(_ configuration: [String: PluginConfigField]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(settingsMetrics.font(weight: .semibold))

            ForEach(configuration.sorted(by: { $0.key < $1.key }), id: \.key) { key, field in
                configRow(key: key, field: field)
            }
        }
    }

    private func configRow(key: String, field: PluginConfigField) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(field.title)
                .font(settingsMetrics.font())
                .frame(width: settingsMetrics.fieldWidth(120), alignment: .trailing)
                .padding(.trailing, 12)
                .padding(.top, 2)

            switch field.type {
            case "boolean":
                Toggle("", isOn: configBoolBinding(pluginID: plugin.id, key: key, field: field))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            case "string" where field.secret == true:
                SecureField("", text: configStringBinding(pluginID: plugin.id, key: key, field: field))
                    .textFieldStyle(.roundedBorder)
                    .font(settingsMetrics.font())
                    .frame(maxWidth: settingsMetrics.fieldWidth(240), minHeight: settingsMetrics.controlHeight)
            case "number":
                TextField("", text: configStringBinding(pluginID: plugin.id, key: key, field: field))
                    .textFieldStyle(.roundedBorder)
                    .font(settingsMetrics.font(monospaced: true))
                    .frame(maxWidth: settingsMetrics.fieldWidth(120), minHeight: settingsMetrics.controlHeight)
            default:
                TextField("", text: configStringBinding(pluginID: plugin.id, key: key, field: field))
                    .textFieldStyle(.roundedBorder)
                    .font(settingsMetrics.font())
                    .frame(maxWidth: settingsMetrics.fieldWidth(240), minHeight: settingsMetrics.controlHeight)
            }
        }
    }

    private func configStringBinding(pluginID: String, key: String, field: PluginConfigField) -> Binding<String> {
        Binding(
            get: {
                if let value = viewModel.configValue(pluginID: pluginID, key: key) as? String {
                    return value
                }
                if case let .string(defaultValue) = field.defaultValue {
                    return defaultValue
                }
                return ""
            },
            set: { viewModel.updateConfig(pluginID: pluginID, key: key, value: $0) }
        )
    }

    private func configBoolBinding(pluginID: String, key: String, field: PluginConfigField) -> Binding<Bool> {
        Binding(
            get: {
                if let value = viewModel.configValue(pluginID: pluginID, key: key) as? Bool {
                    return value
                }
                if case let .bool(defaultValue) = field.defaultValue {
                    return defaultValue
                }
                return false
            },
            set: { viewModel.updateConfig(pluginID: pluginID, key: key, value: $0) }
        )
    }
}
