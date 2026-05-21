import AppKit
import os
import SwiftUI

// Presents the network conditions window for rule editing and management.

// MARK: - NetworkConditionProfileMetadata

struct NetworkConditionProfileMetadata: Equatable {
    let name: String
    let latencyMs: Int
    let downloadBandwidth: String
    let uploadBandwidth: String
    let packetLoss: String
    let systemImage: String

    static func from(preset: NetworkConditionPreset, latencyMs: Int) -> Self {
        let effectiveLatency = latencyMs > 0 ? latencyMs : preset.defaultLatencyMs
        return Self(
            name: preset.displayName,
            latencyMs: effectiveLatency,
            downloadBandwidth: preset.downloadBandwidthLabel,
            uploadBandwidth: preset.uploadBandwidthLabel,
            packetLoss: preset.packetLossLabel,
            systemImage: preset.systemImage
        )
    }
}

// MARK: - NetworkConditionsWindowViewModel

@MainActor @Observable
final class NetworkConditionsWindowViewModel {
    // MARK: Lifecycle

    init(commitChanges: Bool = true, isToolEnabled: Bool? = nil) {
        self.commitChanges = commitChanges
        self.isToolEnabled = isToolEnabled ?? Self.defaultToolEnabled
    }

    // MARK: Internal

    private(set) var allRules: [ProxyRule] = []
    var searchText = ""
    var selectedRuleID: UUID?
    var isFilterVisible = false
    var isToolEnabled: Bool

    var networkConditionRules: [ProxyRule] {
        allRules.filter { rule in
            if case .networkCondition = rule.action {
                return true
            }
            return false
        }
    }

    var filteredRules: [ProxyRule] {
        let conditions = networkConditionRules
        guard !searchText.isEmpty else {
            return conditions
        }
        return conditions.filter { rule in
            rule.name.localizedCaseInsensitiveContains(searchText)
                || (rule.matchCondition.urlPattern ?? "").localizedCaseInsensitiveContains(searchText)
                || hostLabel(for: rule).localizedCaseInsensitiveContains(searchText)
                || networkProfile(for: rule).name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var activeCount: Int {
        networkConditionRules.filter(\.isEnabled).count
    }

    var hasMultipleActive: Bool {
        activeCount > 1
    }

    var ruleCount: Int {
        networkConditionRules.count
    }

    var selectedRule: ProxyRule? {
        guard let selectedRuleID else {
            return nil
        }
        return allRules.first { $0.id == selectedRuleID }
    }

    func loadRules() async {
        allRules = await RuleEngine.shared.allRules
        reconcileSelectionAfterRulesChange()
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
            reconcileSelectionAfterRulesChange()
        }
    }

    func setToolEnabled(_ enabled: Bool) {
        isToolEnabled = enabled
        if commitChanges {
            Task { await RulePolicyGate.shared.setNetworkConditionsToolEnabled(enabled) }
        }
    }

    func toggleRule(id: UUID) {
        guard let rule = allRules.first(where: { $0.id == id }) else {
            return
        }
        if rule.isEnabled {
            if let index = allRules.firstIndex(where: { $0.id == id }) {
                allRules[index].isEnabled = false
            }
            if commitChanges {
                Task { await RulePolicyGate.shared.setRuleEnabled(id: id, enabled: false) }
            }
        } else {
            for index in allRules.indices {
                if case .networkCondition = allRules[index].action, allRules[index].isEnabled {
                    allRules[index].isEnabled = false
                }
            }
            if let index = allRules.firstIndex(where: { $0.id == id }) {
                allRules[index].isEnabled = true
            }
            if commitChanges {
                Task {
                    let accepted = await RulePolicyGate.shared.enableExclusiveNetworkCondition(id: id)
                    if !accepted {
                        allRules = await RuleEngine.shared.allRules
                        reconcileSelectionAfterRulesChange()
                    }
                }
            }
        }
    }

    func addRule(_ rule: ProxyRule) {
        for index in allRules.indices {
            if case .networkCondition = allRules[index].action, allRules[index].isEnabled {
                allRules[index].isEnabled = false
            }
        }
        allRules.append(rule)
        selectedRuleID = rule.id
        if commitChanges {
            Task {
                if rule.isEnabled {
                    let accepted = await RulePolicyGate.shared.addNetworkConditionExclusive(rule)
                    if !accepted {
                        allRules = await RuleEngine.shared.allRules
                        reconcileSelectionAfterRulesChange()
                    }
                } else {
                    let accepted = await RulePolicyGate.shared.addRule(rule)
                    if !accepted {
                        allRules = await RuleEngine.shared.allRules
                        reconcileSelectionAfterRulesChange()
                    }
                }
            }
        }
    }

    func updateRule(_ rule: ProxyRule) {
        guard let index = allRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        allRules[index] = rule
        selectedRuleID = rule.id
        if commitChanges {
            Task { await RulePolicyGate.shared.updateRule(rule) }
        }
    }

    func removeSelectedRule() {
        guard let selectedRuleID else {
            return
        }
        removeRule(id: selectedRuleID)
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = nil
        }
        if commitChanges {
            Task { await RulePolicyGate.shared.removeRule(id: id) }
        }
    }

