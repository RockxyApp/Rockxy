import os
import SwiftUI
import UniformTypeIdentifiers

// Presents the block list window for rule editing and management.

// MARK: - BlockListEditorSession

struct BlockListEditorSession: Identifiable {
    enum Mode {
        case create(context: BlockRuleEditorContext?)
        case edit(rule: ProxyRule)
    }

    let id = UUID()
    let mode: Mode
}

// MARK: - BlockListImportSource

private enum BlockListImportSource {
    case proxyman
    case charlesProxy
}

// MARK: - BlockListViewModel

@MainActor @Observable
final class BlockListViewModel {
    // MARK: Lifecycle

    init() {
        isBlockListActive = UserDefaults.standard.object(forKey: "blockListToolEnabled") as? Bool ?? true
    }

    // MARK: Internal

    var selectedRuleID: UUID?
    var editorSession: BlockListEditorSession?
    var isBlockListActive: Bool
    var searchText = ""
    var mutationError: String?
    private(set) var allRules: [ProxyRule] = []

    var blockRules: [ProxyRule] {
        allRules.filter(\.isBlockRule)
    }

    var ruleCount: Int {
        blockRules.count
    }

    var filteredBlockRules: [ProxyRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return blockRules
        }
        return blockRules.filter { rule in
            rule.name.localizedCaseInsensitiveContains(query)
                || rule.blockActionType.rawValue.localizedCaseInsensitiveContains(query)
                || (rule.matchCondition.method ?? "ANY").localizedCaseInsensitiveContains(query)
                || (rule.matchCondition.sourceURLPattern ?? rule.matchCondition.urlPattern ?? "")
                .localizedCaseInsensitiveContains(query)
        }
    }

    var activeRuleCount: Int {
        blockRules.count(where: \.isEnabled)
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
        reconcileSelectionAfterRulesChange()
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
            reconcileSelectionAfterRulesChange()
        }
    }

    func setBlockListActive(_ active: Bool) {
        isBlockListActive = active
        Task { await RulePolicyGate.shared.setBlockListToolEnabled(active) }
    }

    func presentNewRuleEditor() {
        editorSession = BlockListEditorSession(mode: .create(context: nil))
    }

    func presentEditorForContext(_ context: BlockRuleEditorContext) {
        editorSession = BlockListEditorSession(mode: .create(context: context))
    }

    func presentEditorForEditing(_ rule: ProxyRule) {
        editorSession = BlockListEditorSession(mode: .edit(rule: rule))
    }

    func dismissEditor() {
        editorSession = nil
    }

    func addBlockRule(
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: BlockMatchType,
        blockAction: BlockActionType,
        includeSubpaths: Bool,
        graphQLOperationName: String = "",
        hidesMatchedTraffic: Bool = false
    ) {
        var rule = makeRule(
            ruleName: ruleName,
            urlPattern: urlPattern,
            httpMethod: httpMethod,
            matchType: matchType,
            blockAction: blockAction,
            includeSubpaths: includeSubpaths,
            graphQLOperationName: graphQLOperationName
        )
        rule.hidesMatchedTraffic = hidesMatchedTraffic
        allRules.append(rule)
        selectedRuleID = rule.id
        Task {
            let accepted = await RulePolicyGate.shared.addRule(rule)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
                reconcileSelectionAfterRulesChange()
                mutationError = String(
                    localized: "The active Block List rule limit was reached. Disable another rule and try again.",
                    bundle: RockxyLocalization.bundle
                )
            }
        }
    }

    func updateBlockRule(
        id: UUID,
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: BlockMatchType,
        blockAction: BlockActionType,
        includeSubpaths: Bool,
        graphQLOperationName: String = "",
        hidesMatchedTraffic: Bool = false
    ) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updated = makeRule(
            id: id,
            ruleName: ruleName,
            urlPattern: urlPattern,
            httpMethod: httpMethod,
            matchType: matchType,
            blockAction: blockAction,
            includeSubpaths: includeSubpaths,
            graphQLOperationName: graphQLOperationName
        )
        updated.hidesMatchedTraffic = hidesMatchedTraffic
        updated.isEnabled = allRules[index].isEnabled
        updated.priority = allRules[index].priority
        allRules[index] = updated
        selectedRuleID = updated.id
        Task { await RulePolicyGate.shared.updateRule(updated) }
    }

    func removeSelected() {
        guard let id = selectedRuleID else {
            return
        }
        removeRule(id: id)
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = nil
        }
        Task { await RulePolicyGate.shared.removeRule(id: id) }
    }

    func duplicateSelected() {
        guard let id = selectedRuleID,
              let original = blockRules.first(where: { $0.id == id }) else
        {
            return
        }
        var copy = original
        copy = ProxyRule(
            name: String(localized: "Copy of \(original.name)", bundle: RockxyLocalization.bundle),
            isEnabled: original.isEnabled,
            matchCondition: original.matchCondition,
            action: original.action,
            priority: original.priority
        )
        allRules.append(copy)
        selectedRuleID = copy.id
        Task {
            let accepted = await RulePolicyGate.shared.addRule(copy)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
                reconcileSelectionAfterRulesChange()
            }
        }
    }

    func toggleRule(id: UUID) {
        guard let index = allRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        allRules[index].isEnabled.toggle()
        Task {
            let accepted = await RulePolicyGate.shared.toggleRule(id: id)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
                reconcileSelectionAfterRulesChange()
                mutationError = String(
                    localized: "The active Block List rule limit was reached. Disable another rule and try again.",
                    bundle: RockxyLocalization.bundle
                )
            }
        }
    }

    func exportBlockRules() throws -> Data {
        try BlockListSettingsCodec.exportRules(blockRules)
    }

    func importBlockRules(_ importedRules: [ProxyRule]) {
        // Replace only the Block category against current engine state so a stale
        // window snapshot can never clobber concurrent Map Local (or other-category)
        // additions from another window.
        let nonBlockRules = allRules.filter { !$0.isBlockRule }
        allRules = nonBlockRules + importedRules
        selectedRuleID = importedRules.first?.id
        Task {
            await RulePolicyGate.shared.replaceBlockRules(importedRules)
            allRules = await RuleEngine.shared.allRules
            reconcileSelectionAfterRulesChange()
        }
    }

    // MARK: Private

    private func makeRule(
        id: UUID = UUID(),
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: BlockMatchType,
        blockAction: BlockActionType,
        includeSubpaths: Bool,
        graphQLOperationName: String = ""
    )
        -> ProxyRule
    {
        let operation = graphQLOperationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedPattern = RulePatternBuilder.regexSource(
            rawPattern: urlPattern,
            matchType: matchType,
            includeSubpaths: includeSubpaths
        )
        let displayName = ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? urlPattern
            : ruleName

        return ProxyRule(
            id: id,
            name: displayName,
            matchCondition: RuleMatchCondition(
                urlPattern: escapedPattern,
                sourceURLPattern: urlPattern,
                method: httpMethod.methodValue,
                matchType: matchType,
                includeSubpaths: includeSubpaths,
                graphQLOperationName: operation.isEmpty ? nil : operation
            ),
            action: .block(statusCode: blockAction.statusCode)
        )
    }

    private func reconcileSelectionAfterRulesChange() {
        guard let id = selectedRuleID else {
            return
        }
        if !blockRules.contains(where: { $0.id == id }) {
            selectedRuleID = nil
        }
    }
}

