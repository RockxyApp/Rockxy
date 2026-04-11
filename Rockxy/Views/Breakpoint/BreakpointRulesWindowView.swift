import os
import SwiftUI

// Presents the breakpoint rules window for rule management.

// MARK: - BreakpointRulesViewModel

@MainActor @Observable
final class BreakpointRulesViewModel {
    // MARK: Internal

    var selectedRuleID: UUID?
    var showAddSheet = false
    var editingRule: ProxyRule?
    var pendingContext: BreakpointEditorContext?
    private(set) var allRules: [ProxyRule] = []

    var isFilterBarVisible = false
    var filterColumn: BreakpointFilterColumn = .name
    var filterText = ""

    var isBreakpointToolEnabled: Bool = UserDefaults.standard.object(
        forKey: "breakpointToolEnabled"
    ) as? Bool ?? true

    var breakpointRules: [ProxyRule] {
        allRules.filter { rule in
            if case .breakpoint = rule.action {
                return true
            }
            return false
        }
    }

    var filteredBreakpointRules: [ProxyRule] {
        guard !filterText.isEmpty else {
            return breakpointRules
        }
        return breakpointRules.filter { rule in
            switch filterColumn {
            case .name:
                rule.name.localizedCaseInsensitiveContains(filterText)
            case .matchingRule:
                (rule.matchCondition.urlPattern ?? "").localizedCaseInsensitiveContains(filterText)
            case .method:
                (rule.matchCondition.method ?? "ANY").localizedCaseInsensitiveContains(filterText)
            }
        }
    }

    var ruleCount: Int {
        breakpointRules.count
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
            if let selected = selectedRuleID,
               !breakpointRules.contains(where: { $0.id == selected })
            {
                selectedRuleID = nil
            }
        }
    }

    func addBreakpointRule(
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        phaseRequest: Bool,
        phaseResponse: Bool,
        includeSubpaths: Bool
    ) {
        let rule = ProxyRule(
            name: ruleName.isEmpty ? urlPattern : ruleName,
            matchCondition: RuleMatchCondition(
                urlPattern: Self.compilePattern(
                    urlPattern: urlPattern,
                    matchType: matchType,
                    includeSubpaths: includeSubpaths
                ),
                method: httpMethod.methodValue
            ),
            action: .breakpoint(phase: Self.phase(request: phaseRequest, response: phaseResponse))
        )
        allRules.append(rule)
        selectedRuleID = rule.id
        Task { await RuleSyncService.addRule(rule) }
    }

    func updateRule(
        id: UUID,
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        phaseRequest: Bool,
        phaseResponse: Bool,
        includeSubpaths: Bool
    ) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        var rule = allRules[index]
        rule.name = ruleName.isEmpty ? urlPattern : ruleName
        rule.matchCondition = RuleMatchCondition(
            urlPattern: Self.compilePattern(
                urlPattern: urlPattern,
                matchType: matchType,
                includeSubpaths: includeSubpaths
            ),
            method: httpMethod.methodValue,
            headerName: rule.matchCondition.headerName,
            headerValue: rule.matchCondition.headerValue
        )
        rule.action = .breakpoint(phase: Self.phase(request: phaseRequest, response: phaseResponse))
        allRules[index] = rule
        selectedRuleID = rule.id
        let snapshot = rule
        Task { await RuleSyncService.updateRule(snapshot) }
    }

    func removeSelected() {
        guard let id = selectedRuleID else {
            return
        }
        allRules.removeAll { $0.id == id }
        selectedRuleID = nil
        Task { await RuleSyncService.removeRule(id: id) }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        Task { await RuleSyncService.toggleRule(id: id) }
    }

    func duplicateRule(id: UUID) {
        guard let original = breakpointRules.first(where: { $0.id == id }) else {
            return
        }
        let copy = ProxyRule(
            name: String(localized: "Copy of \(original.name)"),
            isEnabled: original.isEnabled,
            matchCondition: original.matchCondition,
            action: original.action,
            priority: original.priority
        )
        allRules.append(copy)
        selectedRuleID = copy.id
        Task { await RuleSyncService.addRule(copy) }
    }

    func toggleBreakpointTool() {
        isBreakpointToolEnabled.toggle()
        Task { await RuleSyncService.setBreakpointToolEnabled(isBreakpointToolEnabled) }
    }

    // MARK: Private

    private static func compilePattern(
        urlPattern: String,
        matchType: RuleMatchType,
        includeSubpaths: Bool
    )
        -> String
    {
        switch matchType {
        case .wildcard:
            var pattern = NSRegularExpression.escapedPattern(for: urlPattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            if includeSubpaths {
                if !pattern.hasSuffix(".*") {
                    pattern += ".*"
                }
            } else {
                pattern += "($|[?#])"
            }
            return pattern
        case .regex:
            return urlPattern
        }
    }

    private static func phase(request: Bool, response: Bool) -> BreakpointRulePhase {
        switch (request, response) {
        case (true, true): .both
        case (true, false): .request
        case (false, true): .response
        default: .both
        }
    }
}

// MARK: - BreakpointRulesWindowView

