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
                    String(localized: "No Rules", bundle: RockxyLocalization.bundle),
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text(String(
                        localized: "Add rules to intercept, block, or modify requests.",
                        bundle: RockxyLocalization.bundle
                    ))
                )
            } else {
                ruleTable
            }

            Divider()
            bottomBar
        }
        .font(toolMetrics.font())
        .alert(
            operationAlertTitle,
            isPresented: Binding(
                get: { operationError != nil },
                set: { isPresented in
                    if !isPresented {
                        operationError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) { operationError = nil }
        } message: {
            if let operationError {
                Text(operationError)
            }
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
    @State private var operationError: String?
    @State private var operationAlertTitle = String(localized: "Import Failed", bundle: RockxyLocalization.bundle)
    @Environment(\.appUIDisplayMetrics) private var appMetrics

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

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    // MARK: - Toolbar

    private var ruleToolbar: some View {
        HStack(spacing: 8) {
            Button {
                showAddSheet = true
            } label: {
                Label(String(localized: "Add Rule", bundle: RockxyLocalization.bundle), systemImage: "plus")
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)

            Button {
                guard let id = selectedRuleID else {
                    return
                }
                coordinator.removeRule(id: id)
                selectedRuleID = nil
            } label: {
                Label(String(localized: "Remove", bundle: RockxyLocalization.bundle), systemImage: "minus")
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)
            .disabled(selectedRuleID == nil)

            Divider()
                .frame(height: 16)

            Picker(selection: $filterAction) {
                Text(String(localized: "All Actions", bundle: RockxyLocalization.bundle)).tag(RuleActionType?.none)
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

            TextField(String(localized: "Filter rules...", bundle: RockxyLocalization.bundle), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .rockxyFunctionalBar()
    }

    // MARK: - Rule Table

    private var ruleTable: some View {
        List(selection: $selectedRuleID) {
            ruleHeader
                .listRowSeparator(.visible, edges: .bottom)

            ForEach(filteredRules) { rule in
                RuleGridRow(rule: rule) {
                    if case .networkCondition = rule.action, !rule.isEnabled {
                        Task { await RulePolicyGate.shared.enableExclusiveNetworkCondition(id: rule.id) }
                    } else {
                        coordinator.toggleRule(id: rule.id)
                    }
                }
                .tag(rule.id)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        coordinator.removeRule(id: rule.id)
                    } label: {
                        Label(String(localized: "Delete", bundle: RockxyLocalization.bundle), systemImage: "trash")
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

            Text(String(localized: "Name", bundle: RockxyLocalization.bundle))
                .frame(minWidth: 120, alignment: .leading)

            Text(String(localized: "Pattern", bundle: RockxyLocalization.bundle))
                .frame(minWidth: 160, alignment: .leading)

            Spacer()

            Text(String(localized: "Action", bundle: RockxyLocalization.bundle))
                .frame(width: 100, alignment: .center)

            Text(String(localized: "Priority", bundle: RockxyLocalization.bundle))
                .frame(width: 60, alignment: .trailing)
        }
        .font(toolMetrics.secondaryFont())
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text(String(AttributedString(
                localized: "^[\(filteredRules.count) rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Spacer()

            Button(String(localized: "Import", bundle: RockxyLocalization.bundle)) {
                importRules()
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)

            Button(String(localized: "Export", bundle: RockxyLocalization.bundle)) {
                exportRules()
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)
            .disabled(rules.isEmpty)

            Menu(String(localized: "Presets", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "Block Ads", bundle: RockxyLocalization.bundle)) {
                    addPresetRule(
                        name: "Block Ads",
                        pattern: ".*(\\.doubleclick\\.net|ads\\.|adservice\\.).*",
                        action: .block(statusCode: 403)
                    )
                }
                Button(String(localized: "Block Analytics", bundle: RockxyLocalization.bundle)) {
                    addPresetRule(
                        name: "Block Analytics",
                        pattern: ".*(google-analytics\\.com|analytics\\.).*",
                        action: .block(statusCode: 403)
                    )
                }
                Divider()
                Button(String(localized: "Map API Local", bundle: RockxyLocalization.bundle)) {
                    addPresetRule(
                        name: "Map API Local",
                        pattern: ".*/api/.*",
                        action: .mapLocal(filePath: "")
                    )
                }
                Button(String(localized: "Throttle API", bundle: RockxyLocalization.bundle)) {
                    addPresetRule(
                        name: "Throttle API",
                        pattern: ".*/api/.*",
                        action: .throttle(delayMs: 2_000)
                    )
                }
                Divider()
                Button(String(localized: "Breakpoint All", bundle: RockxyLocalization.bundle)) {
                    addPresetRule(
                        name: "Breakpoint All",
                        pattern: ".*",
                        action: .breakpoint()
                    )
                }
                Divider()
                Button(String(localized: "Add CORS Headers", bundle: RockxyLocalization.bundle)) {
                    coordinator.addRule(HeaderModifyPresets.corsHeaders())
                }
                Button(String(localized: "Remove Authorization", bundle: RockxyLocalization.bundle)) {
                    coordinator.addRule(HeaderModifyPresets.removeAuthorization())
                }
                Button(String(localized: "Strip Server Header", bundle: RockxyLocalization.bundle)) {
                    coordinator.addRule(HeaderModifyPresets.stripServerHeader())
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .rockxyFunctionalBar()
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
        panel.title = String(localized: "Import Rules", bundle: RockxyLocalization.bundle)
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
            // Without this the picker just closed: an oversized or malformed rules file failed
            // only into the log, so the window looked like nothing had been asked of it.
            operationAlertTitle = String(localized: "Import Failed", bundle: RockxyLocalization.bundle)
            operationError = error.localizedDescription
            Self.logger.error("Failed to import rules: \(error.localizedDescription)")
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Rules", bundle: RockxyLocalization.bundle)
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "rockxy-rules.json"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try RuleStore().exportRules(to: url)
            Self.logger.info("Exported rules to \(url.lastPathComponent)")
        } catch {
            operationAlertTitle = String(localized: "Export Failed", bundle: RockxyLocalization.bundle)
            operationError = error.localizedDescription
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
                .font(toolMetrics.font(monospaced: true))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 160, alignment: .leading)

            Spacer()

            actionBadge
                .lineLimit(1)
                .frame(width: 140, alignment: .center)

            Text("\(rule.priority)")
                .font(toolMetrics.font(monospaced: true))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder private var actionBadge: some View {
        let (label, color) = actionInfo(rule.action)
        Text(label)
            .font(toolMetrics.metadataFont(weight: .medium))
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
            let opsLabel = String(AttributedString(
                localized: "^[\(count) op](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
            let label = "\(opsLabel) \u{00B7} \(phaseLabel)"
            return (label, .green)
        case let .networkCondition(preset, _, _):
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
                Section(String(localized: "Rule Info", bundle: RockxyLocalization.bundle)) {
                    TextField(String(localized: "Name", bundle: RockxyLocalization.bundle), text: $name)
                }

                Section(String(localized: "Match Condition", bundle: RockxyLocalization.bundle)) {
                    TextField(String(localized: "URL Pattern (regex)", bundle: RockxyLocalization.bundle), text: $urlPattern)
                        .font(toolMetrics.font(monospaced: true))
                    TextField(String(localized: "HTTP Method", bundle: RockxyLocalization.bundle), text: $method)
                        .textCase(.uppercase)
                }

                Section(String(localized: "Action", bundle: RockxyLocalization.bundle)) {
                    Picker(
                        String(localized: "Action type", bundle: RockxyLocalization.bundle),
                        selection: $selectedAction
                    ) {
                        ForEach(RuleActionType.creatableCases) { actionType in
                            Text(actionType.displayName).tag(actionType)
                        }
                    }

                    switch selectedAction {
                    case .block:
                        TextField(
                            String(localized: "Status code", bundle: RockxyLocalization.bundle),
                            value: $blockStatusCode,
                            format: .number
                        )
                    case .throttle:
                        TextField(
                            String(localized: "Delay (ms)", bundle: RockxyLocalization.bundle),
                            value: $throttleDelay,
                            format: .number
                        )
                    case .mapLocal:
                        TextField(
                            String(localized: "File path", bundle: RockxyLocalization.bundle),
                            text: $mapLocalPath
                        )
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
                Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Add Rule", bundle: RockxyLocalization.bundle)) {
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
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(
            width: selectedAction == .modifyHeader ? toolMetrics.fieldWidth(620) : toolMetrics.fieldWidth(420),
            height: selectedAction == .modifyHeader ? toolMetrics.fieldWidth(520) : toolMetrics.fieldWidth(380)
        )
        .animation(.easeInOut(duration: 0.2), value: selectedAction)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlPattern = ""
    @State private var method = ""
    @State private var selectedAction: RuleActionType = .block

    @State private var blockStatusCode = 403
    @State private var throttleDelay = 1_000
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

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
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
