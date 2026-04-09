import SwiftUI

/// Diff viewer that renders the comparison in either Side by Side or Unified mode.
/// Supports structured sections with headers, and freeform text paste fallback.
struct DiffViewerView: View {
    // MARK: Internal

    @Bindable var viewModel: DiffViewModel

    var body: some View {
        if viewModel.workspaceState == .textPaste {
            textPasteMode
        } else if viewModel.workspaceState == .ready {
            diffContent
        } else {
            partialState
        }
    }

    // MARK: Private

    // MARK: - Diff Content

    @ViewBuilder private var diffContent: some View {
        let result = viewModel.diffResult
        switch viewModel.presentationMode {
        case .sideBySide:
            sideBySideView(result)
        case .unified:
            unifiedView(result)
        }
    }

    // MARK: - Text Paste Mode

    private var textPasteMode: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Side A — paste or type text"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                TextEditor(text: $viewModel.textA)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Side B — paste or type text"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                TextEditor(text: $viewModel.textB)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Partial State

    private var partialState: some View {
        VStack(spacing: 6) {
            Image(systemName: viewModel.workspaceState == .missingLeft ? "arrow.left" : viewModel
                .workspaceState == .missingRight ? "arrow.right" : "arrow.left.arrow.right")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            if viewModel.workspaceState == .missingRight {
                Text(String(localized: "Assign a Right Transaction"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Click the R column on a candidate to finish this basic compare."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if viewModel.workspaceState == .missingLeft {
                Text(String(localized: "Assign a Left Transaction"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Click the L column on a candidate to finish this basic compare."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Side by Side

    private func sideBySideView(_ result: DiffResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(String(localized: "Left"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                    Text(String(localized: "Right"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .background(.quaternary.opacity(0.3))

                ForEach(result.sections) { section in
                    sectionHeader(section.title)
                    let rows = DiffResult.sideBySideRows(from: section.lines)
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            sideBySideCell(row.left)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                            sideBySideCell(row.right)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sideBySideCell(_ line: DiffLine?) -> some View {
        if let line {
            diffLineRow(line)
        } else {
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 36)
                Text("")
                    .frame(width: 14)
                Text("")
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .frame(minHeight: 18)
        }
    }

    // MARK: - Unified

    private func unifiedView(_ result: DiffResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(result.sections) { section in
                    sectionHeader(section.title)
                    ForEach(section.lines) { line in
                        diffLineRow(line)
                    }
                }
            }
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String) -> some View {
        Text("— \(title) —")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.2))
    }

    private func diffLineRow(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            Text("\(line.lineNumber)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 4)

            Text(prefix(for: line.type))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(prefixColor(for: line.type))
                .frame(width: 14)

            Text(line.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(contentColor(for: line.type))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(backgroundColor(for: line.type))
    }

    private func prefix(for type: DiffLineType) -> String {
        switch type {
        case .unchanged: " "
        case .added: "+"
        case .removed: "-"
        }
    }

    private func prefixColor(for type: DiffLineType) -> Color {
        switch type {
        case .unchanged: .secondary
        case .added: .green
        case .removed: .red
        }
    }

    private func contentColor(for type: DiffLineType) -> Color {
        switch type {
        case .unchanged: .secondary
        case .added: .green
        case .removed: .red
        }
    }

    private func backgroundColor(for type: DiffLineType) -> Color {
        switch type {
        case .unchanged: .clear
        case .added: .green.opacity(0.15)
        case .removed: .red.opacity(0.15)
        }
    }
}
