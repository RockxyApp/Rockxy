import SwiftUI

// MARK: - AutomaticSystemProxyRoutingControl

struct AutomaticSystemProxyRoutingControl: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                String(
                    localized: "Automatically set macOS system proxy when capture starts",
                    bundle: RockxyLocalization.bundle
                ),
                isOn: Binding(
                    get: { automaticallySetSystemProxy },
                    set: {
                        automaticallySetSystemProxy = $0
                        AppSettingsManager.shared.updateAutomaticSystemProxyRouting($0)
                    }
                )
            )
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("settings.automaticallySetSystemProxy")
            Text(String(
                localized: """
                When off, capture does not take over this Mac's proxy settings. \
                Manually configured apps and devices can still connect. \
                Stop and Restart still restore any proxy override that Rockxy enabled.
                """,
                bundle: RockxyLocalization.bundle
            ))
            .font(SettingsDisplayMetrics(appMetrics: appMetrics).secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @AppStorage(AutomaticSystemProxyRouting.defaultsKey) private var automaticallySetSystemProxy = true
}
