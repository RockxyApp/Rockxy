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
                    .font(.system(size: 13))

                TextEditor(text: $domainsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                Text(String(localized: "Use * to match all, or *.domain.com for subdomains. Separate by comma."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        .frame(width: 550)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var domainsText: String
}
