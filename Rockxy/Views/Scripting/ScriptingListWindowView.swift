import SwiftUI

/// The Scripting List window. Mirrors the approved Allow List / Block List /
/// Breakpoint Rules idiom: header (master toggle + always-visible search),
/// divider, dynamic info banner, native Table (folders + scripts), divider,
/// footer (add/remove + hint + More menu + status capsule).
struct ScriptingListWindowView: View {
    // MARK: Internal

    var body: some View {
        layout
            .confirmationDialog(
                deletionTitle(for: pendingDeletion),
                isPresented: deletionPresented,
                presenting: pendingDeletion
            ) { row in
                Button(deletionButtonTitle(for: row), role: .destructive) {
                    confirmDeletion(row)
                }
                Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { row in
                Text(deletionMessage(for: row))
            }
            .alert(
                String(localized: "Scripting", bundle: RockxyLocalization.bundle),
                isPresented: operationErrorPresented
            ) {
                Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) { viewModel.operationError = nil }
            } message: {
                if let operationError = viewModel.operationError {
                    Text(operationError)
                }
            }
    }

    // MARK: Private

    @State private var viewModel = ScriptingListViewModel()
    @State private var pendingDeletion: ScriptListRowID?
    @FocusState private var searchIsFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: {
                if !$0 {
                    pendingDeletion = nil
                }
            }
        )
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.operationError != nil },
            set: {
                if !$0 {
                    viewModel.operationError = nil
                }
            }
        )
    }

    // MARK: - Selection helpers

    private var selectedRow: Binding<ScriptListRowID?> {
        Binding(
            get: { viewModel.selectedRowID },
            set: { viewModel.selectedRowID = $0 }
        )
    }

    private var isScriptSelected: Bool {
        if case .script = viewModel.selectedRowID {
            return true
        }
        return false
    }

    private var isFolderSelected: Bool {
        if case .folder = viewModel.selectedRowID {
            return true
        }
        return false
    }

    private var isSearching: Bool {
        !viewModel.filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var enabledScriptCount: Int {
        viewModel.plugins.count(where: \.isEnabled)
    }

    private var activeScriptCount: Int {
        viewModel.plugins.count { $0.isEnabled && $0.runtimeStatus == .active }
    }

    private var visibleScriptCount: Int {
        viewModel.filteredDisplayRows.reduce(0) { partial, row in
            if case .script = row.kind {
                return partial + 1
            }
            return partial
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var disclosureSlotWidth: CGFloat {
        max(16, toolMetrics.smallIconFontSize + 5)
    }

    private var toggleControlSize: ControlSize {
        toolMetrics.bodyFontSize >= 20 ? .large : .regular
    }

    private var infoBannerIsWarning: Bool {
        !viewModel.toolEnabled || (enabledScriptCount > 0 && activeScriptCount == 0)
    }

    private var infoBannerMessage: String {
        guard viewModel.toolEnabled else {
            return String(
                localized: "Scripting is off. Enabled scripts are kept, but none run until you turn Scripting on.",
                bundle: RockxyLocalization.bundle
            )
        }
        if enabledScriptCount == 0 {
            return String(
                localized: "Scripting is on, but no script is enabled. Traffic passes through unchanged.",
                bundle: RockxyLocalization.bundle
            )
        }
        if activeScriptCount == 0 {
            return String(
                localized: "Enabled scripts are not active. Review the Status column before testing traffic.",
                bundle: RockxyLocalization.bundle
            )
        }
        if viewModel.advanceAllowChaining {
            return String(
                localized: "Matching scripts can run in sequence. A block or mock result ends the chain.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "Rockxy stops after the first matching script returns a result.",
            bundle: RockxyLocalization.bundle
        )
    }

    private var enableDisableLabel: String {
        guard case let .script(id) = viewModel.selectedRowID,
              let script = viewModel.plugins.first(where: { $0.id == id }) else
        {
            return String(localized: "Enable Script", bundle: RockxyLocalization.bundle)
        }
        return script.isEnabled
            ? String(localized: "Disable Script", bundle: RockxyLocalization.bundle)
            : String(localized: "Enable Script", bundle: RockxyLocalization.bundle)
    }

    private var footerHint: String {
        let total = viewModel.plugins.count
        return isSearching
            ? String(AttributedString(
                localized: "\(visibleScriptCount) of ^[\(total) script](inflect: true)  •  ⌘N New  •  ⌘↩ Edit  •  ⇧⌘N Folder",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
            : String(AttributedString(
                localized: "^[\(total) script](inflect: true)  •  ⌘N New  •  ⌘↩ Edit  •  ⇧⌘N Folder",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
    }

    private var statusText: String {
        guard viewModel.toolEnabled else {
            return String(localized: "SCRIPTING OFF", bundle: RockxyLocalization.bundle)
        }
        if activeScriptCount == 0 {
            return String(localized: "NO ACTIVE SCRIPTS", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "\(activeScriptCount) ACTIVE", bundle: RockxyLocalization.bundle)
    }

    private var statusCapsuleTint: Color {
        if !viewModel.toolEnabled {
            return .secondary
        }
        return activeScriptCount == 0 ? .orange : .green
    }

    private var layout: some View {
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
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { _ in
            Task { await viewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scriptsDidChange)) { _ in
            Task { await viewModel.refresh() }
        }
        .onChange(of: viewModel.filterText) { _, _ in
            viewModel.reconcileSelectionWithVisibleRows()
        }
        .onChange(of: viewModel.filterColumn) { _, _ in
            viewModel.reconcileSelectionWithVisibleRows()
        }
        .onDeleteCommand {
            requestDeletionOfSelection()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { viewModel.toolEnabled },
                    set: { viewModel.setToolEnabled($0) }
                )) {
                    Text(String(localized: "Enable Scripting", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font(weight: .medium))
                }
                .toggleStyle(.checkbox)
                .controlSize(toggleControlSize)

                Text(String(
                    localized: "Rewrite requests and responses with JavaScript before they continue.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Picker(
                    String(localized: "Search field", bundle: RockxyLocalization.bundle),
                    selection: $viewModel.filterColumn
                ) {
                    ForEach(ScriptListFilterColumn.allCases) { column in
                        Text(column.title).tag(column)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .font(toolMetrics.font())
                .frame(minHeight: toolMetrics.formControlHeight)

                TextField(
                    String(localized: "Search scripts", bundle: RockxyLocalization.bundle),
                    text: $viewModel.filterText
                )
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .frame(width: 220, height: toolMetrics.formControlHeight)
                .focused($searchIsFocused)
                .accessibilityLabel(String(localized: "Search scripts", bundle: RockxyLocalization.bundle))
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerTopPadding)
        .rockxyFunctionalBar()
    }

    // MARK: - Info banner

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: infoBannerIsWarning ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(infoBannerIsWarning ? Color.orange : Color.secondary)
                .padding(.top, 1)
            Text(infoBannerMessage)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(infoBannerIsWarning ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(
            infoBannerIsWarning
                ? Color.orange.opacity(0.12)
                : Color(nsColor: .controlBackgroundColor).opacity(0.5)
        )
    }

    // MARK: - Table

    private var tableContent: some View {
        Table(viewModel.filteredDisplayRows, selection: selectedRow) {
            TableColumn(
                Text(String(localized: "Enabled", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { row in
                enabledCell(for: row)
            }
            .width(max(72, toolMetrics.tableHeaderFontSize * 4.5))
            .alignment(.center)

            TableColumn(
                Text(String(localized: "Name", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { row in
                nameCell(for: row)
            }
            .width(
                min: max(220, toolMetrics.bodyFontSize * 10),
                ideal: max(300, toolMetrics.bodyFontSize * 13)
            )

            TableColumn(
                Text(String(localized: "Method", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { row in
                if case let .script(script) = row.kind {
                    Text(script.method ?? "ANY")
                        .font(toolMetrics.font())
                        .lineLimit(1)
                        .foregroundStyle(script.isEnabled ? Color.primary : Color.secondary)
                }
            }
            .width(max(84, toolMetrics.tableHeaderFontSize * 4.8))

            TableColumn(
                Text(String(localized: "Matching Rule", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { row in
                if case let .script(script) = row.kind {
                    matchingRuleCell(for: script)
                }
            }
            .width(
                min: max(260, toolMetrics.bodyFontSize * 12),
                ideal: max(420, toolMetrics.bodyFontSize * 17)
            )

            TableColumn(
                Text(String(localized: "Status", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.tableHeaderFont())
            ) { row in
                if case let .script(script) = row.kind {
                    statusCell(for: script)
                }
            }
            .width(
                min: max(104, toolMetrics.tableHeaderFontSize * 5.2),
                ideal: max(128, toolMetrics.bodyFontSize * 6)
            )
        }
        .contextMenu(forSelectionType: ScriptListRowID.self) { rows in
            if let row = rows.first {
                rowContextMenu(for: row)
            }
        } primaryAction: { rows in
            if let row = rows.first {
                primaryAction(for: row)
            }
        }
        .overlay {
            if viewModel.filteredDisplayRows.isEmpty {
                if isSearching {
                    ContentUnavailableView(
                        String(localized: "No Matching Scripts", bundle: RockxyLocalization.bundle),
                        systemImage: "magnifyingglass",
                        description: Text(String(
                            localized: "Try a different name, method, or matching rule.",
                            bundle: RockxyLocalization.bundle
                        ))
                    )
                } else {
                    ContentUnavailableView {
                        Label(
                            String(localized: "No Scripts", bundle: RockxyLocalization.bundle),
                            systemImage: "curlybraces"
                        )
                    } description: {
                        Text(String(
                            localized: "Start from a template, or click + or press ⌘N for a blank script.",
                            bundle: RockxyLocalization.bundle
                        ))
                    } actions: {
                        templateGrid
                    }
                }
            }
        }
        .font(toolMetrics.font())
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .frame(minHeight: toolMetrics.tableRowHeight * 8, maxHeight: .infinity)
        .onKeyPress(.return, phases: .down, action: handleReturnKeyPress)
        .onKeyPress(.space, phases: .down, action: handleSpaceKeyPress)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl

            Text(footerHint)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            moreMenu
            statusCapsule
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                createNewScript()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.smallIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .disabled(viewModel.isCreatingOrDuplicating)
            .accessibilityLabel(String(localized: "New Script", bundle: RockxyLocalization.bundle))

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 18)

            Button {
                requestDeletionOfSelection()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.smallIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRowID == nil)
            .accessibilityLabel(String(localized: "Delete Selected", bundle: RockxyLocalization.bundle))
        }
        .foregroundStyle(.primary)
        .frame(width: max(43, toolMetrics.compactButtonSize * 2 + 1), height: toolMetrics.footerControlHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New Script", bundle: RockxyLocalization.bundle)) {
                createNewScript()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(viewModel.isCreatingOrDuplicating)

            Menu(String(localized: "New Script from Template", bundle: RockxyLocalization.bundle)) {
                ForEach(ScriptStarterTemplate.allCases) { template in
                    Button(template.title) {
                        createNewScript(from: template)
                    }
                }
            }
            .disabled(viewModel.isCreatingOrDuplicating)

            Button(String(localized: "New Folder", bundle: RockxyLocalization.bundle)) {
                viewModel.createNewFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Edit Script", bundle: RockxyLocalization.bundle)) {
                openEditorForSelection()
            }
            .disabled(!isScriptSelected)

            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                Task { await viewModel.duplicateSelection() }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!isScriptSelected || viewModel.isCreatingOrDuplicating)

            Button(enableDisableLabel) {
                toggleSelectedScript()
            }
            .disabled(!isScriptSelected)

            Button(String(localized: "Rename Folder", bundle: RockxyLocalization.bundle)) {
                viewModel.beginRenameSelectedFolder()
            }
            .disabled(!isFolderSelected)

            Divider()

            Button(String(localized: "Focus Search", bundle: RockxyLocalization.bundle)) {
                searchIsFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)

            Toggle(isOn: Binding(
                get: { viewModel.advanceAllowChaining },
                set: { viewModel.setAdvanceAllowChaining($0) }
            )) {
                Text(String(localized: "Run Every Matching Script", bundle: RockxyLocalization.bundle))
            }
            Toggle(isOn: Binding(
                get: { viewModel.advanceAllowSystemEnvVars },
                set: { viewModel.setAdvanceAllowSystemEnvVars($0) }
            )) {
                Text(String(
                    localized: "Allow Scripts to Read System Environment Variables",
                    bundle: RockxyLocalization.bundle
                ))
            }

            Divider()

            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                requestDeletionOfSelection()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRowID == nil)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More", bundle: RockxyLocalization.bundle))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .rockxyGlassButtonStyle()
        .frame(minHeight: toolMetrics.footerControlHeight)
        .fixedSize()
    }

    private var statusCapsule: some View {
        Text(statusText)
            .font(toolMetrics.secondaryFont(weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: toolMetrics.footerControlHeight)
            .rockxyChipStyle(tint: statusCapsuleTint, isActive: viewModel.toolEnabled)
    }

    private func enabledCell(for row: ScriptListDisplayRow) -> some View {
        HStack {
            Spacer()
            switch row.kind {
            case let .folder(folder):
                Toggle("", isOn: allChildrenBinding(for: folder))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .controlSize(toggleControlSize)
                    .disabled(folder.scriptIDs.contains(where: viewModel.mutatingScriptIDs.contains))
                    .accessibilityLabel(String(
                        localized: "Toggle all scripts in \(folder.name)",
                        bundle: RockxyLocalization.bundle
                    ))
            case let .script(script):
                Toggle("", isOn: Binding(
                    get: { script.isEnabled },
                    set: { enabled in
                        Task { await viewModel.setScriptEnabled(id: script.id, enabled: enabled) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(toggleControlSize)
                .disabled(viewModel.mutatingScriptIDs.contains(script.id))
                .accessibilityLabel(
                    script.isEnabled
                        ? String(localized: "Disable \(script.name)", bundle: RockxyLocalization.bundle)
                        : String(localized: "Enable \(script.name)", bundle: RockxyLocalization.bundle)
                )
            }
            Spacer()
        }
    }

    private func nameCell(for row: ScriptListDisplayRow) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: CGFloat(row.indent) * disclosureSlotWidth)
            switch row.kind {
            case let .folder(folder):
                Button {
                    viewModel.toggleFolder(id: folder.id)
                } label: {
                    Image(systemName: folder.expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(
                            width: disclosureSlotWidth,
                            height: toolMetrics.tableRowHeight
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    folder.expanded
                        ? String(localized: "Collapse \(folder.name)", bundle: RockxyLocalization.bundle)
                        : String(localized: "Expand \(folder.name)", bundle: RockxyLocalization.bundle)
                )

                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)

                if viewModel.renamingFolderID == folder.id {
                    TextField(
                        "",
                        text: $viewModel.renamingFolderText,
                        onEditingChanged: { isEditing in
                            if !isEditing, viewModel.renamingFolderID == folder.id {
                                viewModel.commitFolderRename()
                            }
                        },
                        onCommit: { viewModel.commitFolderRename() }
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font())
                    .frame(width: toolMetrics.fieldWidth(200))
                    .frame(minHeight: toolMetrics.formControlHeight)
                } else {
                    Text(folder.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(folder.name)
                }

            case let .script(script):
                Spacer().frame(width: row.indent == 0 ? disclosureSlotWidth : 0)
                Image(systemName: "curlybraces")
                    .foregroundStyle(.secondary)
                Text(script.name.isEmpty ? String(localized: "Untitled", bundle: RockxyLocalization.bundle) : script
                    .name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(script.isEnabled ? Color.primary : Color.secondary)
                    .help(script.name)
            }
            Spacer()
        }
        .font(toolMetrics.font())
    }

    @ViewBuilder
    private func matchingRuleCell(for script: PluginInfoSnapshot) -> some View {
        if let pattern = script.urlPattern, !pattern.isEmpty {
            Text(pattern)
                .font(toolMetrics.font(monospaced: true))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(script.isEnabled ? Color.primary : Color.secondary)
                .help(pattern)
        } else {
            Text(String(localized: "<Missing URL>", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func statusCell(for script: PluginInfoSnapshot) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(for: script.runtimeStatus))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(script.runtimeStatus.title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(toolMetrics.font())
        .foregroundStyle(.secondary)
        .help(script.statusDetail ?? script.runtimeStatus.title)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func rowContextMenu(for row: ScriptListRowID) -> some View {
        switch row {
        case .script:
            Button(String(localized: "Edit Script", bundle: RockxyLocalization.bundle)) {
                viewModel.selectedRowID = row
                openEditorForSelection()
            }
            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                viewModel.selectedRowID = row
                Task { await viewModel.duplicateSelection() }
            }
            .disabled(viewModel.isCreatingOrDuplicating)
            Button(scriptEnableDisableLabel(for: row)) {
                if case let .script(id) = row {
                    Task { await viewModel.toggleScript(id: id) }
                }
            }
            Divider()
            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                requestDeletion(row)
            }
        case .folder:
            Button(String(localized: "Rename Folder", bundle: RockxyLocalization.bundle)) {
                viewModel.selectedRowID = row
                viewModel.beginRenameSelectedFolder()
            }
            Divider()
            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                requestDeletion(row)
            }
        }
    }

    private func statusColor(for status: ScriptListRuntimeStatus) -> Color {
        switch status {
        case .active:
            .green
        case .error:
            .red
        case .loading:
            .orange
        case .disabled:
            .secondary
        }
    }

    private func createNewScript(from template: ScriptStarterTemplate? = nil) {
        Task {
            if await viewModel.createNewScript(from: template) != nil {
                openWindow(id: "scriptEditor")
            }
        }
    }

    /// Starter templates offered in the empty state, the main way to begin scripting.
    private var templateGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: toolMetrics.controlSpacing)],
            spacing: toolMetrics.controlSpacing
        ) {
            ForEach(ScriptStarterTemplate.allCases) { template in
                Button {
                    createNewScript(from: template)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: template.systemImage)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(toolMetrics.font(weight: .medium))
                            Text(template.summary)
                                .font(toolMetrics.secondaryFont())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .rockxyGlassButtonStyle()
                .disabled(viewModel.isCreatingOrDuplicating)
                .accessibilityIdentifier("scripting.template.\(template.rawValue)")
            }
        }
        .frame(maxWidth: 520)
    }

    private func openEditorForSelection() {
        guard isScriptSelected else {
            return
        }
        viewModel.openEditorForSelection()
        openWindow(id: "scriptEditor")
    }

    private func toggleSelectedScript() {
        guard case let .script(id) = viewModel.selectedRowID,
              let script = viewModel.plugins.first(where: { $0.id == id }) else
        {
            return
        }
        Task { await viewModel.setScriptEnabled(id: id, enabled: !script.isEnabled) }
    }

    private func handleReturnKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard isScriptSelected else {
            return .ignored
        }
        if keyPress.modifiers.contains(.command) {
            openEditorForSelection()
            return .handled
        }
        guard keyPress.modifiers.isEmpty else {
            return .ignored
        }
        toggleSelectedScript()
        return .handled
    }

    private func handleSpaceKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard isScriptSelected, keyPress.modifiers.isEmpty else {
            return .ignored
        }
        toggleSelectedScript()
        return .handled
    }

    private func primaryAction(for row: ScriptListRowID) {
        switch row {
        case let .folder(id):
            viewModel.toggleFolder(id: id)
        case let .script(id):
            viewModel.openEditor(for: id)
            openWindow(id: "scriptEditor")
        }
    }

    private func scriptEnableDisableLabel(for row: ScriptListRowID) -> String {
        guard case let .script(id) = row,
              let script = viewModel.plugins.first(where: { $0.id == id }) else
        {
            return String(localized: "Enable Script", bundle: RockxyLocalization.bundle)
        }
        return script.isEnabled
            ? String(localized: "Disable Script", bundle: RockxyLocalization.bundle)
            : String(localized: "Enable Script", bundle: RockxyLocalization.bundle)
    }

    // MARK: - Deletion confirmation

    private func requestDeletionOfSelection() {
        guard let selection = viewModel.selectedRowID else {
            return
        }
        requestDeletion(selection)
    }

    private func requestDeletion(_ row: ScriptListRowID) {
        viewModel.selectedRowID = row
        pendingDeletion = row
    }

    private func confirmDeletion(_ row: ScriptListRowID) {
        viewModel.selectedRowID = row
        pendingDeletion = nil
        Task { await viewModel.deleteSelection() }
    }

    private func deletionTitle(for row: ScriptListRowID?) -> String {
        switch row {
        case .folder:
            String(localized: "Delete Folder?", bundle: RockxyLocalization.bundle)
        case .script,
             .none:
            String(localized: "Delete Script?", bundle: RockxyLocalization.bundle)
        }
    }

    private func deletionButtonTitle(for row: ScriptListRowID) -> String {
        switch row {
        case .folder:
            String(localized: "Delete Folder", bundle: RockxyLocalization.bundle)
        case .script:
            String(localized: "Delete Script", bundle: RockxyLocalization.bundle)
        }
    }

    private func deletionMessage(for row: ScriptListRowID) -> String {
        switch row {
        case let .folder(id):
            String(
                localized: "“\(folderName(for: id))” will be removed. Scripts inside it are kept and moved to the top level.",
                bundle: RockxyLocalization.bundle
            )
        case let .script(id):
            String(
                localized: "“\(scriptName(for: id))” will be removed from disk. This cannot be undone.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private func scriptName(for id: String) -> String {
        let name = viewModel.plugins.first(where: { $0.id == id })?.name ?? ""
        return name.isEmpty ? String(localized: "Untitled", bundle: RockxyLocalization.bundle) : name
    }

    private func folderName(for id: UUID) -> String {
        for row in viewModel.displayRows {
            if case let .folder(folder) = row.kind, folder.id == id {
                return folder.name.isEmpty ? String(localized: "Untitled", bundle: RockxyLocalization.bundle) : folder
                    .name
            }
        }
        return String(localized: "Untitled", bundle: RockxyLocalization.bundle)
    }

    private func allChildrenBinding(for folder: ScriptFolder) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                let ids = Set(folder.scriptIDs)
                let matching = viewModel.plugins.filter { ids.contains($0.id) }
                return !matching.isEmpty && matching.allSatisfy(\.isEnabled)
            },
            set: { newValue in
                Task { await viewModel.setScriptsEnabled(ids: folder.scriptIDs, enabled: newValue) }
            }
        )
    }
}
