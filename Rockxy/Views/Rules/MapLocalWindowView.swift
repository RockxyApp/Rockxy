import AppKit
import os
import SwiftUI

// Presents the native Map Local management window.
// The rule editor window lives in `MapLocalEditorWindowView.swift`.

// MARK: - MapLocalViewModel

@MainActor @Observable
final class MapLocalViewModel {
    // MARK: Lifecycle

    init(isToolEnabled: Bool? = nil, folderStore: RuleFolderStore = .mapLocal) {
        self.isToolEnabled = isToolEnabled ?? Self.defaultToolEnabled
        self.folderStore = folderStore
    }

    // MARK: Internal

    var allRules: [ProxyRule] = []
    var searchText = ""
    var selectedRuleIDs: Set<UUID> = []
    var isToolEnabled: Bool
    var errorMessage: String?
    let folderStore: RuleFolderStore

    /// Folder-grouped rows; flat while searching so every match shows.
    var rows: [RuleListRow] {
        let searching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return RuleListRow.rows(rules: filteredRules, folders: folderStore.folders, flat: searching)
    }

    /// Selected rules, including every rule inside a selected folder.
    var selectedRuleIDsIncludingFolders: Set<UUID> {
        var ids = Set(mapLocalRules.map(\.id)).intersection(selectedRuleIDs)
        for folder in folderStore.folders where selectedRuleIDs.contains(folder.id) {
            ids.formUnion(folder.ruleIDs)
        }
        return ids
    }

    func dropRules(_ payloads: [String], onto row: RuleListRow) {
        folderStore.drop(payloads, onto: row, knownRuleIDs: Set(mapLocalRules.map(\.id)))
    }

    func rules(in folder: RuleFolder) -> [ProxyRule] {
        let members = Set(folder.ruleIDs)
        return mapLocalRules.filter { members.contains($0.id) }
    }

    /// Enables or disables several rules through the quota gate; reports rules the limit refused.
    func setRulesEnabled(_ ids: [UUID], enabled: Bool) {
        for index in allRules.indices where ids.contains(allRules[index].id) {
            allRules[index].isEnabled = enabled
        }
        Task {
            var refused = false
            for id in ids {
                if await !RulePolicyGate.shared.setRuleEnabled(id: id, enabled: enabled) {
                    refused = true
                }
            }
            allRules = await RuleEngine.shared.allRules
            if refused {
                errorMessage = String(
                    localized: "Some rules stayed off because the active Map Local rule limit was reached.",
                    bundle: RockxyLocalization.bundle
                )
            }
        }
    }

    func newFolderWithSelection() {
        let ids = mapLocalRules.map(\.id).filter { selectedRuleIDs.contains($0) }
        let id = folderStore.createFolder(
            named: String(localized: "New Folder", bundle: RockxyLocalization.bundle),
            containing: ids
        )
        selectedRuleIDs = [id]
    }

    func moveSelectedRules(toFolder folderID: UUID?) {
        let ids = Set(mapLocalRules.map(\.id)).intersection(selectedRuleIDs)
        folderStore.move(ruleIDs: ids, toFolder: folderID)
    }

    var mapLocalRules: [ProxyRule] {
        allRules.filter {
            if case .mapLocal = $0.action {
                return true
            }
            return false
        }
    }

