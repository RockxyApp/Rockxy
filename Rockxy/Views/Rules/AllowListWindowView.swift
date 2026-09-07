import os
import SwiftUI
import UniformTypeIdentifiers

// Presents the Allow List window for rule editing and management.

// MARK: - AllowListEditorSession

/// Identity wrapper for the Allow List editor sheet. Every time the view model
/// needs to show or re-show the editor (New Rule, Edit, quick-create, or a
/// follow-up quick-create while the sheet is already visible), it assigns a
/// fresh `AllowListEditorSession` with a new `UUID`. Because the sheet is
/// driven by `.sheet(item:)`, SwiftUI sees the new identity, tears down the
/// old sheet view (dropping its `@State` draft), and re-inits from this
/// session's mode — guaranteeing a fresh draft every time.
struct AllowListEditorSession: Identifiable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), mode: Mode) {
        self.id = id
        self.mode = mode
    }

    // MARK: Internal

    enum Mode {
        /// Blank new rule or a context-driven quick-create.
        case create(context: AllowListEditorContext?)
        /// Editing an existing rule loaded from the manager.
        case edit(rule: AllowListRule)
    }

    let id: UUID
    let mode: Mode
}

// MARK: - AllowListImportSource

private enum AllowListImportSource {
    case rockxyJSON
    case proxyman
    case charlesProxy
}

// MARK: - AllowListWindowViewModel

@MainActor @Observable
final class AllowListWindowViewModel {
    // MARK: Lifecycle

    init(manager: AllowListManager = .shared) {
        self.manager = manager
    }

    // MARK: Internal

    /// Stable reference to the single source of truth. Observed via SwiftUI `@Observable`.
    let manager: AllowListManager

    var selectedRuleID: UUID?
    /// Drives `.sheet(item:)`. A fresh session (new UUID) forces the sheet to
    /// tear down and rebuild with the new mode's draft — this is how we handle
    /// "new quick-create while the editor is already open" without leaving
    /// stale fields on screen.
    var editorSession: AllowListEditorSession?
    var searchText = ""

