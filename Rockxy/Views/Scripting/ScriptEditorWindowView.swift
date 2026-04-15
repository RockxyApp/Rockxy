import SwiftUI

/// The Script Editor window. Matching rule header + run-on row + code editor +
/// console + footer.
struct ScriptEditorWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            matchingRuleHeader
            Divider()
            runOnRow
            Divider()
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

            HStack(spacing: 8) {
                Text("Name:")
                TextField("", text: $viewModel.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("URL:")
                TextField("", text: $viewModel.urlPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 420)

                Picker("", selection: $viewModel.method) {
                    ForEach([
                        ScriptMatchMethod.any,
                    ]) { Text($0.label).tag($0) }
                    Divider()
                    ForEach([
                        ScriptMatchMethod.get,
                        ScriptMatchMethod.post,
                        ScriptMatchMethod.put,
                        ScriptMatchMethod.delete,
                        ScriptMatchMethod.patch,
                    ]) { Text($0.label).tag($0) }
                    Divider()
                    ForEach([
                        ScriptMatchMethod.head,
                        ScriptMatchMethod.options,
                        ScriptMatchMethod.trace,
                    ]) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 90)

                Picker("", selection: $viewModel.patternMode) {
                    Text("Use Wildcard").tag(ScriptMatchPatternMode.wildcard)
                    Text("Use Regex").tag(ScriptMatchPatternMode.regex)
                    Divider()
                    Text("Advanced").tag(ScriptMatchPatternMode.advanced)
                }
                .labelsHidden()
                .frame(width: 140)

                if viewModel.patternMode == .wildcard {
                    Text("Support wildcard * and ?.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField(String(localized: "Sample URL"), text: $viewModel.sampleURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 240)

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
            }

            if !viewModel.testRulePreview.isEmpty {
                Text(viewModel.testRulePreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $viewModel.includeSubpaths) {
                Text("Include all subpaths of this URL")
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
            Divider().frame(height: 14)
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
            ScriptCodeEditor(text: $viewModel.code)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if viewModel.consolePanelVisible {
                Divider()
                ScriptConsolePanel(viewModel: viewModel)
                    .frame(width: 320)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Menu("More") {
                moreMenuItems
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                viewModel.beautify()
            } label: {
                HStack(spacing: 4) {
                    Text("Beautify")
                    Text("⌘B").foregroundStyle(.secondary)
                }
            }
            .keyboardShortcut("b", modifiers: .command)

            Button {
                // Snippet Code — deferred to v2. Insert a small header-mutation example for now.
                viewModel.insertSnippet("// request.headers[\"X-Custom\"] = \"value\";")
            } label: {
                Text("Snippet Code")
            }

            Spacer()

            Button {
                Task { await viewModel.saveAndActivate() }
            } label: {
                HStack(spacing: 6) {
                    Text("Save & Activate")
                        .fontWeight(.semibold)
                    Text("⌘S")
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .buttonStyle(.borderedProminent)
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
                Image(systemName: "eye")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
}
