import AppKit
import SwiftUI

// MARK: - CommandLineControlSettingsSection

/// Settings > Advanced > Command Line: allows `rockxy-cli` to control this app.
struct CommandLineControlSettingsSection: View {
    // MARK: Internal

    var body: some View {
        SettingsIndentedContent {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    String(localized: "Allow command-line control", bundle: RockxyLocalization.bundle),
                    isOn: Binding(
                        get: { isEnabled },
                        set: { enabled in
                            isEnabled = enabled
                            coordinator.setEnabled(enabled)
                            lastError = coordinator.lastError
                        }
                    )
                )
                .toggleStyle(.checkbox)

                Text(String(
                    localized: """
                    Lets rockxy-cli start and stop the proxy, switch tools, clear the session, and export or import \
                    settings and traffic. Only programs running as you can use it.
                    """,
                    bundle: RockxyLocalization.bundle
                ))
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(verbatim: coordinator.toolPath)
                        .font(settingsMetrics.font(monospaced: true))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(coordinator.toolPath)
                    Button(String(localized: "Copy Path", bundle: RockxyLocalization.bundle)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(coordinator.toolPath, forType: .string)
                    }
                }

                if let lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(settingsMetrics.secondaryFont())
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            isEnabled = coordinator.isEnabled
            lastError = coordinator.lastError
        }
    }

    // MARK: Private

    @State private var isEnabled = false
    @State private var lastError: String?
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var coordinator: CommandLineControlCoordinator {
        CommandLineControlCoordinator.shared
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
