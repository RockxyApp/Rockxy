import SwiftUI

// Renders the breakpoint queue list for breakpoint review and editing.

// MARK: - BreakpointQueueListView

/// Left panel of the Breakpoints window showing all paused items as selectable rows.
/// Each row displays the phase badge, method/status, host + path, and elapsed time.
struct BreakpointQueueListView: View {
    // MARK: Internal

    @Bindable var manager: BreakpointManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                pausedHeader
                    .font(toolMetrics.secondaryFont(weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if manager.pausedItems.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "pause.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "No breakpoints paused."))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Traffic matching breakpoint rules will appear here."))
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(manager.pausedItems, selection: $manager.selectedItemId) { item in
                    BreakpointQueueRow(item: item)
                        .tag(item.id)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    /// Localized, plural-aware header for the paused items section.
    /// Uses SwiftUI `Text` inflection so the singular/plural form resolves at
    /// runtime and the integer count is a first-class argument localizers can
    /// reorder per locale.
    private var pausedHeader: Text {
        let count = manager.pausedItems.count
        return Text(
            "^[\(count) paused](inflect: true)",
            comment: "Header showing how many paused breakpoint items are in the queue"
        )
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - BreakpointQueueRow

/// A single row in the breakpoint queue list.
struct BreakpointQueueRow: View {
    // MARK: Internal

    let item: PausedBreakpointItem

    var body: some View {
        HStack(spacing: 8) {
            phaseBadge
            methodOrStatus
            VStack(alignment: .leading, spacing: 2) {
                Text(item.host)
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                Text(item.path)
                    .font(toolMetrics.secondaryFont(monospaced: true))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            ElapsedTimeLabel(since: item.createdAt)
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var phaseBadge: some View {
        Text(item.phase == .request ? "REQ" : "RES")
            .font(.system(size: toolMetrics.smallIconFontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(item.phase == .request ? Color.green : Color.blue, in: Capsule())
    }

    @ViewBuilder private var methodOrStatus: some View {
        if item.phase == .request {
            Text(item.method)
                .font(toolMetrics.secondaryFont(weight: .semibold, monospaced: true))
                .foregroundStyle(.primary)
        } else if let code = item.statusCode {
            Text("\(code)")
                .font(toolMetrics.secondaryFont(weight: .semibold, monospaced: true))
                .foregroundStyle(statusColor(for: code))
        }
    }

    private func statusColor(for code: Int) -> Color {
        switch code {
        case 200 ..< 300: .green
        case 300 ..< 400: .blue
        case 400 ..< 500: .orange
        case 500...: .red
        default: .secondary
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - ElapsedTimeLabel

/// Live-updating label showing seconds since a given date.
struct ElapsedTimeLabel: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(since))
            Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(.secondary)
        }
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
