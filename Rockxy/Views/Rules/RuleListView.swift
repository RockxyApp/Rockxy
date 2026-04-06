import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

// Renders the rule list for rule editing and management.

// MARK: - RuleListView

struct RuleListView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            ruleToolbar
            Divider()

            if filteredRules.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Rules"),
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text(String(localized: "Add rules to intercept, block, or modify requests."))
                )
            } else {
                ruleTable
            }

            Divider()
            bottomBar
        }
        .sheet(isPresented: $showAddSheet) {
            RuleEditSheet { newRule in
                coordinator.addRule(newRule)
                Self.logger.info("Added rule: \(newRule.name)")
            }
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "RuleListView")

    @State private var selectedRuleID: UUID?
    @State private var showAddSheet = false
    @State private var editingRule: ProxyRule?
    @State private var searchText = ""
    @State private var filterAction: RuleActionType?

    private var rules: [ProxyRule] {
        coordinator.rules
    }

    private var filteredRules: [ProxyRule] {
        rules.filter { rule in
            let matchesSearch = searchText.isEmpty
                || rule.name.localizedCaseInsensitiveContains(searchText)
                || (rule.matchCondition.urlPattern ?? "").localizedCaseInsensitiveContains(searchText)

            let matchesFilter: Bool = if let filterAction {
                actionType(for: rule.action) == filterAction
            } else {
                true
            }

            return matchesSearch && matchesFilter
        }
    }

    // MARK: - Toolbar

    private var ruleToolbar: some View {
        HStack(spacing: 8) {
            Button {
                showAddSheet = true
            } label: {
                Label(String(localized: "Add Rule"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                guard let id = selectedRuleID else {
                    return
                }
                coordinator.removeRule(id: id)
                selectedRuleID = nil
            } label: {
                Label(String(localized: "Remove"), systemImage: "minus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedRuleID == nil)

            Divider()
                .frame(height: 16)

            Picker(selection: $filterAction) {
                Text(String(localized: "All Actions")).tag(RuleActionType?.none)
                Divider()
                ForEach(RuleActionType.allCases) { actionType in
                    Text(actionType.displayName).tag(Optional(actionType))
                }
            } label: {
                EmptyView()
            }
            .frame(width: 140)
            .controlSize(.small)

            Spacer()

            TextField(String(localized: "Filter rules..."), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Rule Table

    private var ruleTable: some View {
        List(selection: $selectedRuleID) {
            ruleHeader
                .listRowSeparator(.visible, edges: .bottom)

            ForEach(filteredRules) { rule in
                RuleGridRow(rule: rule) {
                    if case .networkCondition = rule.action, !rule.isEnabled {
                        Task { await RuleSyncService.enableExclusiveNetworkCondition(id: rule.id) }
                    } else {
                        coordinator.toggleRule(id: rule.id)
                    }
                }
                .tag(rule.id)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        coordinator.removeRule(id: rule.id)
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var ruleHeader: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 40)

            Text(String(localized: "Name"))
                .frame(minWidth: 120, alignment: .leading)

            Text(String(localized: "Pattern"))
                .frame(minWidth: 160, alignment: .leading)

            Spacer()

            Text(String(localized: "Action"))
                .frame(width: 100, alignment: .center)

            Text(String(localized: "Priority"))
                .frame(width: 60, alignment: .trailing)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text(String(localized: "\(filteredRules.count) rules"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(String(localized: "Import")) {
                importRules()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(String(localized: "Export")) {
                exportRules()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(rules.isEmpty)

            Menu(String(localized: "Presets")) {
                Button(String(localized: "Block Ads")) {
                    addPresetRule(
                        name: "Block Ads",
                        pattern: ".*(\\.doubleclick\\.net|ads\\.|adservice\\.).*",
                        action: .block(statusCode: 403)
                    )
                }
                Button(String(localized: "Block Analytics")) {
                    addPresetRule(
                        name: "Block Analytics",
                        pattern: ".*(google-analytics\\.com|analytics\\.).*",
                        action: .block(statusCode: 403)
                    )
                }
                Divider()
                Button(String(localized: "Map API Local")) {
                    addPresetRule(
                        name: "Map API Local",
                        pattern: ".*/api/.*",
                        action: .mapLocal(filePath: "")
                    )
                }
                Button(String(localized: "Throttle API")) {
                    addPresetRule(
                        name: "Throttle API",
                        pattern: ".*/api/.*",
                        action: .throttle(delayMs: 2000)
                    )
                }
                Divider()
                Button(String(localized: "Breakpoint All")) {
                    addPresetRule(
                        name: "Breakpoint All",
                        pattern: ".*",
                        action: .breakpoint()
                    )
                }
                Divider()
                Button(String(localized: "Add CORS Headers")) {
                    coordinator.addRule(HeaderModifyPresets.corsHeaders())
                }
                Button(String(localized: "Remove Authorization")) {
                    coordinator.addRule(HeaderModifyPresets.removeAuthorization())
                }
                Button(String(localized: "Strip Server Header")) {
                    coordinator.addRule(HeaderModifyPresets.stripServerHeader())
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func actionType(for action: RuleAction) -> RuleActionType {
        switch action {
        case .breakpoint: .breakpoint
        case .block: .block
        case .throttle: .throttle
        case .mapLocal: .mapLocal
        case .mapRemote: .mapRemote
        case .modifyHeader: .modifyHeader
        case .networkCondition: .networkCondition
        }
    }

    private func addPresetRule(name: String, pattern: String, action: RuleAction) {
        let rule = ProxyRule(
            name: name,
            matchCondition: RuleMatchCondition(urlPattern: pattern),
            action: action
        )
        coordinator.addRule(rule)
        Self.logger.info("Added preset rule: \(name)")
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Rules")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let imported = try RuleStore().importRules(from: url)
            for rule in imported {
                coordinator.addRule(rule)
            }
            Self.logger.info("Imported \(imported.count) rules from \(url.lastPathComponent)")
        } catch {
            Self.logger.error("Failed to import rules: \(error.localizedDescription)")
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Rules")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "rockxy-rules.json"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try RuleStore().exportRules(to: url)
            Self.logger.info("Exported rules to \(url.lastPathComponent)")
        } catch {
            Self.logger.error("Failed to export rules: \(error.localizedDescription)")
        }
    }
}

// MARK: - RuleGridRow

private struct RuleGridRow: View {
    // MARK: Internal

    let rule: ProxyRule
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 40)

            Text(rule.name)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)

            Text(rule.matchCondition.urlPattern ?? "--")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 160, alignment: .leading)

            Spacer()

            actionBadge
                .lineLimit(1)
                .frame(width: 140, alignment: .center)

            Text("\(rule.priority)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }

    // MARK: Private

    @ViewBuilder private var actionBadge: some View {
        let (label, color) = actionInfo(rule.action)
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func actionInfo(_ action: RuleAction) -> (String, Color) {
        switch action {
        case .breakpoint:
            return ("Breakpoint", .orange)
        case .mapLocal:
            return ("Map Local", .blue)
        case .mapRemote:
            return ("Map Remote", .purple)
        case .block:
            return ("Block", .red)
        case .throttle:
            return ("Throttle", .yellow)
        case let .modifyHeader(operations):
            let count = operations.count
            let phaseLabel = operations.phaseSummaryLabel
            let label = "\(count) \(count == 1 ? "op" : "ops") \u{00B7} \(phaseLabel)"
            return (label, .green)
        case let .networkCondition(preset, _):
            return ("Network \u{00B7} \(preset.displayName)", .cyan)
        }
    }
}

// MARK: - RuleEditSheet

private struct RuleEditSheet: View {
    // MARK: Internal

    let onSave: (ProxyRule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(String(localized: "Rule Info")) {
                    TextField(String(localized: "Name"), text: $name)
                }

                Section(String(localized: "Match Condition")) {
                    TextField("URL Pattern (regex)", text: $urlPattern)
                        .font(.system(.body, design: .monospaced))
                    TextField("HTTP Method", text: $method)
                        .textCase(.uppercase)
                }

                Section(String(localized: "Action")) {
                    Picker(String(localized: "Action type"), selection: $selectedAction) {
                        ForEach(RuleActionType.creatableCases) { actionType in
                            Text(actionType.displayName).tag(actionType)
                        }
                    }

                    switch selectedAction {
                    case .block:
                        TextField(
                            String(localized: "Status code"),
                            value: $blockStatusCode,
                            format: .number
                        )
                    case .throttle:
                        TextField(
                            String(localized: "Delay (ms)"),
                            value: $throttleDelay,
                            format: .number
                        )
                    case .mapLocal:
                        TextField(String(localized: "File path"), text: $mapLocalPath)
                    case .mapRemote:
                        TextField("URL", text: $mapRemoteURL)
                    case .breakpoint:
                        EmptyView()
                    case .modifyHeader:
                        ModifyHeaderEditorView(operations: $headerOperations)
                    case .networkCondition:
                        EmptyView()
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Add Rule")) {
                    let condition = RuleMatchCondition(
                        urlPattern: urlPattern.isEmpty ? nil : urlPattern,
                        method: method.isEmpty ? nil : method.uppercased()
                    )
                    let action = buildAction()
                    let rule = ProxyRule(
                        name: name,
                        matchCondition: condition,
                        action: action
                    )
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(
            width: selectedAction == .modifyHeader ? 620 : 420,
            height: selectedAction == .modifyHeader ? 520 : 380
        )
        .animation(.easeInOut(duration: 0.2), value: selectedAction)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlPattern = ""
    @State private var method = ""
    @State private var selectedAction: RuleActionType = .block

    @State private var blockStatusCode = 403
    @State private var throttleDelay = 1000
    @State private var mapLocalPath = ""
    @State private var mapRemoteURL = ""
    @State private var headerOperations: [EditableHeaderOperation] = [EditableHeaderOperation()]

    private var isValid: Bool {
        guard !name.isEmpty else {
            return false
        }
        if selectedAction == .modifyHeader {
            return !headerOperations.isEmpty && headerOperations.allSatisfy(\.isValid)
        }
        return true
    }

    private func buildAction() -> RuleAction {
        switch selectedAction {
        case .breakpoint:
            .breakpoint()
        case .block:
            .block(statusCode: blockStatusCode)
        case .throttle:
            .throttle(delayMs: throttleDelay)
        case .mapLocal:
            .mapLocal(filePath: mapLocalPath)
        case .mapRemote:
            .mapRemote(configuration: MapRemoteConfiguration(fromLegacyURL: mapRemoteURL))
        case .modifyHeader:
            .modifyHeader(operations: headerOperations.toHeaderOperations())
        case .networkCondition:
            preconditionFailure("Network conditions are created via the dedicated window, not the generic rule editor")
        }
    }
}

// MARK: - RuleActionType

private enum RuleActionType: String, CaseIterable, Identifiable {
    case breakpoint
    case block
    case throttle
    case mapLocal
    case mapRemote
    case modifyHeader
    case networkCondition

    // MARK: Internal

    static var creatableCases: [RuleActionType] {
        allCases.filter { $0 != .networkCondition }
    }

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .breakpoint: "Breakpoint"
        case .block: "Block"
        case .throttle: "Throttle"
        case .mapLocal: "Map Local"
        case .mapRemote: "Map Remote"
        case .modifyHeader: "Modify Header"
        case .networkCondition: "Network Condition"
        }
    }
}