// MARK: - BlockListWindowView

struct BlockListWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            infoBanner
            Divider()
            BlockListTableView(
                rules: viewModel.filteredBlockRules,
                isSearching: !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedRuleID: $viewModel.selectedRuleID,
                onToggle: { viewModel.toggleRule(id: $0) },
                onEdit: openEditorForRule,
                onDelete: { viewModel.removeRule(id: $0) },
                contextMenuItems: contextMenuItems
            )
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496),
            minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)
        )
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingContext() }
        .onReceive(NotificationCenter.default.publisher(for: .openBlockListWindow)) { _ in
            consumePendingContext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(item: $viewModel.editorSession) { session in
            AddBlockRuleSheet(session: session) { ruleName, pattern, method, matchType, action, includeSubpaths, operation, hides in
                switch session.mode {
                case .create:
                    viewModel.addBlockRule(
                        ruleName: ruleName,
                        urlPattern: pattern,
                        httpMethod: method,
                        matchType: matchType,
                        blockAction: action,
                        includeSubpaths: includeSubpaths,
                        graphQLOperationName: operation,
                        hidesMatchedTraffic: hides
                    )
                case let .edit(rule):
                    viewModel.updateBlockRule(
                        id: rule.id,
                        ruleName: ruleName,
                        urlPattern: pattern,
                        httpMethod: method,
                        matchType: matchType,
                        blockAction: action,
                        includeSubpaths: includeSubpaths,
                        graphQLOperationName: operation,
                        hidesMatchedTraffic: hides
                    )
                }
                viewModel.dismissEditor()
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "block-list-settings.json"
        ) { _ in
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .xml, .propertyList],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            String(localized: "Block List", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { displayedErrorMessage != nil },
                set: {
                    if !$0 {
                        importError = nil
                        viewModel.mutationError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) {
                importError = nil
                viewModel.mutationError = nil
            }
        } message: {
            if let displayedErrorMessage {
                Text(displayedErrorMessage)
            }
        }
        .onDeleteCommand {
            viewModel.removeSelected()
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "BlockListWindowView")
    private static let maxImportFileBytes = 1_024 * 1_024

    @State private var viewModel = BlockListViewModel()
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: BlockListSettingsDocument?
    @State private var importError: String?
    @State private var importSource: BlockListImportSource = .proxyman
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var displayedErrorMessage: String? {
        importError ?? viewModel.mutationError
    }

    private var footerHint: String {
        let countText = viewModel.searchText.isEmpty
            ? String(AttributedString(
                localized: "^[\(viewModel.ruleCount) rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
            : String(AttributedString(
                localized: "\(viewModel.filteredBlockRules.count) of ^[\(viewModel.ruleCount) rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        return "\(countText) · ⌘N \(String(localized: "New Rule", bundle: RockxyLocalization.bundle)) · ⌘↩ \(String(localized: "Edit", bundle: RockxyLocalization.bundle))"
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var enableDisableLabel: String {
        guard let id = viewModel.selectedRuleID else {
            return String(localized: "Enable Rule", bundle: RockxyLocalization.bundle)
        }
        return enableDisableLabel(for: id)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(
                    String(localized: "Enable Block List", bundle: RockxyLocalization.bundle),
                    isOn: Binding(
                        get: { viewModel.isBlockListActive },
                        set: { viewModel.setBlockListActive($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font(weight: .medium))
                .help(
                    String(
                        localized: "When off, Block List rules are skipped. Other intervention rules remain active.",
                        bundle: RockxyLocalization.bundle
                    )
                )

                Text(String(
                    localized: "Return 403 Forbidden or drop matching client connections.",
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
                .accessibilityLabel(String(localized: "Search Block List rules", bundle: RockxyLocalization.bundle))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized:
                    "Block List is a network intervention. Enabled rules participate in Rockxy's global first-match runtime order.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(.quaternary.opacity(0.5))
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl

            Button {
                // Help content is intentionally deferred; this mirrors the reference affordance.
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)

            Text(footerHint)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Spacer()

            moreMenu

            Text(
                viewModel.isBlockListActive
                    ? "\(viewModel.activeRuleCount) \(String(localized: "ACTIVE", bundle: RockxyLocalization.bundle))"
                    : String(localized: "BLOCK LIST OFF", bundle: RockxyLocalization.bundle)
            )
            .font(toolMetrics.metadataFont(weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .rockxyChipStyle(tint: .red, isActive: viewModel.isBlockListActive)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.presentNewRuleEditor()
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
                viewModel.removeSelected()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(viewModel.selectedRuleID == nil ? .tertiary : .primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedRuleID == nil)
            .help(String(localized: "Delete Rule", bundle: RockxyLocalization.bundle))
        }
        .frame(width: max(43, toolMetrics.compactButtonSize * 2 + 1), height: toolMetrics.footerControlHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New…", bundle: RockxyLocalization.bundle)) {
                viewModel.presentNewRuleEditor()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                openEditorForSelection()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)

            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                viewModel.duplicateSelected()
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

            Button(String(localized: "Export Settings…", bundle: RockxyLocalization.bundle)) {
                prepareExport()
            }
            .disabled(viewModel.blockRules.isEmpty)

            Menu(String(localized: "Import Settings", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "From Proxyman…", bundle: RockxyLocalization.bundle)) {
                    importSource = .proxyman
                    showImporter = true
                }

                Button(String(localized: "From Charles Proxy…", bundle: RockxyLocalization.bundle)) {
                    importSource = .charlesProxy
                    showImporter = true
                }
            }

            Divider()

            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                viewModel.removeSelected()
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
    private func contextMenuItems(for id: UUID) -> some View {
        Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
            openEditorForRule(id)
        }
        .keyboardShortcut("e", modifiers: .command)

        Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
            viewModel.selectedRuleID = id
            viewModel.duplicateSelected()
        }
        .keyboardShortcut("d", modifiers: .command)

        Button(enableDisableLabel(for: id)) {
            viewModel.toggleRule(id: id)
        }
        .keyboardShortcut(.return, modifiers: [])

        Button(enableDisableLabel(for: id)) {
            viewModel.toggleRule(id: id)
        }
        .keyboardShortcut(.space, modifiers: [])

        Divider()

        Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
            viewModel.removeRule(id: id)
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private func enableDisableLabel(for id: UUID) -> String {
        guard let rule = viewModel.blockRules.first(where: { $0.id == id }) else {
            return String(localized: "Enable Rule", bundle: RockxyLocalization.bundle)
        }
        return rule.isEnabled ? String(localized: "Disable Rule", bundle: RockxyLocalization.bundle) : String(
            localized: "Enable Rule",
            bundle: RockxyLocalization.bundle
        )
    }

    private func openEditorForSelection() {
        guard let id = viewModel.selectedRuleID else {
            return
        }
        openEditorForRule(id)
    }

    private func openEditorForRule(_ id: UUID) {
        guard let rule = viewModel.blockRules.first(where: { $0.id == id }) else {
            return
        }
        viewModel.selectedRuleID = id
        viewModel.presentEditorForEditing(rule)
    }

    private func consumePendingContext() {
        guard let context = BlockRuleEditorContextStore.shared.consumePending() else {
            return
        }
        viewModel.presentEditorForContext(context)
    }

    private func prepareExport() {
        do {
            exportDocument = try BlockListSettingsDocument(data: viewModel.exportBlockRules())
            showExporter = true
        } catch {
            importError = error.localizedDescription
            Self.logger.error("Block list export failed: \(error.localizedDescription)")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize, fileSize > Self.maxImportFileBytes {
                    importError = String(
                        localized: "File is too large to import (max 1 MB).",
                        bundle: RockxyLocalization.bundle
                    )
                    return
                }
                let data = try Data(contentsOf: url)
                let rules: [ProxyRule] = switch importSource {
                case .proxyman:
                    try BlockListSettingsCodec.importFromProxyman(data)
                case .charlesProxy:
                    try BlockListSettingsCodec.importFromCharlesProxy(data)
                }
                viewModel.importBlockRules(rules)
            } catch {
                importError = error.localizedDescription
                Self.logger.error("Block list import failed: \(error.localizedDescription)")
            }
        case let .failure(error):
            importError = error.localizedDescription
        }
    }
}

// MARK: - BlockRuleSaveHandler

/// Name, pattern, method, match type, action, include subpaths, GraphQL operation, hide.
private typealias BlockRuleSaveHandler = (
    String, String, HTTPMethodFilter, BlockMatchType, BlockActionType, Bool, String, Bool
) -> Void

// MARK: - AddBlockRuleSheet

private struct AddBlockRuleSheet: View {
    // MARK: Lifecycle

    init(
        session: BlockListEditorSession,
        onSave: @escaping BlockRuleSaveHandler
    ) {
        self.session = session
        self.onSave = onSave
        switch session.mode {
        case let .create(context):
            _ruleName = State(initialValue: context?.suggestedName ?? "")
            _urlPattern = State(initialValue: context?.defaultPattern ?? "")
            _httpMethod = State(initialValue: context?.httpMethod ?? .any)
            _matchType = State(initialValue: context?.defaultMatchType ?? .wildcard)
            _blockAction = State(initialValue: context?.defaultAction ?? .returnForbidden)
            _includeSubpaths = State(initialValue: context?.includeSubpaths ?? true)
            _graphQLOperationName = State(initialValue: context?.graphQLOperationName ?? "")
            _hidesMatchedTraffic = State(initialValue: false)
        case let .edit(rule):
            _ruleName = State(initialValue: rule.name)
            _hidesMatchedTraffic = State(initialValue: rule.hidesMatchedTraffic)
            _graphQLOperationName = State(initialValue: rule.matchCondition.graphQLOperationName ?? "")
            let normalizedMethod = rule.matchCondition.method?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            _httpMethod = State(
                initialValue: normalizedMethod.flatMap(HTTPMethodFilter.init(rawValue:)) ?? .any
            )
            if let sourcePattern = rule.matchCondition.sourceURLPattern {
                _urlPattern = State(initialValue: sourcePattern)
                _matchType = State(initialValue: rule.matchCondition.matchType ?? .regex)
                _includeSubpaths = State(
                    initialValue: rule.matchCondition.matchType == .wildcard
                        ? rule.matchCondition.includeSubpaths ?? false
                        : false
                )
            } else {
                _urlPattern = State(initialValue: rule.matchCondition.urlPattern ?? "")
                _matchType = State(initialValue: .regex)
                _includeSubpaths = State(initialValue: false)
            }
            _blockAction = State(initialValue: rule.blockActionType)
        }
    }

    // MARK: Internal

    let session: BlockListEditorSession
    let onSave: BlockRuleSaveHandler

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                Text(isEditing ? String(localized: "Edit Block Rule", bundle: RockxyLocalization.bundle) : String(
                    localized: "New Block Rule",
                    bundle: RockxyLocalization.bundle
                ))
                .font(
                    .system(
                        size: max(15, toolMetrics.bodyFontSize + 2),
                        weight: .semibold
                    )
                )

                provenanceBanner

                ruleDetailsSection
                decisionSection
                RuleURLTesterSection(toolMetrics: toolMetrics) {
                    let subpaths = matchType == .wildcard ? includeSubpaths : false
                    return RuleMatchCondition(
                        urlPattern: RulePatternBuilder.regexSource(
                            rawPattern: trimmedPattern,
                            matchType: matchType,
                            includeSubpaths: subpaths
                        ),
                        sourceURLPattern: trimmedPattern,
                        method: httpMethod.methodValue,
                        matchType: matchType,
                        includeSubpaths: subpaths
                    )
                }
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.top, toolMetrics.formVerticalPadding)
            .padding(.bottom, toolMetrics.formVerticalPadding)

            Divider()

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    onSave(
                        trimmedName,
                        trimmedPattern,
                        httpMethod,
                        matchType,
                        blockAction,
                        matchType == .wildcard ? includeSubpaths : false,
                        graphQLOperationName,
                        hidesMatchedTraffic
                    )
                    dismiss()
                } label: {
                    footerButtonLabel(primaryButtonTitle)
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(trimmedPattern.isEmpty)
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.vertical, toolMetrics.controlSpacing)
        }
        .font(toolMetrics.font())
        .frame(minWidth: max(720, toolMetrics.bodyFontSize * 24 + 408))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var ruleName: String
    @State private var urlPattern: String
    @State private var hidesMatchedTraffic: Bool
    @State private var httpMethod: HTTPMethodFilter
    @State private var matchType: BlockMatchType
    @State private var blockAction: BlockActionType
    @State private var includeSubpaths: Bool
    @State private var graphQLOperationName: String

    private var isEditing: Bool {
        if case .edit = session.mode {
            return true
        }
        return false
    }

    private var primaryButtonTitle: String {
        isEditing ? String(localized: "Save", bundle: RockxyLocalization.bundle) : String(
            localized: "Add",
            bundle: RockxyLocalization.bundle
        )
    }

    private var trimmedName: String {
        ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPattern: String {
        urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var actionDescription: String {
        switch blockAction {
        case .returnForbidden:
            String(localized: "Send an HTTP 403 response to the client.", bundle: RockxyLocalization.bundle)
        case .dropConnection:
            String(
                localized: "Close the matching client connection without a response.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder private var provenanceBanner: some View {
        if case let .create(context?) = session.mode {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Group {
                    switch context.origin {
                    case .selectedTransaction:
                        if let method = context.sourceMethod {
                            Text(String(
                                localized: "Created from: \(method) \(context.sourceHost)\(context.sourcePath ?? "")",
                                bundle: RockxyLocalization.bundle
                            ))
                        } else {
                            Text(String(
                                localized: "Created from: \(context.sourceHost)\(context.sourcePath ?? "")",
                                bundle: RockxyLocalization.bundle
                            ))
                        }
                    case .domainQuickCreate:
                        Text(String(
                            localized: "Created from domain: \(context.sourceHost)",
                            bundle: RockxyLocalization.bundle
                        ))
                    }
                }
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var ruleDetailsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Rule Details", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                identityFields
                methodAndMatchRow
                conditionalFields
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

    private var identityFields: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            fieldGroup(String(localized: "Name", bundle: RockxyLocalization.bundle)) {
                TextField(String(localized: "Untitled", bundle: RockxyLocalization.bundle), text: $ruleName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "Rule name", bundle: RockxyLocalization.bundle))
            }
            .frame(width: max(250, toolMetrics.fieldWidth(250)))

            fieldGroup(String(localized: "URL pattern", bundle: RockxyLocalization.bundle)) {
                TextField("https://example.com/api/*", text: $urlPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .accessibilityLabel(String(localized: "URL pattern", bundle: RockxyLocalization.bundle))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var methodAndMatchRow: some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
            inlineField(String(localized: "Method", bundle: RockxyLocalization.bundle)) {
                Menu {
                    ForEach(HTTPMethodFilter.allCases, id: \.self) { method in
                        Button {
                            httpMethod = method
                        } label: {
                            menuCheckmarkLabel(method.rawValue, isSelected: httpMethod == method)
                        }
                    }
                } label: {
                    dataEntryMenuLabel(httpMethod.rawValue, width: toolMetrics.menuWidth(90))
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "HTTP Method", bundle: RockxyLocalization.bundle))
                .frame(width: toolMetrics.menuWidth(90))
            }

            inlineField(String(localized: "Match type", bundle: RockxyLocalization.bundle)) {
                Menu {
                    ForEach(BlockMatchType.allCases, id: \.self) { type in
                        Button {
                            matchType = type
                        } label: {
                            menuCheckmarkLabel(type.rawValue, isSelected: matchType == type)
                        }
                    }
                } label: {
                    dataEntryMenuLabel(matchType.rawValue, width: toolMetrics.menuWidth(175))
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Match Type", bundle: RockxyLocalization.bundle))
                .frame(width: toolMetrics.menuWidth(175))
            }

            if matchType == .wildcard {
                Text(String(localized: "Support wildcard * and ?.", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    @ViewBuilder private var conditionalFields: some View {
        if matchType == .wildcard {
            Toggle(
                String(localized: "Include all subpaths of this URL", bundle: RockxyLocalization.bundle),
                isOn: $includeSubpaths
            )
            .toggleStyle(.checkbox)
            .font(toolMetrics.font())
        }
        inlineField(String(localized: "GraphQL Operation", bundle: RockxyLocalization.bundle)) {
            TextField(
                String(localized: "Any operation", bundle: RockxyLocalization.bundle),
                text: $graphQLOperationName
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: max(220, toolMetrics.fieldWidth(220)))
            .accessibilityLabel(String(
                localized: "GraphQL operation name to match",
                bundle: RockxyLocalization.bundle
            ))
            .help(String(
                localized: "Block only GraphQL requests with this exact operation name. Leave empty to block every request to the URL.",
                bundle: RockxyLocalization.bundle
            ))
        }
    }

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Decision", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
                inlineField(String(localized: "When matched", bundle: RockxyLocalization.bundle)) {
                    Menu {
                        ForEach(BlockActionType.allCases, id: \.self) { action in
                            Button {
                                blockAction = action
                            } label: {
                                menuCheckmarkLabel(action.rawValue, isSelected: blockAction == action)
                            }
                        }
                    } label: {
                        dataEntryMenuLabel(blockAction.rawValue, width: toolMetrics.menuWidth(220))
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Block action", bundle: RockxyLocalization.bundle))
                    .frame(width: toolMetrics.menuWidth(220))
                }

                Text(actionDescription)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle(
                    String(localized: "Hide blocked requests", bundle: RockxyLocalization.bundle),
                    isOn: $hidesMatchedTraffic
                )
                .toggleStyle(.checkbox)
                .help(String(
                    localized: "Requests this rule blocks are not added to the traffic list.",
                    bundle: RockxyLocalization.bundle
                ))
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

    private func inlineField(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
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

    private func dataEntryMenuLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
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

    private func menuCheckmarkLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: max(64, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 3),
                height: max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }
}

// MARK: - BlockListSettingsDocument

struct BlockListSettingsDocument: FileDocument {
    // MARK: Lifecycle

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    // MARK: Internal

    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension ProxyRule {
    var isBlockRule: Bool {
        if case .block = action {
            return true
        }
        return false
    }

    var blockActionType: BlockActionType {
        guard case let .block(statusCode) = action else {
            return .returnForbidden
        }
        return statusCode == 0 ? .dropConnection : .returnForbidden
    }
}