    func duplicateSelectedRule() {
        guard let selectedRule else {
            return
        }
        let copy = ProxyRule(
            name: String(localized: "Copy of \(selectedRule.name)"),
            isEnabled: false,
            matchCondition: selectedRule.matchCondition,
            action: selectedRule.action,
            priority: selectedRule.priority
        )
        addRule(copy)
    }

    func disableAll() {
        var updated = allRules
        for index in updated.indices {
            if case .networkCondition = updated[index].action {
                updated[index].isEnabled = false
            }
        }
        allRules = updated
        if commitChanges {
            Task { await RulePolicyGate.shared.disableAllNetworkConditions() }
        }
    }

    func presetInfo(for rule: ProxyRule) -> (name: String, latencyMs: Int) {
        if case let .networkCondition(preset, delayMs) = rule.action {
            return (preset.displayName, delayMs)
        }
        return ("", 0)
    }

    func networkProfile(for rule: ProxyRule) -> NetworkConditionProfileMetadata {
        if case let .networkCondition(preset, delayMs) = rule.action {
            return .from(preset: preset, latencyMs: delayMs)
        }
        return .from(preset: .custom, latencyMs: 0)
    }

    func hostLabel(for rule: ProxyRule) -> String {
        guard let pattern = rule.matchCondition.urlPattern,
              !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else
        {
            return String(localized: "System-wide")
        }
        return Self.readableHost(from: pattern)
    }

    func statusLabel(for rule: ProxyRule) -> (String, Color) {
        guard isToolEnabled else {
            return (String(localized: "Paused"), .secondary)
        }
        guard rule.isEnabled else {
            return (String(localized: "Inactive"), .secondary)
        }
        if hasMultipleActive {
            return (String(localized: "Conflict"), .orange)
        }
        return (String(localized: "Active"), .green)
    }

    // MARK: Private

    private let commitChanges: Bool

    private static let toolEnabledKey = "networkConditionsToolEnabled"
    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "NetworkConditionsWindowViewModel"
    )
    private static var defaultToolEnabled: Bool {
        UserDefaults.standard.object(forKey: toolEnabledKey) as? Bool ?? true
    }

    private static func readableHost(from pattern: String) -> String {
        let formattedHost = NetworkConditionsPatternFormatter.hostText(from: pattern)
        if !formattedHost.isEmpty, formattedHost != pattern {
            return formattedHost
        }

        var value = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "^", with: "")
        value = value.replacingOccurrences(of: "$", with: "")
        value = value.replacingOccurrences(of: ".*", with: "")
        value = value.replacingOccurrences(of: "\\.", with: ".")
        value = value.replacingOccurrences(of: "\\:", with: ":")
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[..<slashIndex])
        }
        return value.isEmpty ? pattern : value
    }

    private func reconcileSelectionAfterRulesChange() {
        guard let selectedRuleID,
              networkConditionRules.contains(where: { $0.id == selectedRuleID }) else
        {
            self.selectedRuleID = nil
            return
        }
    }
}