struct BreakpointRulesWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            infoBanner
            Divider()
            content
            if viewModel.isFilterBarVisible {
                Divider()
                BreakpointFilterBar(
                    filterColumn: $viewModel.filterColumn,
                    filterText: $viewModel.filterText,
                    onDismiss: hideFilterBar
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            bottomBar
        }
        .frame(width: 860, height: 620)
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingContext() }
        .onReceive(NotificationCenter.default.publisher(for: .openBreakpointRulesWindow)) { _ in
            consumePendingContext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            viewModel.pendingContext = nil
            viewModel.editingRule = nil
        } content: {
            AddBreakpointRuleSheet(
                editorContext: viewModel.editingRule == nil ? viewModel.pendingContext : nil,
                editingRule: viewModel.editingRule
            ) { name, pattern, method, matchType, phaseReq, phaseRes, includeSubpaths in
                if let editing = viewModel.editingRule {
                    viewModel.updateRule(
                        id: editing.id,
                        ruleName: name,
                        urlPattern: pattern,
                        httpMethod: method,
                        matchType: matchType,
                        phaseRequest: phaseReq,
                        phaseResponse: phaseRes,
                        includeSubpaths: includeSubpaths
                    )
                } else {
                    viewModel.addBreakpointRule(
                        ruleName: name,
                        urlPattern: pattern,
                        httpMethod: method,
                        matchType: matchType,
                        phaseRequest: phaseReq,
                        phaseResponse: phaseRes,
                        includeSubpaths: includeSubpaths
                    )
                }
                viewModel.pendingContext = nil
                viewModel.editingRule = nil
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFilterBarVisible)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "BreakpointRulesWindowView"
    )

    @State private var viewModel = BreakpointRulesViewModel()

    private var enableDisableLabel: String {
        guard let id = viewModel.selectedRuleID,
              let rule = viewModel.breakpointRules.first(where: { $0.id == id }) else
        {
            return String(localized: "Enable Rule")
        }
        return rule.isEnabled
            ? String(localized: "Disable Rule")
            : String(localized: "Enable Rule")
    }

    private var toolbar: some View {
        HStack {
            Text(String(localized: "Breakpoint Rules"))
                .font(.headline)
            Spacer()
            Toggle(
                String(localized: "Enable Breakpoint Tool"),
                isOn: Binding(
                    get: { viewModel.isBreakpointToolEnabled },
                    set: { _ in viewModel.toggleBreakpointTool() }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized:
                    "Modify the Request/Response on the fly. Each request is checked against the rules from top to bottom, stopping when a match is found."
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

    @ViewBuilder private var content: some View {
        if viewModel.breakpointRules.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                columnHeader
                Divider()
                List(selection: $viewModel.selectedRuleID) {
                    ForEach(viewModel.filteredBreakpointRules) { rule in
                        BreakpointRulesRow(rule: rule) {
                            viewModel.toggleRule(id: rule.id)
                        }
                        .tag(rule.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 24)
            Text(String(localized: "Name"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)
            Text(String(localized: "Method"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(String(localized: "Matching Rule"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "Request"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60)
            Text(String(localized: "Response"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.background.tertiary)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "pause.circle")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(String(localized: "No Breakpoint Rules"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(String(localized: "Add URL patterns to pause matching requests for inspection."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)

            Button {
                viewModel.removeSelected()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedRuleID == nil)

            Divider()
                .frame(height: 16)

            Text(
                "\(viewModel.ruleCount) \(viewModel.ruleCount == 1 ? String(localized: "rule") : String(localized: "rules"))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                showFilterBar()
            } label: {
                Label(String(localized: "Filter"), systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("f", modifiers: .command)

            moreMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New Rule...")) {
                viewModel.showAddSheet = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button(String(localized: "Edit")) {
                if let id = viewModel.selectedRuleID,
                   let rule = viewModel.breakpointRules.first(where: { $0.id == id })
                {
                    viewModel.editingRule = rule
                    viewModel.showAddSheet = true
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)

            Button(String(localized: "Duplicate")) {
                if let id = viewModel.selectedRuleID {
                    viewModel.duplicateRule(id: id)
                }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)

            Button(enableDisableLabel) {
                if let id = viewModel.selectedRuleID {
                    viewModel.toggleRule(id: id)
                }
            }
            .disabled(viewModel.selectedRuleID == nil)

            Divider()

            Button(String(localized: "Delete"), role: .destructive) {
                viewModel.removeSelected()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
        } label: {
            Text(String(localized: "More"))
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .menuStyle(.borderlessButton)
    }

    private func showFilterBar() {
        viewModel.isFilterBarVisible = true
    }

    private func hideFilterBar() {
        viewModel.isFilterBarVisible = false
        viewModel.filterText = ""
    }

    private func consumePendingContext() {
        guard let context = BreakpointEditorContextStore.shared.consumePending() else {
            return
        }
        viewModel.pendingContext = context
        viewModel.showAddSheet = true
    }
}

// MARK: - BreakpointRulesRow

private struct BreakpointRulesRow: View {
    // MARK: Internal

    let rule: ProxyRule
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
                .frame(width: 180, alignment: .leading)

            Text(rule.matchCondition.method ?? "ANY")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(rule.matchCondition.urlPattern ?? "")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            requestBadge
                .frame(width: 60)
            responseBadge
                .frame(width: 60)
        }
        .padding(.vertical, 2)
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }

    // MARK: Private

    @ViewBuilder private var requestBadge: some View {
        if case let .breakpoint(phase) = rule.action,
           phase == .request || phase == .both
        {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
                .font(.caption)
        }
    }

    @ViewBuilder private var responseBadge: some View {
        if case let .breakpoint(phase) = rule.action,
           phase == .response || phase == .both
        {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
                .font(.caption)
        }
    }
}