    var filteredRules: [ProxyRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return mapLocalRules
        }
        return mapLocalRules.filter { rule in
            rule.name.lowercased().contains(query)
                || (rule.matchCondition.sourceURLPattern?.lowercased().contains(query) ?? false)
                || (rule.matchCondition.urlPattern?.lowercased().contains(query) ?? false)
                || methodLabel(for: rule).lowercased().contains(query)
                || filePath(for: rule).lowercased().contains(query)
        }
    }

    var ruleCount: Int {
        mapLocalRules.count
    }

    var activeRuleCount: Int {
        mapLocalRules.filter(\.isEnabled).count
    }

    var isReorderable: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedRuleIDs.count == 1
    }

    var selectedRule: ProxyRule? {
        guard let id = selectedRuleIDs.first else {
            return nil
        }
        return allRules.first { $0.id == id }
    }

    var areAllEnabled: Bool {
        get {
            let locals = mapLocalRules
            return !locals.isEmpty && locals.allSatisfy(\.isEnabled)
        }
        set {
            // Optimistically reflect the toggle on the local Map Local rows only;
            // the engine stays authoritative. Never rebuild a full snapshot here —
            // a stale `allRules` would clobber concurrent additions from other windows.
            for index in allRules.indices {
                if case .mapLocal = allRules[index].action {
                    allRules[index].isEnabled = newValue
                }
            }
            Task {
                await RulePolicyGate.shared.setMapLocalRulesEnabled(newValue)
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    static func applyingMapLocalOrder(_ orderedSubset: [ProxyRule], to allRules: [ProxyRule]) -> [ProxyRule] {
        let currentIDs = allRules.compactMap { rule -> UUID? in
            if case .mapLocal = rule.action {
                return rule.id
            }
            return nil
        }
        guard orderedSubset.count == currentIDs.count,
              Set(orderedSubset.map(\.id)) == Set(currentIDs) else
        {
            return allRules
        }

        var iterator = orderedSubset.makeIterator()
        return allRules.map { rule in
            if case .mapLocal = rule.action {
                return iterator.next() ?? rule
            }
            return rule
        }
    }

    func refreshFromEngine() async {
        allRules = await RuleEngine.shared.allRules
        folderStore.reconcile(existingRuleIDs: Set(mapLocalRules.map(\.id)))
    }

    func handleRulesDidChange(_ notification: Notification) {
        if let rules = notification.object as? [ProxyRule] {
            allRules = rules
            let folderIDs = Set(folderStore.folders.map(\.id))
            selectedRuleIDs = selectedRuleIDs.filter { id in
                folderIDs.contains(id) || rules.contains { $0.id == id }
            }
            folderStore.reconcile(existingRuleIDs: Set(mapLocalRules.map(\.id)))
        }
    }

    /// Surfaces a durable save/load failure posted by `RuleSyncService` so the
    /// user sees that persistence did not succeed instead of a silent no-op.
    func handlePersistenceFailure(_ notification: Notification) {
        if let message = notification.object as? String {
            errorMessage = message
        }
    }

    func setToolEnabled(_ enabled: Bool) {
        isToolEnabled = enabled
        Task { await RulePolicyGate.shared.setMapLocalToolEnabled(enabled) }
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
            }
        }
    }

    func addRule(_ rule: ProxyRule) {
        allRules.append(rule)
        selectedRuleIDs = [rule.id]
        Task {
            let accepted = await RulePolicyGate.shared.addRule(rule)
            if !accepted {
                allRules = await RuleEngine.shared.allRules
            }
        }
    }

    func updateRule(_ rule: ProxyRule) {
        guard let index = allRules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        allRules[index] = rule
        Task { await RulePolicyGate.shared.updateRule(rule) }
    }

    func removeSelectedRules() {
        // Deleting a folder keeps its rules; they move back to the top level.
        for folder in folderStore.folders where selectedRuleIDs.contains(folder.id) {
            folderStore.deleteFolder(id: folder.id)
        }
        let idsToRemove = Set(mapLocalRules.map(\.id)).intersection(selectedRuleIDs)
        guard !idsToRemove.isEmpty else {
            selectedRuleIDs.removeAll()
            return
        }
        allRules.removeAll { idsToRemove.contains($0.id) }
        selectedRuleIDs.removeAll()
        Task {
            // Remove only the selected IDs against current engine state instead of
            // persisting a full stale snapshot, so concurrent additions and other
            // categories survive.
            await RulePolicyGate.shared.removeRules(ids: idsToRemove)
            allRules = await RuleEngine.shared.allRules
        }
    }

    func removeRule(id: UUID) {
        allRules.removeAll { $0.id == id }
        selectedRuleIDs.remove(id)
        Task { await RulePolicyGate.shared.removeRule(id: id) }
    }

    func duplicateSelectedRule() {
        guard var rule = selectedRule else {
            return
        }
        rule = ProxyRule(
            name: "\(rule.name) Copy",
            isEnabled: rule.isEnabled,
            matchCondition: rule.matchCondition,
            action: rule.action,
            priority: rule.priority
        )
        addRule(rule)
    }

    func moveSelectedRule(by offset: Int) {
        guard isReorderable, let selectedID = selectedRuleIDs.first,
              let sourceIndex = mapLocalRules.firstIndex(where: { $0.id == selectedID }) else
        {
            return
        }
        let destinationIndex = sourceIndex + offset
        guard mapLocalRules.indices.contains(destinationIndex) else {
            return
        }

        var reordered = mapLocalRules
        let moved = reordered.remove(at: sourceIndex)
        reordered.insert(moved, at: destinationIndex)
        let orderedIDs = reordered.map(\.id)
        allRules = Self.applyingMapLocalOrder(reordered, to: allRules)
        Task {
            await RulePolicyGate.shared.reorderMapLocalRules(orderedIDs: orderedIDs)
            allRules = await RuleEngine.shared.allRules
        }
    }

    func filePath(for rule: ProxyRule) -> String {
        if case let .mapLocal(path, _, _, _, _) = rule.action {
            return path
        }
        return ""
    }

    func methodLabel(for rule: ProxyRule) -> String {
        rule.matchCondition.method?.uppercased() ?? "ANY"
    }

    func matchingRuleLabel(for rule: ProxyRule) -> String {
        if let sourcePattern = rule.matchCondition.sourceURLPattern,
           !sourcePattern.isEmpty
        {
            let prefix = rule.matchCondition.matchType == .regex ? "Regex: " : "Wildcard: "
            return prefix + sourcePattern
        }
        guard let pattern = rule.matchCondition.urlPattern, !pattern.isEmpty else {
            return "<Missing URL>"
        }
        if MapLocalPatternFormatter.prefersWildcardPresentation(pattern) {
            return "Wildcard: \(MapLocalPatternFormatter.readablePattern(pattern))"
        }
        return pattern
    }

    func mapFromLabel(for rule: ProxyRule) -> String {
        let prefix = isDirectory(for: rule) ? "Directory: " : "File: "
        let path = filePath(for: rule)
        return prefix + (path.isEmpty ? "<Missing Path>" : abbreviatedPath(path))
    }

    func isDirectory(for rule: ProxyRule) -> Bool {
        if case let .mapLocal(_, _, isDirectory, _, _) = rule.action {
            return isDirectory
        }
        return false
    }

    func delayLabel(for rule: ProxyRule) -> String {
        if case let .mapLocal(_, _, _, delayMs, _) = rule.action, delayMs != 0 {
            return MapLocalDelayPreset.from(delayMs: delayMs).displayName
        }
        return ""
    }

    // MARK: Private

    private static let toolEnabledKey = "mapLocalToolEnabled"
    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MapLocalViewModel")

    private static var defaultToolEnabled: Bool {
        UserDefaults.standard.object(forKey: toolEnabledKey) as? Bool ?? true
    }

    private func abbreviatedPath(_ path: String) -> String {
        guard !path.isEmpty else {
            return "<Missing Path>"
        }
        let maxLength = 78
        guard path.count > maxLength else {
            return path
        }
        let suffix = path.suffix(maxLength - 3)
        return "...\(suffix)"
    }
}