// MARK: - NetworkConditionsWindowView

enum NetworkConditionsPatternFormatter {
    static func hostScopedPattern(from hostText: String) -> String {
        let host = normalizedHostAndPort(from: hostText)
        let escapedHost = NSRegularExpression.escapedPattern(for: host)
        let portPattern = hostContainsPort(host) ? "" : "(?::\\d+)?"
        return "^https?://\(escapedHost)\(portPattern)(?:/.*)?$"
    }

    static func hostText(from pattern: String?) -> String {
        guard var value = pattern, !value.isEmpty else {
            return ""
        }
        value = value.replacingOccurrences(of: "^https?://", with: "")
        value = value.replacingOccurrences(of: "^", with: "")
        value = value.replacingOccurrences(of: "$", with: "")
        value = value.replacingOccurrences(of: "(?:/.*)?", with: "")
        value = value.replacingOccurrences(of: "(?::\\d+)?", with: "")
        value = value.replacingOccurrences(of: "\\.", with: ".")
        value = value.replacingOccurrences(of: "\\:", with: ":")
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[..<slashIndex])
        }
        return value.isEmpty ? pattern ?? "" : value
    }

    private static func normalizedHostAndPort(from hostText: String) -> String {
        var value = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: value), let host = components.host {
            value = host
            if let port = components.port {
                value += ":\(port)"
            }
        }
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[..<slashIndex])
        }
        return value
    }

    private static func hostContainsPort(_ host: String) -> Bool {
        guard let colonIndex = host.lastIndex(of: ":") else {
            return false
        }
        return host[host.index(after: colonIndex)...].allSatisfy(\.isNumber)
    }
}

// MARK: - NetworkConditionsRuleForm

enum NetworkConditionsRuleForm {
    static let defaultName = "Untitled"
    static let defaultPreset = NetworkConditionPreset.threeG
    static let defaultCustomLatencyMs = 500

    static func effectiveLatencyMs(preset: NetworkConditionPreset, customLatencyMs: Int) -> Int {
        preset == .custom ? customLatencyMs : preset.defaultLatencyMs
    }

