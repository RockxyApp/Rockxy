import SwiftUI

// MARK: - AddAllowListRuleSheet

/// Modal editor sheet for creating or editing an `AllowListRule`.
/// Saves raw user-facing fields only — regex compilation happens in
/// `AllowListManager.rebuildCache()`, never here.
///
/// The sheet's draft state is seeded from the `AllowListEditorSession`
/// passed in via init. `AllowListWindowView` uses `.sheet(item:)` keyed on
/// `session.id`, so every new quick-create (even one that arrives while the
/// sheet is already open) assigns a fresh session id which causes SwiftUI to
/// tear down this view, drop its `@State` draft, and re-init from the new
/// session's mode.
struct AddAllowListRuleSheet: View {
    // MARK: Lifecycle

    init(
        session: AllowListEditorSession,
        onSave: @escaping (String, String, HTTPMethodFilter, RuleMatchType, Bool) -> Void
    ) {
        self.session = session
        self.onSave = onSave

        switch session.mode {
        case let .edit(rule):
            _ruleName = State(initialValue: rule.name)
            _urlPattern = State(initialValue: rule.rawPattern)
            // Normalize before enum lookup — imported rules may carry
            // lowercase method strings that would otherwise fall back to `.any`.
            let normalizedMethod = rule.method?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            _httpMethod = State(
                initialValue: normalizedMethod.flatMap(HTTPMethodFilter.init(rawValue:)) ?? .any
            )
            _matchType = State(initialValue: rule.matchType)
            _includeSubpaths = State(initialValue: rule.includeSubpaths)
        case let .create(context):
            _ruleName = State(initialValue: context?.suggestedName ?? "")
            _urlPattern = State(initialValue: context?.defaultPattern ?? "")
            _httpMethod = State(initialValue: context?.httpMethod ?? .any)
            _matchType = State(initialValue: context?.defaultMatchType ?? .wildcard)
            _includeSubpaths = State(initialValue: context?.includeSubpaths ?? true)
        }
    }

    // MARK: Internal

    let session: AllowListEditorSession
    let onSave: (String, String, HTTPMethodFilter, RuleMatchType, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                provenanceBanner

                formRow(String(localized: "Name:")) {
                    TextField("", text: $ruleName, prompt: Text(String(localized: "Untitled")))
                        .textFieldStyle(.roundedBorder)
                }

                formRow(String(localized: "Matching Rule:")) {
                    TextField("", text: $urlPattern, prompt: Text("https://example.com/api/*"))
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font(monospaced: true))
                }

                methodAndMatchRow

                conditionalFields
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.top, toolMetrics.formVerticalPadding)
            .padding(.bottom, toolMetrics.formVerticalPadding)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                let trimmedName = ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedURL = urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)

                Button(isEditing ? String(localized: "Save") : String(localized: "Add")) {
                    // `includeSubpaths` is a wildcard-only display toggle.
                    // Zero it out for regex rules so we never persist stale
                    // state from a user who flipped the match type.
                    let effectiveIncludeSubpaths = matchType == .wildcard ? includeSubpaths : false
                    onSave(
                        trimmedName,
                        trimmedURL,
                        httpMethod,
                        matchType,
                        effectiveIncludeSubpaths
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedURL.isEmpty)
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.vertical, toolMetrics.controlSpacing)
        }
        .font(toolMetrics.font())
        .frame(minWidth: max(640, toolMetrics.bodyFontSize * 20 + 380))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var ruleName: String
    @State private var urlPattern: String
    @State private var httpMethod: HTTPMethodFilter
    @State private var matchType: RuleMatchType
    @State private var includeSubpaths: Bool

    private var isEditing: Bool {
        if case .edit = session.mode {
            return true
        }
        return false
    }

    private var labelWidth: CGFloat {
        max(122, toolMetrics.formLabelWidth)
    }

    private var quickCreateContext: AllowListEditorContext? {
        if case let .create(context) = session.mode {
            return context
        }
        return nil
    }

    @ViewBuilder private var provenanceBanner: some View {
        if let context = quickCreateContext {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Group {
                    switch context.origin {
                    case .selectedTransaction:
                        if let method = context.sourceMethod {
                            Text(
                                String(
                                    localized: "Created from: \(method) \(context.sourceHost)\(context.sourcePath ?? "")"
                                )
                            )
                        } else {
                            Text(
                                String(
                                    localized: "Created from: \(context.sourceHost)\(context.sourcePath ?? "")"
                                )
                            )
                        }
                    case .domainQuickCreate:
                        Text(String(localized: "Created from domain: \(context.sourceHost)"))
                    }
                }
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var methodAndMatchRow: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Spacer()
                .frame(width: labelWidth + toolMetrics.controlSpacing)
            Picker("", selection: $httpMethod) {
                ForEach(HTTPMethodFilter.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(String(localized: "HTTP Method"))
            .frame(width: toolMetrics.menuWidth(90))

            Picker("", selection: $matchType) {
                ForEach(RuleMatchType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(String(localized: "Match Type"))
            .frame(width: toolMetrics.menuWidth(175))

            if matchType == .wildcard {
                Text(String(localized: "Support wildcard * and ?."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var conditionalFields: some View {
        if matchType == .wildcard {
            HStack(spacing: toolMetrics.controlSpacing) {
                Spacer()
                    .frame(width: labelWidth + toolMetrics.controlSpacing)
                Toggle(String(localized: "Include all subpaths of this URL"), isOn: $includeSubpaths)
                    .toggleStyle(.checkbox)
                    .font(toolMetrics.font())
            }
        }
    }

    private func formRow(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .trailing)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .frame(minHeight: toolMetrics.formControlHeight)
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
