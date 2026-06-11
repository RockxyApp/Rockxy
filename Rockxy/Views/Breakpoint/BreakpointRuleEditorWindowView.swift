import SwiftUI

// MARK: - BreakpointRuleEditorStore

@MainActor @Observable
final class BreakpointRuleEditorStore {
    // MARK: Internal

    typealias SaveHandler = (String, String, HTTPMethodFilter, RuleMatchType, Bool, Bool, Bool) -> Void

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

    // MARK: Private

    private init() {}
}

// MARK: - BreakpointRuleEditorWindowView

struct BreakpointRuleEditorWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: toolMetrics.headerSpacing) {
            formRows
            Spacer(minLength: 8)
            actionRow
        }
        .font(toolMetrics.font())
        .padding(.horizontal, toolMetrics.formHorizontalPadding)
        .padding(.top, toolMetrics.formVerticalPadding)
        .padding(.bottom, toolMetrics.footerBottomPadding)
        .frame(minWidth: max(815, toolMetrics.bodyFontSize * 24 + 504), minHeight: max(270, toolMetrics.bodyFontSize * 10 + 150))
        .onAppear { loadFromStore() }
        .onChange(of: store.draftVersion) { _, _ in loadFromStore() }
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

    private var isEditing: Bool {
        store.editingRule != nil
    }

    private var canSave: Bool {
        !urlPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (breakpointRequest || breakpointResponse)
    }

    private var labelWidth: CGFloat {
        max(122, toolMetrics.formLabelWidth)
    }

    private var formRows: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            formRow(String(localized: "Name:")) {
                TextField(String(localized: "Untitled"), text: $ruleName)
                    .textFieldStyle(.roundedBorder)
            }

            formRow(String(localized: "Matching Rule:")) {
                TextField("/v1/*", text: $urlPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
            }

            HStack(spacing: toolMetrics.controlSpacing) {
                Spacer()
                    .frame(width: labelWidth)
                Picker("", selection: $httpMethod) {
                    ForEach(HTTPMethodFilter.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: toolMetrics.menuWidth(100))

                Picker("", selection: $matchType) {
                    ForEach(RuleMatchType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: toolMetrics.menuWidth(132))

                Text(String(localized: "Support wildcard * and ?."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(String(localized: "Test your Rule")) {
                    NSSound.beep()
                }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: toolMetrics.controlSpacing) {
                Spacer()
                    .frame(width: labelWidth)
                Toggle(String(localized: "Include all subpaths of this URL"), isOn: $includeSubpaths)
                    .toggleStyle(.checkbox)
                    .font(toolMetrics.font())
                    .disabled(matchType != .wildcard)
            }

            formRow(String(localized: "Breakpoint:")) {
                Toggle(String(localized: "Request"), isOn: $breakpointRequest)
                    .toggleStyle(.checkbox)
                    .font(toolMetrics.font())
                Toggle(String(localized: "Response"), isOn: $breakpointResponse)
                    .toggleStyle(.checkbox)
                    .font(toolMetrics.font())
            }

            HStack {
                Spacer()
                    .frame(width: labelWidth)
                Text(String(localized: "Start the breakpoint for out-going request or in-coming response."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Spacer()
            Button(String(localized: "Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .frame(width: toolMetrics.footerButtonWidth)

            Button(isEditing ? String(localized: "Save (⌘↵)") : String(localized: "Add (⌘↵)")) {
                store.onSave?(
                    ruleName,
                    urlPattern,
                    httpMethod,
                    matchType,
                    breakpointRequest,
                    breakpointResponse,
                    includeSubpaths
                )
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
            .frame(width: toolMetrics.footerButtonWidth)
        }
    }

    private func formRow(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .firstTextBaseline, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .trailing)
            content()
                .frame(minHeight: toolMetrics.formControlHeight)
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private func loadFromStore() {
        if let editingRule = store.editingRule {
            let decoded = AddBreakpointRuleSheet.decode(rule: editingRule)
            ruleName = editingRule.name
            urlPattern = decoded.displayPattern
            httpMethod = decoded.httpMethod
            matchType = decoded.matchType
            includeSubpaths = decoded.includeSubpaths
            breakpointRequest = decoded.breakpointRequest
            breakpointResponse = decoded.breakpointResponse
        } else if let context = store.editorContext {
            ruleName = context.suggestedName.isEmpty ? "Untitled" : context.suggestedName
            urlPattern = context.defaultPattern
            httpMethod = context.httpMethod
            matchType = context.defaultMatchType
            includeSubpaths = context.includeSubpaths
            breakpointRequest = context.breakpointRequest
            breakpointResponse = context.breakpointResponse
        } else {
            ruleName = "Untitled"
            urlPattern = ""
            httpMethod = .any
            matchType = .wildcard
            includeSubpaths = true
            breakpointRequest = true
            breakpointResponse = true
        }
    }
}
