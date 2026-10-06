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

    init(folderStore: RuleFolderStore = .blockList) {
        isBlockListActive = UserDefaults.standard.object(forKey: "blockListToolEnabled") as? Bool ?? true
        self.folderStore = folderStore
    }

    // MARK: Internal

    var selectedRuleID: UUID?
    var editorSession: BlockListEditorSession?
    var isBlockListActive: Bool
    var searchText = ""
    var mutationError: String?
    var collapsedFolderIDs: Set<UUID> = []
    let folderStore: RuleFolderStore
    private(set) var allRules: [ProxyRule] = []

    /// Rows as displayed: folders with their rules beneath (unless collapsed); flat while searching.
    var displayRows: [BlockListDisplayRow] {
        let searching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var result: [BlockListDisplayRow] = []
        for row in RuleListRow.rows(rules: filteredBlockRules, folders: folderStore.folders, flat: searching) {
            result.append(BlockListDisplayRow(row: row, indented: false))
            if row.folder != nil, !collapsedFolderIDs.contains(row.id) {
                result.append(contentsOf: (row.children ?? []).map { BlockListDisplayRow(row: $0, indented: true) })
            }
        }
        return result
    }

    func rules(in folder: RuleFolder) -> [ProxyRule] {
        let members = Set(folder.ruleIDs)
        return blockRules.filter { members.contains($0.id) }
    }

    func toggleFolderCollapsed(_ id: UUID) {
        if collapsedFolderIDs.contains(id) {
            collapsedFolderIDs.remove(id)
        } else {
            collapsedFolderIDs.insert(id)
        }
    }

    func dropRules(_ payloads: [String], onto row: RuleListRow) {
        folderStore.drop(payloads, onto: row, knownRuleIDs: Set(blockRules.map(\.id)))
    }

    func newFolderWithSelection() {
        let ids = blockRules.map(\.id).filter { $0 == selectedRuleID }
        if let id = folderStore.createFolder(
            named: String(localized: "New Folder", bundle: RockxyLocalization.bundle),
            containing: ids
        ) {
            selectedRuleID = id
        }
    }

    /// Enables or disables several rules through the quota gate; reports rules the limit refused.
    func setRulesEnabled(_ ids: [UUID], enabled: Bool) {
        for index in allRules.indices where ids.contains(allRules[index].id) {
            allRules[index].isEnabled = enabled
        }
        Task {
            var refused = false
            for id in ids where await !RulePolicyGate.shared.setRuleEnabled(id: id, enabled: enabled) {
                refused = true
            }
            allRules = await RuleEngine.shared.allRules
            if refused {
                mutationError = String(
                    localized: "The active Block List rule limit was reached. Disable another rule and try again.",
                    bundle: RockxyLocalization.bundle
                )
            }
        }
    }

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
        folderStore.reconcile(existingRuleIDs: Set(blockRules.map(\.id)))
        reconcileSelectionAfterRulesChange()
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
            folderStore.reconcile(existingRuleIDs: Set(blockRules.map(\.id)))
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
        hidesMatchedTraffic: Bool = false,
        clientApplication: String = ""
    ) {
        var rule = makeRule(
            ruleName: ruleName,
            urlPattern: urlPattern,
            httpMethod: httpMethod,
            matchType: matchType,
            blockAction: blockAction,
            includeSubpaths: includeSubpaths,
            graphQLOperationName: graphQLOperationName,
            clientApplication: clientApplication
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
        hidesMatchedTraffic: Bool = false,
        clientApplication: String = ""
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
            graphQLOperationName: graphQLOperationName,
            clientApplication: clientApplication
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
        if folderStore.folders.contains(where: { $0.id == id }) {
            // Deleting a folder keeps its rules; they move back to the top level.
            folderStore.deleteFolder(id: id)
            selectedRuleID = nil
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
        graphQLOperationName: String = "",
        clientApplication: String = ""
    )
        -> ProxyRule
    {
        let operation = graphQLOperationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let application = clientApplication.trimmingCharacters(in: .whitespacesAndNewlines)
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
                graphQLOperationName: operation.isEmpty ? nil : operation,
                clientApplication: application.isEmpty ? nil : application
            ),
            action: .block(statusCode: blockAction.statusCode)
        )
    }

    private func reconcileSelectionAfterRulesChange() {
        guard let id = selectedRuleID else {
            return
        }
        let isFolder = folderStore.folders.contains { $0.id == id }
        if !isFolder, !blockRules.contains(where: { $0.id == id }) {
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
                rows: viewModel.displayRows,
                folderRules: viewModel.rules(in:),
                collapsedFolderIDs: viewModel.collapsedFolderIDs,
                onToggleCollapse: { viewModel.toggleFolderCollapsed($0) },
                onSetFolderEnabled: { viewModel.setRulesEnabled($0, enabled: $1) },
                onDrop: { viewModel.dropRules($0, onto: $1) },
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
        .ruleFolderRenameAlert(store: viewModel.folderStore, folder: $renamingFolder)
        .sheet(item: $viewModel.editorSession) { session in
            AddBlockRuleSheet(session: session) { ruleName, pattern, method, matchType, action, includeSubpaths, operation, hides, application in
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
                        hidesMatchedTraffic: hides,
                        clientApplication: application
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
                        hidesMatchedTraffic: hides,
                        clientApplication: application
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
    @State private var renamingFolder: RuleFolder?
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

            Button(String(localized: "New Folder", bundle: RockxyLocalization.bundle)) {
                viewModel.newFolderWithSelection()
            }
            RuleFolderMenuItems(
                store: viewModel.folderStore,
                ruleIDs: viewModel.blockRules.map(\.id).filter { $0 == viewModel.selectedRuleID }
            ) { viewModel.selectedRuleID = $0 }

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
        if let folder = viewModel.folderStore.folders.first(where: { $0.id == id }) {
            RuleFolderContextItems(store: viewModel.folderStore, folder: folder) { renamingFolder = $0 }
        } else {
            ruleContextMenuItems(for: id)
        }
    }

    @ViewBuilder
    private func ruleContextMenuItems(for id: UUID) -> some View {
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

        RuleFolderMenuItems(store: viewModel.folderStore, ruleIDs: [id]) { viewModel.selectedRuleID = $0 }

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
}
