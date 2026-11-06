import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SSLProxyingListView

/// HTTPS Decryption management window. Presents every `SSLProxyingRule` in one
/// unified native `Table` with an explicit per-row behavior column, following the
/// AllowListWindowView / NetworkConditionsWindowView shell pattern.
struct SSLProxyingListView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let failure = viewModel.manager.persistenceFailure {
                PersistenceFailureBanner(
                    title: String(
                        localized: "Couldn't save the HTTPS Decryption rules",
                        bundle: RockxyLocalization.bundle
                    ),
                    reason: failure,
                    retry: { viewModel.manager.save() }
                )
                Divider()
            }
            infoBanner
            Divider()
            tableContent
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(width: toolMetrics.fieldWidth(880), height: 620)
        .onChange(of: viewModel.manager.rules) { _, _ in
            viewModel.reconcileSelectionAfterRulesChange()
        }
        .onChange(of: viewModel.manager.applicationRules) { _, _ in
            viewModel.reconcileSelectionAfterRulesChange()
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.reconcileSelectionAfterRulesChange()
        }
        .sheet(isPresented: $viewModel.showAddDomainSheet) {
            viewModel.editingRule = nil
        } content: {
            AddSSLDomainSheet(
                editingRule: viewModel.editingRule,
                existingRules: viewModel.manager.rules
            ) { domain, listType in
                if let editing = viewModel.editingRule {
                    let didUpdate = viewModel.updateRule(id: editing.id, domain: domain, listType: listType)
                    if didUpdate {
                        viewModel.editingRule = nil
                    }
                    return didUpdate
                } else {
                    return viewModel.addRule(domain: domain, listType: listType)
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddAppSheet) {
            viewModel.editingApplicationRule = nil
        } content: {
            AddSSLApplicationSheet(
                editingRule: viewModel.editingApplicationRule,
                existingRules: viewModel.manager.applicationRules
            ) { identity, listType in
                if let editing = viewModel.editingApplicationRule {
                    let didUpdate = viewModel.updateApplicationRule(
                        id: editing.id,
                        identity: identity,
                        listType: listType
                    )
                    if didUpdate {
                        viewModel.editingApplicationRule = nil
                    }
                    return didUpdate
                }
                return viewModel.addApplicationRule(identity: identity, listType: listType)
            }
        }
        .sheet(isPresented: $viewModel.showAddObservedHostsSheet) {
            AddSSLAppDomainSheet(existingRules: viewModel.manager.rules) { domains, listType in
                viewModel.addRules(domains, listType: listType)
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
        .confirmationDialog(
            String(localized: "Replace existing HTTPS decryption settings?", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { pendingImportSource != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingImportSource = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "Choose File and Replace…", bundle: RockxyLocalization.bundle),
                role: .destructive
            ) {
                guard let pendingImportSource else {
                    return
                }
                importSource = pendingImportSource
                self.pendingImportSource = nil
                showImporter = true
            }
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {
                pendingImportSource = nil
            }
        } message: {
            Text(importConfirmationMessage)
        }
        .alert(
            String(localized: "HTTPS Decryption", bundle: RockxyLocalization.bundle),
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
        .onDeleteCommand {
            viewModel.removeSelected()
        }
        .background {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    // MARK: Private

    private enum ImportSource: Equatable {
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
    @State private var pendingImportSource: ImportSource?

    @FocusState private var isSearchFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var canInterceptHTTPS: Bool {
        ReadinessCoordinator.shared.canInterceptHTTPS
    }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var infoBannerMessage: String {
        if !viewModel.isSSLProxyingEnabled {
            return String(
                localized:
                "HTTPS decryption is off. All HTTPS connections are tunneled unread; individual rules keep their state.",
                bundle: RockxyLocalization.bundle
            )
        }
        if canInterceptHTTPS {
            return String(
                localized:
                "Decrypt rules apply to new HTTPS connections. Tunnel rules take priority on overlaps; row order does not affect matching.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized:
            "HTTPS decryption is unavailable until the Rockxy root certificate is trusted. HTTPS is tunneled unread for now.",
            bundle: RockxyLocalization.bundle
        )
    }

    private var footerHint: String {
        let countText = isSearching
            ? String(AttributedString(
                localized: "\(viewModel.filteredRows.count) of ^[\(viewModel.ruleCount) rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
            : String(AttributedString(
                localized: "^[\(viewModel.ruleCount) rule](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        let breakdown = String(
            localized: "\(viewModel.decryptCount) decrypt · \(viewModel.tunnelCount) tunnel",
            bundle: RockxyLocalization.bundle
        )
        return "\(countText) · \(breakdown)"
    }

    private var statusCapsuleText: String {
        if !viewModel.isSSLProxyingEnabled {
            return String(localized: "TOOL OFF", bundle: RockxyLocalization.bundle)
        }
        if !canInterceptHTTPS {
            return String(localized: "PASSTHROUGH ACTIVE", bundle: RockxyLocalization.bundle)
        }
        if viewModel.enabledDecryptCount == 0 {
            return String(localized: "NO DECRYPT RULES", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "DECRYPTION READY", bundle: RockxyLocalization.bundle)
    }

    private var statusCapsuleColor: Color {
        if !viewModel.isSSLProxyingEnabled || viewModel.enabledDecryptCount == 0 {
            return .secondary
        }
        return canInterceptHTTPS ? .green : .orange
    }

    private var statusCapsuleIsActive: Bool {
        viewModel.isSSLProxyingEnabled && viewModel.enabledDecryptCount > 0
    }

    private var importConfirmationMessage: String {
        if pendingImportSource == .rockxy {
            return String(
                localized:
                "Rockxy import replaces the current rules, master state, and TLS passthrough exceptions. Export first if you need a backup.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized:
            "This import replaces the current host rules. Application rules, the master state, and TLS passthrough exceptions remain unchanged.",
            bundle: RockxyLocalization.bundle
        )
    }

    private var infoBannerSystemImage: String {
        if !viewModel.isSSLProxyingEnabled {
            return "pause.circle"
        }
        return canInterceptHTTPS ? "info.circle" : "exclamationmark.triangle.fill"
    }

    private var infoBannerColor: Color {
        canInterceptHTTPS || !viewModel.isSSLProxyingEnabled ? .secondary : .orange
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(
                    String(localized: "Enable HTTPS Decryption", bundle: RockxyLocalization.bundle),
                    isOn: Binding(
                        get: { viewModel.isSSLProxyingEnabled },
                        set: { viewModel.setEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(toolMetrics.font(weight: .medium))
                .help(
                    String(
                        localized:
                        "When off, Rockxy tunnels all HTTPS without decrypting it. Individual rules keep their state.",
                        bundle: RockxyLocalization.bundle
                    )
                )

                Text(
                    String(
                        localized:
                        "Rules decide which apps and hosts Rockxy decrypts. Other connections remain opaque TLS tunnels.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            TextField(String(localized: "Search rules", bundle: RockxyLocalization.bundle), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(width: 240, height: toolMetrics.formControlHeight)
                .focused($isSearchFocused)
                .accessibilityLabel(String(
                    localized: "Search HTTPS decryption rules",
                    bundle: RockxyLocalization.bundle
                ))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    // MARK: - Info Banner

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: infoBannerSystemImage)
                .foregroundStyle(infoBannerColor)
            Text(infoBannerMessage)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(canInterceptHTTPS || !viewModel.isSSLProxyingEnabled ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if !canInterceptHTTPS {
                Button(String(localized: "Open Advanced Proxy Settings…", bundle: RockxyLocalization.bundle)) {
                    openWindow(id: "advancedProxySettings")
                }
                .buttonStyle(.link)
                .font(toolMetrics.secondaryFont())
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background {
            if canInterceptHTTPS || !viewModel.isSSLProxyingEnabled {
                Color(nsColor: .controlBackgroundColor).opacity(0.5)
            } else {
                Color.orange.opacity(0.12)
            }
        }
    }

    // MARK: - Table

    private var tableContent: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedRuleID) {
            TableColumn(String(localized: "Enabled", bundle: RockxyLocalization.bundle)) { row in
                Toggle("", isOn: Binding(
                    get: { row.isEnabled },
                    set: { viewModel.setRuleEnabled(id: row.id, enabled: $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(
                    row.isEnabled
                        ? String(localized: "Disable \(row.target)", bundle: RockxyLocalization.bundle)
                        : String(localized: "Enable \(row.target)", bundle: RockxyLocalization.bundle)
                )
            }
            .width(62)

            TableColumn(String(localized: "Target", bundle: RockxyLocalization.bundle)) { row in
                HStack(spacing: 8) {
                    rowIcon(row)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.target)
                            .font(row.isHost
                                ? toolMetrics.font(monospaced: true)
                                : toolMetrics.font())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let detail = row.targetDetail {
                            Text(detail)
                                .font(toolMetrics.metadataFont(monospaced: true))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .help(row.targetDetail ?? row.target)
                .opacity(row.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 230, ideal: 320)

            TableColumn(String(localized: "Scope", bundle: RockxyLocalization.bundle)) { row in
                Text(row.scopeLabel)
                    .foregroundStyle(.secondary)
                    .opacity(row.isEnabled ? 1.0 : 0.5)
            }
            .width(92)

            TableColumn(String(localized: "Behavior", bundle: RockxyLocalization.bundle)) { row in
                HStack(spacing: 6) {
                    Image(systemName: row.listType == .include ? "lock.open" : "lock")
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(row.listType == .include ? Color.accentColor : Color.secondary)
                    Text(SSLProxyingListViewModel.behaviorLabel(for: row.listType))
                        .lineLimit(1)
                    if hasOppositeBehaviorOverlap(for: row) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(toolMetrics.metadataFont())
                            .foregroundStyle(.orange)
                            .help(
                                String(
                                    localized:
                                    "This target has both behaviors. Tunnel Without Decryption takes priority.",
                                    bundle: RockxyLocalization.bundle
                                )
                            )
                    }
                }
                .opacity(row.isEnabled ? 1.0 : 0.5)
            }
            .width(min: 190, ideal: 220)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            tableContextMenu(ids: ids)
        } primaryAction: { ids in
            if let id = ids.first {
                viewModel.presentEditor(for: id)
            }
        }
        .overlay {
            if viewModel.filteredRows.isEmpty {
                ContentUnavailableView(
                    isSearching
                        ? String(localized: "No matching rules", bundle: RockxyLocalization.bundle)
                        : String(localized: "No HTTPS decryption rules", bundle: RockxyLocalization.bundle),
                    systemImage: isSearching ? "magnifyingglass" : "lock.shield",
                    description: Text(
                        isSearching
                            ? String(
                                localized: "Try a different app, host, scope, or behavior.",
                                bundle: RockxyLocalization.bundle
                            )
                            : String(
                                localized: "Add an application, host pattern, or observed hosts to decrypt HTTPS.",
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

    // MARK: - Footer

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
                .rockxyChipStyle(tint: statusCapsuleColor, isActive: statusCapsuleIsActive)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                presentAddApplicationRule()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Add Application…", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Add Application…", bundle: RockxyLocalization.bundle))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Menu {
                Button(String(localized: "Add Application…", bundle: RockxyLocalization.bundle)) {
                    presentAddApplicationRule()
                }

                Button(String(localized: "Add Host Pattern…", bundle: RockxyLocalization.bundle)) {
                    presentAddHostRule()
                }

                Divider()

                Button(String(localized: "Add Observed Hosts…", bundle: RockxyLocalization.bundle)) {
                    viewModel.showAddObservedHostsSheet = true
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: toolMetrics.compactButtonSize - 9, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "Add Rule", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Add Rule", bundle: RockxyLocalization.bundle))
            .accessibilityHint(
                String(
                    localized: "Choose an application, host pattern, or observed hosts.",
                    bundle: RockxyLocalization.bundle
                )
            )

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
            .accessibilityLabel(String(localized: "Delete Rule", bundle: RockxyLocalization.bundle))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(
            width: toolMetrics.compactButtonSize * 3 - 3,
            height: toolMetrics.footerControlHeight
        )
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                viewModel.presentEditorForSelection()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.selectedRuleID == nil)

            Button(viewModel.enableDisableLabel) {
                if let id = viewModel.selectedRuleID {
                    viewModel.toggleRule(id: id)
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(viewModel.selectedRuleID == nil)

            Divider()

            Section(String(localized: "Bypass", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "TLS Passthrough Exceptions…", bundle: RockxyLocalization.bundle)) {
                    viewModel.showBypassSheet = true
                }
                .help(
                    String(
                        localized:
                        "Hosts here skip decryption but still flow through Rockxy. It never disables Rockxy proxying.",
                        bundle: RockxyLocalization.bundle
                    )
                )

                Button(String(localized: "Full Proxy Bypass…", bundle: RockxyLocalization.bundle)) {
                    openWindow(id: "bypassProxyList")
                }
                .help(
                    String(
                        localized:
                        "System-proxy clients connect directly. Manually configured clients that still reach Rockxy are tunneled without decryption.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }

            Divider()

            Menu(String(localized: "Import Settings", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "From Rockxy…", bundle: RockxyLocalization.bundle)) {
                    requestImport(from: .rockxy)
                }

                Divider()

                Button(String(localized: "From Proxyman…", bundle: RockxyLocalization.bundle)) {
                    requestImport(from: .proxyman)
                }

                Button(String(localized: "From Charles Proxy…", bundle: RockxyLocalization.bundle)) {
                    requestImport(from: .charlesProxy)
                }

                Button(String(localized: "From HTTP Toolkit…", bundle: RockxyLocalization.bundle)) {
                    requestImport(from: .httpToolkit)
                }
            }

            Button(String(localized: "Export Settings…", bundle: RockxyLocalization.bundle)) {
                prepareExport()
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

    // MARK: - Context Menu

    @ViewBuilder
    private func tableContextMenu(ids: Set<UUID>) -> some View {
        if let id = ids.first {
            Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                viewModel.presentEditor(for: id)
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button(viewModel.toggleLabel(for: id)) {
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
    }

    @ViewBuilder
    private func rowIcon(_ row: SSLProxyingListViewModel.Row) -> some View {
        switch row {
        case .host:
            Image(systemName: "network")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        case let .application(rule):
            if let bundleIdentifier = rule.bundleIdentifier,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            } else if let icon = AppIconProvider.applicationIcon(named: rule.displayName, size: 20) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
        }
    }

    // MARK: - Import / Export

    private func presentAddApplicationRule() {
        viewModel.editingApplicationRule = nil
        viewModel.showAddAppSheet = true
    }

    private func presentAddHostRule() {
        viewModel.editingRule = nil
        viewModel.showAddDomainSheet = true
    }

    private func hasOppositeBehaviorOverlap(for row: SSLProxyingListViewModel.Row) -> Bool {
        viewModel.filteredRows.contains {
            $0.id != row.id
                && $0.listType != row.listType
                && $0.scopeLabel == row.scopeLabel
                && $0.targetDetail == row.targetDetail
                && $0.target.caseInsensitiveCompare(row.target) == .orderedSame
        }
    }

    private func prepareExport() {
        guard let data = viewModel.manager.exportRules() else {
            importError = String(
                localized: "Rockxy could not prepare the HTTPS Decryption export.",
                bundle: RockxyLocalization.bundle
            )
            return
        }
        exportDocument = SSLProxyingJSONDocument(data: data)
        showExporter = true
    }

    private func requestImport(from source: ImportSource) {
        pendingImportSource = source
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
                guard data.count <= Self.maxImportFileBytes else {
                    importError = String(
                        localized: "File is too large to import (max 1 MB).",
                        bundle: RockxyLocalization.bundle
                    )
                    return
                }
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
