import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Diff workspace window — 4-zone layout: toolbar, candidate pool table,
/// diff viewer, and control bar. Supports Request/Response/Timing comparison
/// in Side by Side or Unified mode.
struct DiffWindowView: View {
    // MARK: Internal

    @State var viewModel = DiffViewModel()

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
        .frame(minWidth: 900, idealWidth: 1240, minHeight: 600, idealHeight: 820)
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
            .font(.caption)
            .foregroundStyle(.secondary)
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
