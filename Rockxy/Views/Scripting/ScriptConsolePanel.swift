import SwiftUI

// MARK: - ScriptConsolePanel

/// Right-side console panel in the Script Editor window. Shows user `console.log`
/// output filtered by the eye-icon menu. Empty state shows an "Empty Console"
/// header with a hint to call `console.log()` to log events.
struct ScriptConsolePanel: View {
    // MARK: Internal

    @Bindable var viewModel: ScriptEditorViewModel

    var body: some View {
        content
            .font(toolMetrics.font())
            .frame(maxHeight: .infinity)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    @ViewBuilder private var content: some View {
        let visible = viewModel.consoleEntries.filter { viewModel.consoleFilter.contains($0.level) }
        if visible.isEmpty {
            VStack(spacing: 6) {
                Text("Empty Console")
                    .font(.system(size: max(16, toolMetrics.bodyFontSize + 3), weight: .medium))
                    .foregroundStyle(.primary)
                Text("Use console.log() to log events")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - ScriptConsoleEntryRow

private struct ScriptConsoleEntryRow: View {
    // MARK: Internal

    let entry: ScriptConsoleEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.formatter.string(from: entry.timestamp))
                .font(toolMetrics.metadataFont(monospaced: true))
                .foregroundStyle(.tertiary)
            Text(entry.message)
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(colorFor(level: entry.level))
                .textSelection(.enabled)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

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

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
