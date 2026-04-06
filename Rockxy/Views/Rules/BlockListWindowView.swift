import os
import SwiftUI

// Presents the block list window for rule editing and management.

// MARK: - BlockListViewModel

@MainActor @Observable
final class BlockListViewModel {
    var selectedRuleID: UUID?
    var showAddSheet = false
    private(set) var allRules: [ProxyRule] = []

    var blockRules: [ProxyRule] {
        allRules.filter { rule in
            if case .block = rule.action {
                return true
            }
            return false
        }
    }

    var ruleCount: Int {
        blockRules.count
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
        }
    }

    func addBlockRule(urlPattern: String, matchType: BlockMatchType, blockAction: BlockActionType) {
        let escapedPattern: String = switch matchType {
        case .wildcard:
            NSRegularExpression.escapedPattern(for: urlPattern)
                .replacingOccurrences(of: "\\*", with: ".*")
        case .regex:
            urlPattern
        case .exact:
            "^" + NSRegularExpression.escapedPattern(for: urlPattern) + "$"
        }

        let statusCode = switch blockAction {
        case .forbidden: 403
        case .dropConnection: 0
        }

        let rule = ProxyRule(
            name: urlPattern,
            matchCondition: RuleMatchCondition(urlPattern: escapedPattern),
            action: .block(statusCode: statusCode)
        )
        allRules.append(rule)
        Task { await RuleSyncService.addRule(rule) }
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
}

// MARK: - BlockMatchType

enum BlockMatchType: String, CaseIterable {
    case wildcard = "Wildcard"
    case regex = "Regex"
    case exact = "Exact"
}

// MARK: - BlockActionType

enum BlockActionType: String, CaseIterable {
    case forbidden = "403 Forbidden"
    case dropConnection = "Drop Connection"
}

// MARK: - BlockListWindowView

struct BlockListWindowView: View {
    // MARK: Internal

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
        .frame(width: 600, height: 480)
        .task { await viewModel.refreshFromEngine() }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            AddBlockRuleSheet { pattern, matchType, action in
                viewModel.addBlockRule(urlPattern: pattern, matchType: matchType, blockAction: action)
            }
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "BlockListWindowView")

    @State private var viewModel = BlockListViewModel()

    private var toolbar: some View {
        HStack {
            Text(String(localized: "Block List"))
                .font(.headline)
            Spacer()
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
                    "Blocked requests return 403 Forbidden or are silently dropped. Use wildcards (*) or regex for pattern matching."
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
        if viewModel.blockRules.isEmpty {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "nosign")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text(String(localized: "No Block Rules"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Add URL patterns to block matching requests."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red.opacity(0.4))
                        .frame(width: 2, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Example"))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 5) {
                            Text("*.example.com/ads/*")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text("403 Forbidden")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.leading, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 12)
        } else {
            List(selection: $viewModel.selectedRuleID) {
                ForEach(viewModel.blockRules) { rule in
                    BlockRuleRow(rule: rule) {
                        viewModel.toggleRule(id: rule.id)
                    }
                    .tag(rule.id)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - BlockRuleRow

private struct BlockRuleRow: View {
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
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            matchTypeBadge

            Spacer()

            actionLabel
        }
        .padding(.vertical, 2)
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }

    // MARK: Private

    @ViewBuilder private var matchTypeBadge: some View {
        let detected = detectMatchType(rule.matchCondition.urlPattern ?? "")
        HStack(spacing: 4) {
            Text(detected.symbol)
                .font(.caption2.bold())
                .frame(width: 18, height: 18)
                .background(detected.color.opacity(0.15))
                .foregroundStyle(detected.color)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if detected.isAutoDetected {
                Text(String(localized: "auto"))
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.yellow.opacity(0.2))
                    .foregroundStyle(.yellow)
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder private var actionLabel: some View {
        if case let .block(statusCode) = rule.action {
            let text = statusCode == 0 ? String(localized: "Drop Connection") : String(localized: "403 Forbidden")
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func detectMatchType(_ pattern: String) -> (symbol: String, color: Color, isAutoDetected: Bool) {
        let isAnchored = pattern.hasPrefix("^") && pattern.hasSuffix("$")
        let regexSpecial = CharacterSet(charactersIn: "[](){}+?|^$\\")
        let hasRegexChars = pattern.unicodeScalars.contains { regexSpecial.contains($0) }

        if isAnchored, !hasRegexInner(pattern) {
            return ("=", .green, true)
        } else if hasRegexChars {
            return ("R", .purple, true)
        } else {
            return ("*", .blue, true)
        }
    }

    private func hasRegexInner(_ pattern: String) -> Bool {
        let inner = String(pattern.dropFirst().dropLast())
        let unescaped = inner.replacingOccurrences(of: "\\.", with: "")
        let regexSpecial = CharacterSet(charactersIn: "[](){}+?|^$\\.*")
        return unescaped.unicodeScalars.contains { regexSpecial.contains($0) }
    }
}

// MARK: - AddBlockRuleSheet

private struct AddBlockRuleSheet: View {
    // MARK: Internal

    let onSave: (String, BlockMatchType, BlockActionType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(String(localized: "URL Pattern")) {
                    TextField(String(localized: "e.g. *.example.com/ads/*"), text: $urlPattern)
                        .font(.system(.body, design: .monospaced))
                }

                Section(String(localized: "Match Type")) {
                    Picker(String(localized: "Match Type"), selection: $matchType) {
                        ForEach(BlockMatchType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(String(localized: "Block Action")) {
                    Picker(String(localized: "Action"), selection: $blockAction) {
                        ForEach(BlockActionType.allCases, id: \.self) { action in
                            Text(action.rawValue).tag(action)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Add")) {
                    onSave(urlPattern, matchType, blockAction)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlPattern.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 300)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var urlPattern = ""
    @State private var matchType: BlockMatchType = .wildcard
    @State private var blockAction: BlockActionType = .forbidden
}
