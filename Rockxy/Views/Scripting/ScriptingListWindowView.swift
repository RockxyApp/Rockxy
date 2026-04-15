import SwiftUI

/// The main Scripting List window. Mirrors the AllowList / BlockList / SSL Proxying
/// list-window idiom: title + master toggle, info banner, column header, List rows
/// (flat scripts + folders), slide-up filter bar, bottom bar with +/-/New Folder/?/Filter/Advance/More.
struct ScriptingListWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            infoBanner
            Divider()
            columnHeader
            Divider()
            listContent
            if viewModel.isFilterVisible {
                Divider()
                filterBar
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 860, minHeight: 600)
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .rulesDidChange)) { _ in
            Task { await viewModel.refresh() }
        }
    }

    // MARK: Private

    @State private var viewModel = ScriptingListViewModel()
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

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { viewModel.toolEnabled },
                set: { viewModel.setToolEnabled($0) }
            )) {
                Text("Enable Scripting Tool")
                    .font(.headline)
            }
            .toggleStyle(.checkbox)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Info banner

    private var infoBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "Modify the Request or Response automatically with JavaScript. Support URL, Status Code, Header, Method, and Body."
            )
            .font(.system(size: 12))
            Text("Each request is checked against the rules from top to bottom, stopping when a match is found.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4))
    }

    // MARK: - Column header

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(width: 380 + 34, alignment: .leading)
            Text("Method")
                .frame(width: 110, alignment: .leading)
            Text("Matching Rule")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.background.tertiary)
    }

    // MARK: - List

    @ViewBuilder private var listContent: some View {
        if viewModel.filteredDisplayRows.isEmpty {
            emptyState
        } else {
            List(selection: $viewModel.selectedRowID) {
                ForEach(viewModel.filteredDisplayRows) { row in
                    ScriptListRow(viewModel: viewModel, row: row)
                        .tag(row.id)
                        .contextMenu { rowContextMenu }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onDeleteCommand { Task { await viewModel.deleteSelection() } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "curlybraces")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No scripts yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click + to create a new script.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .keyboardShortcut("n", modifiers: [.command, .option])

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
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    Text("Filter")
                }
            }
            .keyboardShortcut("f", modifiers: .command)

            Menu("Advance") {
                Toggle(isOn: Binding(
                    get: { viewModel.advanceAllowSystemEnvVars },
                    set: { viewModel.setAdvanceAllowSystemEnvVars($0) }
                )) { Text("Allow Scripts to read System Environment Variables") }
                Toggle(isOn: Binding(
                    get: { viewModel.advanceAllowChaining },
                    set: { viewModel.setAdvanceAllowChaining($0) }
                )) { Text("Allow Running Multiple Scripts for one Request") }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu("More") {
                moreMenuItems
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
                    .frame(width: 22, height: 22)
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider().frame(height: 14)

            Button {
                Task { await viewModel.deleteSelection() }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 22)
            }
            .disabled(viewModel.selectedRowID == nil)
        }
        .buttonStyle(.bordered)
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
            .keyboardShortcut("n", modifiers: [.command, .option])
        Divider()
        Button("Edit") {
            viewModel.openEditorForSelection()
            openWindow(id: "scriptEditor")
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!isScriptSelected)
        Button("Duplicate") { Task { await viewModel.duplicateSelection() } }
            .keyboardShortcut("d", modifiers: .command)
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

    private var rowContextMenu: some View {
        moreMenuItems
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.3))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
