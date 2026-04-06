import os
import SwiftUI

// Presents the network conditions window for rule editing and management.

// MARK: - NetworkConditionsMatchMode

private enum NetworkConditionsMatchMode: String, CaseIterable {
    case exactPath
    case includeSubpaths
    case regexAdvanced

    // MARK: Internal

    var displayName: String {
        switch self {
        case .exactPath: "Exact Path"
        case .includeSubpaths: "Subpaths"
        case .regexAdvanced: "Regex"
        }
    }
}

// MARK: - NetworkConditionsWindowViewModel

@MainActor @Observable
final class NetworkConditionsWindowViewModel {
    // MARK: Internal

    private(set) var allRules: [ProxyRule] = []
    var searchText = ""

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
                || presetInfo(for: rule).name.localizedCaseInsensitiveContains(searchText)
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

    func loadRules() async {
        allRules = await RuleEngine.shared.allRules
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
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
            Task { await RuleSyncService.setRuleEnabled(id: id, enabled: false) }
        } else {
            for index in allRules.indices {
                if case .networkCondition = allRules[index].action, allRules[index].isEnabled {
                    allRules[index].isEnabled = false
                }
            }
            if let index = allRules.firstIndex(where: { $0.id == id }) {
                allRules[index].isEnabled = true
            }
            Task { await RuleSyncService.enableExclusiveNetworkCondition(id: id) }
        }
    }

    func addRule(_ rule: ProxyRule) {
        for index in allRules.indices {
            if case .networkCondition = allRules[index].action, allRules[index].isEnabled {
                allRules[index].isEnabled = false
            }
        }
        allRules.append(rule)
        Task {
            if rule.isEnabled {
                await RuleSyncService.addNetworkConditionExclusive(rule)
            } else {
                await RuleSyncService.addRule(rule)
            }
        }
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

    func disableAll() {
        var updated = allRules
        for index in updated.indices {
            if case .networkCondition = updated[index].action {
                updated[index].isEnabled = false
            }
        }
        allRules = updated
        Task { await RuleSyncService.disableAllNetworkConditions() }
    }

    func presetInfo(for rule: ProxyRule) -> (name: String, latencyMs: Int) {
        if case let .networkCondition(preset, delayMs) = rule.action {
            return (preset.displayName, delayMs)
        }
        return ("", 0)
    }

    func statusLabel(for rule: ProxyRule) -> (String, Color) {
        guard rule.isEnabled else {
            return (String(localized: "Inactive"), .secondary)
        }
        if hasMultipleActive {
            return (String(localized: "Conflict"), .orange)
        }
        return (String(localized: "Active"), .green)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "NetworkConditionsWindowViewModel")
}

// MARK: - NetworkConditionsWindowView

struct NetworkConditionsWindowView: View {
    // MARK: Internal

    @State var viewModel = NetworkConditionsWindowViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            infoBar
            Divider()
            if viewModel.hasMultipleActive {
                warningBanner
                Divider()
            }
            tableContent
            Divider()
            bottomBar
        }
        .frame(width: 880, height: 480)
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

    @State private var selectedRuleID: UUID?
    @State private var showEditSheet = false
    @State private var editingRule: ProxyRule?
    @State private var pendingDraft: NetworkConditionsDraft?

    @ViewBuilder private var tableContent: some View {
        if viewModel.networkConditionRules.isEmpty {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text(String(localized: "No Network Conditions"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Simulate slow or unreliable networks. Click + below to create a condition."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange.opacity(0.4))
                        .frame(width: 2, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Example"))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 5) {
                            Text("api.example.com")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "tortoise")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text("3G — 400 ms")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.leading, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 12)
        } else {
            Table(viewModel.filteredRules, selection: $selectedRuleID) {
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
                .width(min: 100, ideal: 140)

                TableColumn(String(localized: "Scope")) { rule in
                    Text(rule.matchCondition.urlPattern ?? "*")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .help(rule.matchCondition.urlPattern ?? "*")
                        .opacity(rule.isEnabled ? 1.0 : 0.5)
                }
                .width(min: 160, ideal: 200)

                TableColumn(String(localized: "Profile")) { rule in
                    Text(viewModel.presetInfo(for: rule).name)
                        .lineLimit(1)
                        .opacity(rule.isEnabled ? 1.0 : 0.5)
                }
                .width(80)

                TableColumn(String(localized: "Latency")) { rule in
                    Text("\(viewModel.presetInfo(for: rule).latencyMs) ms")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .opacity(rule.isEnabled ? 1.0 : 0.5)
                }
                .width(80)

                TableColumn(String(localized: "Status")) { rule in
                    let (label, color) = viewModel.statusLabel(for: rule)
                    Text(label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12))
                        .foregroundStyle(color)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .width(80)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    Button(String(localized: "Edit")) {
                        editingRule = viewModel.allRules.first { $0.id == id }
                        pendingDraft = nil
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

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.disableAll()
            } label: {
                Text(String(localized: "Disable All"))
                    .font(.callout)
            }

            Spacer()

            TextField(String(localized: "Search"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            Button {
                pendingDraft = nil
                editingRule = nil
                showEditSheet = true
            } label: {
                Label(String(localized: "Add Rule"), systemImage: "plus")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var infoBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(String(localized: "Simulate slow network behavior for proxied requests using latency presets."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5))
    }

    private var warningBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(String(localized: "Only one Network Conditions rule can be active at a time."))
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.08))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                pendingDraft = nil
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

            Text(
                "\(viewModel.ruleCount) \(viewModel.ruleCount == 1 ? String(localized: "rule") : String(localized: "rules"))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
            _urlPattern = State(initialValue: existingRule.matchCondition.urlPattern ?? "")
            _matchMode = State(initialValue: .regexAdvanced)
            _isEnabled = State(initialValue: existingRule.isEnabled)
            if case let .networkCondition(preset, delayMs) = existingRule.action {
                _selectedPreset = State(initialValue: preset)
                if preset == .custom {
                    _customLatencyMs = State(initialValue: delayMs)
                } else {
                    _customLatencyMs = State(initialValue: delayMs)
                }
            }
        } else if let draft {
            _name = State(initialValue: draft.suggestedName)
            let defaultMode: NetworkConditionsMatchMode = draft.origin == .domainQuickCreate
                ? .includeSubpaths : .exactPath
            _matchMode = State(initialValue: defaultMode)
            if let url = draft.sourceURL {
                _urlPattern = State(initialValue: Self.generatePattern(from: url, mode: defaultMode))
            } else {
                _urlPattern = State(initialValue: Self.generateDomainPattern(
                    from: draft.sourceHost, mode: defaultMode
                ))
            }
        }
    }

    // MARK: Internal

    let onSave: (ProxyRule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ruleInfoSection
                scopeSection
                profileSection
                if selectedPreset == .custom {
                    advancedSection
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? String(localized: "Save") : String(localized: "Add Rule")) {
                    saveRule()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 520, height: 420)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlPattern = ""
    @State private var matchMode: NetworkConditionsMatchMode = .exactPath
    @State private var selectedPreset: NetworkConditionPreset = .lte
    @State private var customLatencyMs = 500
    @State private var isEnabled = true

    private let draft: NetworkConditionsDraft?
    private let existingID: UUID?

    private var isEditing: Bool {
        existingID != nil
    }

    private var effectiveLatencyMs: Int {
        selectedPreset == .custom ? customLatencyMs : selectedPreset.defaultLatencyMs
    }

    private var isValid: Bool {
        !name.isEmpty && effectiveLatencyMs > 0
    }

    // MARK: - Rule Info Section

    private var ruleInfoSection: some View {
        Section(String(localized: "Rule Info")) {
            TextField(String(localized: "Name"), text: $name)
        }
    }

    // MARK: - Scope Section

    private var scopeSection: some View {
        Section(String(localized: "Scope")) {
            Picker(String(localized: "Match"), selection: $matchMode) {
                ForEach(NetworkConditionsMatchMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: matchMode) { _, newMode in
                if let draft, let url = draft.sourceURL {
                    urlPattern = Self.generatePattern(from: url, mode: newMode)
                } else if let draft {
                    urlPattern = Self.generateDomainPattern(from: draft.sourceHost, mode: newMode)
                }
            }

            TextField(String(localized: "URL Pattern"), text: $urlPattern)
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section(String(localized: "Profile")) {
            Picker(String(localized: "Preset"), selection: $selectedPreset) {
                ForEach(NetworkConditionPreset.allCases, id: \.self) { preset in
                    HStack {
                        Text(preset.displayName)
                        Spacer()
                        if preset != .custom {
                            Text("\(preset.defaultLatencyMs) ms")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(preset)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: selectedPreset.systemImage)
                    .foregroundStyle(.secondary)
                Text("\(selectedPreset.displayName) — \(effectiveLatencyMs) ms")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section(String(localized: "Advanced")) {
            HStack {
                Text(String(localized: "Latency (ms)"))
                TextField("", value: $customLatencyMs, format: .number)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 100)
                Stepper("", value: $customLatencyMs, in: 1 ... 30000, step: 50)
                    .labelsHidden()
            }

            Text(String(localized: "Bandwidth throttling and packet loss will be available in a future update."))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Pattern Helpers

    private static func escapeRegex(_ string: String) -> String {
        NSRegularExpression.escapedPattern(for: string)
    }

    private static func generatePattern(from url: URL, mode: NetworkConditionsMatchMode) -> String {
        let scheme = url.scheme ?? "https"
        let host = escapeRegex(url.host ?? "")
        let path = escapeRegex(url.path)
        switch mode {
        case .exactPath:
            return "^\(scheme)://\(host)\(path)$"
        case .includeSubpaths:
            return "^\(scheme)://\(host)\(path).*"
        case .regexAdvanced:
            return "\(scheme)://\(host)\(path)"
        }
    }

    private static func generateDomainPattern(from host: String, mode: NetworkConditionsMatchMode) -> String {
        let escapedHost = escapeRegex(host)
        switch mode {
        case .exactPath:
            return "^https://\(escapedHost)/?$"
        case .includeSubpaths:
            return "^https://\(escapedHost)/.*"
        case .regexAdvanced:
            return ".*\(escapedHost).*"
        }
    }

    private func saveRule() {
        let condition = RuleMatchCondition(
            urlPattern: urlPattern.isEmpty ? nil : urlPattern
        )
        let rule = ProxyRule(
            id: existingID ?? UUID(),
            name: name,
            isEnabled: isEnabled,
            matchCondition: condition,
            action: .networkCondition(preset: selectedPreset, delayMs: effectiveLatencyMs)
        )
        onSave(rule)
        dismiss()
    }
}
