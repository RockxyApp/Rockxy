import SwiftUI

// MARK: - BypassProxySettingsSheet

/// Popup sheet for editing bypass proxy domains as a comma-separated text field.
struct BypassProxySettingsSheet: View {
    // MARK: Lifecycle

    init(manager: SSLProxyingManager) {
        self.manager = manager
        _domainsText = State(initialValue: manager.bypassDomains)
    }

    // MARK: Internal

    let manager: SSLProxyingManager

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Layout.contentPadding) {
                Text(String(localized: "Bypass Proxy Settings for these List & Domain:"))
                    .font(toolMetrics.font())

                TextEditor(text: $domainsText)
                    .font(toolMetrics.font(monospaced: true))
                    .frame(minHeight: max(120, toolMetrics.bodyFontSize * 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                Text(String(localized: "Use * to match all, or *.domain.com for subdomains. Separate by comma."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            HStack(spacing: Theme.Layout.contentPadding) {
                Button {
                    domainsText = SSLProxyingManager.defaultBypassDomains
                } label: {
                    Text(String(localized: "Reset to Default"))
                }

                Spacer()

                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Done")) {
                    manager.setBypassDomains(domainsText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: max(550, toolMetrics.fieldWidth(550)))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.dismiss) private var dismiss
    @State private var domainsText: String

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