// MARK: - MapLocalWindowView

struct MapLocalWindowView: View {
    // MARK: Internal

    @State var viewModel = MapLocalViewModel()

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
            minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496),
            minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)
        )
        .background {
            Button("") { searchIsFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
        .task {
            // Ensure persisted rules are loaded even when macOS restored ONLY this
            // tool window (no main window ran its startup task). Idempotent and
            // app-scoped — independent of main-window project hydration.
            if case let .failed(message) = await RuleSyncService.ensureLoaded() {
                viewModel.errorMessage = message
            }
            await viewModel.refreshFromEngine()
        }
        .onAppear { consumePendingDraftIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .openMapLocalWindow)) { _ in
            consumePendingDraftIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { notification in
            viewModel.handleRulesDidChange(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulePersistenceDidFail)) { notification in
            viewModel.handlePersistenceFailure(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidFailToLoad)) { notification in
            viewModel.handlePersistenceFailure(notification)
        }
        .alert(
            String(localized: "Map Local", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .ruleFolderRenameAlert(store: viewModel.folderStore, folder: $renamingFolder)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow
    @State private var renamingFolder: RuleFolder?
    @FocusState private var searchIsFocused: Bool

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

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(
                    String(localized: "Enable Map Local", bundle: RockxyLocalization.bundle),
                    isOn: Binding(
                        get: { viewModel.isToolEnabled },
                        set: { viewModel.setToolEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font(weight: .medium))

                Text(String(
                    localized: "Serve a local file or directory for matching requests.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }

            Spacer()

            TextField(String(localized: "Search rules", bundle: RockxyLocalization.bundle), text: $viewModel.searchText)
                .focused($searchIsFocused)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(width: 240, height: toolMetrics.formControlHeight)
                .accessibilityLabel(String(localized: "Search Map Local rules", bundle: RockxyLocalization.bundle))
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
                    "Map Local participates in Rockxy's global first-match rule order. Reorder rules from the More menu; unavailable local targets safely fall back to the origin.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @TableRowBuilder<RuleListRow>
    private func draggableRuleRow(_ row: RuleListRow) -> some TableRowContent<RuleListRow> {
        TableRow(row)
            .draggable(RuleFolderDrag.payload(for: row.id, selection: viewModel.selectedRuleIDs))
            .dropDestination(for: String.self) { viewModel.dropRules($0, onto: row) }
    }

    private var tableContent: some View {
        Table(of: RuleListRow.self, selection: $viewModel.selectedRuleIDs) {
            TableColumn(String(localized: "Enabled", bundle: RockxyLocalization.bundle)) { row in
                enabledCell(for: row)
            }
            .width(62)

            TableColumn(String(localized: "Name", bundle: RockxyLocalization.bundle)) { row in
                switch row.kind {
                case let .folder(folder):
                    RuleFolderNameLabel(folder: folder, ruleCount: viewModel.rules(in: folder).count)
                case let .rule(rule):
                    Text(rule.name.isEmpty ? String(localized: "Untitled", bundle: RockxyLocalization.bundle) : rule.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(rule.name)
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn(String(localized: "Method", bundle: RockxyLocalization.bundle)) { row in
                if let rule = row.rule {
                    Text(viewModel.methodLabel(for: rule))
                        .lineLimit(1)
                }
            }
            .width(76)

            TableColumn(String(localized: "Matching Rule", bundle: RockxyLocalization.bundle)) { row in
                if let rule = row.rule {
                    Text(viewModel.matchingRuleLabel(for: rule))
                        .font(toolMetrics.font(monospaced: true))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(viewModel.matchingRuleLabel(for: rule))
                } else if let folder = row.folder {
                    Text(String(AttributedString(
                        localized: "^[\(viewModel.rules(in: folder).count) rule](inflect: true)",
                        bundle: RockxyLocalization.bundle,
                        locale: RockxyLocalization.locale
                    ).characters))
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 220, ideal: 300)

            TableColumn(String(localized: "Local Response", bundle: RockxyLocalization.bundle)) { row in
                if let rule = row.rule {
                    HStack(spacing: 6) {
                        Text(viewModel.mapFromLabel(for: rule))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(viewModel.filePath(for: rule))
                        if !viewModel.delayLabel(for: rule).isEmpty {
                            Text(viewModel.delayLabel(for: rule))
                                .font(toolMetrics.metadataFont(weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .width(min: 280, ideal: 420)
        } rows: {
            ForEach(viewModel.rows) { row in
                if let children = row.children {
                    DisclosureTableRow(row) {
                        ForEach(children) { child in
                            draggableRuleRow(child)
                        }
                    }
                    .dropDestination(for: String.self) { viewModel.dropRules($0, onto: row) }
                } else {
                    draggableRuleRow(row)
                }
            }
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
                        : String(localized: "No Map Local rules", bundle: RockxyLocalization.bundle),
                    systemImage: isSearching ? "magnifyingglass" : "folder.badge.gearshape",
                    description: Text(
                        isSearching
                            ? String(
                                localized: "Try a different name, method, URL, or local path.",
                                bundle: RockxyLocalization.bundle
                            )
                            : String(
                                localized: "Click \"+\" or press ⌘N to create a rule.",
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

            Text(
                viewModel.isToolEnabled
                    ? "\(viewModel.activeRuleCount) \(String(localized: "ACTIVE", bundle: RockxyLocalization.bundle))"
                    : String(localized: "MAP LOCAL OFF", bundle: RockxyLocalization.bundle)
            )
            .font(toolMetrics.metadataFont(weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .rockxyChipStyle(tint: .green, isActive: viewModel.isToolEnabled)
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
                viewModel.removeSelectedRules()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleIDs.isEmpty)
            .help(String(localized: "Remove Selected Rules", bundle: RockxyLocalization.bundle))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(
            width: max(43, toolMetrics.compactButtonSize * 2 + 1),
            height: toolMetrics.footerControlHeight
        )
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New Rule", bundle: RockxyLocalization.bundle)) { openNewEditor() }
                .keyboardShortcut("n", modifiers: .command)
            Button(String(localized: "Edit Rule", bundle: RockxyLocalization.bundle)) {
                if let rule = viewModel.selectedRule {
                    openEditor(for: rule)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedRule == nil)
            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                viewModel.duplicateSelectedRule()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel.selectedRule == nil)
            Button(String(localized: "Toggle Enabled", bundle: RockxyLocalization.bundle)) {
                if let id = viewModel.selectedRuleIDs.first {
                    viewModel.toggleRule(id: id)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(viewModel.selectedRule == nil)
            Divider()
            Button(String(localized: "New Folder", bundle: RockxyLocalization.bundle)) {
                viewModel.newFolderWithSelection()
            }
            folderMenuItems(selection: viewModel.selectedRuleIDs)
            Divider()
            Button(String(localized: "Move Up", bundle: RockxyLocalization.bundle)) {
                viewModel.moveSelectedRule(by: -1)
            }
            .disabled(!canMoveSelectedRule(by: -1))
            Button(String(localized: "Move Down", bundle: RockxyLocalization.bundle)) {
                viewModel.moveSelectedRule(by: 1)
            }
            .disabled(!canMoveSelectedRule(by: 1))
            Divider()
            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                viewModel.removeSelectedRules()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleIDs.isEmpty)
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

    /// Rules toggle themselves; a folder's checkbox shows mixed when only some rules are on and
    /// turns all of them on or off.
    @ViewBuilder
    private func enabledCell(for row: RuleListRow) -> some View {
        switch row.kind {
        case let .rule(rule):
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in viewModel.toggleRule(id: rule.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
        case let .folder(folder):
            RuleFolderToggle(folder: folder, rules: viewModel.rules(in: folder)) { ids, enabled in
                viewModel.setRulesEnabled(ids, enabled: enabled)
            }
        }
    }

    private func folderMenuItems(selection ids: Set<UUID>) -> some View {
        RuleFolderMenuItems(
            store: viewModel.folderStore,
            ruleIDs: viewModel.mapLocalRules.map(\.id).filter { ids.contains($0) }
        ) { folderID in
            viewModel.selectedRuleIDs = [folderID]
        }
    }

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let folderID = ids.first,
           let folder = viewModel.folderStore.folders.first(where: { $0.id == folderID })
        {
            RuleFolderContextItems(store: viewModel.folderStore, folder: folder) { renamingFolder = $0 }
        } else if let id = ids.first {
            Button(String(localized: "Edit Rule", bundle: RockxyLocalization.bundle)) {
                if let rule = viewModel.allRules.first(where: { $0.id == id }) {
                    openEditor(for: rule)
                }
            }
            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                viewModel.selectedRuleIDs = [id]
                viewModel.duplicateSelectedRule()
            }
            Divider()
            Button(String(localized: "Move Up", bundle: RockxyLocalization.bundle)) {
                viewModel.selectedRuleIDs = [id]
                viewModel.moveSelectedRule(by: -1)
            }
            .disabled(!canMoveRule(id: id, by: -1))
            Button(String(localized: "Move Down", bundle: RockxyLocalization.bundle)) {
                viewModel.selectedRuleIDs = [id]
                viewModel.moveSelectedRule(by: 1)
            }
            .disabled(!canMoveRule(id: id, by: 1))
            Divider()
            folderMenuItems(selection: ids.count > 1 ? ids : [id])
            Divider()
            Button(String(localized: "Delete Rule", bundle: RockxyLocalization.bundle), role: .destructive) {
                viewModel.removeRule(id: id)
            }
        }
    }

    private func openNewEditor(draft: MapLocalDraft? = nil) {
        MapLocalEditorStore.shared.openNew(draft: draft)
        openWindow(id: "mapLocalEditor")
    }

    private func openEditor(for rule: ProxyRule) {
        MapLocalEditorStore.shared.openExisting(rule)
        openWindow(id: "mapLocalEditor")
    }

    private func consumePendingDraftIfNeeded() {
        guard let draft = MapLocalDraftStore.shared.consumePending() else {
            return
        }
        openNewEditor(draft: draft)
    }

    private func canMoveSelectedRule(by offset: Int) -> Bool {
        guard let id = viewModel.selectedRuleIDs.first else {
            return false
        }
        return canMoveRule(id: id, by: offset)
    }

    private func canMoveRule(id: UUID, by offset: Int) -> Bool {
        guard viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = viewModel.mapLocalRules.firstIndex(where: { $0.id == id }) else
        {
            return false
        }
        return viewModel.mapLocalRules.indices.contains(index + offset)
    }
}
