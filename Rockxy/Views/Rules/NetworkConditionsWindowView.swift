import AppKit
import Darwin
import os
import SwiftUI

// The management window, editor, and their testable form contracts remain colocated
// while this workflow is stabilized so rule semantics cannot drift across files.
// swiftlint:disable file_length

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
            name: title(for: preset),
            latencyMs: effectiveLatency,
            downloadBandwidth: preset.downloadBandwidthLabel,
            uploadBandwidth: preset.uploadBandwidthLabel,
            packetLoss: preset.packetLossLabel,
            systemImage: preset.systemImage
        )
    }

    static func title(for preset: NetworkConditionPreset) -> String {
        preset == .custom ? String(localized: "Custom Latency", bundle: RockxyLocalization.bundle) : preset.displayName
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return conditions
        }
        return conditions.filter { rule in
            rule.name.localizedCaseInsensitiveContains(query)
                || (rule.matchCondition.urlPattern ?? "").localizedCaseInsensitiveContains(query)
                || hostLabel(for: rule).localizedCaseInsensitiveContains(query)
                || networkProfile(for: rule).name.localizedCaseInsensitiveContains(query)
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
        if rule.isEnabled {
            for index in allRules.indices {
                if case .networkCondition = allRules[index].action, allRules[index].isEnabled {
                    allRules[index].isEnabled = false
                }
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

    @discardableResult
    func saveRule(_ rule: ProxyRule, using gate: RulePolicyGate = .shared) async -> Bool {
        guard commitChanges else {
            if allRules.contains(where: { $0.id == rule.id }) {
                updateRule(rule)
            } else {
                addRule(rule)
            }
            return true
        }

        if allRules.contains(where: { $0.id == rule.id }) {
            await gate.updateRule(rule)
        } else {
            let accepted = if rule.isEnabled {
                await gate.addNetworkConditionExclusive(rule)
            } else {
                await gate.addRule(rule)
            }
            guard accepted else {
                allRules = await RuleEngine.shared.allRules
                reconcileSelectionAfterRulesChange()
                return false
            }
        }

        allRules = await RuleEngine.shared.allRules
        selectedRuleID = rule.id
        reconcileSelectionAfterRulesChange()
        return true
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
            name: String(localized: "Copy of \(selectedRule.name)", bundle: RockxyLocalization.bundle),
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
            return String(localized: "System-wide", bundle: RockxyLocalization.bundle)
        }
        return Self.readableHost(from: pattern)
    }

    func statusLabel(for rule: ProxyRule) -> (String, Color) {
        guard isToolEnabled else {
            return (String(localized: "Paused", bundle: RockxyLocalization.bundle), .secondary)
        }
        guard rule.isEnabled else {
            return (String(localized: "Inactive", bundle: RockxyLocalization.bundle), .secondary)
        }
        if hasMultipleActive {
            return (String(localized: "Conflict", bundle: RockxyLocalization.bundle), .orange)
        }
        return (String(localized: "Enabled", bundle: RockxyLocalization.bundle), .green)
    }

    // MARK: Private

    private static let toolEnabledKey = "networkConditionsToolEnabled"
    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "NetworkConditionsWindowViewModel"
    )

    private static var defaultToolEnabled: Bool {
        UserDefaults.standard.object(forKey: toolEnabledKey) as? Bool ?? true
    }

    private let commitChanges: Bool

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

// MARK: - NetworkConditionsPatternFormatter

enum NetworkConditionsPatternFormatter {
    // MARK: Internal

    static func hostScopedPattern(from hostText: String) -> String {
        let host = normalizedHostAndPort(from: hostText)
        let escapedHost = NSRegularExpression.escapedPattern(for: host)
        let portPattern = hostContainsPort(host) ? "" : "(?::\\d+)?"
        return "(?i)^https?://\(escapedHost)\(portPattern)(?:/.*)?$"
    }

    static func hostText(from pattern: String?) -> String {
        guard var value = pattern, !value.isEmpty else {
            return ""
        }
        value = value.replacingOccurrences(of: "(?i)", with: "")
        value = value.replacingOccurrences(of: "^https?://", with: "")
        value = value.replacingOccurrences(of: "^", with: "")
        value = value.replacingOccurrences(of: "$", with: "")
        value = value.replacingOccurrences(of: "(?:/.*)?", with: "")
        value = value.replacingOccurrences(of: "(?::\\d+)?", with: "")
        value = value.replacingOccurrences(of: "\\.", with: ".")
        value = value.replacingOccurrences(of: "\\:", with: ":")
        value = value.replacingOccurrences(of: "\\[", with: "[")
        value = value.replacingOccurrences(of: "\\]", with: "]")
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[..<slashIndex])
        }
        return value.isEmpty ? pattern ?? "" : value
    }

    static func hostValidationMessage(for hostText: String) -> String? {
        let trimmed = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return String(localized: "Enter a host or choose All proxied traffic.", bundle: RockxyLocalization.bundle)
        }
        guard normalizedHostAndPortIfValid(from: trimmed) != nil else {
            return String(
                localized:
                "Enter a valid hostname, IPv4 address, or IPv6 address with an optional port from 1 to 65535.",
                bundle: RockxyLocalization.bundle
            )
        }
        return nil
    }

    // MARK: Private

    private static let supportedURLSchemes = Set(["http", "https"])

    private static func normalizedHostAndPort(from hostText: String) -> String {
        normalizedHostAndPortIfValid(from: hostText)
            ?? hostText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedHostAndPortIfValid(from hostText: String) -> String? {
        let value = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace), !value.contains("@") else {
            return nil
        }

        if value.contains("://") {
            guard let components = URLComponents(string: value),
                  let scheme = components.scheme?.lowercased(),
                  supportedURLSchemes.contains(scheme),
                  let host = components.host,
                  !host.isEmpty,
                  components.user == nil,
                  components.password == nil else
            {
                return nil
            }
            let unwrappedHost = host.hasPrefix("[") && host.hasSuffix("]")
                ? String(host.dropFirst().dropLast())
                : host
            guard let normalizedHost = normalizedHostIfValid(unwrappedHost) else {
                return nil
            }
            let authorityHost = normalizedHost.contains(":") ? "[\(normalizedHost)]" : normalizedHost
            guard let port = components.port else {
                return authorityHost
            }
            guard (1 ... 65_535).contains(port) else {
                return nil
            }
            return "\(authorityHost):\(port)"
        }

        guard !value.contains(where: { $0 == "/" || $0 == "?" || $0 == "#" }) else {
            return nil
        }

        if value.hasPrefix("[") {
            guard let closingBracket = value.firstIndex(of: "]") else {
                return nil
            }
            let bracketedHost = String(value[...closingBracket])
            let innerHost = String(value[value.index(after: value.startIndex) ..< closingBracket])
            guard isValidIPv6(innerHost) else {
                return nil
            }
            let remainder = String(value[value.index(after: closingBracket)...])
            guard !remainder.isEmpty else {
                return bracketedHost.lowercased()
            }
            guard remainder.hasPrefix(":"),
                  let port = Int(remainder.dropFirst()),
                  (1 ... 65_535).contains(port) else
            {
                return nil
            }
            return "\(bracketedHost.lowercased()):\(port)"
        }

        if value.filter({ $0 == ":" }).count > 1 {
            guard isValidIPv6(value) else {
                return nil
            }
            return "[\(value.lowercased())]"
        }

        if let colon = value.lastIndex(of: ":") {
            let host = String(value[..<colon])
            guard let port = Int(value[value.index(after: colon)...]),
                  let normalizedHost = normalizedHostIfValid(host),
                  (1 ... 65_535).contains(port) else
            {
                return nil
            }
            return "\(normalizedHost):\(port)"
        }

        return normalizedHostIfValid(value)
    }

    private static func normalizedHostIfValid(_ host: String) -> String? {
        let normalized = host.lowercased()
        if isValidIPv4(normalized) || isValidIPv6(normalized) {
            return normalized
        }
        guard normalized.utf8.count <= 253 else {
            return nil
        }

        let hostname = normalized.hasSuffix(".") ? String(normalized.dropLast()) : normalized
        guard !hostname.isEmpty else {
            return nil
        }
        if hostname.allSatisfy({ $0.isNumber || $0 == "." }) {
            return nil
        }

        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty
                && label.utf8.count <= 63
                && label.first != "-"
                && label.last != "-"
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else {
            return nil
        }
        return hostname
    }

    private static func isValidIPv4(_ host: String) -> Bool {
        var address = in_addr()
        return host.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    private static func isValidIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1
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
    // MARK: Internal

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
        customLatencyMs: Int,
        original: ProxyRule? = nil
    )
        -> Bool
    {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (preset.isOffline || effectiveLatencyMs(preset: preset, customLatencyMs: customLatencyMs) > 0)
            && hostValidationMessage(
                original: original,
                hostText: hostText,
                applySystemWide: applySystemWide
            ) == nil
    }

    static func hostValidationMessage(
        original: ProxyRule?,
        hostText: String,
        applySystemWide: Bool
    )
        -> String?
    {
        guard !applySystemWide, !scopeIsUnchanged(
            original: original,
            hostText: hostText,
            applySystemWide: applySystemWide
        ) else {
            return nil
        }
        return NetworkConditionsPatternFormatter.hostValidationMessage(for: hostText)
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
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            matchCondition: condition,
            action: .networkCondition(
                preset: preset,
                delayMs: effectiveLatencyMs(preset: preset, customLatencyMs: customLatencyMs)
            )
        )
    }

    static func makeRule(
        original: ProxyRule?,
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
        let originalCondition = original?.matchCondition
        let originalPattern = originalCondition?.urlPattern
        let scopeIsUnchanged = scopeIsUnchanged(
            original: original,
            hostText: trimmedHost,
            applySystemWide: applySystemWide
        )

        let updatedPattern: String? = if scopeIsUnchanged {
            originalPattern
        } else if applySystemWide || trimmedHost.isEmpty {
            nil
        } else {
            NetworkConditionsPatternFormatter.hostScopedPattern(from: trimmedHost)
        }

        let condition = RuleMatchCondition(
            urlPattern: updatedPattern,
            sourceURLPattern: scopeIsUnchanged ? originalCondition?.sourceURLPattern : nil,
            method: originalCondition?.method,
            headerName: originalCondition?.headerName,
            headerValue: originalCondition?.headerValue,
            matchType: scopeIsUnchanged ? originalCondition?.matchType : nil,
            includeSubpaths: scopeIsUnchanged ? originalCondition?.includeSubpaths : nil
        )

        return ProxyRule(
            id: original?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            matchCondition: condition,
            action: .networkCondition(
                preset: preset,
                delayMs: effectiveLatencyMs(preset: preset, customLatencyMs: customLatencyMs)
            ),
            priority: original?.priority ?? 0
        )
    }

    // MARK: Private

    private static func scopeIsUnchanged(
        original: ProxyRule?,
        hostText: String,
        applySystemWide: Bool
    )
        -> Bool
    {
        guard let original else {
            return false
        }
        let originalPattern = original.matchCondition.urlPattern
        let originalWasSystemWide = originalPattern == nil
        let originalHostText = NetworkConditionsPatternFormatter.hostText(from: originalPattern)
        let trimmedHost = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        return originalWasSystemWide == applySystemWide
            && (
                applySystemWide
                    || originalHostText.caseInsensitiveCompare(trimmedHost) == .orderedSame
            )
    }
}

