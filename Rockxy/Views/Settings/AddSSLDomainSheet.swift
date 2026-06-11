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
                    .font(toolMetrics.font(weight: .bold))

                VStack(spacing: 2) {
                    Text(String(localized: "Only Host: without Port, Path and Query"))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Use * to match all, or *.domain.com for subdomains"))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                TextField("", text: $domain, prompt: Text("api.example.com"))
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .frame(minHeight: toolMetrics.formControlHeight)
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
                    let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .frame(width: max(350, toolMetrics.fieldWidth(350)))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.dismiss) private var dismiss
    @State private var domain: String

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
