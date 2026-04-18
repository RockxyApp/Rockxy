import SwiftUI
import UniformTypeIdentifiers

// MARK: - SSLProxyingListView

/// Window for managing SSL proxying rules with Include and Exclude lists.
/// Follows the AllowListWindowView / BreakpointRulesWindowView pattern.
struct SSLProxyingListView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            infoBanner
            Divider()
            tabPicker
            tabDescription
            Divider()
            content
            if viewModel.isFilterBarVisible {
                Divider()
                filterBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            bottomBar
            Divider()
            outerBottomBar
        }
        .frame(width: 860, height: 620)
        .onChange(of: viewModel.manager.rules) { _, _ in
            viewModel.reconcileSelectionAfterRulesChange()
        }
        .onChange(of: viewModel.currentTabRules.map(\.id)) { _, _ in
            viewModel.reconcileSelectionAfterRulesChange()
        }
        .sheet(isPresented: $viewModel.showAddDomainSheet) {
            viewModel.editingRule = nil
        } content: {
            AddSSLDomainSheet(editingRule: viewModel.editingRule) { domain in
                if let editing = viewModel.editingRule {
                    viewModel.updateRule(id: editing.id, domain: domain)
                } else {
                    viewModel.addRule(domain: domain)
                }
                viewModel.editingRule = nil
            }
        }
        .sheet(isPresented: $viewModel.showAddAppSheet) {
            AddSSLAppDomainSheet { domains in
                viewModel.addRules(domains)
            }
        }
        .sheet(isPresented: $viewModel.showBypassSheet) {
            BypassProxySettingsSheet(manager: viewModel.manager)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "ssl-proxying-settings.json"
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

    private enum ImportSource {
        case rockxy
        case charlesProxy
        case proxyman
        case httpToolkit
    }

    private static let maxImportFileBytes = 1_024 * 1_024

    @State private var viewModel = SSLProxyingListViewModel()
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: SSLProxyingJSONDocument?
    @State private var importError: String?
    @State private var importSource: ImportSource = .rockxy

    @FocusState private var isFilterFocused: Bool

    private var tabDescriptionText: String {
        switch viewModel.selectedTab {
        case .include:
            String(localized: "Intercept & Decrypt HTTPS in below list")
        case .exclude:
            String(
                localized: "DO NOT Decrypt HTTPS in below list. Useful to exclude some domains/apps from the Include List"
            )
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text(String(localized: "SSL Proxying List"))
                .font(.headline)
            Spacer()
            Toggle(
                String(localized: "Enable SSL Proxying Tool"),
                isOn: Binding(
                    get: { viewModel.isSSLProxyingEnabled },
                    set: { viewModel.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Info Banner

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized: "Define Clients or Domains (wildcard) that Rockxy will decrypt their HTTPS Request/Response."
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

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack {
            Spacer()
            Picker("", selection: Binding(
                get: { viewModel.selectedTab },
                set: { viewModel.switchTab(to: $0) }
            )) {
                Text(String(localized: "Include List")).tag(SSLProxyingListType.include)
                Text(String(localized: "Exclude List")).tag(SSLProxyingListType.exclude)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var tabDescription: some View {
        HStack {
            Text(tabDescriptionText)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if viewModel.currentTabRules.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                columnHeader
                Divider()
                List(selection: $viewModel.selectedRuleID) {
                    ForEach(viewModel.currentTabRules) { rule in
                        SSLProxyingRuleRow(rule: rule) {
                            viewModel.selectRule(id: rule.id)
                        } onToggle: { newValue in
                            viewModel.setRuleEnabled(id: rule.id, enabled: newValue)
                        }
                        .tag(rule.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: UUID.self) { items in
                    if let id = items.first {
                        contextMenuItems(for: id)
                    }
                } primaryAction: { items in
                    if let id = items.first {
                        viewModel.presentEditor(for: id)
                    }
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
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.background.tertiary)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)

            if viewModel.selectedTab == .exclude {
                Text(String(localized: "⌘N: Add new apps"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(String(localized: "⇧⌘N: Add custom Domains / Wildcards"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text(String(localized: "No SSL Proxying Rules"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Add domains or apps to intercept their HTTPS traffic."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            TextField(
                String(localized: "Filter"),
                text: $viewModel.filterText,
                prompt: Text(String(localized: "Filter (Hide: ESC)"))
            )
            .textFieldStyle(.roundedBorder)
            .focused($isFilterFocused)
            .onExitCommand { hideFilterBar() }
            .onAppear { isFilterFocused = true }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.background)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            plusMenu

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
                viewModel.isFilterBarVisible = true
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

    private var plusMenu: some View {
        Menu {
            Button(String(localized: "Add App…")) {
                viewModel.showAddAppSheet = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(String(localized: "Add Domain…")) {
                viewModel.showAddDomainSheet = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(String(localized: "Add Rule"))
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "Add App…")) {
                viewModel.showAddAppSheet = true
            }

            Button(String(localized: "Add Domain…")) {
                viewModel.showAddDomainSheet = true
            }

            Divider()

            Button(String(localized: "Edit…")) {
                viewModel.presentEditorForSelection()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)

            Divider()

            Button(viewModel.enableDisableLabel) {
                if let id = viewModel.selectedRuleID {
                    viewModel.toggleRule(id: id)
                }
            }
            .disabled(viewModel.selectedRuleID == nil)

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

    // MARK: - Outer Bottom Bar

    private var outerBottomBar: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Bypass Proxy Setting…")) {
                viewModel.showBypassSheet = true
            }
            .buttonStyle(.borderless)

            Spacer()

            outerMoreMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var outerMoreMenu: some View {
        Menu {
            Menu(String(localized: "Import Settings")) {
                Button(String(localized: "From Rockxy…")) {
                    importSource = .rockxy
                    showImporter = true
                }

                Divider()

                Button(String(localized: "From Proxyman…")) {
                    importSource = .proxyman
                    showImporter = true
                }

                Button(String(localized: "From Charles Proxy…")) {
                    importSource = .charlesProxy
                    showImporter = true
                }

                Button(String(localized: "From HTTPToolkit…")) {
                    importSource = .httpToolkit
                    showImporter = true
                }
            }

            Divider()

            Button(String(localized: "Export Settings…")) {
                prepareExport()
            }
        } label: {
            Text(String(localized: "More"))
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for id: UUID) -> some View {
        Button(String(localized: "Edit…")) {
            viewModel.presentEditor(for: id)
        }

        Button(enableDisableLabel(for: id)) {
            viewModel.toggleRule(id: id)
        }

        Divider()

        Button(String(localized: "Delete"), role: .destructive) {
            viewModel.removeRule(id: id)
        }
    }

    private func enableDisableLabel(for id: UUID) -> String {
        guard let rule = viewModel.manager.rules.first(where: { $0.id == id }) else {
            return String(localized: "Enable Rule")
        }
        return rule.isEnabled
            ? String(localized: "Disable Rule")
            : String(localized: "Enable Rule")
    }

    // MARK: - Import / Export

    private func prepareExport() {
        guard let data = viewModel.manager.exportRules() else {
            return
        }
        exportDocument = SSLProxyingJSONDocument(data: data)
        showExporter = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart {
                url.stopAccessingSecurityScopedResource()
            } }
            do {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize, fileSize > Self.maxImportFileBytes {
                    importError = String(localized: "File is too large to import (max 1 MB).")
                    return
                }
                let data = try Data(contentsOf: url)
                switch importSource {
                case .rockxy:
                    try viewModel.manager.importRules(from: data)
                case .charlesProxy:
                    let rules = try CharlesSSLImporter.importRules(from: data)
                    viewModel.manager.replaceAllRules(rules)
                case .proxyman:
                    let rules = try ProxymanSSLImporter.importRules(from: data)
                    viewModel.manager.replaceAllRules(rules)
                case .httpToolkit:
                    let rules = try HTTPToolkitImporter.importRules(from: data)
                    viewModel.manager.replaceAllRules(rules)
                }
            } catch {
                importError = error.localizedDescription
            }
        case let .failure(error):
            importError = error.localizedDescription
        }
    }

    private func hideFilterBar() {
        viewModel.isFilterBarVisible = false
        viewModel.filterText = ""
    }
}

// MARK: - SSLProxyingRuleRow

private struct SSLProxyingRuleRow: View {
    let rule: SSLProxyingRule
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    onSelect()
                    onToggle(newValue)
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: "circle.slash")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(rule.domain)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .opacity(rule.isEnabled ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - SSLProxyingJSONDocument

struct SSLProxyingJSONDocument: FileDocument {
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
