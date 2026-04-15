import SwiftUI

// MARK: - ScriptConsolePanel

/// Right-side console panel in the Script Editor window. Shows user `console.log`
/// output filtered by the eye-icon menu. Empty state shows an "Empty Console"
/// header with a hint to call `console.log()` to log events.
struct ScriptConsolePanel: View {
    // MARK: Internal

    @Bindable var viewModel: ScriptEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Private

    private var header: some View {
        HStack {
            Text(viewModel.consoleEntries.isEmpty ? "Empty Console" : "Console")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                viewModel.clearConsole()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.consoleEntries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.3))
    }

    @ViewBuilder private var content: some View {
        let visible = viewModel.consoleEntries.filter { viewModel.consoleFilter.contains($0.level) }
        if visible.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Use console.log() to log events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(visible) { entry in
                            ScriptConsoleEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: visible.count) { _, _ in
                    if let last = visible.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - ScriptConsoleEntryRow

private struct ScriptConsoleEntryRow: View {
    // MARK: Internal

    let entry: ScriptConsoleEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.formatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(colorFor(level: entry.level))
                .textSelection(.enabled)
        }
    }

    // MARK: Private

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func colorFor(level: ScriptConsoleLogLevel) -> Color {
        switch level {
        case .errors: .red
        case .warnings: .orange
        case .userLogs: .primary
        case .system: .secondary
        }
    }
}
