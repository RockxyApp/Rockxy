import SwiftUI

// Keyboard-first command search for the main workspace.

// MARK: - CommandPaletteView

/// Type to filter workspace commands, move with ↑/↓, run with Return, dismiss
/// with Esc. Commands are the same actions the menus expose; the palette only
/// makes them searchable.
struct CommandPaletteView: View {
    // MARK: Internal

    let commands: [CommandPaletteCommand]
    let onRun: (CommandPaletteCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    String(localized: "Search commands", bundle: RockxyLocalization.bundle),
                    text: $query
                )
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .onSubmit(runSelection)
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .accessibilityLabel(String(localized: "Search commands", bundle: RockxyLocalization.bundle))
            }
            .padding(12)

            Divider()

            if results.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Matching Commands", bundle: RockxyLocalization.bundle),
                    systemImage: "command"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(results, selection: $selection) { command in
                        row(command)
                            .tag(command.id)
                            .id(command.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                onRun(command)
                            }
                    }
                    .listStyle(.plain)
                    .onChange(of: selection) { _, newValue in
                        if let newValue {
                            proxy.scrollTo(newValue)
                        }
                    }
                }
            }
        }
        .frame(width: 560, height: 380)
        .onAppear {
            isSearchFocused = true
            selection = results.first?.id
        }
        .onChange(of: query) {
            selection = results.first?.id
        }
        .onExitCommand {
            dismiss()
        }
    }

    // MARK: Private

    @State private var query = ""
    @State private var selection: CommandPaletteCommand.ID?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var results: [CommandPaletteCommand] {
        CommandPaletteMatcher.rank(commands, query: query)
    }

    private func row(_ command: CommandPaletteCommand) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                Text(command.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let shortcut = command.shortcut {
                Text(verbatim: shortcut)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func moveSelection(by offset: Int) {
        let ids = results.map(\.id)
        guard !ids.isEmpty else {
            return
        }
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? (offset > 0 ? -1 : ids.count)
        selection = ids[min(max(current + offset, 0), ids.count - 1)]
    }

    private func runSelection() {
        guard let command = results.first(where: { $0.id == selection }) ?? results.first else {
            return
        }
        onRun(command)
    }
}

// MARK: - CommandPaletteSheet

/// Presents the Command Palette over the main window and runs the chosen command
/// once the sheet has closed.
struct CommandPaletteSheet: ViewModifier {
    // MARK: Internal

    let lifecycleState: AppLifecycleState
    let coordinator: MainContentCoordinator

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { lifecycleState.showCommandPalette },
            set: { lifecycleState.showCommandPalette = $0 }
        )) {
            CommandPaletteView(commands: CommandPaletteCatalog.commands) { command in
                lifecycleState.showCommandPalette = false
                // Run after the sheet closes so panels and windows the command
                // opens are not presented over a dismissing sheet.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    perform(command.action)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow

    private func perform(_ action: CommandPaletteAction) {
        let actions = MainContentCommandActions(coordinator: coordinator)
        switch action {
        case let .openWindow(id):
            openWindow(id: id)
        case .startProxy:
            actions.startProxy()
        case .stopProxy:
            actions.stopProxy()
        case .toggleRecording:
            actions.toggleRecording()
        case .toggleSystemProxy:
            actions.toggleSystemProxyOverride()
        case .clearSession:
            actions.clearSession()
        case .clearSessionAndFilters:
            actions.clearCaptureAndFilters()
        case .compose:
            actions.composeFreshRequest()
        case .openSession:
            actions.openSession()
        case .saveSession:
            actions.saveSession()
        case .importHAR:
            actions.importHAR()
        case .exportHAR:
            actions.exportHAR()
        case .exportCSV:
            actions.exportCSV()
        case .exportOpenAPIYAML:
            actions.exportOpenAPIYAML()
        case .exportOpenAPIHTML:
            actions.exportOpenAPIHTML()
        case .toggleAdvancedFilters:
            actions.toggleFilterBar()
        case .findInCapture:
            actions.focusSearchField()
        case .searchAppsAndDomains:
            actions.focusSidebarSearchField()
        case .toggleTrafficInsights:
            actions.toggleTrafficInsights()
        case .newTab:
            actions.newWorkspaceTab()
        case .showKeyboardShortcuts:
            lifecycleState.showKeyboardShortcuts = true
        }
    }
}
