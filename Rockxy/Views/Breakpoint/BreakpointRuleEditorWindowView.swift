import SwiftUI

// MARK: - BreakpointRuleEditorStore

@MainActor @Observable
final class BreakpointRuleEditorStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    typealias SaveHandler = (
        String,
        String,
        HTTPMethodFilter,
        RuleMatchType,
        Bool,
        Bool,
        Bool,
        String?
    )
    async -> Bool

    static let shared = BreakpointRuleEditorStore()

    private(set) var editorContext: BreakpointEditorContext?
    private(set) var editingRule: ProxyRule?
    private(set) var draftVersion: UInt64 = 0
    var onSave: SaveHandler?

    func openNew(context: BreakpointEditorContext? = nil, onSave: @escaping SaveHandler) {
        editorContext = context
        editingRule = nil
        self.onSave = onSave
        draftVersion &+= 1
    }

    func openExisting(_ rule: ProxyRule, onSave: @escaping SaveHandler) {
        editorContext = nil
        editingRule = rule
        self.onSave = onSave
        draftVersion &+= 1
    }

    func reset() {
        editorContext = nil
        editingRule = nil
        onSave = nil
    }
}

// MARK: - BreakpointRuleEditorWindowView

struct BreakpointRuleEditorWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing + 3) {
                    Text(editorTitle)
                        .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))

                    if let quickCreateProvenance {
                        provenanceBanner(quickCreateProvenance)
                    }

                    ruleDetailsSection
                    breakpointPhasesSection
                    RuleURLTesterSection(toolMetrics: toolMetrics) {
                        RuleMatchCondition(
                            urlPattern: RulePatternBuilder.regexSource(
                                rawPattern: urlPattern,
                                matchType: matchType,
                                includeSubpaths: includeSubpaths
                            ),
                            sourceURLPattern: urlPattern,
                            method: httpMethod.methodValue,
                            matchType: matchType,
                            includeSubpaths: includeSubpaths
                        )
                    }
                }
                .padding(.horizontal, toolMetrics.formHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
            }
            .id(store.draftVersion)

            Divider()

            VStack(alignment: .trailing, spacing: toolMetrics.controlSpacing) {
                if let saveError {
                    validationLabel(saveError)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                HStack {
                    Spacer()
                    Button {
                        cancel()
                    } label: {
                        footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)

                    Button {
                        Task { await save() }
                    } label: {
                        footerButtonLabel(
                            isSaving
                                ? String(localized: "Saving…", bundle: RockxyLocalization.bundle)
                                : isEditing ? String(localized: "Save", bundle: RockxyLocalization.bundle) : String(
                                    localized: "Add",
                                    bundle: RockxyLocalization.bundle
                                )
                        )
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .rockxyGlassButtonStyle(prominent: true)
                    .disabled(!isValid || isSaving)
                }
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.vertical, toolMetrics.controlSpacing)
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(760, toolMetrics.bodyFontSize * 24 + 472),
            minHeight: max(430, toolMetrics.bodyFontSize * 13 + 261)
        )
        .onAppear { loadFromStore() }
        .onChange(of: store.draftVersion) { _, _ in
            loadFromStore()
        }
        .onDisappear {
            store.reset()
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var store = BreakpointRuleEditorStore.shared

    @State private var ruleName = "Untitled"
    @State private var urlPattern = ""
    @State private var httpMethod: HTTPMethodFilter = .any
    @State private var matchType: RuleMatchType = .wildcard
    @State private var includeSubpaths = true
    @State private var breakpointRequest = true
    @State private var breakpointResponse = true
    @State private var graphQLOperationName = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var isEditing: Bool {
        store.editingRule != nil
    }

    private var editorTitle: String {
        isEditing
            ? String(localized: "Edit Breakpoint Rule", bundle: RockxyLocalization.bundle)
            : String(localized: "New Breakpoint Rule", bundle: RockxyLocalization.bundle)
    }

    private var patternValidationMessage: String? {
        BreakpointRuleForm.patternValidationMessage(
            rawPattern: urlPattern,
            matchType: matchType,
            includeSubpaths: includeSubpaths
        )
    }

    private var phaseValidationMessage: String? {
        BreakpointRuleForm.phaseValidationMessage(
            request: breakpointRequest,
            response: breakpointResponse
        )
    }

    private var isValid: Bool {
        patternValidationMessage == nil && phaseValidationMessage == nil
    }

    private var quickCreateProvenance: String? {
        guard let context = store.editorContext else {
            return nil
        }
        switch context.origin {
        case .selectedTransaction:
            let method = context.sourceMethod ?? "ANY"
            return String(
                localized: "Created from \(method) \(context.sourceHost)\(context.sourcePath ?? "/")",
                bundle: RockxyLocalization.bundle
            )
        case .domainQuickCreate:
            return String(localized: "Created from domain \(context.sourceHost)", bundle: RockxyLocalization.bundle)
        }
    }

    private var patternHelpText: String {
        switch matchType {
        case .wildcard:
            String(
                localized:
                "Wildcard patterns support * for any sequence and ? for one character. Turn on Include subpaths to extend the match beyond this URL.",
                bundle: RockxyLocalization.bundle
            )
        case .regex:
            String(
                localized: "Regular expressions are validated before the rule is saved.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var ruleDetailsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Rule Details", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                    fieldGroup(String(localized: "Name", bundle: RockxyLocalization.bundle)) {
                        TextField(String(localized: "Untitled", bundle: RockxyLocalization.bundle), text: $ruleName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(String(
                                localized: "Breakpoint rule name",
                                bundle: RockxyLocalization.bundle
                            ))
                    }
                    .frame(width: max(250, toolMetrics.fieldWidth(250)))

                    fieldGroup(String(localized: "URL Pattern", bundle: RockxyLocalization.bundle)) {
                        TextField("https://api.example.com/v1/*", text: $urlPattern)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(String(
                                localized: "Breakpoint URL pattern",
                                bundle: RockxyLocalization.bundle
                            ))
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                    fieldGroup(String(localized: "Method", bundle: RockxyLocalization.bundle)) {
                        methodMenu
                    }
                    .frame(width: toolMetrics.menuWidth(90))

                    fieldGroup(String(localized: "Match Type", bundle: RockxyLocalization.bundle)) {
                        matchTypeMenu
                    }
                    .frame(width: toolMetrics.menuWidth(175))

                    if matchType == .wildcard {
                        fieldGroup(String(localized: "Path Scope", bundle: RockxyLocalization.bundle)) {
                            Toggle(
                                String(localized: "Include subpaths", bundle: RockxyLocalization.bundle),
                                isOn: $includeSubpaths
                            )
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Spacer(minLength: 0)
                }

                fieldGroup(String(localized: "GraphQL Operation", bundle: RockxyLocalization.bundle)) {
                    TextField(
                        String(localized: "Any operation", bundle: RockxyLocalization.bundle),
                        text: $graphQLOperationName
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(
                        localized: "GraphQL operation name to match",
                        bundle: RockxyLocalization.bundle
                    ))
                    .help(String(
                        localized: "Pause only GraphQL requests with this exact operation name. Leave empty to match every request to the URL.",
                        bundle: RockxyLocalization.bundle
                    ))
                }
                .frame(width: max(250, toolMetrics.fieldWidth(250)))

                if let patternValidationMessage {
                    validationLabel(patternValidationMessage)
                }

                Text(patternHelpText)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var breakpointPhasesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Pause Phases", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                HStack(spacing: toolMetrics.controlSpacing) {
                    phaseOption(
                        title: String(localized: "Request", bundle: RockxyLocalization.bundle),
                        detail: String(
                            localized: "Pause before the outgoing request is forwarded.",
                            bundle: RockxyLocalization.bundle
                        ),
                        systemImage: "arrow.up.right",
                        isOn: $breakpointRequest
                    )
                    phaseOption(
                        title: String(localized: "Response", bundle: RockxyLocalization.bundle),
                        detail: String(
                            localized: "Pause after the incoming response is received.",
                            bundle: RockxyLocalization.bundle
                        ),
                        systemImage: "arrow.down.left",
                        isOn: $breakpointResponse
                    )
                }

                if let phaseValidationMessage {
                    validationLabel(phaseValidationMessage)
                }

                Text(
                    String(
                        localized:
                        "The Breakpoint Queue lets you inspect, edit, continue, or abort traffic after this rule pauses it.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    private var methodMenu: some View {
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
        .accessibilityLabel(String(localized: "HTTP method", bundle: RockxyLocalization.bundle))
    }

    private var matchTypeMenu: some View {
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
        .accessibilityLabel(String(localized: "Match type", bundle: RockxyLocalization.bundle))
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
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func phaseOption(
        title: String,
        detail: String,
        systemImage: String,
        isOn: Binding<Bool>
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 9) {
            Toggle("", isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(title)
                .padding(.top, 2)
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(toolMetrics.font(weight: .medium))
                Text(detail)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private func menuCheckmarkLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    private func dataEntryMenuLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(toolMetrics.font())
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

    private func provenanceBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(message)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: max(64, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 3),
                height: max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }

    private func validationLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func loadFromStore() {
        saveError = nil
        isSaving = false
        if let editingRule = store.editingRule {
            let decoded = BreakpointRuleForm.decode(rule: editingRule)
            ruleName = editingRule.name
            urlPattern = decoded.displayPattern
            httpMethod = decoded.httpMethod
            matchType = decoded.matchType
            includeSubpaths = decoded.includeSubpaths
            breakpointRequest = decoded.breakpointRequest
            breakpointResponse = decoded.breakpointResponse
            graphQLOperationName = decoded.graphQLOperationName
        } else if let context = store.editorContext {
            ruleName = context.suggestedName.isEmpty ? "Untitled" : context.suggestedName
            urlPattern = context.defaultPattern
            httpMethod = context.httpMethod
            matchType = context.defaultMatchType
            includeSubpaths = context.includeSubpaths
            breakpointRequest = context.breakpointRequest
            breakpointResponse = context.breakpointResponse
            graphQLOperationName = context.graphQLOperationName ?? ""
        } else {
            ruleName = "Untitled"
            urlPattern = ""
            httpMethod = .any
            matchType = .wildcard
            includeSubpaths = true
            breakpointRequest = true
            breakpointResponse = true
            graphQLOperationName = ""
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving, isValid, let onSave = store.onSave else {
            return
        }
        isSaving = true
        saveError = nil
        let accepted = await onSave(
            ruleName,
            urlPattern,
            httpMethod,
            matchType,
            breakpointRequest,
            breakpointResponse,
            includeSubpaths,
            graphQLOperationName
        )
        isSaving = false
        guard accepted else {
            saveError = String(
                localized: "This rule could not be saved. Disable another Breakpoint rule and try again.",
                bundle: RockxyLocalization.bundle
            )
            return
        }
        store.reset()
        dismiss()
    }

    private func cancel() {
        store.reset()
        dismiss()
    }
}
