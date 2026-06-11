import SwiftUI

// Renders the previewer tab interface for the settings experience.

struct PreviewerTabSettingsView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Body Previewer Tabs"))
                .font(settingsMetrics.font(weight: .semibold))
            Text(String(localized: "Select tabs to render body content as a specific format"))
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                panelColumn(title: String(localized: "Request Panel"), panel: .request)
                panelColumn(title: String(localized: "Response Panel"), panel: .response)
            }

            Divider()

            Toggle(isOn: $store.autoBeautify) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Auto beautify minified content"))
                        .font(settingsMetrics.font())
                    Text(String(localized: "Only applies to HTML, CSS, and JavaScript"))
                        .font(settingsMetrics.metadataFont())
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
        }
        .padding(12)
        .font(settingsMetrics.font())
        .frame(width: settingsMetrics.fieldWidth(480))
    }

    // MARK: Private

    @State private var store = PreviewTabStore()
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private func panelColumn(title: String, panel: PreviewPanel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(settingsMetrics.secondaryFont(weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(PreviewRenderMode.allCases) { mode in
                    Toggle(mode.displayName, isOn: Binding(
                        get: { store.isEnabled(renderMode: mode, panel: panel) },
                        set: { enabled in
                            if enabled {
                                store.enableTab(renderMode: mode, panel: panel)
                            } else {
                                store.disableTab(renderMode: mode, panel: panel)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(settingsMetrics.font())
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity)
    }
}