    /// Derived from manager.rules — never cached locally.
    var filteredRules: [AllowListRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return manager.rules
        }
        return manager.rules.filter { rule in
            rule.name.localizedCaseInsensitiveContains(query)
                || (rule.method ?? "ANY").localizedCaseInsensitiveContains(query)
                || rule.rawPattern.localizedCaseInsensitiveContains(query)
        }
    }

    var ruleCount: Int {
        manager.rules.count
    }

    var activeRuleCount: Int {
        manager.rules.count(where: \.isEnabled)
    }

    var effectiveRuleCount: Int {
        manager.rules.count { rule in
            rule.isEnabled && AllowListRulePatternValidation.isValid(
                rawPattern: rule.rawPattern,
                matchType: rule.matchType,
                includeSubpaths: rule.includeSubpaths
            )
        }
    }

    var isAllowListActive: Bool {
        manager.isActive
    }

    // MARK: - Editor Session Presentation

    /// Opens the editor for a blank new rule.
    func presentNewRuleEditor() {
        editorSession = AllowListEditorSession(mode: .create(context: nil))
    }

    /// Opens (or re-opens) the editor pre-filled from a quick-create context.
    /// Always assigns a fresh session id so a pending sheet is replaced with
    /// the new draft, and SwiftUI's `.sheet(item:)` tears down the prior
    /// instance to drop its stale `@State`.
    func presentEditorForContext(_ context: AllowListEditorContext) {
        editorSession = AllowListEditorSession(mode: .create(context: context))
    }

    /// Opens the editor in edit mode for an existing rule.
    func presentEditorForEditing(_ rule: AllowListRule) {
        editorSession = AllowListEditorSession(mode: .edit(rule: rule))
    }

    func dismissEditor() {
        editorSession = nil
    }

    // MARK: - CRUD (view model owns selection + delegates storage to manager)

    func addRule(
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        includeSubpaths: Bool
    ) {
        let rule = AllowListRule(
            name: ruleName.isEmpty ? urlPattern : ruleName,
            rawPattern: urlPattern,
            method: httpMethod.methodValue,
            matchType: matchType,
            includeSubpaths: includeSubpaths
        )
        selectedRuleID = rule.id
        manager.addRule(rule)
    }

    func updateRule(
        id: UUID,
        ruleName: String,
        urlPattern: String,
        httpMethod: HTTPMethodFilter,
        matchType: RuleMatchType,
        includeSubpaths: Bool
    ) {
        guard let existing = manager.rules.first(where: { $0.id == id }) else {
            return
        }
        var updated = existing
        updated.name = ruleName.isEmpty ? urlPattern : ruleName
        updated.rawPattern = urlPattern
        updated.method = httpMethod.methodValue
        updated.matchType = matchType
        updated.includeSubpaths = includeSubpaths
        manager.updateRule(updated)
        selectedRuleID = updated.id
    }

    func removeSelected() {
        guard let id = selectedRuleID else {
            return
        }
        manager.removeRule(id: id)
        selectedRuleID = nil
    }

    func toggleRule(id: UUID) {
        manager.toggleRule(id: id)
    }

    func duplicateSelected() {
        guard let id = selectedRuleID,
              let original = manager.rules.first(where: { $0.id == id }) else
        {
            return
        }
        let copy = AllowListRule(
            id: UUID(),
            name: String(localized: "Copy of \(original.name)", bundle: RockxyLocalization.bundle),
            isEnabled: original.isEnabled,
            rawPattern: original.rawPattern,
            method: original.method,
            matchType: original.matchType,
            includeSubpaths: original.includeSubpaths
        )
        selectedRuleID = copy.id
        manager.addRule(copy)
    }

    func setActive(_ active: Bool) {
        manager.setActive(active)
    }

    func exportRulesJSON() throws -> Data {
        guard let data = manager.exportRulesJSON() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    func importRules(_ rules: [AllowListRule]) {
        manager.replaceAll(rules)
        selectedRuleID = rules.first?.id
    }

    /// Called from the view layer's `.onChange(of: manager.rules)` to keep the
    /// table selection in sync when rules change externally (import, migration).
    func reconcileSelectionAfterRulesChange() {
        guard let id = selectedRuleID else {
            return
        }
        if !manager.rules.contains(where: { $0.id == id }) {
            selectedRuleID = nil
        }
    }
}

// MARK: - AllowListWindowView

