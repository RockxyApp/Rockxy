import SwiftUI

/// The Script Editor window. Matching rule header + run-on row + code editor +
/// console + footer.
struct ScriptEditorWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            bodySplit
            Divider()
            footer
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            if let intent = ScriptEditorSession.shared.consumePending() {
                Task { await viewModel.load(intent: intent) }
            }
        }
        .onChange(of: ScriptEditorSession.shared.contextVersion) { _, _ in
            if let intent = ScriptEditorSession.shared.consumePending() {
                Task { await viewModel.load(intent: intent) }
            }
        }
    }

    // MARK: Private

    @State private var viewModel = ScriptEditorViewModel()

    // MARK: - Matching Rule header

    private var matchingRuleHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Matching Rule")
                .font(.headline)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text("Name:")
                        .frame(width: 58, alignment: .trailing)
                    TextField("", text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    Text("URL:")
                        .frame(width: 58, alignment: .trailing)
                    TextField("", text: $viewModel.urlPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 66)

                    methodMenu
                    patternModeMenu

                    if viewModel.patternMode == .wildcard {
                        Text("Support wildcard * and ?.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        let sample = viewModel.sampleURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        let effectiveSample = sample.isEmpty ? "https://api.example.com/path" : sample
                        viewModel.testRulePreview = viewModel.testRule(against: effectiveSample)
                            ? "Matches: \(effectiveSample)"
                            : "No match for: \(effectiveSample)"
                    } label: {
                        Text("Test your Rule")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    Spacer(minLength: 0)
                }

                Toggle(isOn: $viewModel.includeSubpaths) {
                    Text("Include all subpaths of this URL")
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 66)

                if !viewModel.testRulePreview.isEmpty {
                    Text(viewModel.testRulePreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 66)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var methodMenu: some View {
        Menu {
            ForEach(Array(ScriptEditorMenuContent.methodSections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { method in
                    Button {
                        viewModel.method = method
                    } label: {
                        menuCheckmarkLabel(method.label, isSelected: viewModel.method == method)
                    }
                }
                if index < ScriptEditorMenuContent.methodSections.count - 1 {
                    Divider()
                }
            }
        } label: {
            menuLabel(viewModel.method.label, minWidth: 88)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    private var patternModeMenu: some View {
        Menu {
            ForEach(Array(ScriptEditorMenuContent.patternModeSections.enumerated()), id: \.offset) { index, section in
                ForEach(section) { mode in
                    Button {
                        viewModel.patternMode = mode
                    } label: {
                        menuCheckmarkLabel(mode.title, isSelected: viewModel.patternMode == mode)
                    }
                }
                if index < ScriptEditorMenuContent.patternModeSections.count - 1 {
                    Divider()
                }
            }
        } label: {
            menuLabel(viewModel.patternMode.title, minWidth: 128)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    // MARK: - Run On row

    private var runOnRow: some View {
        HStack(spacing: 16) {
            Text("Run Script on:")
                .fontWeight(.medium)
            Toggle(isOn: $viewModel.runOnRequest) { Text("Request") }
                .toggleStyle(.checkbox)
            Toggle(isOn: $viewModel.runOnResponse) { Text("Response") }
                .toggleStyle(.checkbox)
            Toggle(isOn: $viewModel.runAsMock) { Text("Run as Mock API") }
                .toggleStyle(.checkbox)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.savedAndActive ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(viewModel.statusMessage.isEmpty ? " " : viewModel.statusMessage)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Body split

    private var bodySplit: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                matchingRuleHeader
                runOnRow
                Divider()
                ScriptCodeEditor(text: $viewModel.code)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if viewModel.consolePanelVisible {
                Divider()
                ScriptConsolePanel(viewModel: viewModel)
                    .frame(width: 230)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                moreMenuItems
            }
            label: {
                menuLabel(String(localized: "More"))
            }
            .menuIndicator(.hidden)
            .buttonStyle(.bordered)
            .fixedSize()

            Button {
                viewModel.beautify()
            } label: {
                Text("Beautify (⌘B)")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("b", modifiers: .command)

            Button {
                // Snippet Code — deferred to v2. Insert a small header-mutation example for now.
                viewModel.insertSnippet("// request.headers[\"X-Custom\"] = \"value\";")
            } label: {
                Text("Snippet Code")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                Task { await viewModel.saveAndActivate() }
            } label: {
                Text("Save & Activate ⌘S")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("s", modifiers: .command)

            Menu {
                ForEach(ScriptConsoleLogLevel.allCases) { level in
                    Toggle(isOn: Binding(
                        get: { viewModel.consoleFilter.contains(level) },
                        set: { newValue in
                            if newValue {
                                viewModel.consoleFilter.insert(level)
                            } else {
                                viewModel.consoleFilter.remove(level)
                            }
                        }
                    )) { Text(level.title) }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "eye")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()

            Button {
                viewModel.clearConsole()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(viewModel.consoleEntries.isEmpty)

            Button {
                viewModel.toggleConsolePanel()
            } label: {
                Image(systemName: "sidebar.right")
                    .frame(width: 24, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder private var moreMenuItems: some View {
        Menu("Open with…") {
            Button("System Default") {} // deferred
        }
        Divider()
        Button("Toggle Console Log Panel") { viewModel.toggleConsolePanel() }
        Divider()
        Button("Import JSON or Other File…") {} // deferred
        Divider()
        Button("Reset Shared State") { viewModel.resetSharedState() }
        Menu("Environment Variables") {
            Text("(from plugin configuration)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Divider()
        Menu("Configs") {
            Text("(from plugin manifest)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Divider()
        Menu("Documentations") {
            Button("Scripting Guide") {} // deferred
            Button("Matching Rules") {}
            Button("Mock Responses") {}
        }
    }

    private func menuCheckmarkLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    private func menuLabel(_ title: String, minWidth: CGFloat? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .frame(minWidth: minWidth, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
    }
}
