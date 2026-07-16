import SwiftUI

// MARK: - FocusSetEditorSheet

/// Native macOS sheet for creating a reusable traffic scope from captured apps, domains, and paths.
struct FocusSetEditorSheet: View {
    // MARK: Lifecycle

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
        suggestions = FocusSetEditorSuggestions(transactions: transactions)
        _draft = State(initialValue: initialValue)
    }

    // MARK: Internal

    let initialValue: FocusSet
    let transactions: [HTTPTransaction]
    let isCreating: Bool
    let onSave: (FocusSet) -> Void

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            editorContent
            Divider()
            actionBar
        }
        .frame(width: 600, height: 570)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var draft: FocusSet

    private let suggestions: FocusSetEditorSuggestions

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                nameField

                conditionGroup(
                    title: String(localized: "Include"),
                    description: String(localized: "Traffic must match every condition you fill in.")
                ) {
                    applicationCondition
                    conditionDivider
                    suggestionCondition(
                        title: String(localized: "Domain"),
                        icon: "globe",
                        placeholder: String(localized: "Any domain"),
                        hint: String(localized: "Matches this domain and its subdomains, for example api.example.com."),
                        pickerTitle: String(localized: "Choose Captured Domain"),
                        searchPrompt: String(localized: "Search captured domains"),
                        emptySelectionTitle: String(localized: "Any Domain"),
                        text: $draft.domain,
                        suggestions: suggestions.domains,
                        kind: .domain
                    )
                    conditionDivider
                    suggestionCondition(
                        title: String(localized: "Path Prefix"),
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        placeholder: String(localized: "Any path"),
                        hint: String(
                            localized: "Matches URL paths that begin with this value, for example /v1/orders."
                        ),
                        pickerTitle: String(localized: "Choose Captured Path"),
                        searchPrompt: String(localized: "Search captured paths"),
                        emptySelectionTitle: String(localized: "Any Path"),
                        text: $draft.pathPrefix,
                        suggestions: suggestions.paths,
                        kind: .path
                    )
                }

                conditionGroup(
                    title: String(localized: "Exclude"),
                    description: String(
                        localized: "Matching traffic is removed after the include conditions are applied."
                    )
                ) {
                    suggestionCondition(
                        title: String(localized: "Domain"),
                        icon: "globe.badge.xmark",
                        placeholder: String(localized: "No excluded domain"),
                        hint: String(localized: "Removes this domain and its subdomains from the Focus Set."),
                        pickerTitle: String(localized: "Choose Excluded Domain"),
                        searchPrompt: String(localized: "Search captured domains"),
                        emptySelectionTitle: String(localized: "No Excluded Domain"),
                        text: $draft.excludedDomain,
                        suggestions: suggestions.domains,
                        kind: .domain
                    )
                    conditionDivider
                    suggestionCondition(
                        title: String(localized: "Path Prefix"),
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        placeholder: String(localized: "No excluded path"),
                        hint: String(localized: "Removes URL paths that begin with this value from the Focus Set."),
                        pickerTitle: String(localized: "Choose Excluded Path"),
                        searchPrompt: String(localized: "Search captured paths"),
                        emptySelectionTitle: String(localized: "No Excluded Path"),
                        text: $draft.excludedPathPrefix,
                        suggestions: suggestions.paths,
                        kind: .path
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .controlSize(.regular)
    }

    private var nameField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(localized: "Name"))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
            TextField(String(localized: "For example: Checkout API"), text: $draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var applicationCondition: some View {
        conditionRow(
            title: String(localized: "Application"),
            icon: "app",
            hint: String(localized: "Only includes traffic captured from the selected application.")
        ) {
            CapturedApplicationSelectionField(
                selection: $draft.appName,
                suggestions: suggestions.applications
            )
        }
    }

    private var conditionDivider: some View {
        Divider()
            .padding(.leading, 104)
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

    private func conditionGroup(
        title: String,
        description: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                content()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }

    private func suggestionCondition(
        title: String,
        icon: String,
        placeholder: String,
        hint: String,
        pickerTitle: String,
        searchPrompt: String,
        emptySelectionTitle: String,
        text: Binding<String>,
        suggestions: [CapturedValueSuggestion],
        kind: CapturedValueKind
    )
        -> some View
    {
        conditionRow(title: title, icon: icon, hint: hint) {
            CapturedTextSuggestionField(
                text: text,
                placeholder: placeholder,
                pickerTitle: pickerTitle,
                searchPrompt: searchPrompt,
                emptySelectionTitle: emptySelectionTitle,
                suggestions: suggestions,
                kind: kind
            )
        }
    }

    private func conditionRow(
        title: String,
        icon: String,
        hint: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 12) {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                content()
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - FocusSetEditorSuggestions

struct FocusSetEditorSuggestions: Equatable {
    // MARK: Lifecycle

    init(transactions: [HTTPTransaction]) {
        applications = Self.aggregate(transactions.compactMap(\.clientApp))
        domains = Self.aggregate(transactions.map(\.request.host))
        paths = Self.aggregate(transactions.map(\.request.path))
    }

    // MARK: Internal

    let applications: [CapturedValueSuggestion]
    let domains: [CapturedValueSuggestion]
    let paths: [CapturedValueSuggestion]

    // MARK: Private

    private static func aggregate(_ values: [String]) -> [CapturedValueSuggestion] {
        var counts: [String: Int] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            counts[trimmed, default: 0] += 1
        }
        return counts.map { CapturedValueSuggestion(value: $0.key, requestCount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.requestCount != rhs.requestCount {
                    return lhs.requestCount > rhs.requestCount
                }
                return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
            }
    }
}
