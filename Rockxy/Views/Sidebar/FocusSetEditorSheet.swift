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
        _draft = State(initialValue: initialValue)
        _usesSuggestedName = State(initialValue: isCreating && initialValue.name == initialValue.suggestedName)
    }

    // MARK: Internal

    let initialValue: FocusSet
    let transactions: [HTTPTransaction]
    let isCreating: Bool
    let onSave: (FocusSet) -> Void

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            editorContent
            actionBar
        }
        .font(toolMetrics.font())
        .frame(width: max(640, toolMetrics.fieldWidth(640)), height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("focusSetEditor.sheet")
        .task {
            // The sheet is re-initialised on every captured request while it is open, because
            // the presenting closure reads the live transaction list. Aggregating the
            // suggestions here instead of in `init` means that re-initialisation costs nothing:
            // this runs once for the sheet's lifetime, not once per request.
            suggestions = FocusSetEditorSuggestions(transactions: transactions)
        }
        .task(id: draft) {
            await refreshMatchCount()
        }
        .onChange(of: draft.suggestedName) { _, suggestedName in
            guard isCreating, usesSuggestedName else {
                return
            }
            draft.name = suggestedName
        }
        .onChange(of: draft.name) { _, name in
            guard isCreating, name != draft.suggestedName else {
                return
            }
            usesSuggestedName = false
        }
    }

    // MARK: Private

    /// Long enough to coalesce typing, short enough that the preview still reads as live.
    /// Matches the traffic search field's debounce, which solves the same problem.
    private static let matchCountDebounce = Duration.milliseconds(150)

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FocusSet
    @State private var usesSuggestedName: Bool
    @State private var suggestions = FocusSetEditorSuggestions()
    @State private var matchCount = 0
    @State private var hasMatchCount = false

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var matchSummary: String {
        if draft.ruleCount == 0 {
            return String(
                localized: "Add an include or exclude condition to preview matches",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(AttributedString(
            localized: "^[\(matchCount) matching request](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isCreating
                    ? String(localized: "Create Focus Set", bundle: RockxyLocalization.bundle)
                    : String(localized: "Edit Focus Set", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))
                Text(String(
                    localized: "Save a reusable view of the traffic relevant to one task.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                nameField

                Divider()

                conditionGroup(
                    title: String(localized: "Include", bundle: RockxyLocalization.bundle),
                    description: String(
                        localized: "A request must match every condition you set. Empty fields match any value.",
                        bundle: RockxyLocalization.bundle
                    )
                ) {
                    applicationCondition
                    conditionDivider
                    suggestionCondition(
                        title: String(localized: "Domain", bundle: RockxyLocalization.bundle),
                        placeholder: String(localized: "Any domain", bundle: RockxyLocalization.bundle),
                        hint: String(
                            localized: "Matches this domain and its subdomains, such as api.example.com.",
                            bundle: RockxyLocalization.bundle
                        ),
                        pickerTitle: String(localized: "Choose Captured Domain", bundle: RockxyLocalization.bundle),
                        searchPrompt: String(localized: "Search captured domains", bundle: RockxyLocalization.bundle),
                        emptySelectionTitle: String(localized: "Any Domain", bundle: RockxyLocalization.bundle),
                        text: $draft.domain,
                        suggestions: suggestions.domains,
                        kind: .domain
                    )
                    conditionDivider
                    suggestionCondition(
                        title: String(localized: "Path Prefix", bundle: RockxyLocalization.bundle),
                        placeholder: String(localized: "Any path", bundle: RockxyLocalization.bundle),
                        hint: String(
                            localized: "Matches URL paths that begin with this value, such as /v1/orders.",
                            bundle: RockxyLocalization.bundle
                        ),
                        pickerTitle: String(localized: "Choose Captured Path", bundle: RockxyLocalization.bundle),
                        searchPrompt: String(localized: "Search captured paths", bundle: RockxyLocalization.bundle),
                        emptySelectionTitle: String(localized: "Any Path", bundle: RockxyLocalization.bundle),
                        text: $draft.pathPrefix,
                        suggestions: suggestions.paths,
                        kind: .path
                    )
                }

                Divider()

                conditionGroup(
                    title: String(localized: "Exclude", bundle: RockxyLocalization.bundle),
                    description: String(
                        localized: "Matching requests are hidden after the include conditions are applied.",
                        bundle: RockxyLocalization.bundle
                    )
                ) {
                    suggestionCondition(
                        title: String(localized: "Domain", bundle: RockxyLocalization.bundle),
                        placeholder: String(localized: "No excluded domain", bundle: RockxyLocalization.bundle),
                        hint: String(
                            localized: "Hides this domain and its subdomains from the Focus Set.",
                            bundle: RockxyLocalization.bundle
                        ),
                        pickerTitle: String(localized: "Choose Excluded Domain", bundle: RockxyLocalization.bundle),
                        searchPrompt: String(localized: "Search captured domains", bundle: RockxyLocalization.bundle),
                        emptySelectionTitle: String(localized: "No Excluded Domain", bundle: RockxyLocalization.bundle),
                        text: $draft.excludedDomain,
                        suggestions: suggestions.domains,
                        kind: .domain
                    )
                    conditionDivider
                    suggestionCondition(
                        title: String(localized: "Path Prefix", bundle: RockxyLocalization.bundle),
                        placeholder: String(localized: "No excluded path", bundle: RockxyLocalization.bundle),
                        hint: String(
                            localized: "Hides URL paths that begin with this value from the Focus Set.",
                            bundle: RockxyLocalization.bundle
                        ),
                        pickerTitle: String(localized: "Choose Excluded Path", bundle: RockxyLocalization.bundle),
                        searchPrompt: String(localized: "Search captured paths", bundle: RockxyLocalization.bundle),
                        emptySelectionTitle: String(localized: "No Excluded Path", bundle: RockxyLocalization.bundle),
                        text: $draft.excludedPathPrefix,
                        suggestions: suggestions.paths,
                        kind: .path
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .controlSize(.regular)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            conditionRow(title: String(localized: "Name", bundle: RockxyLocalization.bundle)) {
                TextField(
                    String(localized: "For example: Checkout API", bundle: RockxyLocalization.bundle),
                    text: $draft.name
                )
                .textFieldStyle(.roundedBorder)
                .frame(height: toolMetrics.formControlHeight)
                .accessibilityIdentifier("focusSetEditor.name")
            }

            Text(
                String(
                    localized: "Focus Sets are available in every Project. Saving applies this set to the current Traffic Tab.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, toolMetrics.formLabelWidth + toolMetrics.controlSpacing)
        }
    }

    private var applicationCondition: some View {
        conditionRow(
            title: String(localized: "Application", bundle: RockxyLocalization.bundle),
            hint: String(
                localized: "Only includes traffic captured from the selected application.",
                bundle: RockxyLocalization.bundle
            )
        ) {
            CapturedApplicationSelectionField(
                selection: $draft.appName,
                suggestions: suggestions.applications
            )
        }
    }

    private var conditionDivider: some View {
        Divider()
            .padding(.leading, toolMetrics.formLabelWidth + toolMetrics.controlSpacing)
    }

    private var actionBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Label(matchSummary, systemImage: "line.3.horizontal.decrease.circle")
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(matchCount == 0 ? Color.orange : Color.secondary)
            Spacer()
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .rockxyGlassButtonStyle()
            Button(isCreating ? String(localized: "Create", bundle: RockxyLocalization.bundle) : String(
                localized: "Save",
                bundle: RockxyLocalization.bundle
            )) {
                draft.name = trimmedName
                onSave(draft)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(trimmedName.isEmpty || draft.ruleCount == 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private func conditionGroup(
        title: String,
        description: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(toolMetrics.font(weight: .semibold))
                Text(description)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                content()
            }
        }
    }

    private func suggestionCondition(
        title: String,
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
        conditionRow(title: title, hint: hint) {
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
        hint: String? = nil,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(toolMetrics.font(weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: toolMetrics.formLabelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                content()
                if let hint {
                    Text(hint)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One match pass per settled edit, not one per keystroke. The pass walks every captured
    /// transaction and the preview used to be read twice per render, so after a long capture
    /// two full passes landed on the main actor for every character typed in the editor.
    ///
    /// `task(id:)` cancels and restarts this on each `draft` change, so the sleep at the head
    /// is the debounce. The very first pass skips it: the sheet opens showing a real count
    /// rather than "no matching requests" for the length of the delay.
    private func refreshMatchCount() async {
        if hasMatchCount {
            do {
                try await Task.sleep(for: Self.matchCountDebounce)
            } catch {
                // Cancelled by a newer edit, which is coalesced into that edit's pass.
                return
            }
        }
        let draft = draft
        matchCount = transactions.count { !$0.isTLSFailure && draft.matches($0) }
        hasMatchCount = true
    }
}

// MARK: - FocusSetEditorSuggestions

struct FocusSetEditorSuggestions: Equatable {
    // MARK: Lifecycle

    /// What a sheet shows before its first aggregation lands. The fields are suggestion lists
    /// for free-text pickers, so an empty one offers nothing rather than reading as "none".
    init() {
        applications = []
        domains = []
        paths = []
    }

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