struct AllowListWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            infoBanner
            Divider()
            AllowListTableView(
                rules: viewModel.filteredRules,
                isSearching: !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedRuleID: $viewModel.selectedRuleID,
                onToggle: { viewModel.toggleRule(id: $0) },
                onEdit: openEditorForRule,
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
        .onAppear { consumePendingContext() }
        .onReceive(NotificationCenter.default.publisher(for: .openAllowListWindow)) { _ in
            consumePendingContext()
        }
        .onChange(of: viewModel.manager.rules) { _, _ in
            viewModel.reconcileSelectionAfterRulesChange()
        }
        .sheet(item: $viewModel.editorSession) { session in
            // `session.id` feeds `.sheet(item:)` identity — a new session id
            // rebuilds this view and drops any stale `@State` from a prior open.
            AddAllowListRuleSheet(
                session: session
            ) { name, pattern, method, matchType, includeSubpaths in
                if case let .edit(rule) = session.mode {
                    viewModel.updateRule(
                        id: rule.id,
                        ruleName: name,
                        urlPattern: pattern,
                        httpMethod: method,
                        matchType: matchType,
                        includeSubpaths: includeSubpaths
                    )
                } else {
                    viewModel.addRule(
                        ruleName: name,
                        urlPattern: pattern,
                        httpMethod: method,
                        matchType: matchType,
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
            defaultFilename: "allow-list-settings.json"
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
            operationAlertTitle,
            isPresented: Binding(
                get: { importError != nil },
                set: { newValue in
                    if !newValue {
                        importError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) { importError = nil }
        } message: {
            if let error = importError {
                Text(error)
            }
        }
        .alert(
            String(localized: "Replace Allow List Rules?", bundle: RockxyLocalization.bundle),
            isPresented: $showImportConfirmation
        ) {
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {}
            Button(String(localized: "Choose File…", bundle: RockxyLocalization.bundle)) {
                showImporter = true
            }
        } message: {
            Text(importConfirmationMessage)
        }
        .onDeleteCommand {
            viewModel.removeSelected()
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "AllowListWindowView"
    )

    /// Maximum imported-file size — 1 MiB is plenty for thousands of rules and
    /// bounds any accidental allocation if the user picks the wrong file.
    private static let maxImportFileBytes = 1_024 * 1_024

    @State private var viewModel = AllowListWindowViewModel()
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showImportConfirmation = false
    @State private var exportDocument: AllowListJSONDocument?
    @State private var importError: String?
    @State private var operationAlertTitle = String(localized: "Import Failed", bundle: RockxyLocalization.bundle)
    @State private var importSource: AllowListImportSource = .rockxyJSON
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var enableDisableLabel: String {
        guard let id = viewModel.selectedRuleID,
              let rule = viewModel.manager.rules.first(where: { $0.id == id }) else
        {
            return String(localized: "Enable Rule", bundle: RockxyLocalization.bundle)
        }
        return rule.isEnabled
            ? String(localized: "Disable Rule", bundle: RockxyLocalization.bundle)
            : String(localized: "Enable Rule", bundle: RockxyLocalization.bundle)
    }

    private var isCapturingNothing: Bool {
        viewModel.isAllowListActive && viewModel.effectiveRuleCount == 0
    }

    private var infoBannerMessage: String {
        if isCapturingNothing {
            return String(
                localized:
                "Allow List is on, but no valid enabled rule can match. Rockxy will not record traffic until a rule is enabled.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized:
            "Allow List controls what Rockxy records in the session. Non-matching traffic is still forwarded normally.",
            bundle: RockxyLocalization.bundle
        )
    }

    private var footerHint: String {
        let countText = viewModel.searchText.isEmpty
            ? "\(viewModel.ruleCount) \(String(localized: "rules", bundle: RockxyLocalization.bundle))"
            : String(
                localized: "\(viewModel.filteredRules.count) of \(viewModel.ruleCount) rules",
                bundle: RockxyLocalization.bundle
            )
        return "\(countText) · ⌘N \(String(localized: "New Rule", bundle: RockxyLocalization.bundle)) · ⌘↩ \(String(localized: "Edit", bundle: RockxyLocalization.bundle))"
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var importConfirmationMessage: String {
        switch importSource {
        case .rockxyJSON:
            String(
                localized:
                "Importing replaces all current rules and applies the Allow List on/off state stored in the file.",
                bundle: RockxyLocalization.bundle
            )
        case .proxyman,
             .charlesProxy:
            String(
                localized:
                "Migrating replaces all current rules. Rockxy keeps the current Allow List on/off state.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(
                    String(localized: "Enable Allow List", bundle: RockxyLocalization.bundle),
                    isOn: Binding(
                        get: { viewModel.isAllowListActive },
                        set: { viewModel.setActive($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font(weight: .medium))
                .help(
                    String(
                        localized:
                        "When off, Rockxy captures all traffic. Individual Allow List rules keep their enabled state.",
                        bundle: RockxyLocalization.bundle
                    )
                )

                Text(String(
                    localized: "Capture and display only traffic that matches an enabled rule.",
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
                .accessibilityLabel(String(localized: "Search Allow List rules", bundle: RockxyLocalization.bundle))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: isCapturingNothing ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(isCapturingNothing ? Color.orange : Color.secondary)
            Text(infoBannerMessage)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(isCapturingNothing ? Color.primary : Color.secondary)
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background {
            if isCapturingNothing {
                Color.orange.opacity(0.12)
            } else {
                Color(nsColor: .controlBackgroundColor).opacity(0.5)
            }
        }
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
                viewModel.isAllowListActive
                    ? "\(viewModel.effectiveRuleCount) \(String(localized: "ACTIVE", bundle: RockxyLocalization.bundle))"
                    : String(localized: "ALLOW LIST OFF", bundle: RockxyLocalization.bundle)
            )
            .font(toolMetrics.metadataFont(weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .rockxyChipStyle(tint: .green, isActive: viewModel.isAllowListActive)
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
            .keyboardShortcut(.return, modifiers: .command)
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
            .keyboardShortcut(.space, modifiers: [])
            .disabled(viewModel.selectedRuleID == nil)

            Divider()

            Button(String(localized: "Export Settings…", bundle: RockxyLocalization.bundle)) {
                prepareExport()
            }
            .disabled(viewModel.manager.rules.isEmpty)

            Button(String(localized: "Import Rockxy Settings…", bundle: RockxyLocalization.bundle)) {
                requestImport(from: .rockxyJSON)
            }

            Menu(String(localized: "Migrate from Another Proxy", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "Proxyman Settings…", bundle: RockxyLocalization.bundle)) {
                    requestImport(from: .proxyman)
                }

                Button(String(localized: "Charles Proxy Settings…", bundle: RockxyLocalization.bundle)) {
                    requestImport(from: .charlesProxy)
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
        .keyboardShortcut(.return, modifiers: .command)

        Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
            viewModel.selectedRuleID = id
            viewModel.duplicateSelected()
        }
        .keyboardShortcut("d", modifiers: .command)

        Button(enableDisableLabel(for: id)) {
            viewModel.toggleRule(id: id)
        }
        .keyboardShortcut(.space, modifiers: [])

        Divider()

        Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
            viewModel.selectedRuleID = id
            viewModel.removeSelected()
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private func enableDisableLabel(for id: UUID) -> String {
        guard let rule = viewModel.manager.rules.first(where: { $0.id == id }) else {
            return String(localized: "Enable Rule", bundle: RockxyLocalization.bundle)
        }
        return rule.isEnabled ? String(localized: "Disable Rule", bundle: RockxyLocalization.bundle) : String(
            localized: "Enable Rule",
            bundle: RockxyLocalization.bundle
        )
    }

    private func openEditorForSelection() {
        guard let id = viewModel.selectedRuleID,
              let rule = viewModel.manager.rules.first(where: { $0.id == id }) else
        {
            return
        }
        viewModel.presentEditorForEditing(rule)
    }

    private func openEditorForRule(_ id: UUID) {
        guard let rule = viewModel.manager.rules.first(where: { $0.id == id }) else {
            return
        }
        viewModel.selectedRuleID = id
        viewModel.presentEditorForEditing(rule)
    }

    private func consumePendingContext() {
        guard let context = AllowListEditorContextStore.shared.consumePending() else {
            return
        }
        // Always assigns a fresh session id — if the editor was already open
        // from a prior quick-create, SwiftUI will see a new `.sheet(item:)`
        // identity and rebuild the sheet with this new context's draft.
        viewModel.presentEditorForContext(context)
    }

    private func prepareExport() {
        do {
            exportDocument = try AllowListJSONDocument(data: viewModel.exportRulesJSON())
            showExporter = true
        } catch {
            operationAlertTitle = String(localized: "Export Failed", bundle: RockxyLocalization.bundle)
            importError = error.localizedDescription
            Self.logger.error("Allow list export failed: \(error.localizedDescription)")
        }
    }

    private func requestImport(from source: AllowListImportSource) {
        importSource = source
        showImportConfirmation = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        operationAlertTitle = String(localized: "Import Failed", bundle: RockxyLocalization.bundle)
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
                        localized: "File is too large to import (max 1 MB).", bundle: RockxyLocalization.bundle
                    )
                    return
                }
                let data = try Data(contentsOf: url)
                switch importSource {
                case .rockxyJSON:
                    try viewModel.manager.importRulesJSON(data)
                case .proxyman:
                    try viewModel.importRules(AllowListSettingsCodec.importFromProxyman(data))
                case .charlesProxy:
                    try viewModel.importRules(AllowListSettingsCodec.importFromCharlesProxy(data))
                }
            } catch {
                importError = error.localizedDescription
                Self.logger.error("Allow list import failed: \(error.localizedDescription)")
            }
        case let .failure(error):
            importError = error.localizedDescription
        }
    }
}

// MARK: - AllowListTableLayout

private enum AllowListTableLayout {
    static let enabledWidth: CGFloat = 66
    static let nameWidth: CGFloat = 330
    static let methodWidth: CGFloat = 90
    static let contentInset: CGFloat = 10
}

// MARK: - AllowListTableView

private struct AllowListTableView<ContextMenuContent: View>: View {
    // MARK: Internal

    let rules: [AllowListRule]
    let isSearching: Bool
    @Binding var selectedRuleID: UUID?

    let onToggle: (UUID) -> Void
    let onEdit: (UUID) -> Void
    @ViewBuilder let contextMenuItems: (UUID) -> ContextMenuContent

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            ZStack {
                zebraRows

                if rules.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: isSearching ? "magnifyingglass" : "checklist")
                            .font(.system(size: max(22, toolMetrics.emptyStateFontSize + 8)))
                            .foregroundStyle(.secondary)
                        Text(
                            isSearching
                                ? String(localized: "No matching rules", bundle: RockxyLocalization.bundle)
                                : String(localized: "No Allow List rules", bundle: RockxyLocalization.bundle)
                        )
                        .font(toolMetrics.font(weight: .medium))
                        Text(
                            isSearching
                                ? String(
                                    localized: "Try a different name, method, or URL pattern.",
                                    bundle: RockxyLocalization.bundle
                                )
                                : String(
                                    localized: "Click \"+\" or press ⌘N to create a rule.",
                                    bundle: RockxyLocalization.bundle
                                )
                        )
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                                AllowListTableRow(
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
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            columnHeaderCell(
                String(localized: "Enabled", bundle: RockxyLocalization.bundle),
                width: AllowListTableLayout.enabledWidth
            )
            columnHeaderCell(
                String(localized: "Name", bundle: RockxyLocalization.bundle),
                width: AllowListTableLayout.nameWidth,
                alignment: .center
            )
            columnHeaderCell(
                String(localized: "Method", bundle: RockxyLocalization.bundle),
                width: AllowListTableLayout.methodWidth,
                leadingInset: AllowListTableLayout.contentInset
            )
            Text(String(localized: "Matching Rule", bundle: RockxyLocalization.bundle))
                .padding(.leading, AllowListTableLayout.contentInset)
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
    }

    private var zebraRows: some View {
        GeometryReader { proxy in
            let rowCount = max(1, Int(ceil(proxy.size.height / toolMetrics.tableRowHeight)))
            VStack(spacing: 0) {
                ForEach(0 ..< rowCount, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color.secondary
                            .opacity(0.08))
                        .frame(height: toolMetrics.tableRowHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }

    private func columnHeaderCell(
        _ title: String,
        width: CGFloat,
        alignment: Alignment = .leading,
        leadingInset: CGFloat = 0
    )
        -> some View
    {
        Text(title)
            .padding(.leading, leadingInset)
            .frame(width: width, alignment: alignment)
            .overlay(alignment: .trailing) {
                tableDivider
            }
    }
}

// MARK: - AllowListTableRow

private struct AllowListTableRow: View {
    // MARK: Internal

    let rule: AllowListRule
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
            .frame(width: AllowListTableLayout.enabledWidth)

            Text(rule.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, AllowListTableLayout.contentInset)
                .frame(width: AllowListTableLayout.nameWidth, alignment: .leading)

            Text(rule.method ?? "ANY")
                .lineLimit(1)
                .padding(.leading, AllowListTableLayout.contentInset)
                .frame(width: AllowListTableLayout.methodWidth, alignment: .leading)

            Text(rule.rawPattern)
                .font(toolMetrics.font(monospaced: true))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, AllowListTableLayout.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(rule.rawPattern)
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

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.22))
        }
        return AnyShapeStyle(rowIndex.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color.secondary
            .opacity(0.08))
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - AllowListJSONDocument

/// SwiftUI `fileExporter` document wrapper for Allow List JSON export.
struct AllowListJSONDocument: FileDocument {
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

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
