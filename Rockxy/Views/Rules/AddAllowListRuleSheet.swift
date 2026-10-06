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
        onSave: @escaping (String, String, HTTPMethodFilter, RuleMatchType, Bool, String, String) -> Void
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
            _graphQLOperationName = State(initialValue: rule.graphQLOperationName ?? "")
            _clientApplication = State(initialValue: rule.clientApplication ?? "")
        case let .create(context):
            _ruleName = State(initialValue: context?.suggestedName ?? "")
            _urlPattern = State(initialValue: context?.defaultPattern ?? "")
            _httpMethod = State(initialValue: context?.httpMethod ?? .any)
            _matchType = State(initialValue: context?.defaultMatchType ?? .wildcard)
            _includeSubpaths = State(initialValue: context?.includeSubpaths ?? true)
            _graphQLOperationName = State(initialValue: context?.graphQLOperationName ?? "")
            _clientApplication = State(initialValue: "")
        }
    }

    // MARK: Internal

    let session: AllowListEditorSession
    let onSave: (String, String, HTTPMethodFilter, RuleMatchType, Bool, String, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                Text(isEditing ? String(localized: "Edit Allow Rule", bundle: RockxyLocalization.bundle) : String(
                    localized: "New Allow Rule",
                    bundle: RockxyLocalization.bundle
                ))
                .font(
                    .system(
                        size: max(15, toolMetrics.bodyFontSize + 2),
                        weight: .semibold
                    )
                )

                provenanceBanner

                ruleDetailsSection
                captureEffectSection
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.top, toolMetrics.formVerticalPadding)
            .padding(.bottom, toolMetrics.formVerticalPadding)

            Divider()

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    // `includeSubpaths` is a wildcard-only display toggle.
                    // Zero it out for regex rules so we never persist stale
                    // state from a user who flipped the match type.
                    let effectiveIncludeSubpaths = matchType == .wildcard ? includeSubpaths : false
                    onSave(
                        trimmedName,
                        trimmedURL,
                        httpMethod,
                        matchType,
                        effectiveIncludeSubpaths,
                        graphQLOperationName.trimmingCharacters(in: .whitespacesAndNewlines),
                        clientApplication.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    dismiss()
                } label: {
                    footerButtonLabel(primaryButtonTitle)
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(trimmedURL.isEmpty || validationMessage != nil)
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.vertical, toolMetrics.controlSpacing)
        }
        .font(toolMetrics.font())
        .frame(minWidth: max(720, toolMetrics.bodyFontSize * 24 + 408))
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
    @State private var graphQLOperationName: String
    @State private var clientApplication: String

    private var isEditing: Bool {
        if case .edit = session.mode {
            return true
        }
        return false
    }

    private var primaryButtonTitle: String {
        isEditing ? String(localized: "Save", bundle: RockxyLocalization.bundle) : String(
            localized: "Add",
            bundle: RockxyLocalization.bundle
        )
    }

    private var trimmedName: String {
        ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURL: String {
        urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        AllowListRulePatternValidation.editorMessage(
            rawPattern: trimmedURL,
            matchType: matchType,
            includeSubpaths: includeSubpaths
        )
    }

    private var quickCreateContext: AllowListEditorContext? {
        if case let .create(context) = session.mode {
            return context
        }
        return nil
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
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
                                    localized: "Created from: \(method) \(context.sourceHost)\(context.sourcePath ?? "")",
                                    bundle: RockxyLocalization.bundle
                                )
                            )
                        } else {
                            Text(
                                String(
                                    localized: "Created from: \(context.sourceHost)\(context.sourcePath ?? "")",
                                    bundle: RockxyLocalization.bundle
                                )
                            )
                        }
                    case .domainQuickCreate:
                        Text(String(
                            localized: "Created from domain: \(context.sourceHost)",
                            bundle: RockxyLocalization.bundle
                        ))
                    }
                }
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(provenanceDescription(context))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var ruleDetailsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Rule Details", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                identityFields
                methodAndMatchRow
                conditionalFields
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var identityFields: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            fieldGroup(String(localized: "Name", bundle: RockxyLocalization.bundle)) {
                TextField(String(localized: "Untitled", bundle: RockxyLocalization.bundle), text: $ruleName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "Rule name", bundle: RockxyLocalization.bundle))
            }
            .frame(width: max(250, toolMetrics.fieldWidth(250)))

            fieldGroup(String(localized: "URL pattern", bundle: RockxyLocalization.bundle)) {
                TextField("https://example.com/api/*", text: $urlPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .accessibilityLabel(String(localized: "URL pattern", bundle: RockxyLocalization.bundle))

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var methodAndMatchRow: some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
            inlineField(String(localized: "Method", bundle: RockxyLocalization.bundle)) {
                Menu {
                    ForEach(HTTPMethodFilter.allCases, id: \.self) { method in
                        Button {
                            httpMethod = method
                        } label: {
                            menuCheckmarkLabel(method.rawValue, isSelected: httpMethod == method)
                        }
                    }
                } label: {
                    dataEntryMenuLabel(httpMethod.rawValue, width: toolMetrics.menuWidth(90))
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "HTTP Method", bundle: RockxyLocalization.bundle))
                .frame(width: toolMetrics.menuWidth(90))
            }

            inlineField(String(localized: "Match type", bundle: RockxyLocalization.bundle)) {
                Menu {
                    ForEach(RuleMatchType.allCases, id: \.self) { type in
                        Button {
                            matchType = type
                        } label: {
                            menuCheckmarkLabel(type.rawValue, isSelected: matchType == type)
                        }
                    }
                } label: {
                    dataEntryMenuLabel(matchType.rawValue, width: toolMetrics.menuWidth(175))
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Match Type", bundle: RockxyLocalization.bundle))
                .frame(width: toolMetrics.menuWidth(175))
            }

            if matchType == .wildcard {
                Text(String(localized: "Support wildcard * and ?.", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    @ViewBuilder private var conditionalFields: some View {
        if matchType == .wildcard {
            Toggle(
                String(localized: "Include all subpaths of this URL", bundle: RockxyLocalization.bundle),
                isOn: $includeSubpaths
            )
            .toggleStyle(.checkbox)
            .font(toolMetrics.font())
        }

        inlineField(String(localized: "Client Application", bundle: RockxyLocalization.bundle)) {
            TextField(
                String(localized: "Any application", bundle: RockxyLocalization.bundle),
                text: $clientApplication
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: max(220, toolMetrics.fieldWidth(220)))
            .accessibilityLabel(String(
                localized: "Client application name to match",
                bundle: RockxyLocalization.bundle
            ))
            .help(String(
                localized: "Record only requests made by this app, by name or bundle identifier. Applies to apps on this Mac; leave empty to record every client.",
                bundle: RockxyLocalization.bundle
            ))
        }

        inlineField(String(localized: "GraphQL Operation", bundle: RockxyLocalization.bundle)) {
            TextField(
                String(localized: "Any operation", bundle: RockxyLocalization.bundle),
                text: $graphQLOperationName
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: max(220, toolMetrics.fieldWidth(220)))
            .accessibilityLabel(String(
                localized: "GraphQL operation name to match",
                bundle: RockxyLocalization.bundle
            ))
            .help(String(
                localized: "Record only GraphQL requests with this exact operation name. Leave empty to record every request to the URL.",
                bundle: RockxyLocalization.bundle
            ))
        }
    }

    private var captureEffectSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Capture Effect", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Record matching traffic", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font(weight: .medium))
                    Text(
                        String(
                            localized:
                            "Matching requests appear in the session. Other traffic continues through the proxy without being recorded.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private func inlineField(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func fieldGroup(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(minHeight: toolMetrics.formControlHeight)
        }
    }

    private func dataEntryMenuLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .frame(width: width, height: toolMetrics.formControlHeight, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }

    private func menuCheckmarkLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: max(64, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 3),
                height: max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }

    private func provenanceDescription(_ context: AllowListEditorContext) -> String {
        switch context.origin {
        case .selectedTransaction:
            if let method = context.sourceMethod {
                return String(
                    localized: "Created from: \(method) \(context.sourceHost)\(context.sourcePath ?? "")",
                    bundle: RockxyLocalization.bundle
                )
            }
            return String(
                localized: "Created from: \(context.sourceHost)\(context.sourcePath ?? "")",
                bundle: RockxyLocalization.bundle
            )
        case .domainQuickCreate:
            return String(localized: "Created from domain: \(context.sourceHost)", bundle: RockxyLocalization.bundle)
        }
    }
}
