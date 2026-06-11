import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Diff workspace window — 4-zone layout: toolbar, candidate pool table,
/// diff viewer, and control bar. Supports Request/Response/Timing comparison
/// in Side by Side or Unified mode.
struct DiffWindowView: View {
    // MARK: Internal

    @State var viewModel = DiffViewModel()
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    var body: some View {
        VStack(spacing: 0) {
            infoBar
            Divider()
            DiffCandidateTableView(viewModel: viewModel)
                .frame(minHeight: 60, idealHeight: 120, maxHeight: 200)
            Divider()
            DiffViewerView(viewModel: viewModel)
            Divider()
            DiffControlBar(viewModel: viewModel)
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(900, toolMetrics.bodyFontSize * 32 + 484),
            idealWidth: max(1_240, toolMetrics.bodyFontSize * 42 + 694),
            minHeight: max(600, toolMetrics.bodyFontSize * 18 + 366),
            idealHeight: max(820, toolMetrics.bodyFontSize * 24 + 508)
        )
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.swapSides()
                } label: {
                    Label(String(localized: "Swap Sides"), systemImage: "arrow.left.arrow.right")
                }
                .help(String(localized: "Swap left and right sides"))

                Button {
                    exportDiff()
                } label: {
                    Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                }
                .help(String(localized: "Export unified diff"))
            }
        }
        .onAppear {
            viewModel.consumeFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDiffWindow)) { _ in
            viewModel.consumeFromStore()
        }
    }

    // MARK: Private

    private var infoBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.2x1")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(
                String(
                    localized: "Basic Compare helps you quickly inspect Request, Response, or Timing differences between two local transactions."
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45))
    }

    private func exportDiff() {
        let result = viewModel.activeDiffResult
        guard result.differenceCount > 0 else {
            return
        }

        var output = ""
        for section in result.sections {
            output += "--- \(section.title) ---\n"
            for line in section.lines {
                switch line.type {
                case .unchanged: output += "  \(line.content)\n"
                case .added: output += "+ \(line.content)\n"
                case .removed: output += "- \(line.content)\n"
                }
            }
            output += "\n"
        }

        let panel = NSSavePanel()
        panel.title = String(localized: "Export Diff")
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "diff.txt"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }
}
