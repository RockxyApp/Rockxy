import os
import SwiftUI

// Dedicated window for managing Modify Header rules. Displays a table of all
// modifyHeader rules with enable toggles, URL patterns, operation counts, phase
// summary, and operation shorthand. Supports add/edit/delete with a modal sheet.

// MARK: - ModifyHeaderWindowViewModel

@MainActor @Observable
final class ModifyHeaderWindowViewModel {
    // MARK: Internal

    private(set) var allRules: [ProxyRule] = []
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
        Task { await RuleSyncService.toggleRule(id: id) }
    }

    func addRule(_ rule: ProxyRule) {
        allRules.append(rule)
        Task { await RuleSyncService.addRule(rule) }
    }

    func updateRule(_ rule: ProxyRule) {
        guard let index = allRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        allRules[index] = rule
        Task { await RuleSyncService.updateRule(rule) }
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        Task { await RuleSyncService.removeRule(id: id) }
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

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ModifyHeaderWindowViewModel")
}

// MARK: - ModifyHeaderWindowView

struct ModifyHeaderWindowView: View {
    // MARK: Internal

    @State var viewModel = ModifyHeaderWindowViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.modifyHeaderRules.isEmpty {
                infoBar
                Divider()
            }
            tableContent
            Divider()
            bottomBar
        }
        .frame(width: 780, height: 480)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    editingRule = nil
                    showEditSheet = true
                } label: {
                    Label(String(localized: "Add Rule"), systemImage: "plus")
                }

                TextField(String(localized: "Search"), text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
        }
        .task { await viewModel.refreshFromEngine() }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(isPresented: $showEditSheet) {
            ModifyHeaderEditSheet(existingRule: editingRule) { rule in
                if editingRule != nil {
                    viewModel.updateRule(rule)
                } else {
                    viewModel.addRule(rule)
                }
            }
        }
    }

    // MARK: Private

    @State private var selectedRuleID: UUID?
    @State private var showEditSheet = false
    @State private var editingRule: ProxyRule?

    @ViewBuilder private var tableContent: some View {
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
        } else {
            Table(viewModel.modifyHeaderRules, selection: $selectedRuleID) {
                TableColumn("") { rule in
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { _ in viewModel.toggleRule(id: rule.id) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .width(40)

                TableColumn(String(localized: "Name")) { rule in
                    Text(rule.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .opacity(rule.isEnabled ? 1.0 : 0.5)
                }
                .width(min: 100, ideal: 120)

                TableColumn(String(localized: "URL Pattern")) { rule in
                    Text(rule.matchCondition.urlPattern ?? "*")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .help(rule.matchCondition.urlPattern ?? "*")
                        .opacity(rule.isEnabled ? 1.0 : 0.5)
                }
                .width(min: 140, ideal: 180)

                TableColumn(String(localized: "Ops")) { rule in
                    Text("\(viewModel.operationCount(for: rule))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(40)

                TableColumn(String(localized: "Phase")) { rule in
                    Text(viewModel.phaseSummary(for: rule))
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.12))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .width(60)

                TableColumn(String(localized: "Summary")) { rule in
                    Text(viewModel.operationSummary(for: rule))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(viewModel.operationSummary(for: rule))
                        .opacity(rule.isEnabled ? 1.0 : 0.5)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    Button(String(localized: "Edit")) {
                        editingRule = viewModel.allRules.first { $0.id == id }
                        showEditSheet = true
                    }
                    Divider()
                    Button(String(localized: "Delete"), role: .destructive) {
                        viewModel.removeRule(id: id)
                        selectedRuleID = nil
                    }
                }
            }
        }
    }

    private var infoBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized: "Add, remove, or replace HTTP headers on matching requests and responses. Each rule can have multiple header operations."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                editingRule = nil
                showEditSheet = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)

            Button {
                guard let id = selectedRuleID else {
                    return
                }
                viewModel.removeRule(id: id)
                selectedRuleID = nil
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(selectedRuleID == nil)

            Spacer()

            Menu(String(localized: "Presets")) {
                Button(String(localized: "Add CORS Headers")) {
                    viewModel.addRule(HeaderModifyPresets.corsHeaders())
                }
                Button(String(localized: "Remove Authorization")) {
                    viewModel.addRule(HeaderModifyPresets.removeAuthorization())
                }
                Button(String(localized: "Strip Server Header")) {
                    viewModel.addRule(HeaderModifyPresets.stripServerHeader())
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()

            Text(
                "\(viewModel.ruleCount) \(viewModel.ruleCount == 1 ? String(localized: "rule") : String(localized: "rules"))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - ModifyHeaderEditSheet

private struct ModifyHeaderEditSheet: View {
    // MARK: Lifecycle

    init(existingRule: ProxyRule?, onSave: @escaping (ProxyRule) -> Void) {
        self.existingRule = existingRule
        self.onSave = onSave

        if let rule = existingRule {
            _name = State(initialValue: rule.name)
            _urlPattern = State(initialValue: rule.matchCondition.urlPattern ?? "")
            _method = State(initialValue: rule.matchCondition.method ?? "")
            if case let .modifyHeader(ops) = rule.action {
                _operations = State(initialValue: [EditableHeaderOperation].from(ops))
            }
        }
    }

    // MARK: Internal

    let existingRule: ProxyRule?
    let onSave: (ProxyRule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(String(localized: "Rule Info")) {
                    TextField(String(localized: "Name"), text: $name)
                }

                Section(String(localized: "Match Condition")) {
                    TextField(String(localized: "URL Pattern (regex)"), text: $urlPattern)
                        .font(.system(.body, design: .monospaced))
                    TextField(String(localized: "HTTP Method"), text: $method)
                        .textCase(.uppercase)
                }

                Section(String(localized: "Header Operations")) {
                    ModifyHeaderEditorView(operations: $operations)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(existingRule != nil ? String(localized: "Save") : String(localized: "Add Rule")) {
                    saveRule()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 560, height: 480)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlPattern = ""
    @State private var method = ""
    @State private var operations: [EditableHeaderOperation] = [EditableHeaderOperation()]

    private var isValid: Bool {
        !name.isEmpty
            && !operations.isEmpty
            && operations.allSatisfy(\.isValid)
    }

    private func saveRule() {
        let condition = RuleMatchCondition(
            urlPattern: urlPattern.isEmpty ? nil : urlPattern,
            method: method.isEmpty ? nil : method.uppercased()
        )
        let action = RuleAction.modifyHeader(operations: operations.toHeaderOperations())
        let rule = ProxyRule(
            id: existingRule?.id ?? UUID(),
            name: name,
            isEnabled: existingRule?.isEnabled ?? true,
            matchCondition: condition,
            action: action,
            priority: existingRule?.priority ?? 0
        )
        onSave(rule)
        dismiss()
    }
}
