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
    var isFilterBarVisible = false
    var filterColumn: AllowListFilterColumn = .name
    var filterText = ""

    /// Derived from manager.rules — never cached locally.
    var filteredRules: [AllowListRule] {
        guard !filterText.isEmpty else {
            return manager.rules
        }
        return manager.rules.filter { rule in
            switch filterColumn {
            case .name:
                rule.name.localizedCaseInsensitiveContains(filterText)
            case .method:
                (rule.method ?? "ANY").localizedCaseInsensitiveContains(filterText)
            case .matchingRule:
                rule.rawPattern.localizedCaseInsensitiveContains(filterText)
            }
        }
    }

    var ruleCount: Int {
        manager.rules.count
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
            name: String(localized: "Copy of \(original.name)"),
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
        VStack(spacing: 0) {
            toolbar
            Divider()
            infoBanner
            Divider()
            content
            if viewModel.isFilterBarVisible {
                Divider()
                AllowListFilterBar(
                    filterColumn: $viewModel.filterColumn,
                    filterText: $viewModel.filterText,
                    onDismiss: hideFilterBar
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            bottomBar
        }
        .frame(width: 860, height: 620)
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
            defaultFilename: "allow-list"
        ) { _ in
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            String(localized: "Import Failed"),
            isPresented: Binding(
                get: { importError != nil },
                set: { newValue in
                    if !newValue {
                        importError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK")) { importError = nil }
        } message: {
            if let error = importError {
                Text(error)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFilterBarVisible)
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
    @State private var exportDocument: AllowListJSONDocument?
    @State private var importError: String?

    private var enableDisableLabel: String {
        guard let id = viewModel.selectedRuleID,
              let rule = viewModel.manager.rules.first(where: { $0.id == id }) else
        {
            return String(localized: "Enable Rule")
        }
        return rule.isEnabled
            ? String(localized: "Disable Rule")
            : String(localized: "Enable Rule")
    }

    private var toolbar: some View {
        HStack {
            Text(String(localized: "Allow List"))
                .font(.headline)
            Spacer()
            Toggle(
                String(localized: "Enable Allow List Tool"),
                isOn: Binding(
                    get: { viewModel.isAllowListActive },
                    set: { viewModel.setActive($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
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
                    "Define URL patterns for capturing only matching requests. Each request is checked against the rules from top to bottom, stopping when a match is found."
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
        if viewModel.manager.rules.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                columnHeader
                Divider()
                List(selection: $viewModel.selectedRuleID) {
                    ForEach(viewModel.filteredRules) { rule in
                        AllowListRulesRow(rule: rule) {
                            viewModel.toggleRule(id: rule.id)
                        }
                        .tag(rule.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: UUID.self) { _ in
                    contextMenuItems
                } primaryAction: { _ in
                    openEditorForSelection()
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 24)
            Text(String(localized: "Name"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 220, alignment: .leading)
            Text(String(localized: "Method"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(String(localized: "Matching Rule"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.background.tertiary)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(String(localized: "No Allow List Rules"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized:
                    "Add URL patterns to capture only matching requests.\nWhen active, unmatched traffic is forwarded but not recorded."
                )
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.presentNewRuleEditor()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "New Rule"))

            Button {
                viewModel.removeSelected()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedRuleID == nil)
            .help(String(localized: "Delete Rule"))

            Divider()
                .frame(height: 16)

            Text(
                "\(viewModel.ruleCount) \(viewModel.ruleCount == 1 ? String(localized: "rule") : String(localized: "rules"))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                showFilterBar()
            } label: {
                Label(String(localized: "Filter"), systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("f", modifiers: .command)

            moreMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var contextMenuItems: some View {
        Button(String(localized: "Edit…")) {
            openEditorForSelection()
        }
        .keyboardShortcut(.return, modifiers: .command)

        Button(String(localized: "Duplicate")) {
            viewModel.duplicateSelected()
        }
        .keyboardShortcut("d", modifiers: .command)

        Button(enableDisableLabel) {
            if let id = viewModel.selectedRuleID {
                viewModel.toggleRule(id: id)
            }
        }

        Divider()

        Button(String(localized: "Delete"), role: .destructive) {
            viewModel.removeSelected()
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New Rule…")) {
                viewModel.presentNewRuleEditor()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button(String(localized: "Edit…")) {
                openEditorForSelection()
            }
            .keyboardShortcut(.return, modifiers: .command)
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
            .disabled(viewModel.selectedRuleID == nil)

            Divider()

            Button(String(localized: "Export Settings…")) {
                prepareExport()
            }

            Button(String(localized: "Import Settings…")) {
                showImporter = true
            }

            Divider()

            Button(String(localized: "Delete"), role: .destructive) {
                viewModel.removeSelected()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)
        } label: {
            Text(String(localized: "More"))
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .menuStyle(.borderlessButton)
    }

    private func openEditorForSelection() {
        guard let id = viewModel.selectedRuleID,
              let rule = viewModel.manager.rules.first(where: { $0.id == id }) else
        {
            return
        }
        viewModel.presentEditorForEditing(rule)
    }

    private func showFilterBar() {
        viewModel.isFilterBarVisible = true
    }

    private func hideFilterBar() {
        viewModel.isFilterBarVisible = false
        viewModel.filterText = ""
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
        guard let data = viewModel.manager.exportRulesJSON() else {
            return
        }
        exportDocument = AllowListJSONDocument(data: data)
        showExporter = true
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
                        localized: "File is too large to import (max 1 MB)."
                    )
                    return
                }
                let data = try Data(contentsOf: url)
                try viewModel.manager.importRulesJSON(data)
            } catch {
                importError = error.localizedDescription
                Self.logger.error("Allow list import failed: \(error.localizedDescription)")
            }
        case let .failure(error):
            importError = error.localizedDescription
        }
    }
}

// MARK: - AllowListRulesRow

private struct AllowListRulesRow: View {
    let rule: AllowListRule
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
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 220, alignment: .leading)

            Text(rule.method ?? "ANY")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(rule.rawPattern)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .opacity(rule.isEnabled ? 1.0 : 0.5)
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
