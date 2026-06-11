import SwiftUI

/// Debugging tools settings.
///
/// ## Settings Wiring Status
///
/// | Key                    | Wired? | Consumer                          |
/// |------------------------|--------|-----------------------------------|
/// | noCaching              | WIRED  | NoCacheHeaderMutator               |
struct ToolsSettingsTab: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                checkboxRow(
                    title: String(localized: "Disable caching (No-Cache headers)"),
                    isOn: $noCaching
                )

                Spacer()
            }
            .padding(.horizontal, settingsMetrics.contentPadding)
            .padding(.top, 20)
        }
        .font(settingsMetrics.font())
    }

    // MARK: Private

    @AppStorage(RockxyIdentity.current.defaultsKey("noCaching")) private var noCaching =
        false // WIRED: NoCacheHeaderMutator
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private func checkboxRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Color.clear.frame(width: settingsMetrics.rowLeading)
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
        }
    }
}
