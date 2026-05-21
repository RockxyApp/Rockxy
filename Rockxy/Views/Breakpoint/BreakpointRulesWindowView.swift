import os
import SwiftUI

// Presents the breakpoint rules window for rule management.

// MARK: - BreakpointRulesViewModel

@MainActor @Observable
final class BreakpointRulesViewModel {
    // MARK: Lifecycle

    init(syncsChanges: Bool = !RockxyIdentity.isRunningTests) {
        self.syncsChanges = syncsChanges
    }

    // MARK: Internal

    var selectedRuleID: UUID?
    private(set) var allRules: [ProxyRule] = []

    var isFilterBarVisible = false
    var filterColumn: BreakpointFilterColumn = .name
    var filterText = ""
    var alertMessage: String?

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

    var selectedRule: ProxyRule? {
        guard let id = selectedRuleID else {
            return nil
        }
        return breakpointRules.first { $0.id == id }
    }

    func refreshFromEngine() async {
        if await RuleEngine.shared.allRules.isEmpty {
            await RuleSyncService.loadFromDisk()
        }
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
                method: httpMethod.methodValue,
                matchType: matchType,
                includeSubpaths: includeSubpaths
            ),
            action: .breakpoint(phase: Self.phase(request: phaseRequest, response: phaseResponse))
        )
        allRules.append(rule)
        selectedRuleID = rule.id
        guard syncsChanges else {
            return
        }
        Task {
            let accepted = await RulePolicyGate.shared.addRule(rule)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
                if !allRules.contains(where: { $0.id == rule.id }) {
                    selectedRuleID = nil
                }
            }
        }
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
            headerValue: rule.matchCondition.headerValue,
            matchType: matchType,
            includeSubpaths: includeSubpaths
        )
        rule.action = .breakpoint(phase: Self.phase(request: phaseRequest, response: phaseResponse))
        allRules[index] = rule
        selectedRuleID = rule.id
        let snapshot = rule
        guard syncsChanges else {
            return
        }
        Task { await RulePolicyGate.shared.updateRule(snapshot) }
    }

    func removeSelected() {
        guard let id = selectedRuleID else {
            return
        }
        allRules.removeAll { $0.id == id }
        selectedRuleID = nil
        guard syncsChanges else {
            return
        }
        Task { await RulePolicyGate.shared.removeRule(id: id) }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        guard syncsChanges else {
            return
        }
        Task {
            let accepted = await RulePolicyGate.shared.toggleRule(id: id)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
            }
        }
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
        guard syncsChanges else {
            return
        }
        Task {
            let accepted = await RulePolicyGate.shared.addRule(copy)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
                if !allRules.contains(where: { $0.id == copy.id }) {
                    selectedRuleID = nil
                }
            }
        }
    }

    func toggleBreakpointTool() {
        isBreakpointToolEnabled.toggle()
        Task { await RulePolicyGate.shared.setBreakpointToolEnabled(isBreakpointToolEnabled) }
    }

    func setBreakpointToolEnabled(_ enabled: Bool) {
        isBreakpointToolEnabled = enabled
        Task { await RulePolicyGate.shared.setBreakpointToolEnabled(enabled) }
    }

    func methodLabel(for rule: ProxyRule) -> String {
        rule.matchCondition.method?.uppercased() ?? "ANY"
    }

    func matchingRuleLabel(for rule: ProxyRule) -> String {
        let decoded = AddBreakpointRuleSheet.decode(rule: rule)
        switch decoded.matchType {
        case .wildcard:
            return "Wildcard: \(decoded.displayPattern)"
        case .regex:
            return "Regex: \(rule.matchCondition.urlPattern ?? "")"
        }
    }

    func breaksOnRequest(_ rule: ProxyRule) -> Bool {
        guard case let .breakpoint(phase) = rule.action else {
            return false
        }
        return phase == .request || phase == .both
    }

    func breaksOnResponse(_ rule: ProxyRule) -> Bool {
        guard case let .breakpoint(phase) = rule.action else {
            return false
        }
        return phase == .response || phase == .both
    }

    // MARK: Private

    private let syncsChanges: Bool

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
        VStack(alignment: .leading, spacing: 0) {
            header
            tableContent
            shortcutStrip
            bottomBar
        }
        .frame(width: 1_200, height: 675)
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingContext() }
        .onReceive(NotificationCenter.default.publisher(for: .openBreakpointRulesWindow)) { _ in
            consumePendingContext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .alert(
            String(localized: "Breakpoint Rules"),
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            )
        ) {
            Button(String(localized: "OK")) { viewModel.alertMessage = nil }
        } message: {
            if let message = viewModel.alertMessage {
                Text(message)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFilterBarVisible)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "BreakpointRulesWindowView"
    )

    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = BreakpointRulesViewModel()

    private var enableDisableLabel: String {
        guard let rule = viewModel.selectedRule else {
            return String(localized: "Enable Rule")
        }
        return rule.isEnabled
            ? String(localized: "Disable Rule")
            : String(localized: "Enable Rule")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { viewModel.isBreakpointToolEnabled },
                set: { viewModel.setBreakpointToolEnabled($0) }
            )) {
                Text(String(localized: "Enable Breakpoint Tool"))
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .padding(.top, 16)

            Text(String(localized: "Modify the Request/Response on the fly. Support URL, Method, Status Code, Headers, and Body."))
                .font(.system(size: 13))
            Text(String(localized: "Each request is checked against the rules from top to bottom, stopping when a match is found."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if viewModel.isFilterBarVisible {
                BreakpointFilterBar(
                    filterColumn: $viewModel.filterColumn,
                    filterText: $viewModel.filterText,
                    onDismiss: hideFilterBar
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }

    private var tableContent: some View {
        Table(viewModel.filteredBreakpointRules, selection: $viewModel.selectedRuleID) {
            TableColumn(String(localized: "Name")) { rule in
                HStack(spacing: 7) {
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { _ in viewModel.toggleRule(id: rule.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    Text(rule.name.isEmpty ? String(localized: "Untitled") : rule.name)
                        .lineLimit(1)
                }
                .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 190, ideal: 240)

            TableColumn(String(localized: "Method")) { rule in
                Text(viewModel.methodLabel(for: rule))
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(86)

            TableColumn(String(localized: "Matching Rule")) { rule in
                Text(viewModel.matchingRuleLabel(for: rule))
                    .lineLimit(1)
                    .help(viewModel.matchingRuleLabel(for: rule))
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 420, ideal: 520)

            TableColumn(String(localized: "Request")) { rule in
                phaseIndicator(isActive: viewModel.breaksOnRequest(rule))
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(78)

            TableColumn(String(localized: "Response")) { rule in
                phaseIndicator(isActive: viewModel.breaksOnResponse(rule))
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(86)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            tableContextMenu(ids: ids)
        } primaryAction: { ids in
            guard let id = ids.first,
                  let rule = viewModel.breakpointRules.first(where: { $0.id == id }) else
            {
                return
            }
            openEditor(for: rule)
        }
        .overlay {
            if viewModel.filteredBreakpointRules.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Breakpoint Rules"),
                    systemImage: "pause.circle",
                    description: Text(String(localized: "Click + or create a rule from a captured request."))
                )
            }
        }
        .padding(.horizontal, 22)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Button {
                    openNewEditor()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1, height: 18)

                Button {
                    viewModel.removeSelected()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selectedRuleID == nil)
            }
            .foregroundStyle(.primary)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .frame(width: 37, height: 19)

            Button(String(localized: "New Folder")) {}
                .disabled(true)
                .help(String(localized: "Breakpoint folders are not supported yet."))

            Button {
                viewModel.alertMessage = String(
                    localized: "Breakpoint rules pause matching traffic so requests or responses can be inspected and modified before forwarding."
                )
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                withAnimation {
                    viewModel.isFilterBarVisible.toggle()
                }
            } label: {
                Label(String(localized: "Filter"), systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(String(localized: "Templates...")) {
                openWindow(id: "breakpointTemplates")
            }
            .keyboardShortcut("t", modifiers: .command)

            moreMenu
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .padding(.top, 8)
    }

    private var shortcutStrip: some View {
        Text("New: ⌘N    Edit: ⌘↵    Delete: ⌘⌫    Duplicate: ⌘D    Toggle: ↵")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New")) {
                openNewEditor()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(String(localized: "Edit")) {
                if let rule = viewModel.selectedRule {
                    openEditor(for: rule)
                }
            }
            .keyboardShortcut("e", modifiers: .command)
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
            .keyboardShortcut(.return, modifiers: [])
            .disabled(viewModel.selectedRuleID == nil)

            Button(enableDisableLabel) {
                if let id = viewModel.selectedRuleID {
                    viewModel.toggleRule(id: id)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(viewModel.selectedRuleID == nil)

            Divider()

            Button(String(localized: "Delete"), role: .destructive) {
                viewModel.removeSelected()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More"))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    private func hideFilterBar() {
        viewModel.isFilterBarVisible = false
        viewModel.filterText = ""
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first {
            Button(String(localized: "Edit Rule")) {
                if let rule = viewModel.breakpointRules.first(where: { $0.id == id }) {
                    openEditor(for: rule)
                }
            }
            Button(String(localized: "Duplicate")) {
                viewModel.selectedRuleID = id
                viewModel.duplicateRule(id: id)
            }
            Divider()
            Button(String(localized: "Delete Rule"), role: .destructive) {
                viewModel.selectedRuleID = id
                viewModel.removeSelected()
            }
        }
    }

    private func phaseIndicator(isActive: Bool) -> some View {
        HStack {
            Spacer()
            Image(systemName: isActive ? "checkmark.square.fill" : "square")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            Spacer()
        }
    }

    private func openNewEditor(context: BreakpointEditorContext? = nil) {
        BreakpointRuleEditorStore.shared.openNew(context: context) { name, pattern, method, matchType, phaseReq, phaseRes, includeSubpaths in
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
        openWindow(id: "breakpointRuleEditor")
    }

    private func openEditor(for rule: ProxyRule) {
        BreakpointRuleEditorStore.shared.openExisting(rule) { name, pattern, method, matchType, phaseReq, phaseRes, includeSubpaths in
            viewModel.updateRule(
                id: rule.id,
                ruleName: name,
                urlPattern: pattern,
                httpMethod: method,
                matchType: matchType,
                phaseRequest: phaseReq,
                phaseResponse: phaseRes,
                includeSubpaths: includeSubpaths
            )
        }
        openWindow(id: "breakpointRuleEditor")
    }

    private func consumePendingContext() {
        guard let context = BreakpointEditorContextStore.shared.consumePending() else {
            return
        }
        openNewEditor(context: context)
    }
}
