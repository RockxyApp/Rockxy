import SwiftUI

// MARK: - AutomaticSystemProxyRoutingControl

struct AutomaticSystemProxyRoutingControl: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(
                String(localized: "macOS system proxy", bundle: RockxyLocalization.bundle),
                selection: Binding(get: { mode }, set: select)
            ) {
                ForEach(SystemProxyRoutingMode.allCases) { option in
                    Text(Self.title(for: option)).tag(option)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("settings.systemProxyRoutingMode")
            Text(Self.explanation(for: mode))
                .font(SettingsDisplayMetrics(appMetrics: appMetrics).secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.systemProxyRoutingMode.explanation")
        }
        .onAppear { mode = AutomaticSystemProxyRouting.mode() }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var mode = AutomaticSystemProxyRouting.mode()

    private static func title(for mode: SystemProxyRoutingMode) -> String {
        switch mode {
        case .automatic:
            String(localized: "Automatic: set when capture starts", bundle: RockxyLocalization.bundle)
        case .manual:
            String(localized: "Manual: set only from the system proxy control", bundle: RockxyLocalization.bundle)
        case .never:
            String(localized: "Never: Rockxy does not change the system proxy", bundle: RockxyLocalization.bundle)
        }
    }

    private static func explanation(for mode: SystemProxyRoutingMode) -> String {
        switch mode {
        case .automatic:
            String(
                localized: "Starting or restarting capture sets this Mac's proxy settings for you.",
                bundle: RockxyLocalization.bundle
            )
        case .manual:
            String(
                localized: """
                Capture does not take over this Mac's proxy settings. Manually configured apps and \
                devices can still connect, and the system proxy control stays available. \
                Stop and Restart still restore any proxy override that Rockxy enabled.
                """,
                bundle: RockxyLocalization.bundle
            )
        case .never:
            String(
                localized: """
                Rockxy never sets this Mac's proxy settings, and the system proxy control is unavailable. \
                Stop and Restart still restore any proxy override that Rockxy enabled earlier.
                """,
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private func select(_ newMode: SystemProxyRoutingMode) {
        mode = newMode
        // The mode key is authoritative; refresh the in-memory Bool (true only for Automatic)
        // so readers of AppSettings stay consistent. Saving never rewrites an existing mode.
        AutomaticSystemProxyRouting.setMode(newMode)
        AppSettingsManager.shared.updateAutomaticSystemProxyRouting(newMode == .automatic)
    }
}
