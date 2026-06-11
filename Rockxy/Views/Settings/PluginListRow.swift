import SwiftUI

// Renders the plugin list row used by the settings experience.

// MARK: - PluginListRow

struct PluginListRow: View {
    // MARK: Internal

    let plugin: PluginInfo
    let isSelected: Bool
    var onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(plugin.manifest.name)
                    .font(settingsMetrics.font(weight: .medium))
                    .lineLimit(1)
                Text(subtitleText)
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var statusColor: Color {
        switch plugin.status {
        case .active: Theme.Plugin.statusActive
        case .disabled: Theme.Plugin.statusDisabled
        case .error: Theme.Plugin.statusError
        case .loading: Theme.Plugin.statusDisabled
        }
    }

    private var subtitleText: String {
        if plugin.isBuiltIn {
            "Built-in · \(plugin.statusText)"
        } else {
            "v\(plugin.manifest.version) · \(plugin.statusText)"
        }
    }
}
