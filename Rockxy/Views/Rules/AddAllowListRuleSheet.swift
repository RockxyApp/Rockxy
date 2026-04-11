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
            _httpMethod = State(
                initialValue: rule.method.flatMap(HTTPMethodFilter.init(rawValue:)) ?? .any
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
            VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                provenanceBanner

                formRow(String(localized: "Name:")) {
                    TextField("", text: $ruleName, prompt: Text(String(localized: "Untitled")))
                        .textFieldStyle(.roundedBorder)
                }

                formRow(String(localized: "Matching Rule:")) {
                    TextField("", text: $urlPattern, prompt: Text("https://example.com/api/*"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                methodAndMatchRow

                conditionalFields
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? String(localized: "Save") : String(localized: "Add")) {
                    onSave(
                        ruleName,
                        urlPattern,
                        httpMethod,
                        matchType,
                        includeSubpaths
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlPattern.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    private static let labelWidth: CGFloat = 110

    @Environment(\.dismiss) private var dismiss
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
                    .font(.caption)
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
                .font(.caption)
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
        HStack(spacing: 8) {
            Spacer()
                .frame(width: Self.labelWidth + Theme.Layout.sectionSpacing)
            Picker("", selection: $httpMethod) {
                ForEach(HTTPMethodFilter.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(String(localized: "HTTP Method"))
            .frame(width: 90)

            Picker("", selection: $matchType) {
                ForEach(RuleMatchType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(String(localized: "Match Type"))
            .frame(width: 175)

            if matchType == .wildcard {
                Text(String(localized: "Support wildcard * and ?."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var conditionalFields: some View {
        if matchType == .wildcard {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: Self.labelWidth + Theme.Layout.sectionSpacing)
                Toggle(String(localized: "Include all subpaths of this URL"), isOn: $includeSubpaths)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
            }
        }
    }

    private func formRow(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: Theme.Layout.sectionSpacing) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: Self.labelWidth, alignment: .trailing)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
        }
    }
}
