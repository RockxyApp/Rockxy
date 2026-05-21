import os
import SwiftUI

// Dedicated window for managing Modify Header rules. Displays a table of all
// modifyHeader rules with enable toggles, URL patterns, operation counts, phase
// summary, and operation shorthand. Supports add/edit/delete with a modal sheet.

// MARK: - ModifyHeaderEditorSession

struct ModifyHeaderEditorSession: Identifiable {
    enum Mode {
        case create
        case edit(rule: ProxyRule)
    }

    let id = UUID()
    let mode: Mode
}

// MARK: - ModifyHeaderWindowViewModel

@MainActor @Observable
final class ModifyHeaderWindowViewModel {
    // MARK: Internal

    private(set) var allRules: [ProxyRule] = []
    var selectedRuleID: UUID?
    var editorSession: ModifyHeaderEditorSession?
    var searchText = ""

    var modifyHeaderRules: [ProxyRule] {
        let headerRules = allRules.filter { rule in
            if case .modifyHeader = rule.action {
                return true
            }
            return false
        }
        guard !searchText.isEmpty else {
            return headerRules
        }
        return headerRules.filter { rule in
            rule.name.localizedCaseInsensitiveContains(searchText)
                || (rule.matchCondition.urlPattern ?? "").localizedCaseInsensitiveContains(searchText)
                || operationSummary(for: rule).localizedCaseInsensitiveContains(searchText)
        }
    }

    var ruleCount: Int {
        modifyHeaderRules.count
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
        }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        Task {
            let accepted = await RulePolicyGate.shared.toggleRule(id: id)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    func presentNewRuleEditor() {
        editorSession = ModifyHeaderEditorSession(mode: .create)
    }

    func presentEditorForSelection() {
        guard let id = selectedRuleID,
              let rule = allRules.first(where: { $0.id == id }) else
        {
            return
        }
        editorSession = ModifyHeaderEditorSession(mode: .edit(rule: rule))
    }

    func dismissEditor() {
        editorSession = nil
    }

    @discardableResult
    func addRule(_ rule: ProxyRule) async -> Bool {
        let accepted = await RulePolicyGate.shared.addRule(rule)
        allRules = await RuleEngine.shared.allRules
        if accepted {
            selectedRuleID = rule.id
        }
        return accepted
    }

    @discardableResult
    func updateRule(_ rule: ProxyRule) async -> Bool {
        guard allRules.contains(where: { $0.id == rule.id }) else {
            return false
        }
        await RulePolicyGate.shared.updateRule(rule)
        allRules = await RuleEngine.shared.allRules
        selectedRuleID = rule.id
        return true
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = nil
        }
        Task { await RulePolicyGate.shared.removeRule(id: id) }
    }

    @discardableResult
    func saveRule(
        existingRule: ProxyRule?,
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        includeSubpaths: Bool,
        operations: [EditableHeaderOperation]
    )
        async -> Bool
    {
        let rule = ModifyHeaderRuleBuilder.build(
            existingRule: existingRule,
            ruleName: ruleName,
            rawPattern: urlPattern,
            httpMethod: httpMethod,
            matchType: matchType,
            includeSubpaths: includeSubpaths,
            operations: operations.toHeaderOperations()
        )
        if existingRule == nil {
            return await addRule(rule)
        }
        return await updateRule(rule)
    }

    func operations(for rule: ProxyRule) -> [HeaderOperation] {
        if case let .modifyHeader(ops) = rule.action {
            return ops
        }
        return []
    }

    func operationCount(for rule: ProxyRule) -> Int {
        operations(for: rule).count
    }

    func phaseSummary(for rule: ProxyRule) -> String {
        operations(for: rule).phaseSummaryLabel
    }

    func operationSummary(for rule: ProxyRule) -> String {
        operations(for: rule).operationSummary
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ModifyHeaderWindowViewModel"
    )
}

// MARK: - ModifyHeaderWindowView

struct ModifyHeaderWindowView: View {
    // MARK: Internal

    @State var viewModel = ModifyHeaderWindowViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            infoBanner
            Divider()
            content
            Divider()
            bottomBar
        }
        .frame(width: 860, height: 620)
        .task { await viewModel.refreshFromEngine() }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(item: $viewModel.editorSession) { session in
            ModifyHeaderEditSheet(session: session) { name, pattern, method, matchType, includeSubpaths, operations in
                let existingRule: ProxyRule? = if case let .edit(rule) = session.mode {
                    rule
                } else {
                    nil
                }
                let accepted = await viewModel.saveRule(
                    existingRule: existingRule,
                    ruleName: name,
                    urlPattern: pattern,
                    httpMethod: method,
                    matchType: matchType,
                    includeSubpaths: includeSubpaths,
                    operations: operations
                )
                if accepted {
                    viewModel.dismissEditor()
                }
            }
        }
    }

    // MARK: Private

    private var toolbar: some View {
        HStack {
            Text(String(localized: "Modify Headers"))
                .font(.headline)
            Spacer()
            TextField(String(localized: "Search"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        if viewModel.modifyHeaderRules.isEmpty {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "list.bullet.header")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text(String(localized: "No Modify Header Rules"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Add rules to modify HTTP request and response headers."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 12)
        } else {
            VStack(spacing: 0) {
                columnHeader
                Divider()
                List(selection: $viewModel.selectedRuleID) {
                    ForEach(viewModel.modifyHeaderRules) { rule in
                        ModifyHeaderRuleRow(
                            rule: rule,
                            operationCount: viewModel.operationCount(for: rule),
                            phaseSummary: viewModel.phaseSummary(for: rule),
                            operationSummary: viewModel.operationSummary(for: rule)
                        ) {
                            viewModel.toggleRule(id: rule.id)
                        }
                        .tag(rule.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: UUID.self) { _ in
                    contextMenuItems
                } primaryAction: { _ in
                    viewModel.presentEditorForSelection()
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 24)
            Text(String(localized: "Name"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)
            Text(String(localized: "Method"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(String(localized: "Matching Rule"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "Ops"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
            Text(String(localized: "Phase"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(String(localized: "Summary"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.background.tertiary)
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized: "Set, add, or remove HTTP headers on matching requests and responses. Each rule can have multiple header operations."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.presentNewRuleEditor()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "New Rule"))

            Button {
                guard let id = viewModel.selectedRuleID else {
                    return
                }
                viewModel.removeRule(id: id)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
            .help(String(localized: "Delete Rule"))

            Divider()
                .frame(height: 16)

            Text(
                "\(viewModel.ruleCount) \(viewModel.ruleCount == 1 ? String(localized: "rule") : String(localized: "rules"))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            presetsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var contextMenuItems: some View {
        Button(String(localized: "Edit…")) {
            viewModel.presentEditorForSelection()
        }
        .keyboardShortcut("e", modifiers: .command)

        Divider()

        Button(String(localized: "Delete"), role: .destructive) {
            if let id = viewModel.selectedRuleID {
                viewModel.removeRule(id: id)
            }
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private var presetsMenu: some View {
        Menu {
            Button(String(localized: "Add CORS Headers")) {
                Task { await viewModel.addRule(HeaderModifyPresets.corsHeaders()) }
            }
            Button(String(localized: "Remove Authorization")) {
                Task { await viewModel.addRule(HeaderModifyPresets.removeAuthorization()) }
            }
            Button(String(localized: "Strip Server Header")) {
                Task { await viewModel.addRule(HeaderModifyPresets.stripServerHeader()) }
            }
        } label: {
            Text(String(localized: "Presets"))
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - ModifyHeaderRuleRow

private struct ModifyHeaderRuleRow: View {
    let rule: ProxyRule
    let operationCount: Int
    let phaseSummary: String
    let operationSummary: String
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            Text(rule.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 190, alignment: .leading)

            Text(rule.matchCondition.method ?? "ANY")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(rule.matchCondition.urlPattern ?? ".*")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(rule.matchCondition.urlPattern ?? ".*")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(operationCount)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)

            Text(phaseSummary)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.12))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(width: 72, alignment: .leading)

            Text(operationSummary)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(operationSummary)
                .frame(width: 150, alignment: .leading)
        }
        .padding(.vertical, 2)
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - ModifyHeaderEditSheet

private struct ModifyHeaderEditSheet: View {
    // MARK: Lifecycle

    init(
        session: ModifyHeaderEditorSession,
        onSave: @escaping (String, String, HTTPMethodFilter, RuleMatchType, Bool, [EditableHeaderOperation]) async -> Void
    ) {
        self.session = session
        self.onSave = onSave

        switch session.mode {
        case .create:
            _name = State(initialValue: "")
            _urlPattern = State(initialValue: "*")
            _httpMethod = State(initialValue: .any)
            _matchType = State(initialValue: .wildcard)
            _includeSubpaths = State(initialValue: true)
            _operations = State(initialValue: [EditableHeaderOperation()])
        case let .edit(rule):
            _name = State(initialValue: rule.name)
            _urlPattern = State(initialValue: rule.matchCondition.urlPattern ?? ".*")
            let normalizedMethod = rule.matchCondition.method?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            _httpMethod = State(
                initialValue: normalizedMethod.flatMap(HTTPMethodFilter.init(rawValue:)) ?? .any
            )
            _matchType = State(initialValue: .regex)
            _includeSubpaths = State(initialValue: false)
            if case let .modifyHeader(ops) = rule.action {
                _operations = State(initialValue: [EditableHeaderOperation].from(ops))
            } else {
                _operations = State(initialValue: [EditableHeaderOperation()])
            }
        }
    }

    // MARK: Internal

    let session: ModifyHeaderEditorSession
    let onSave: (String, String, HTTPMethodFilter, RuleMatchType, Bool, [EditableHeaderOperation]) async -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                formRow(String(localized: "Name:")) {
                    TextField("", text: $name, prompt: Text(String(localized: "Untitled")))
                        .textFieldStyle(.roundedBorder)
                }

                formRow(String(localized: "Matching Rule:")) {
                    TextField("", text: $urlPattern, prompt: Text("https://example.com/api/*"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                methodAndMatchRow

                conditionalFields

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Header Operations"))
                        .font(.system(size: 13, weight: .medium))
                    ScrollView {
                        ModifyHeaderEditorView(operations: $operations)
                            .padding(10)
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .frame(maxHeight: 300)
                }
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
                    Task {
                        isSaving = true
                        await onSave(
                            trimmedName,
                            trimmedPattern,
                            httpMethod,
                            matchType,
                            matchType == .wildcard ? includeSubpaths : false,
                            operations
                        )
                        isSaving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    private static let labelWidth: CGFloat = 110

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlPattern = ""
    @State private var httpMethod: HTTPMethodFilter
    @State private var matchType: RuleMatchType
    @State private var includeSubpaths: Bool
    @State private var operations: [EditableHeaderOperation] = [EditableHeaderOperation()]
    @State private var isSaving = false

    private var isEditing: Bool {
        if case .edit = session.mode {
            return true
        }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPattern: String {
        urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedPattern.isEmpty
            && !operations.isEmpty
            && operations.allSatisfy(\.isValid)
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