// MARK: - NetworkConditionsEditorSession

private struct NetworkConditionsEditorSession: Identifiable {
    let id = UUID()
    let existingRule: ProxyRule?
    let draft: NetworkConditionsDraft?
}

// MARK: - NetworkConditionsWindowView

struct NetworkConditionsWindowView: View {
    // MARK: Internal

    @State var viewModel = NetworkConditionsWindowViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            infoBanner
            Divider()
            tableContent
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(900, toolMetrics.bodyFontSize * 30 + 520),
            minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)
        )
        .task { await viewModel.loadRules() }
        .onAppear { consumePendingDraft() }
        .onReceive(NotificationCenter.default.publisher(for: .openNetworkConditionsWindow)) { _ in
            consumePendingDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(item: $editorSession) { session in
            NetworkConditionsEditSheet(
                existingRule: session.existingRule,
                draft: session.draft,
                willReplaceEnabledRule: session.existingRule == nil && viewModel.activeCount > 0,
                onSave: { rule in
                    await viewModel.saveRule(rule)
                }
            )
            .id(session.id)
        }
        .onDeleteCommand {
            viewModel.removeSelectedRule()
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    @FocusState private var isSearchFocused: Bool
    @State private var editorSession: NetworkConditionsEditorSession?

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var enableDisableLabel: String {
        guard let selectedRule = viewModel.selectedRule else {
            return String(localized: "Toggle", bundle: RockxyLocalization.bundle)
        }
        return selectedRule.isEnabled ? String(localized: "Disable", bundle: RockxyLocalization.bundle) : String(
            localized: "Enable",
            bundle: RockxyLocalization.bundle
        )
    }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footerHint: String {
        let countText = isSearching
            ? String(AttributedString(
                localized: "\(viewModel.filteredRules.count) of ^[\(viewModel.ruleCount) rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
            : String(AttributedString(
                localized: "^[\(viewModel.ruleCount) rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        return "\(countText) · ⌘N \(String(localized: "New Rule", bundle: RockxyLocalization.bundle)) · ⌘↩ \(String(localized: "Edit", bundle: RockxyLocalization.bundle))"
    }

    private var infoBannerText: String {
        if viewModel.hasMultipleActive {
            return String(
                localized:
                "Multiple profiles are enabled in stored rules. Choose one profile to restore exclusive behavior.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized:
            """
            Only one profile can be enabled. It follows Rockxy's global first-match rule order and applies to \
            intercepted HTTP and HTTPS traffic.
            """, bundle: RockxyLocalization.bundle
        )
    }

    private var statusCapsuleText: String {
        if !viewModel.isToolEnabled {
            return String(localized: "CONDITIONS OFF", bundle: RockxyLocalization.bundle)
        }
        if viewModel.hasMultipleActive {
            return String(localized: "MULTIPLE ENABLED", bundle: RockxyLocalization.bundle)
        }
        if viewModel.activeCount == 0 {
            return String(localized: "NO PROFILE ENABLED", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "1 ENABLED", bundle: RockxyLocalization.bundle)
    }

    private var statusCapsuleIsActive: Bool {
        viewModel.isToolEnabled && (viewModel.hasMultipleActive || viewModel.activeCount == 1)
    }

    private var statusCapsuleTint: Color {
        if viewModel.hasMultipleActive, viewModel.isToolEnabled {
            return .orange
        }
        if viewModel.activeCount == 1, viewModel.isToolEnabled {
            return .green
        }
        return .secondary
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(isOn: Binding(
                    get: { viewModel.isToolEnabled },
                    set: { viewModel.setToolEnabled($0) }
                )) {
                    Text(String(localized: "Enable Network Conditions", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font(weight: .medium))
                }
                .toggleStyle(.checkbox)

                Text(String(
                    localized: "Simulate latency and bandwidth limits for matching HTTP and HTTPS traffic.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }

            Spacer()

            TextField(String(localized: "Search rules", bundle: RockxyLocalization.bundle), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(width: 240, height: toolMetrics.formControlHeight)
                .focused($isSearchFocused)
                .accessibilityLabel(String(
                    localized: "Search Network Conditions rules",
                    bundle: RockxyLocalization.bundle
                ))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.hasMultipleActive ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(viewModel.hasMultipleActive ? .orange : .secondary)
            Text(infoBannerText)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(viewModel.hasMultipleActive ? Color.primary : Color.secondary)
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(
            viewModel.hasMultipleActive
                ? Color.orange.opacity(0.1)
                : Color(nsColor: .controlBackgroundColor).opacity(0.5)
        )
    }

    private var tableContent: some View {
        Table(viewModel.filteredRules, selection: $viewModel.selectedRuleID) {
            TableColumn(String(localized: "Enabled", bundle: RockxyLocalization.bundle)) { rule in
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in viewModel.toggleRule(id: rule.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(
                    String(
                        localized: "Enable \(rule.name.isEmpty ? "Untitled" : rule.name)",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
            .width(62)

            TableColumn(String(localized: "Name", bundle: RockxyLocalization.bundle)) { rule in
                Text(rule.name.isEmpty ? String(localized: "Untitled", bundle: RockxyLocalization.bundle) : rule.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.name)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 150, ideal: 200)

            TableColumn(String(localized: "Scope", bundle: RockxyLocalization.bundle)) { rule in
                Text(viewModel.hostLabel(for: rule))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.matchCondition.urlPattern ?? String(
                        localized: "System-wide",
                        bundle: RockxyLocalization.bundle
                    ))
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 180, ideal: 260)

            TableColumn(String(localized: "Profile", bundle: RockxyLocalization.bundle)) { rule in
                let profile = viewModel.networkProfile(for: rule)
                Text(profile.name)
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 110, ideal: 145)

            TableColumn(String(localized: "Latency", bundle: RockxyLocalization.bundle)) { rule in
                Text(String(
                    localized: "\(viewModel.networkProfile(for: rule).latencyMs) ms",
                    bundle: RockxyLocalization.bundle
                ))
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(84)

            TableColumn(String(localized: "Download", bundle: RockxyLocalization.bundle)) { rule in
                Text(viewModel.networkProfile(for: rule).downloadBandwidth)
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 105, ideal: 125)

            TableColumn(String(localized: "Upload", bundle: RockxyLocalization.bundle)) { rule in
                Text(viewModel.networkProfile(for: rule).uploadBandwidth)
                    .lineLimit(1)
                    .opacity(rule.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 105, ideal: 125)
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
                ContentUnavailableView(
                    isSearching
                        ? String(localized: "No matching rules", bundle: RockxyLocalization.bundle)
                        : String(localized: "No Network Conditions rules", bundle: RockxyLocalization.bundle),
                    systemImage: isSearching ? "magnifyingglass" : "speedometer",
                    description: Text(
                        isSearching
                            ? String(
                                localized: "Try a different name, scope, or profile.",
                                bundle: RockxyLocalization.bundle
                            )
                            : String(
                                localized: "Click \"+\" or press ⌘N to create a profile.",
                                bundle: RockxyLocalization.bundle
                            )
                    )
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl

            Text(footerHint)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Spacer()

            moreMenu

            Text(statusCapsuleText)
                .font(toolMetrics.metadataFont(weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .rockxyChipStyle(tint: statusCapsuleTint, isActive: statusCapsuleIsActive)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                openNewEditor()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "New Rule", bundle: RockxyLocalization.bundle))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Button {
                viewModel.removeSelectedRule()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(viewModel.selectedRuleID == nil ? .tertiary : .primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
            .help(String(localized: "Delete Rule", bundle: RockxyLocalization.bundle))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(width: max(43, toolMetrics.compactButtonSize * 2 + 1), height: toolMetrics.footerControlHeight)
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New Rule", bundle: RockxyLocalization.bundle)) {
                openNewEditor()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(String(localized: "Edit Rule", bundle: RockxyLocalization.bundle)) {
                openEditorForSelection()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedRule == nil)

            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                viewModel.duplicateSelectedRule()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel.selectedRule == nil)

            Button(enableDisableLabel) {
                if let id = viewModel.selectedRuleID {
                    viewModel.toggleRule(id: id)
                }
            }
            .disabled(viewModel.selectedRule == nil)

            Divider()

            Button(String(localized: "Focus Search", bundle: RockxyLocalization.bundle)) {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(String(localized: "Disable All", bundle: RockxyLocalization.bundle)) {
                viewModel.disableAll()
            }
            .disabled(viewModel.activeCount == 0)

            Divider()

            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                viewModel.removeSelectedRule()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More", bundle: RockxyLocalization.bundle))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .rockxyGlassButtonStyle()
        .fixedSize()
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first {
            Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                if let rule = viewModel.allRules.first(where: { $0.id == id }) {
                    openEditor(for: rule)
                }
            }
            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                viewModel.selectedRuleID = id
                viewModel.duplicateSelectedRule()
            }
            Button(enableDisableContextLabel(for: id)) {
                viewModel.toggleRule(id: id)
            }
            Divider()
            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                viewModel.removeRule(id: id)
            }
        }
    }

    private func enableDisableContextLabel(for id: UUID) -> String {
        guard let rule = viewModel.allRules.first(where: { $0.id == id }) else {
            return String(localized: "Toggle", bundle: RockxyLocalization.bundle)
        }
        return rule.isEnabled ? String(localized: "Disable", bundle: RockxyLocalization.bundle) : String(
            localized: "Enable",
            bundle: RockxyLocalization.bundle
        )
    }

    private func openNewEditor() {
        editorSession = NetworkConditionsEditorSession(existingRule: nil, draft: nil)
    }

    private func openEditorForSelection() {
        guard let rule = viewModel.selectedRule else {
            return
        }
        openEditor(for: rule)
    }

    private func openEditor(for rule: ProxyRule) {
        editorSession = NetworkConditionsEditorSession(existingRule: rule, draft: nil)
    }

    private func consumePendingDraft() {
        guard let draft = NetworkConditionsDraftStore.shared.consumePending() else {
            return
        }
        editorSession = NetworkConditionsEditorSession(existingRule: nil, draft: draft)
    }
}

// MARK: - NetworkConditionsEditSheet

private struct NetworkConditionsEditSheet: View {
    // MARK: Lifecycle

    init(
        existingRule: ProxyRule?,
        draft: NetworkConditionsDraft? = nil,
        willReplaceEnabledRule: Bool,
        onSave: @escaping (ProxyRule) async -> Bool
    ) {
        self.onSave = onSave
        self.existingRule = existingRule
        self.draft = draft
        self.willReplaceEnabledRule = willReplaceEnabledRule

        if let existingRule {
            _name = State(initialValue: existingRule.name)
            _hostText = State(
                initialValue: NetworkConditionsPatternFormatter.hostText(
                    from: existingRule.matchCondition.urlPattern
                )
            )
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

    let onSave: (ProxyRule) async -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing + 3) {
                    Text(editorTitle)
                        .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))

                    if let provenance = quickCreateProvenance {
                        provenanceBanner(provenance)
                    }

                    ruleDetailsSection
                    networkProfileSection

                    if willReplaceEnabledRule {
                        Label(
                            String(
                                localized:
                                "Adding this enabled profile will disable the profile that is currently enabled.",
                                bundle: RockxyLocalization.bundle
                            ),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, toolMetrics.formHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
            }

            Divider()
            VStack(alignment: .trailing, spacing: toolMetrics.controlSpacing) {
                if let saveError {
                    validationLabel(saveError)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)

                    Button {
                        Task { await saveRule() }
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
                    .keyboardShortcut(.defaultAction)
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
            minHeight: max(460, toolMetrics.bodyFontSize * 14 + 278)
        )
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var name = NetworkConditionsRuleForm.defaultName
    @State private var hostText = ""
    @State private var applySystemWide = false
    @State private var selectedPreset = NetworkConditionsRuleForm.defaultPreset
    @State private var customLatencyMs = NetworkConditionsRuleForm.defaultCustomLatencyMs
    @State private var isEnabled = true
    @State private var isSaving = false
    @State private var saveError: String?

    private let existingRule: ProxyRule?
    private let draft: NetworkConditionsDraft?
    private let willReplaceEnabledRule: Bool

    private var isEditing: Bool {
        existingRule != nil
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
            customLatencyMs: customLatencyMs,
            original: existingRule
        )
    }

    private var editorTitle: String {
        isEditing
            ? String(localized: "Edit Network Conditions Rule", bundle: RockxyLocalization.bundle)
            : String(localized: "New Network Conditions Rule", bundle: RockxyLocalization.bundle)
    }

    private var quickCreateProvenance: String? {
        guard let draft else {
            return nil
        }
        if let sourceURL = draft.sourceURL {
            let method = draft.sourceMethod ?? "ANY"
            let path = sourceURL.path.isEmpty ? "/" : sourceURL.path
            return String(
                localized: "Created from \(method) \(draft.sourceHost)\(path)",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(localized: "Created from domain \(draft.sourceHost)", bundle: RockxyLocalization.bundle)
    }

    private var scopeHelpText: String {
        if applySystemWide {
            return String(
                localized:
                """
                This profile is eligible for intercepted HTTP and HTTPS traffic that reaches it in Rockxy's \
                global first-match rule order.
                """, bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized:
            """
            Enter a host with an optional port, or paste an HTTP or HTTPS URL. URL paths and queries are ignored. \
            Wildcards and raw regular expressions are not added from this editor.
            """, bundle: RockxyLocalization.bundle
        )
    }

    private var hostValidationMessage: String? {
        guard !applySystemWide else {
            return nil
        }
        return NetworkConditionsRuleForm.hostValidationMessage(
            original: existingRule,
            hostText: hostText,
            applySystemWide: applySystemWide
        )
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
                        TextField(String(localized: "Untitled", bundle: RockxyLocalization.bundle), text: $name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(String(localized: "Rule name", bundle: RockxyLocalization.bundle))
                    }
                    .frame(width: max(250, toolMetrics.fieldWidth(250)))

                    fieldGroup(String(localized: "Scope", bundle: RockxyLocalization.bundle)) {
                        scopeMenu
                    }
                    .frame(width: toolMetrics.menuWidth(190))

                    fieldGroup(String(localized: "Host", bundle: RockxyLocalization.bundle)) {
                        TextField("api.example.com", text: $hostText)
                            .textFieldStyle(.roundedBorder)
                            .disabled(applySystemWide)
                            .accessibilityLabel(String(
                                localized: "Network Conditions host",
                                bundle: RockxyLocalization.bundle
                            ))
                    }
                    .frame(maxWidth: .infinity)
                }

                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    validationLabel(String(localized: "Enter a rule name.", bundle: RockxyLocalization.bundle))
                }
                if let hostValidationMessage {
                    validationLabel(hostValidationMessage)
                }

                Text(scopeHelpText)
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

    private var networkProfileSection: some View {
        let metadata = NetworkConditionProfileMetadata.from(preset: selectedPreset, latencyMs: effectiveLatencyMs)
        return VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Network Profile", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                    fieldGroup(String(localized: "Preset", bundle: RockxyLocalization.bundle)) {
                        presetMenu
                    }
                    .frame(width: toolMetrics.menuWidth(190))

                    if selectedPreset == .custom {
                        fieldGroup(String(localized: "Latency", bundle: RockxyLocalization.bundle)) {
                            HStack(spacing: 6) {
                                TextField("", value: $customLatencyMs, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: toolMetrics.fieldWidth(90))
                                    .accessibilityLabel(String(
                                        localized: "Custom latency",
                                        bundle: RockxyLocalization.bundle
                                    ))
                                Text(String(localized: "ms", bundle: RockxyLocalization.bundle))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                }

                if selectedPreset == .custom, customLatencyMs <= 0 {
                    validationLabel(String(
                        localized: "Custom latency must be greater than 0 ms.",
                        bundle: RockxyLocalization.bundle
                    ))
                }

                HStack(spacing: toolMetrics.controlSpacing) {
                    profileMetric(
                        title: String(localized: "Latency", bundle: RockxyLocalization.bundle),
                        value: "\(metadata.latencyMs) ms",
                        systemImage: "timer"
                    )
                    profileMetric(
                        title: String(localized: "Download", bundle: RockxyLocalization.bundle),
                        value: metadata.downloadBandwidth,
                        systemImage: "arrow.down"
                    )
                    profileMetric(
                        title: String(localized: "Upload", bundle: RockxyLocalization.bundle),
                        value: metadata.uploadBandwidth,
                        systemImage: "arrow.up"
                    )
                }

                Text(
                    String(
                        localized:
                        """
                        Presets add connection latency and pace request and response bodies at the displayed limits. \
                        Custom Latency leaves upload and download bandwidth unlimited.
                        """, bundle: RockxyLocalization.bundle
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

    private var scopeMenu: some View {
        Menu {
            Button {
                applySystemWide = false
            } label: {
                menuCheckmarkLabel(
                    String(localized: "Specific host", bundle: RockxyLocalization.bundle),
                    isSelected: !applySystemWide
                )
            }
            Button {
                applySystemWide = true
            } label: {
                menuCheckmarkLabel(
                    String(localized: "All proxied traffic", bundle: RockxyLocalization.bundle),
                    isSelected: applySystemWide
                )
            }
        } label: {
            dataEntryMenuLabel(
                applySystemWide
                    ? String(localized: "All proxied traffic", bundle: RockxyLocalization.bundle)
                    : String(localized: "Specific host", bundle: RockxyLocalization.bundle),
                width: toolMetrics.menuWidth(190)
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Traffic scope", bundle: RockxyLocalization.bundle))
    }

    private var presetMenu: some View {
        Menu {
            ForEach(NetworkConditionPreset.allCases, id: \.self) { preset in
                Button {
                    selectedPreset = preset
                } label: {
                    menuCheckmarkLabel(profileTitle(for: preset), isSelected: selectedPreset == preset)
                }
            }
        } label: {
            dataEntryMenuLabel(profileTitle(for: selectedPreset), width: toolMetrics.menuWidth(190))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Network profile", bundle: RockxyLocalization.bundle))
    }

    private func profileMetric(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(toolMetrics.font(weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
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

    private func profileTitle(for preset: NetworkConditionPreset) -> String {
        NetworkConditionProfileMetadata.title(for: preset)
    }

    @MainActor
    private func saveRule() async {
        guard !isSaving else {
            return
        }
        let rule = NetworkConditionsRuleForm.makeRule(
            original: existingRule,
            name: name,
            isEnabled: isEnabled,
            hostText: hostText,
            applySystemWide: applySystemWide,
            preset: selectedPreset,
            customLatencyMs: customLatencyMs
        )
        isSaving = true
        saveError = nil
        let accepted = await onSave(rule)
        isSaving = false
        guard accepted else {
            saveError = String(
                localized:
                "This rule could not be saved. Disable another Network Conditions rule and try again.",
                bundle: RockxyLocalization.bundle
            )
            return
        }
        dismiss()
    }
}