    static func isValid(
        name: String,
        hostText: String,
        applySystemWide: Bool,
        preset: NetworkConditionPreset,
        customLatencyMs: Int
    )
        -> Bool
    {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && effectiveLatencyMs(preset: preset, customLatencyMs: customLatencyMs) > 0
            && (applySystemWide || !hostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    static func makeRule(
        existingID: UUID?,
        name: String,
        isEnabled: Bool,
        hostText: String,
        applySystemWide: Bool,
        preset: NetworkConditionPreset,
        customLatencyMs: Int
    )
        -> ProxyRule
    {
        let trimmedHost = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        let condition = RuleMatchCondition(
            urlPattern: applySystemWide || trimmedHost.isEmpty ? nil : NetworkConditionsPatternFormatter
                .hostScopedPattern(from: trimmedHost)
        )
        return ProxyRule(
            id: existingID ?? UUID(),
            name: name,
            isEnabled: isEnabled,
            matchCondition: condition,
            action: .networkCondition(
                preset: preset,
                delayMs: effectiveLatencyMs(preset: preset, customLatencyMs: customLatencyMs)
            )
        )
    }
}

struct NetworkConditionsWindowView: View {
    // MARK: Internal

    @State var viewModel = NetworkConditionsWindowViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if viewModel.isFilterVisible {
                filterBar
            }
            tableContent
            shortcutStrip
            bottomBar
        }
        .frame(width: 1_198, height: 641)
        .task { await viewModel.loadRules() }
        .onAppear { consumePendingDraft() }
        .onReceive(NotificationCenter.default.publisher(for: .openNetworkConditionsWindow)) { _ in
            consumePendingDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(isPresented: $showEditSheet) {
            NetworkConditionsEditSheet(
                existingRule: editingRule,
                draft: pendingDraft,
                onSave: { rule in
                    if editingRule != nil {
                        viewModel.updateRule(rule)
                    } else {
                        viewModel.addRule(rule)
                    }
                    pendingDraft = nil
                }
            )
        }
    }

    // MARK: Private

    @State private var showEditSheet = false
    @State private var editingRule: ProxyRule?
    @State private var pendingDraft: NetworkConditionsDraft?

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { viewModel.isToolEnabled },
                set: { viewModel.setToolEnabled($0) }
            )) {
                Text(String(localized: "Enable Network Conditions"))
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .padding(.top, 16)

            Text(String(localized: "Simulate Network Conditions with various Preset Profiles. Useful to test with slow networks."))
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Text(String(localized: "Only 1 Rule can be activated at once."))
                .font(.system(size: 13))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "Filter Network Conditions"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
            Button {
                viewModel.searchText = ""
                viewModel.isFilterVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var tableContent: some View {
        Table(viewModel.filteredRules, selection: $viewModel.selectedRuleID) {
            TableColumn(String(localized: "Enabled")) { rule in
                HStack {
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { _ in viewModel.toggleRule(id: rule.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .controlSize(.small)
                    Spacer()
                }
            }
            .width(62)

            TableColumn(String(localized: "Name")) { rule in
                Text(rule.name.isEmpty ? String(localized: "Untitled") : rule.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1.0 : 0.62)
            }
            .width(min: 250, ideal: 300)

            TableColumn(String(localized: "Status")) { rule in
                let (label, color) = viewModel.statusLabel(for: rule)
                Text(label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(color)
            }
            .width(110)

            TableColumn(String(localized: "Host")) { rule in
                Text(viewModel.hostLabel(for: rule))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .help(rule.matchCondition.urlPattern ?? String(localized: "System-wide"))
                    .opacity(rule.isEnabled ? 1.0 : 0.75)
            }
            .width(min: 230, ideal: 250)

            TableColumn(String(localized: "Network Profile")) { rule in
                let profile = viewModel.networkProfile(for: rule)
                Text(profile.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .help("\(profile.name), \(profile.latencyMs) ms")
                    .opacity(rule.isEnabled ? 1.0 : 0.75)
            }
            .width(min: 230, ideal: 260)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            tableContextMenu(ids: ids)
        } primaryAction: { ids in
            guard let id = ids.first,
                  let rule = viewModel.allRules.first(where: { $0.id == id }) else
            {
                return
            }
            openEditor(for: rule)
        }
        .overlay {
            if viewModel.filteredRules.isEmpty {
                Text(emptyTableMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
    }

    private var shortcutStrip: some View {
        Text("New: ⌘N    Edit: ⌘↩    Delete: ⌘⌫    Duplicate: ⌘D    Toggle: ↵")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            addRemoveControl

            Button {
                // Help content is intentionally deferred; this mirrors the reference affordance.
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary.opacity(0.35), .clear)
                    .overlay(Text("?").font(.system(size: 15, weight: .medium)).foregroundStyle(.primary))
                    .frame(width: 34, height: 22)
            }
            .buttonStyle(.borderless)
            .padding(.leading, 2)

            Spacer()

            moreMenu
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                openNewEditor()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 21, height: 21)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "New Rule"))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 21)

            Button {
                viewModel.removeSelectedRule()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(viewModel.selectedRuleID == nil ? .tertiary : .primary)
                    .frame(width: 21, height: 21)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
            .help(String(localized: "Delete Rule"))
        }
        .frame(height: 23)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New…")) {
                openNewEditor()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button(String(localized: "Edit…")) {
                openEditorForSelection()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(viewModel.selectedRule == nil)

            Button(String(localized: "Duplicate")) {
                viewModel.duplicateSelectedRule()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel.selectedRule == nil)

            Button(enableDisableLabel) {
                if let id = viewModel.selectedRuleID {
                    viewModel.toggleRule(id: id)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(viewModel.selectedRule == nil)
            Button(enableDisableLabel) {
                if let id = viewModel.selectedRuleID {
                    viewModel.toggleRule(id: id)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(viewModel.selectedRule == nil)

            Divider()

            Button(viewModel.isFilterVisible ? String(localized: "Hide Filter") : String(localized: "Show Filter")) {
                withAnimation {
                    viewModel.isFilterVisible.toggle()
                }
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(String(localized: "Disable All")) {
                viewModel.disableAll()
            }
            .disabled(viewModel.activeCount == 0)

            Divider()

            Button(String(localized: "Delete"), role: .destructive) {
                viewModel.removeSelectedRule()
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

    private var emptyTableMessage: String {
        if viewModel.networkConditionRules.isEmpty {
            return String(localized: "Click \"+\" or ⌘N to add new entry")
        }
        return String(localized: "No Network Conditions match the current filter")
    }

    private var enableDisableLabel: String {
        guard let selectedRule = viewModel.selectedRule else {
            return String(localized: "Toggle")
        }
        return selectedRule.isEnabled ? String(localized: "Disable") : String(localized: "Enable")
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first {
            Button(String(localized: "Edit…")) {
                if let rule = viewModel.allRules.first(where: { $0.id == id }) {
                    openEditor(for: rule)
                }
            }
            Button(String(localized: "Duplicate")) {
                viewModel.selectedRuleID = id
                viewModel.duplicateSelectedRule()
            }
            Button(enableDisableContextLabel(for: id)) {
                viewModel.toggleRule(id: id)
            }
            Divider()
            Button(String(localized: "Delete"), role: .destructive) {
                viewModel.removeRule(id: id)
            }
        }
    }

    private func enableDisableContextLabel(for id: UUID) -> String {
        guard let rule = viewModel.allRules.first(where: { $0.id == id }) else {
            return String(localized: "Toggle")
        }
        return rule.isEnabled ? String(localized: "Disable") : String(localized: "Enable")
    }

    private func openNewEditor() {
        pendingDraft = nil
        editingRule = nil
        showEditSheet = true
    }

    private func openEditorForSelection() {
        guard let rule = viewModel.selectedRule else {
            return
        }
        openEditor(for: rule)
    }

    private func openEditor(for rule: ProxyRule) {
        editingRule = rule
        pendingDraft = nil
        showEditSheet = true
    }

    private func consumePendingDraft() {
        guard let draft = NetworkConditionsDraftStore.shared.consumePending() else {
            return
        }
        pendingDraft = draft
        editingRule = nil
        showEditSheet = true
    }
}

// MARK: - NetworkConditionsEditSheet

private struct NetworkConditionsEditSheet: View {
    // MARK: Lifecycle

    init(
        existingRule: ProxyRule?,
        draft: NetworkConditionsDraft? = nil,
        onSave: @escaping (ProxyRule) -> Void
    ) {
        self.onSave = onSave
        self.draft = draft
        self.existingID = existingRule?.id

        if let existingRule {
            _name = State(initialValue: existingRule.name)
            _hostText = State(initialValue: Self.hostText(from: existingRule.matchCondition.urlPattern))
            _applySystemWide = State(initialValue: existingRule.matchCondition.urlPattern == nil)
            _isEnabled = State(initialValue: existingRule.isEnabled)
            if case let .networkCondition(preset, delayMs) = existingRule.action {
                _selectedPreset = State(initialValue: preset)
                _customLatencyMs = State(initialValue: delayMs)
            }
        } else if let draft {
            _name = State(initialValue: draft.suggestedName)
            _hostText = State(initialValue: draft.sourceURL?.host ?? draft.sourceHost)
        }
    }

    // MARK: Internal

    let onSave: (ProxyRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                labeledTextField(
                    String(localized: "Name:"),
                    text: $name,
                    prompt: String(localized: "Untitled")
                )

                labeledTextField(
                    String(localized: "Host:"),
                    text: $hostText,
                    prompt: "api.proxyman.com"
                )
                .disabled(applySystemWide)

                Text(String(localized: "Only support Host and Port. No Wildcard or Regex"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.fieldLeading)

                Toggle(isOn: $applySystemWide) {
                    Text(String(localized: "Apply System-wide"))
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .padding(.leading, Self.fieldLeading)

                Text(String(localized: "All traffic being proxied through Rockxy will be affected by Network Throttling"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.fieldLeading)
                    .padding(.bottom, 6)

                HStack(spacing: 8) {
                    Text(String(localized: "Preset Profiles:"))
                        .font(.system(size: 13))
                        .frame(width: Self.labelWidth, alignment: .trailing)
                    Picker("", selection: $selectedPreset) {
                        ForEach(NetworkConditionPreset.allCases, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                profileStats
            }
            .padding(.top, 14)
            .padding(.horizontal, 18)

            Text(String(localized: "To simulate network condition in real-life, the bandwidth is generated randomly in a given range"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.leading, Self.fieldLeading + 18)
                .padding(.top, 12)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 100)
                Button(isEditing ? String(localized: "Save (⌘↩)") : String(localized: "Add (⌘↩)")) {
                    saveRule()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .frame(width: 100)
            }
            .padding(.top, 16)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 838, height: 390)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var name = NetworkConditionsRuleForm.defaultName
    @State private var hostText = ""
    @State private var applySystemWide = false
    @State private var selectedPreset = NetworkConditionsRuleForm.defaultPreset
    @State private var customLatencyMs = NetworkConditionsRuleForm.defaultCustomLatencyMs
    @State private var isEnabled = true

    private let draft: NetworkConditionsDraft?
    private let existingID: UUID?
    private static let labelWidth: CGFloat = 96
    private static let fieldWidth: CGFloat = 700
    private static let fieldLeading = labelWidth + 8

    private var isEditing: Bool {
        existingID != nil
    }

    private var effectiveLatencyMs: Int {
        NetworkConditionsRuleForm.effectiveLatencyMs(preset: selectedPreset, customLatencyMs: customLatencyMs)
    }

    private var isValid: Bool {
        NetworkConditionsRuleForm.isValid(
            name: name,
            hostText: hostText,
            applySystemWide: applySystemWide,
            preset: selectedPreset,
            customLatencyMs: customLatencyMs
        )
    }

    private var profileStats: some View {
        let metadata = NetworkConditionProfileMetadata.from(preset: selectedPreset, latencyMs: effectiveLatencyMs)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 20) {
                Text(String(localized: "Download"))
                    .font(.system(size: 13))
                    .frame(width: 260, alignment: .leading)
                Text(String(localized: "Upload"))
                    .font(.system(size: 13))
                    .frame(width: 260, alignment: .leading)
            }
            HStack(spacing: 20) {
                statsCard(
                    bandwidth: metadata.downloadBandwidth,
                    packetLoss: metadata.packetLoss,
                    latencyMs: metadata.latencyMs
                )
                statsCard(
                    bandwidth: metadata.uploadBandwidth,
                    packetLoss: metadata.packetLoss,
                    latencyMs: metadata.latencyMs
                )
            }
        }
        .padding(.leading, Self.fieldLeading)
        .padding(.top, 4)
    }

    private func labeledTextField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: Self.labelWidth, alignment: .trailing)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .frame(width: Self.fieldWidth)
        }
    }

    private func statsCard(bandwidth: String, packetLoss: String, latencyMs: Int) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("Bandwidth:  \(bandwidth)")
            Text("Packets Dropped:  \(packetLoss)")
            HStack(spacing: 6) {
                Text("Delay:")
                if selectedPreset == .custom {
                    TextField("", value: $customLatencyMs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("ms")
                } else {
                    Text("\(latencyMs).0 ms")
                }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 20)
        .frame(width: 260, height: 88, alignment: .center)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static func hostText(from pattern: String?) -> String {
        NetworkConditionsPatternFormatter.hostText(from: pattern)
    }

    private func saveRule() {
        let rule = NetworkConditionsRuleForm.makeRule(
            existingID: existingID,
            name: name,
            isEnabled: isEnabled,
            hostText: hostText,
            applySystemWide: applySystemWide,
            preset: selectedPreset,
            customLatencyMs: customLatencyMs
        )
        onSave(rule)
        dismiss()
    }
}
