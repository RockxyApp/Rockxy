import SwiftUI

// MARK: - SOCKSProxySettingsView

struct SOCKSProxySettingsView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(String(localized: "Enable SOCKS Proxy"), isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .font(toolMetrics.font(weight: .medium))
                .disabled(!store.canSelectSOCKS5)

            Text(String(localized: "Compatible with SOCKS 5"))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Text(String(localized: "SOCKS Proxy Host:"))
                        .font(toolMetrics.font())
                        .frame(width: toolMetrics.formWideLabelWidth, alignment: .trailing)
                    TextField(String(localized: "proxy.example.com"), text: $host)
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(width: toolMetrics.fieldWidth(240))
                        .frame(minHeight: toolMetrics.formControlHeight)
                        .disabled(!store.canSelectSOCKS5)
                }

                HStack(spacing: 14) {
                    Text(String(localized: "SOCKS Proxy Port:"))
                        .font(toolMetrics.font())
                        .frame(width: toolMetrics.formWideLabelWidth, alignment: .trailing)
                    TextField(String(localized: "1080"), text: $port)
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font(monospaced: true))
                        .frame(width: toolMetrics.fieldWidth(110))
                        .frame(minHeight: toolMetrics.formControlHeight)
                        .disabled(!store.canSelectSOCKS5)
                }

                Divider()

                if store.canSelectSOCKS5 {
                    Text(String(localized: "SOCKS5 uses domain-name targets so the upstream proxy resolves DNS."))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    PolicyLockNotice(
                        title: String(localized: "SOCKS5 unavailable"),
                        message: String(localized: "SOCKS5 upstream proxy is unavailable in this build.")
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(toolMetrics.font())
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let errorMessage {
                Text(errorMessage)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: max(22, toolMetrics.bodyFontSize + 9)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Done")) {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canSelectSOCKS5)
            }
        }
        .font(toolMetrics.font())
        .padding(28)
        .frame(width: toolMetrics.fieldWidth(760))
        .onAppear(perform: loadDraft)
        .alert(String(localized: "SOCKS Proxy"), isPresented: $showHelp) {
            Button(String(localized: "OK")) {}
        } message: {
            Text(
                String(
                    localized: "This window configures the SOCKS5 variant of Upstream Proxy. External Proxy Settings uses the same saved configuration."
                )
            )
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var store = UpstreamProxyStore.shared
    @State private var isEnabled = false
    @State private var host = ""
    @State private var port = "1080"
    @State private var errorMessage: String?
    @State private var showHelp = false

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private func loadDraft() {
        let configuration = store.configuration
        if configuration.type == .socks5 {
            isEnabled = configuration.isEnabled
            host = configuration.host
            port = "\(configuration.port)"
        }
    }

    private func saveAndDismiss() {
        do {
            let configuration = UpstreamProxyConfiguration(
                isEnabled: isEnabled,
                type: .socks5,
                host: host,
                port: Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
                bypassHostPatterns: store.configuration.bypassHostPatterns,
                bypassLocalhost: store.configuration.bypassLocalhost
            )
            try store.saveConfiguration(configuration)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
