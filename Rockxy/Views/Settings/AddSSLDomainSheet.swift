import SwiftUI

// MARK: - AddSSLDomainSheet

/// Small centered popup for adding or editing a domain in the SSL Proxying list.
struct AddSSLDomainSheet: View {
    // MARK: Lifecycle

    init(editingRule: SSLProxyingRule? = nil, onSave: @escaping (String) -> Void) {
        self.editingRule = editingRule
        self.onSave = onSave
        _domain = State(initialValue: editingRule?.domain ?? "")
    }

    // MARK: Internal

    let editingRule: SSLProxyingRule?
    let onSave: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                Text(editingRule != nil
                    ? String(localized: "Edit Domain")
                    : String(localized: "Add Domain"))
                    .font(.system(size: 14, weight: .bold))

                VStack(spacing: 2) {
                    Text(String(localized: "Only Host: without Port, Path and Query"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Use * to match all, or *.domain.com for subdomains"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("", text: $domain, prompt: Text("api.example.com"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            HStack {
                Spacer()

                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(editingRule != nil
                    ? String(localized: "Done")
                    : String(localized: "Add"))
                {
                    onSave(domain)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(domain.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var domain: String
}
