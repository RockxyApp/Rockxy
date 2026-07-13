import SwiftUI

/// Native macOS sheet for creating a reusable traffic scope from captured apps, domains, and paths.
struct FocusSetEditorSheet: View {
    let initialValue: FocusSet
    let transactions: [HTTPTransaction]
    let isCreating: Bool
    let onSave: (FocusSet) -> Void

    init(
        initialValue: FocusSet,
        transactions: [HTTPTransaction],
        isCreating: Bool,
        onSave: @escaping (FocusSet) -> Void
    ) {
        self.initialValue = initialValue
        self.transactions = transactions
        self.isCreating = isCreating
        self.onSave = onSave
        _draft = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            editorContent
            Divider()
            actionBar
        }
        .frame(width: 560, height: 440)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var draft: FocusSet

    private var sheetHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(isCreating
                    ? String(localized: "Create Focus Set")
                    : String(localized: "Edit Focus Set"))
                    .font(.headline)
                Text(String(localized: "Show only the traffic that matters for this task."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                fieldRow(
                    String(localized: "Name"),
                    placeholder: String(localized: "For example: Checkout API"),
                    text: $draft.name
                )

                sectionHeader(String(localized: "Include"))

                suggestionField(
                    String(localized: "Application"),
                    placeholder: String(localized: "Any application"),
                    text: $draft.appName,
                    suggestions: appSuggestions
                )
                suggestionField(
                    String(localized: "Domain"),
                    placeholder: String(localized: "Any domain"),
                    text: $draft.domain,
                    suggestions: domainSuggestions
                )
                suggestionField(
                    String(localized: "Path Prefix"),
                    placeholder: String(localized: "Any path"),
                    text: $draft.pathPrefix,
                    suggestions: pathSuggestions
                )

                sectionHeader(String(localized: "Exclude"))

                suggestionField(
                    String(localized: "Domain"),
                    placeholder: String(localized: "No excluded domain"),
                    text: $draft.excludedDomain,
                    suggestions: domainSuggestions
                )
                suggestionField(
                    String(localized: "Path Prefix"),
                    placeholder: String(localized: "No excluded path"),
                    text: $draft.excludedPathPrefix,
                    suggestions: pathSuggestions
                )
            }
            Spacer(minLength: 0)
        }
        .controlSize(.regular)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Label(matchSummary, systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption)
                .foregroundStyle(matchCount == 0 ? Color.orange : Color.secondary)
            Spacer()
            Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isCreating ? String(localized: "Create") : String(localized: "Save")) {
                draft.name = trimmedName
                onSave(draft)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedName.isEmpty || draft.ruleCount == 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private func suggestionField(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        suggestions: [String]
    ) -> some View {
        GridRow {
            fieldLabel(title)
            HStack(spacing: 6) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                Menu {
                    Button(String(localized: "Any")) { text.wrappedValue = "" }
                    if !suggestions.isEmpty {
                        Divider()
                        ForEach(suggestions, id: \.self) { value in
                            Button(value) { text.wrappedValue = value }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 14, height: 18)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "Choose from captured traffic"))
            }
            .frame(width: 360)
        }
    }

    private func fieldRow(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        GridRow {
            fieldLabel(title)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 104, alignment: .trailing)
    }

    private func sectionHeader(_ title: String) -> some View {
        GridRow {
            Divider()
                .gridCellColumns(2)
                .overlay(alignment: .leading) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
                .padding(.vertical, 4)
        }
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchCount: Int {
        transactions.count { !$0.isTLSFailure && draft.matches($0) }
    }

    private var matchSummary: String {
        if draft.ruleCount == 0 {
            return String(localized: "Add at least one include or exclude condition")
        }
        return String(localized: "\(matchCount) matching requests")
    }

    private var appSuggestions: [String] {
        Array(Set(transactions.compactMap(\.clientApp))).sorted()
    }

    private var domainSuggestions: [String] {
        Array(Set(transactions.map { $0.request.host }.filter { !$0.isEmpty })).sorted()
    }

    private var pathSuggestions: [String] {
        Array(Set(transactions.map { $0.request.path }.filter { !$0.isEmpty })).sorted()
    }
}
