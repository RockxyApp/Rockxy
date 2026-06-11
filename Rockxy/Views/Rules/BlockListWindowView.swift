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
    var selectedRuleID: UUID?
    var editorSession: BlockListEditorSession?
    var isBlockListActive: Bool
    private(set) var allRules: [ProxyRule] = []

    init() {
        isBlockListActive = UserDefaults.standard.object(forKey: "blockListToolEnabled") as? Bool ?? true
    }

    var blockRules: [ProxyRule] {
        allRules.filter(\.isBlockRule)
    }

    var ruleCount: Int {
        blockRules.count
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
        includeSubpaths: Bool
    ) {
        let rule = makeRule(
            ruleName: ruleName,
            urlPattern: urlPattern,
            httpMethod: httpMethod,
            matchType: matchType,
            blockAction: blockAction,
            includeSubpaths: includeSubpaths
        )
        allRules.append(rule)
        selectedRuleID = rule.id
        Task {
            let accepted = await RulePolicyGate.shared.addRule(rule)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
                reconcileSelectionAfterRulesChange()
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
        includeSubpaths: Bool
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
            includeSubpaths: includeSubpaths
        )
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
            name: String(localized: "Copy of \(original.name)"),
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
            }
        }
    }

    func exportBlockRules() throws -> Data {
        try BlockListSettingsCodec.exportRules(blockRules)
    }

    func importBlockRules(_ importedRules: [ProxyRule]) {
        let nonBlockRules = allRules.filter { !$0.isBlockRule }
        allRules = nonBlockRules + importedRules
        selectedRuleID = importedRules.first?.id
        Task {
            await RulePolicyGate.shared.replaceAllRules(allRules)
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
        includeSubpaths: Bool
    )
        -> ProxyRule
    {
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
                method: httpMethod.methodValue,
                matchType: matchType,
                includeSubpaths: includeSubpaths
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
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            BlockListTableView(
                rules: viewModel.blockRules,
                selectedRuleID: $viewModel.selectedRuleID,
                onToggle: { viewModel.toggleRule(id: $0) },
                onEdit: openEditorForRule,
                onDelete: { viewModel.removeRule(id: $0) },
                contextMenuItems: contextMenuItems
            )
            shortcutHelp
            footer
        }
        .font(toolMetrics.font())
        .frame(width: 1_200, height: 672)
        .task { await viewModel.refreshFromEngine() }
        .onAppear { consumePendingContext() }
        .onReceive(NotificationCenter.default.publisher(for: .openBlockListWindow)) { _ in
            consumePendingContext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .sheet(item: $viewModel.editorSession) { session in
            AddBlockRuleSheet(session: session) { ruleName, pattern, method, matchType, action, includeSubpaths in
                switch session.mode {
                case .create:
                    viewModel.addBlockRule(
                        ruleName: ruleName,
                        urlPattern: pattern,
                        httpMethod: method,
                        matchType: matchType,
                        blockAction: action,
                        includeSubpaths: includeSubpaths
                    )
                case let .edit(rule):
                    viewModel.updateBlockRule(
                        id: rule.id,
                        ruleName: ruleName,
                        urlPattern: pattern,
                        httpMethod: method,
                        matchType: matchType,
                        blockAction: action,
                        includeSubpaths: includeSubpaths
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
            String(localized: "Import Failed"),
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button(String(localized: "OK")) { importError = nil }
        } message: {
            if let importError {
                Text(importError)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: toolMetrics.headerSpacing) {
            Toggle(
                String(localized: "Enable Block List Tool"),
                isOn: Binding(
                    get: { viewModel.isBlockListActive },
                    set: { viewModel.setBlockListActive($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(toolMetrics.font(weight: .medium))
            .padding(.top, toolMetrics.headerTopPadding)

            Text(String(localized: "Block or Hide any Requests. Useful to block/hide unnecessary requests."))
                .font(toolMetrics.font())
                .foregroundStyle(.primary)

            Text(
                String(
                    localized:
                    "Each request is checked against the rules from top to bottom, stopping when a match is found."
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
    }

    private var shortcutHelp: some View {
        Text(String(localized: "New: ⌘N    Edit: ⌘↩    Delete: ⌘⌫    Duplicate: ⌘D    Toggle: ␣"))
            .font(.system(size: toolMetrics.shortcutFontSize))
            .foregroundStyle(.secondary)
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.top, toolMetrics.shortcutTopPadding)
            .padding(.bottom, toolMetrics.shortcutBottomPadding)
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl

            Button {
                // Help content is intentionally deferred; this mirrors the reference affordance.
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.bordered)

            Spacer()

            moreMenu
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.bottom, toolMetrics.footerBottomPadding)
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
            .help(String(localized: "New Rule"))

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
            .help(String(localized: "Delete Rule"))
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
            Button(String(localized: "New…")) {
                viewModel.presentNewRuleEditor()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button(String(localized: "Edit…")) {
                openEditorForSelection()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)

            Button(String(localized: "Duplicate")) {
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

            Button(String(localized: "Export Settings…")) {
                prepareExport()
            }
            .disabled(viewModel.blockRules.isEmpty)

            Menu(String(localized: "Import Settings")) {
                Button(String(localized: "From Proxyman…")) {
                    importSource = .proxyman
                    showImporter = true
                }

                Button(String(localized: "From Charles Proxy…")) {
                    importSource = .charlesProxy
                    showImporter = true
                }
            }

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
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder
    private func contextMenuItems(for id: UUID) -> some View {
        Button(String(localized: "Edit…")) {
            openEditorForRule(id)
        }
        .keyboardShortcut("e", modifiers: .command)

        Button(String(localized: "Duplicate")) {
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

        Button(String(localized: "Delete"), role: .destructive) {
            viewModel.removeRule(id: id)
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private var enableDisableLabel: String {
        guard let id = viewModel.selectedRuleID else {
            return String(localized: "Enable Rule")
        }
        return enableDisableLabel(for: id)
    }

    private func enableDisableLabel(for id: UUID) -> String {
        guard let rule = viewModel.blockRules.first(where: { $0.id == id }) else {
            return String(localized: "Enable Rule")
        }
        return rule.isEnabled ? String(localized: "Disable Rule") : String(localized: "Enable Rule")
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
            exportDocument = BlockListSettingsDocument(data: try viewModel.exportBlockRules())
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
                    importError = String(localized: "File is too large to import (max 1 MB).")
                    return
                }
                let data = try Data(contentsOf: url)
                let rules: [ProxyRule]
                switch importSource {
                case .proxyman:
                    rules = try BlockListSettingsCodec.importFromProxyman(data)
                case .charlesProxy:
                    rules = try BlockListSettingsCodec.importFromCharlesProxy(data)
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

// MARK: - BlockListTableView

private struct BlockListTableView<ContextMenuContent: View>: View {
    let rules: [ProxyRule]
    @Binding var selectedRuleID: UUID?
    let onToggle: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDelete: (UUID) -> Void
    @ViewBuilder let contextMenuItems: (UUID) -> ContextMenuContent

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            ZStack {
                zebraRows

                if rules.isEmpty {
                    Text(String(localized: "Click \"+\" or ⌘N to add new entry"))
                        .font(.system(size: toolMetrics.emptyStateFontSize))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                                BlockRuleTableRow(
                                    rule: rule,
                                    isSelected: selectedRuleID == rule.id,
                                    rowIndex: index,
                                    onSelect: { selectedRuleID = rule.id },
                                    onToggle: { onToggle(rule.id) }
                                )
                                .contextMenu {
                                    contextMenuItems(rule.id)
                                }
                                .onTapGesture(count: 2) {
                                    onEdit(rule.id)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minHeight: toolMetrics.tableRowHeight * 8, maxHeight: .infinity)
        .clipped()
        .overlay {
            Rectangle()
                .stroke(.secondary.opacity(0.45), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text(String(localized: "Enabled"))
                .frame(width: 66, alignment: .leading)
            tableDivider
            Text(String(localized: "Name"))
                .frame(width: 300, alignment: .leading)
            tableDivider
            Text(String(localized: "Block Action"))
                .frame(width: 150, alignment: .leading)
            tableDivider
            Text(String(localized: "Method"))
                .frame(width: 90, alignment: .leading)
            tableDivider
            Text(String(localized: "Matching Rule"))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(toolMetrics.tableHeaderFont())
        .lineLimit(1)
        .padding(.horizontal, toolMetrics.tableCellHorizontalPadding)
        .frame(height: toolMetrics.tableRowHeight)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var tableDivider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.22))
            .frame(width: 1, height: max(16, toolMetrics.tableRowHeight - 10))
            .padding(.trailing, 10)
    }

    private var zebraRows: some View {
        GeometryReader { proxy in
            let rowCount = max(1, Int(ceil(proxy.size.height / toolMetrics.tableRowHeight)))
            VStack(spacing: 0) {
                ForEach(0 ..< rowCount, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color.secondary.opacity(0.08))
                        .frame(height: toolMetrics.tableRowHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics
}

// MARK: - BlockRuleTableRow

private struct BlockRuleTableRow: View {
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    let rule: ProxyRule
    let isSelected: Bool
    let rowIndex: Int
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 66)

            Text(rule.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 300, alignment: .leading)

            actionLabel
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 150, alignment: .leading)

            Text(rule.matchCondition.method ?? "ANY")
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            Text(rule.matchCondition.urlPattern ?? "")
                .font(toolMetrics.font(monospaced: true))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(toolMetrics.font())
        .padding(.horizontal, toolMetrics.tableCellHorizontalPadding)
        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
        .frame(height: toolMetrics.tableRowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }

    @ViewBuilder private var actionLabel: some View {
        if case let .block(statusCode) = rule.action {
            Text(statusCode == 0 ? String(localized: "Drop Connection") : String(localized: "Return 403 Forbidden"))
        }
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.22))
        }
        return AnyShapeStyle(rowIndex.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color.secondary.opacity(0.08))
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - AddBlockRuleSheet

private struct AddBlockRuleSheet: View {
    init(
        session: BlockListEditorSession,
        onSave: @escaping (String, String, HTTPMethodFilter, BlockMatchType, BlockActionType, Bool) -> Void
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
        case let .edit(rule):
            _ruleName = State(initialValue: rule.name)
            _urlPattern = State(initialValue: rule.matchCondition.urlPattern ?? "")
            _httpMethod = State(initialValue: HTTPMethodFilter(rawValue: rule.matchCondition.method ?? "ANY") ?? .any)
            _matchType = State(initialValue: .regex)
            _blockAction = State(initialValue: rule.blockActionType)
            _includeSubpaths = State(initialValue: false)
        }
    }

    let session: BlockListEditorSession
    let onSave: (String, String, HTTPMethodFilter, BlockMatchType, BlockActionType, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                provenanceBanner

                formRow(String(localized: "Name:")) {
                    TextField("", text: $ruleName, prompt: Text(String(localized: "Untitled")))
                        .textFieldStyle(.roundedBorder)
                }

                formRow(String(localized: "Matching Rule:")) {
                    TextField("", text: $urlPattern, prompt: Text("https://example.com"))
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font(monospaced: true))
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
                    .frame(width: toolMetrics.menuWidth(220))
                }
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.top, toolMetrics.formVerticalPadding)
            .padding(.bottom, toolMetrics.formVerticalPadding)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(primaryButtonTitle) {
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
                .disabled(urlPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.vertical, toolMetrics.controlSpacing)
        }
        .font(toolMetrics.font())
        .frame(minWidth: max(640, toolMetrics.bodyFontSize * 20 + 380))
        .fixedSize(horizontal: false, vertical: true)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var ruleName: String
    @State private var urlPattern: String
    @State private var httpMethod: HTTPMethodFilter
    @State private var matchType: BlockMatchType
    @State private var blockAction: BlockActionType
    @State private var includeSubpaths: Bool

    private var primaryButtonTitle: String {
        if case .edit = session.mode {
            return String(localized: "Save")
        }
        return String(localized: "Done")
    }

    private var labelWidth: CGFloat {
        max(122, toolMetrics.formLabelWidth)
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
                            Text(String(localized: "Created from: \(method) \(context.sourceHost)\(context.sourcePath ?? "")"))
                        } else {
                            Text(String(localized: "Created from: \(context.sourceHost)\(context.sourcePath ?? "")"))
                        }
                    case .domainQuickCreate:
                        Text(String(localized: "Created from domain: \(context.sourceHost)"))
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

    private var methodAndMatchRow: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Spacer()
                .frame(width: labelWidth + toolMetrics.controlSpacing)
            Picker("", selection: $httpMethod) {
                ForEach(HTTPMethodFilter.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(String(localized: "HTTP Method"))
            .frame(width: toolMetrics.menuWidth(90))

            Picker("", selection: $matchType) {
                ForEach(BlockMatchType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(String(localized: "Match Type"))
            .frame(width: toolMetrics.menuWidth(175))

            if matchType == .wildcard {
                Text(String(localized: "Support wildcard * and ?."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var conditionalFields: some View {
        if matchType == .wildcard {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: labelWidth + toolMetrics.controlSpacing)
                Toggle(String(localized: "Include all subpaths of this URL"), isOn: $includeSubpaths)
                    .toggleStyle(.checkbox)
                    .font(toolMetrics.font())
            }
        }
    }

    private func formRow(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .trailing)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .frame(minHeight: toolMetrics.formControlHeight)
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - BlockListSettingsDocument

struct BlockListSettingsDocument: FileDocument {
    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

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
