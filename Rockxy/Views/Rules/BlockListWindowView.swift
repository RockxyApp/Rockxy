import os
import SwiftUI

// Presents the block list window for rule editing and management.

// MARK: - BlockListViewModel

@MainActor @Observable
final class BlockListViewModel {
    var selectedRuleID: UUID?
    var showAddSheet = false
    var pendingContext: BlockRuleEditorContext?
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

    func addBlockRule(
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: BlockMatchType,
        blockAction: BlockActionType,
        includeSubpaths: Bool
    ) {
        let escapedPattern: String
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
            escapedPattern = pattern
        case .regex:
            escapedPattern = urlPattern
        }

        let displayName = ruleName.isEmpty ? urlPattern : ruleName

        let rule = ProxyRule(
            name: displayName,
            matchCondition: RuleMatchCondition(
                urlPattern: escapedPattern,
                method: httpMethod.methodValue
            ),
            action: .block(statusCode: blockAction.statusCode)
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
        .frame(width: 860, height: 620)
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingContext() }
        .onReceive(NotificationCenter.default.publisher(for: .openBlockListWindow)) { _ in
            consumePendingContext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            viewModel.pendingContext = nil
        } content: {
            AddBlockRuleSheet(editorContext: viewModel
                .pendingContext)
            { ruleName, pattern, method, matchType, action, includeSubpaths in
                viewModel.addBlockRule(
                    ruleName: ruleName,
                    urlPattern: pattern,
                    httpMethod: method,
                    matchType: matchType,
                    blockAction: action,
                    includeSubpaths: includeSubpaths
                )
                viewModel.pendingContext = nil
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

    private func consumePendingContext() {
        guard let context = BlockRuleEditorContextStore.shared.consumePending() else {
            return
        }
        viewModel.pendingContext = context
        viewModel.showAddSheet = true
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
            let text = statusCode == 0
                ? String(localized: "Drop Connection")
                : String(localized: "403 Forbidden")
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
    // MARK: Lifecycle

    init(
        editorContext: BlockRuleEditorContext? = nil,
        onSave: @escaping (String, String, HTTPMethodFilter, BlockMatchType, BlockActionType, Bool) -> Void
    ) {
        self.editorContext = editorContext
        self.onSave = onSave
        _ruleName = State(initialValue: editorContext?.suggestedName ?? "")
        _urlPattern = State(initialValue: editorContext?.defaultPattern ?? "")
        _httpMethod = State(initialValue: editorContext?.httpMethod ?? .any)
        _matchType = State(initialValue: editorContext?.defaultMatchType ?? .wildcard)
        _blockAction = State(initialValue: editorContext?.defaultAction ?? .returnForbidden)
        _includeSubpaths = State(initialValue: editorContext?.includeSubpaths ?? true)
    }

    // MARK: Internal

    let editorContext: BlockRuleEditorContext?
    let onSave: (String, String, HTTPMethodFilter, BlockMatchType, BlockActionType, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                provenanceBanner

                formRow(String(localized: "Name:")) {
                    TextField("", text: $ruleName, prompt: Text(String(localized: "Untitled")))
                        .textFieldStyle(.roundedBorder)
                }

                formRow(String(localized: "Matching Rule:")) {
                    TextField("", text: $urlPattern, prompt: Text("https://example.com"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                methodAndMatchRow

                conditionalFields

                formRow(String(localized: "Action:")) {
                    Picker("", selection: $blockAction) {
                        ForEach(BlockActionType.allCases, id: \.self) { action in
                            Text(action.rawValue).tag(action)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel(String(localized: "Action"))
                    .frame(width: 220)
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

                Button(String(localized: "Done")) {
                    onSave(
                        ruleName,
                        urlPattern,
                        httpMethod,
                        matchType,
                        blockAction,
                        includeSubpaths
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlPattern.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    private static let labelWidth: CGFloat = 110

    @Environment(\.dismiss) private var dismiss
    @State private var ruleName: String
    @State private var urlPattern: String
    @State private var httpMethod: HTTPMethodFilter
    @State private var matchType: BlockMatchType
    @State private var blockAction: BlockActionType
    @State private var includeSubpaths: Bool

    @ViewBuilder private var provenanceBanner: some View {
        if let context = editorContext {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Group {
                    switch context.origin {
                    case .selectedTransaction:
                        if let method = context.sourceMethod {
                            Text(
                                String(
                                    localized: "Created from: \(method) \(context.sourceHost)\(context.sourcePath ?? "")"
                                )
                            )
                        } else {
                            Text(
                                String(
                                    localized: "Created from: \(context.sourceHost)\(context.sourcePath ?? "")"
                                )
                            )
                        }
                    case .domainQuickCreate:
                        Text(String(localized: "Created from domain: \(context.sourceHost)"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
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
                ForEach(BlockMatchType.allCases, id: \.self) { type in
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
