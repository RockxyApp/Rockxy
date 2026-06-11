import SwiftUI

// Presents the preview tab popover for the request and response inspector.

struct PreviewTabPopover: View {
    // MARK: Internal

    let panel: PreviewPanel
    let store: PreviewTabStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Preview Tabs"))
                .font(.system(size: metrics.controlFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
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
                    .font(.system(size: metrics.controlFontSize))
                }
            }

            Divider()

            Toggle(isOn: Binding(
                get: { store.autoBeautify },
                set: { store.autoBeautify = $0 }
            )) {
                Text(String(localized: "Auto beautify"))
                    .font(.system(size: metrics.secondaryFontSize))
            }
            .toggleStyle(.checkbox)
        }
        .padding(12)
        .frame(width: 220)
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
