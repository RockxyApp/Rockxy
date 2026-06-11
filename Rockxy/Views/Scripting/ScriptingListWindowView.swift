import SwiftUI

/// The main Scripting List window. Mirrors the AllowList / BlockList / SSL Proxying
/// list-window idiom: title + master toggle, info banner, column header, List rows
/// (flat scripts + folders), slide-up filter bar, bottom bar with +/-/New Folder/?/Filter/Advance/More.
struct ScriptingListWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tableContent
            shortcutStrip
            bottomBar
        }
        .font(toolMetrics.font())
        .frame(width: 1_200, height: 672)
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { _ in
            Task { await viewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scriptsDidChange)) { _ in
            Task { await viewModel.refresh() }
        }
    }

    // MARK: Private

    @State private var viewModel = ScriptingListViewModel()
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow

    // MARK: - Helpers

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

    private var selectedRows: Binding<Set<ScriptListRowID>> {
        Binding(
            get: {
                if let selected = viewModel.selectedRowID {
                    return [selected]
                }
                return []
            },
            set: { newValue in
                viewModel.selectedRowID = newValue.first
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { viewModel.toolEnabled },
                set: { viewModel.setToolEnabled($0) }
            )) {
                Text("Enable Scripting Tool")
                    .font(toolMetrics.font())
            }
            .toggleStyle(.checkbox)
            .padding(.top, 16)

            Text(
                "Modify the Request or Response automatically with JavaScript. Support URL, Status Code, Header, Method, and Body."
            )
            .font(toolMetrics.font())
            Text("Each request is checked against the rules from top to bottom, stopping when a match is found.")
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)

            if viewModel.isFilterVisible {
                filterBar
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    // MARK: - Table

    private var tableContent: some View {
        Table(viewModel.filteredDisplayRows, selection: selectedRows) {
            TableColumn(String(localized: "Name")) { row in
                nameCell(for: row)
            }
            .width(min: 300, ideal: 340)

            TableColumn(String(localized: "Method")) { row in
                switch row.kind {
                case .folder:
                    Text("")
                case let .script(script):
                    Text(script.method ?? "ANY")
                        .lineLimit(1)
                }
            }
            .width(96)

            TableColumn(String(localized: "Matching Rule")) { row in
                switch row.kind {
                case .folder:
                    Text("")
                case let .script(script):
                    Text(script.urlPattern?.isEmpty == false ? script.urlPattern ?? "" : "<Missing URL>")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(script.urlPattern ?? "<Missing URL>")
                }
            }
            .width(min: 420, ideal: 660)
        }
        .contextMenu(forSelectionType: ScriptListRowID.self) { rows in
            tableContextMenu(rows: rows)
        } primaryAction: { rows in
            guard let row = rows.first else {
                return
            }
            primaryAction(for: row)
        }
        .overlay {
            if viewModel.filteredDisplayRows.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Scripts"),
                    systemImage: "curlybraces",
                    description: Text(String(localized: "Click + to create a new script."))
                )
            }
        }
        .padding(.horizontal, 18)
        .onDeleteCommand {
            Task { await viewModel.deleteSelection() }
        }
    }

    private func nameCell(for row: ScriptListDisplayRow) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: CGFloat(row.indent) * 16)
            switch row.kind {
            case let .folder(folder):
                Button {
                    viewModel.toggleFolder(id: folder.id)
                } label: {
                    Image(systemName: folder.expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: allChildrenBinding(for: folder))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)

                if viewModel.renamingFolderID == folder.id {
                    TextField(
                        "",
                        text: $viewModel.renamingFolderText,
                        onEditingChanged: { isEditing in
                            if !isEditing, viewModel.renamingFolderID == folder.id {
                                viewModel.cancelFolderRename()
                            }
                        },
                        onCommit: {
                            viewModel.commitFolderRename()
                        }
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                } else {
                    Text(folder.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

            case let .script(script):
                Spacer().frame(width: row.indent == 0 ? 14 : 0)
                Toggle("", isOn: Binding(
                    get: { script.isEnabled },
                    set: { _ in Task { await viewModel.toggleScript(id: script.id) } }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
                Text(script.name.isEmpty ? String(localized: "Untitled") : script.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(script.isEnabled ? Color.primary : Color.secondary)
            }
            Spacer()
        }
        .opacity(row.isEnabled ? 1.0 : 0.6)
    }

    private var shortcutStrip: some View {
        Text("New: ⌘N    Edit: ⌘↩    Delete: ⌘⌫    Duplicate: ⌘D    Toggle: ↵")
            .font(.system(size: toolMetrics.shortcutFontSize))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            addRemoveButtons
            Button {
                viewModel.createNewFolder()
            } label: {
                Text("New Folder")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button {
                // help button — opens docs in a future milestone; for now, no-op.
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                withAnimation { viewModel.isFilterVisible.toggle() }
            } label: {
                Label(String(localized: "Filter"), systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("f", modifiers: .command)

            Menu {
                Toggle(isOn: Binding(
                    get: { viewModel.advanceAllowSystemEnvVars },
                    set: { viewModel.setAdvanceAllowSystemEnvVars($0) }
                )) { Text("Allow Scripts to read System Environment Variables") }
                Toggle(isOn: Binding(
                    get: { viewModel.advanceAllowChaining },
                    set: { viewModel.setAdvanceAllowChaining($0) }
                )) { Text("Allow Running Multiple Scripts for one Request") }
            } label: {
                menuLabel(String(localized: "Advance"))
            }
            .menuIndicator(.hidden)
            .buttonStyle(.bordered)
            .fixedSize()

            Menu {
                moreMenuItems
            } label: {
                menuLabel(String(localized: "More"))
            }
            .menuIndicator(.hidden)
            .buttonStyle(.bordered)
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var addRemoveButtons: some View {
        HStack(spacing: 0) {
            Button {
                Task {
                    if await viewModel.createNewScript() != nil {
                        await MainActor.run {
                            openWindow(id: "scriptEditor")
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .regular))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 18)

            Button {
                Task { await viewModel.deleteSelection() }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .regular))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRowID == nil)
        }
        .foregroundStyle(.primary)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .frame(width: max(43, toolMetrics.compactButtonSize * 2 + 1), height: toolMetrics.footerControlHeight)
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder private var moreMenuItems: some View {
        Button("New…") {
            Task {
                if await viewModel.createNewScript() != nil {
                    await MainActor.run {
                        openWindow(id: "scriptEditor")
                    }
                }
            }
        }
        .keyboardShortcut("n", modifiers: .command)
        Button("New Folder") { viewModel.createNewFolder() }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        Divider()
        Button("Edit") {
            viewModel.openEditorForSelection()
            openWindow(id: "scriptEditor")
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(!isScriptSelected)
        Button("Duplicate") { Task { await viewModel.duplicateSelection() } }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!isScriptSelected)
        Button("Enable Rule") {
            if case let .script(id) = viewModel.selectedRowID {
                Task { await viewModel.toggleScript(id: id) }
            }
        }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!isScriptSelected)
        Button("Enable Rule") {
            if case let .script(id) = viewModel.selectedRowID {
                Task { await viewModel.toggleScript(id: id) }
            }
        }
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!isScriptSelected)
        Button("Rename Folder") { viewModel.beginRenameSelectedFolder() }
            .disabled(!isFolderSelected)
        Divider()
        Menu("Export Settings") {
            Button("JSON…") {} // deferred
        }
        Menu("Import Settings") {
            Button("JSON…") {} // deferred
        }
        Divider()
        Button("Show in Finder…") {} // deferred
            .disabled(!isScriptSelected)
        Menu("Open local file with") {
            Button("System Default") {} // deferred
        }
        .disabled(!isScriptSelected)
        Divider()
        Button("Delete") { Task { await viewModel.deleteSelection() } }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedRowID == nil)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Picker("", selection: $viewModel.filterColumn) {
                ForEach(ScriptListFilterColumn.allCases) { column in
                    Text(column.title).tag(column)
                }
            }
            .labelsHidden()
            .fixedSize()
            TextField("Filter…", text: $viewModel.filterText)
                .textFieldStyle(.roundedBorder)
            Button {
                viewModel.isFilterVisible = false
                viewModel.filterText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func allChildrenBinding(for folder: ScriptFolder) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                let ids = Set(folder.scriptIDs)
                let matching = viewModel.plugins.filter { ids.contains($0.id) }
                return !matching.isEmpty && matching.allSatisfy(\.isEnabled)
            },
            set: { newValue in
                Task {
                    await viewModel.setScriptsEnabled(ids: folder.scriptIDs, enabled: newValue)
                }
            }
        )
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

    @ViewBuilder
    private func tableContextMenu(rows: Set<ScriptListRowID>) -> some View {
        if let row = rows.first {
            moreMenuItems(for: row)
        }
    }

    @ViewBuilder
    private func moreMenuItems(for row: ScriptListRowID) -> some View {
        let previousSelection = viewModel.selectedRowID
        Button("Edit") {
            viewModel.selectedRowID = row
            viewModel.openEditorForSelection()
            openWindow(id: "scriptEditor")
            if case .folder = row {
                viewModel.selectedRowID = previousSelection
            }
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled({
            if case .script = row {
                return false
            }
            return true
        }())
        Button("Duplicate") {
            viewModel.selectedRowID = row
            Task { await viewModel.duplicateSelection() }
        }
        .keyboardShortcut("d", modifiers: .command)
        .disabled({
            if case .script = row {
                return false
            }
            return true
        }())
        Button("Toggle") {
            if case let .script(id) = row {
                Task { await viewModel.toggleScript(id: id) }
            }
        }
        .keyboardShortcut(.return, modifiers: [])
        .disabled({
            if case .script = row {
                return false
            }
            return true
        }())
        Button("Rename Folder") {
            viewModel.selectedRowID = row
            viewModel.beginRenameSelectedFolder()
        }
        .disabled({
            if case .folder = row {
                return false
            }
            return true
        }())
        Divider()
        Button("Delete", role: .destructive) {
            viewModel.selectedRowID = row
            Task { await viewModel.deleteSelection() }
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
        }
    }
}

private extension ScriptListDisplayRow {
    var isEnabled: Bool {
        switch kind {
        case .folder:
            true
        case let .script(script):
            script.isEnabled
        }
    }
}
