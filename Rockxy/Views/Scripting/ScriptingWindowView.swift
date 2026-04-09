import os
import SwiftUI

// Presents the scripting window for plugin scripting.

// MARK: - ScriptingWindowView

struct ScriptingWindowView: View {
    // MARK: Internal

    var body: some View {
        HSplitView {
            scriptSidebar
            VStack(spacing: 0) {
                scriptEditor
                Divider()
                consolePanel
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .frame(idealWidth: 960, idealHeight: 620)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Text("JavaScript")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.25))
                    .foregroundStyle(Color.yellow)
                    .clipShape(Capsule())

                if viewModel.runStatus != .idle || viewModel.runStatusMessage != nil {
                    runStatusBadge
                }

                Button {
                    Task { await viewModel.createNewScript() }
                } label: {
                    Label(String(localized: "New Script"), systemImage: "plus.square")
                }

                Button {
                    viewModel.saveScript()
                } label: {
                    Label(String(localized: "Save"), systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.selectedPluginID == nil)
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    Task { await viewModel.runTest() }
                } label: {
                    Label(String(localized: "Run Test"), systemImage: "play.fill")
                }
                .disabled(viewModel.selectedPluginID == nil)

                Button {
                    viewModel.clearConsole()
                } label: {
                    Label(String(localized: "Clear Console"), systemImage: "trash")
                }

                Menu {
                    ForEach(Array(ScriptingViewModel.scriptTemplates.keys.sorted()), id: \.self) { name in
                        Button(name) {
                            if viewModel.selectedPluginID == nil {
                                Task { await viewModel.createNewScript(templateName: name) }
                            } else {
                                viewModel.applyTemplate(name)
                            }
                        }
                    }
                } label: {
                    Label(String(localized: "Templates"), systemImage: "doc.on.doc")
                }
            }
        }
        .task {
            await viewModel.loadPlugins()
        }
    }

    // MARK: Private

    @State private var viewModel = ScriptingViewModel()

    private var runStatusLabel: String {
        switch viewModel.runStatus {
        case .idle:
            String(localized: "Idle")
        case .running:
            String(localized: "Running")
        case .success:
            String(localized: "Ready")
        case .failure:
            String(localized: "Attention Needed")
        }
    }

    private var runStatusColor: Color {
        switch viewModel.runStatus {
        case .idle:
            .secondary
        case .running:
            .orange
        case .success:
            .green
        case .failure:
            .red
        }
    }

    // MARK: - Sidebar

    private var scriptSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $viewModel.selectedPluginID) {
                ForEach(viewModel.plugins) { plugin in
                    ScriptListRow(plugin: plugin) { enabled in
                        Task { await viewModel.togglePlugin(id: plugin.id, enabled: enabled) }
                    }
                    .tag(plugin.id)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.selectedPluginID) { _, newValue in
                if let id = newValue {
                    viewModel.selectPlugin(id: id)
                }
            }

            Divider()

            HStack {
                Button {
                    Task { await viewModel.createNewScript() }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button {
                    if let id = viewModel.selectedPluginID {
                        Task { await viewModel.deletePlugin(id: id) }
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.selectedPluginID == nil)

                Spacer()
            }
            .padding(8)
        }
        .frame(width: 220)
    }

    // MARK: - Editor

    private var scriptEditor: some View {
        Group {
            if viewModel.selectedPluginID != nil {
                ScriptEditorView(text: $viewModel.scriptContent)
            } else if viewModel.plugins.isEmpty {
                scriptEmptyState
            } else {
                ContentUnavailableView {
                    Label(String(localized: "No Script Selected"), systemImage: "doc.text")
                } description: {
                    Text("Select a script from the sidebar or create a new one.")
                } actions: {
                    Button(String(localized: "New Script")) {
                        Task { await viewModel.createNewScript() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var scriptEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("JavaScript Scripting")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Intercept and modify HTTP traffic with JavaScript. Scripts run in a sandboxed runtime and can:")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Modify request headers, URLs, and bodies", systemImage: "arrow.up.right")
                    Label("Inspect and transform responses", systemImage: "arrow.down.left")
                    Label("Block requests matching patterns", systemImage: "xmark.octagon")
                    Label("Return custom mock responses", systemImage: "doc.text")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360)

            Button {
                Task { await viewModel.createNewScript() }
            } label: {
                Label(String(localized: "Create Your First Script"), systemImage: "plus.square")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Menu {
                ForEach(Array(ScriptingViewModel.scriptTemplates.keys.sorted()), id: \.self) { name in
                    Button(name) {
                        Task { await viewModel.createNewScript(templateName: name) }
                    }
                }
            } label: {
                Label(String(localized: "Start from Template"), systemImage: "doc.on.doc")
            }

            Text("Templates are the fastest way to start a local request modifier, blocker, or mock response.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Console

    private var consolePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Console")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.consoleOutput.count) entries")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.consoleOutput) { entry in
                            ConsoleEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: viewModel.consoleOutput.count) { _, _ in
                    if let last = viewModel.consoleOutput.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(height: 140)
        .background(.background.opacity(0.5))
    }

    private var runStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(runStatusColor)
                .frame(width: 8, height: 8)
            Text(viewModel.runStatusMessage ?? runStatusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5))
        .clipShape(Capsule())
    }
}

// MARK: - ScriptListRow

private struct ScriptListRow: View {
    // MARK: Lifecycle

    init(plugin: PluginInfo, onToggle: @escaping (Bool) -> Void) {
        self.plugin = plugin
        self.onToggle = onToggle
        self._isEnabled = State(initialValue: plugin.isEnabled)
    }

    // MARK: Internal

    let plugin: PluginInfo
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isEnabled) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .onChange(of: isEnabled) { _, newValue in
                onToggle(newValue)
            }

            statusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.manifest.name)
                    .font(.body)
                    .lineLimit(1)
                statusSubtitle
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    @State private var isEnabled: Bool

    private var statusColor: Color {
        switch plugin.status {
        case .active: .green
        case .disabled: .gray
        case .error: .red
        case .loading: .orange
        }
    }

    private var statusTooltip: String {
        switch plugin.status {
        case .active: "Active"
        case .disabled: "Disabled"
        case let .error(message): "Error: \(message)"
        case .loading: "Loading\u{2026}"
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .help(statusTooltip)
    }

    @ViewBuilder private var statusSubtitle: some View {
        switch plugin.status {
        case let .error(message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
                .help(message)
        case .loading:
            Text("Loading\u{2026}")
                .font(.caption2)
                .foregroundStyle(.orange)
        default:
            Text("v\(plugin.manifest.version)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ScriptEditorView

/// Wraps NSTextView for a code editor with line numbers and monospaced font.
private struct ScriptEditorView: NSViewRepresentable {
    final class Coordinator: NSObject, NSTextViewDelegate {
        // MARK: Lifecycle

        init(text: Binding<String>) {
            self.text = text
        }

        // MARK: Internal

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
        }

        // MARK: Private

        private var text: Binding<String>
    }

    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isRichText = false
        textView.delegate = context.coordinator

        // Line number ruler
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
}

// MARK: - LineNumberRulerView

private final class LineNumberRulerView: NSRulerView {
    // MARK: Lifecycle

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.ruleThickness = 40
        self.clientView = textView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else
        {
            return
        }

        let visibleRect = scrollView?.contentView.bounds ?? rect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let content = textView.string as NSString
        var lineNumber = 1
        var index = 0

        while index < visibleCharRange.location {
            if content.character(at: index) == 0x0A {
                lineNumber += 1
            }
            index += 1
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        var glyphIndex = visibleGlyphRange.location
        while glyphIndex < NSMaxRange(visibleGlyphRange) {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineRange = content.lineRange(for: NSRange(location: charIndex, length: 0))
            var lineRect = layoutManager.boundingRect(forGlyphRange: layoutManager.glyphRange(
                forCharacterRange: NSRange(location: lineRange.location, length: 0),
                actualCharacterRange: nil
            ), in: textContainer)
            lineRect.origin.y += textView.textContainerInset.height - (scrollView?.contentView.bounds.origin.y ?? 0)

            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(
                at: NSPoint(x: ruleThickness - size.width - 4, y: lineRect.origin.y),
                withAttributes: attrs
            )

            lineNumber += 1
            glyphIndex = NSMaxRange(layoutManager.glyphRange(
                forCharacterRange: lineRange,
                actualCharacterRange: nil
            ))
        }
    }

    // MARK: Private

    private weak var textView: NSTextView?

    @objc
    private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }
}

// MARK: - ConsoleEntryRow

private struct ConsoleEntryRow: View {
    // MARK: Internal

    let entry: ConsoleEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(timestampColor)
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(levelColor)
                .textSelection(.enabled)
        }
    }

    // MARK: Private

    private var timestampColor: Color {
        switch entry.level {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        case .output: .green
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: .primary
        case .warning: .orange
        case .error: .red
        case .output: .green
        }
    }
}

// MARK: - Preview

#Preview {
    ScriptingWindowView()
}
