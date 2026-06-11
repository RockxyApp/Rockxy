import SwiftUI

// Presents the proxy status popover for toolbar controls and filtering.

// MARK: - ProxyStatusPopover

/// Popover shown when clicking the toolbar status indicator. Displays the current
/// proxy connection details (IP, port, loopback) and provides quick access to
/// the Advanced Proxy Settings window.
struct ProxyStatusPopover: View {
    // MARK: Internal

    let listenAddress: String
    let port: Int
    let loopbackAddress: String

    @Binding var showPopover: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow(label: String(localized: "IP:"), value: listenAddress)

            HStack(spacing: 4) {
                Text(String(localized: "Proxy Port:"))
                    .font(.system(size: metrics.chromeFontSize))
                    .foregroundStyle(.secondary)
                Text("\(port)")
                    .font(.system(size: metrics.chromeFontSize, weight: .medium, design: .monospaced))
                Button {
                    openWindow(id: "advancedProxySettings")
                    showPopover = false
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: metrics.badgeFontSize))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Edit port in Advanced Settings"))
            }

            infoRow(label: String(localized: "Loopback:"), value: loopbackAddress)

            Divider()

            Button(String(localized: "Advanced Settings…")) {
                openWindow(id: "advancedProxySettings")
                showPopover = false
            }
            .controlSize(.regular)
        }
        .padding(14)
        .frame(width: 240)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var metrics

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: metrics.chromeFontSize))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: metrics.chromeFontSize, weight: .medium, design: .monospaced))
        }
    }
}
