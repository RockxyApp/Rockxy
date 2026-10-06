import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - DiffWindowView

/// Diff workspace window — 4-zone layout: header, candidate pool card,
/// diff viewer, and control bar. Supports Request/Response/Timing comparison
/// in Side by Side or Unified mode. Comparison is local and read-only.
struct DiffWindowView: View {
    // MARK: Internal

    @State var viewModel = DiffViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.workspaceMode == .captured {
                DiffCandidateTableView(viewModel: viewModel)
                    .frame(minHeight: 100, idealHeight: 150, maxHeight: 230)
                Divider()
            }
            DiffViewerView(viewModel: viewModel)
            Divider()
            DiffControlBar(viewModel: viewModel)
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(900, toolMetrics.bodyFontSize * 32 + 484),
            idealWidth: max(1_240, toolMetrics.bodyFontSize * 42 + 694),
            minHeight: max(600, min(780, toolMetrics.bodyFontSize * 18 + 366)),
            idealHeight: max(820, toolMetrics.bodyFontSize * 24 + 508)
        )
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.swapSides()
                } label: {
                    Label(
                        String(localized: "Swap Sides", bundle: RockxyLocalization.bundle),
                        systemImage: "arrow.left.arrow.right"
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!viewModel.canSwapSides)
                .help(String(localized: "Swap the left and right sides", bundle: RockxyLocalization.bundle))

                Button {
                    exportDiff()
                } label: {
                    Label(
                        String(localized: "Export", bundle: RockxyLocalization.bundle),
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(!canExport)
                .help(String(localized: "Export the comparison as a text file", bundle: RockxyLocalization.bundle))

                if DiffFileMerge.isAvailable {
                    Button {
                        do {
                            try DiffFileMerge.open(viewModel.activeDiffResult)
                        } catch {
                            exportErrorMessage = error.localizedDescription
                        }
                    } label: {
                        Label(
                            String(localized: "Open in FileMerge", bundle: RockxyLocalization.bundle),
                            systemImage: "rectangle.split.2x1"
                        )
                    }
                    .disabled(!canExport)
                    .help(String(
                        localized: "Compare both sides in FileMerge",
                        bundle: RockxyLocalization.bundle
                    ))
                }
            }
        }
        .alert(
            String(localized: "Export Failed", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: {
                    if !$0 {
                        exportErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle), role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            if let exportErrorMessage {
                Text(exportErrorMessage)
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

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    @State private var exportErrorMessage: String?

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var canExport: Bool {
        guard !viewModel.isComparing, !viewModel.activeDiffResult.sections.isEmpty else {
            return false
        }
        return viewModel.workspaceState == .ready || viewModel.workspaceState == .textReady
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Basic Compare", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .semibold))
                Text(
                    String(
                        localized: "Compare captured transactions or pasted text without modifying live traffic.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: toolMetrics.controlSpacing)

            comparisonSourcePicker

            contextBadge
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var contextBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: toolMetrics.smallIconFontSize))
                .accessibilityHidden(true)
            Text(String(localized: "Local · Read-only", bundle: RockxyLocalization.bundle))
        }
        .font(toolMetrics.metadataFont(weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .rockxyChipStyle()
        .help(String(
            localized: "Comparison runs on your captured transactions and never modifies live traffic.",
            bundle: RockxyLocalization.bundle
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Local, read-only comparison", bundle: RockxyLocalization.bundle))
    }

    @ViewBuilder private var comparisonSourcePicker: some View {
        if toolMetrics.bodyFontSize >= 20 {
            Picker(
                String(localized: "Comparison Source", bundle: RockxyLocalization.bundle),
                selection: $viewModel.workspaceMode
            ) {
                ForEach(DiffViewModel.WorkspaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 150)
            .accessibilityLabel(String(localized: "Comparison source", bundle: RockxyLocalization.bundle))
        } else {
            Picker(
                String(localized: "Comparison Source", bundle: RockxyLocalization.bundle),
                selection: $viewModel.workspaceMode
            ) {
                ForEach(DiffViewModel.WorkspaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: max(200, toolMetrics.secondaryFontSize * 10 + 92))
            .accessibilityLabel(String(localized: "Comparison source", bundle: RockxyLocalization.bundle))
        }
    }

    private func exportDiff() {
        let result = viewModel.activeDiffResult
        guard !result.sections.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.title = String(localized: "Export Diff", bundle: RockxyLocalization.bundle)
        panel.allowedContentTypes = [UTType(filenameExtension: "diff") ?? .plainText, .plainText]
        panel.nameFieldStringValue = "rockxy-comparison.diff"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try DiffExportFormatter.write(result, to: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - DiffExportFormatter

enum DiffExportFormatter {
    static func text(for result: DiffResult) -> String {
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
        return output
    }

    /// Writes a unified diff (`diff -u` / `git apply` format) so the export opens in
    /// FileMerge, code review tools, and editors that understand patches.
    static func write(_ result: DiffResult, to url: URL) throws {
        try unifiedPatch(for: result).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Unified diff with one file entry per changed section and `context` unchanged
    /// lines around each change. Sections without changes are omitted.
    static func unifiedPatch(for result: DiffResult, context: Int = 3) -> String {
        var output = ""
        for section in result.sections {
            let hunks = unifiedHunks(for: section.lines, context: max(0, context))
            guard !hunks.isEmpty else {
                continue
            }
            let path = patchPath(for: section.title)
            output += "--- a/\(path)\n+++ b/\(path)\n"
            for hunk in hunks {
                output += hunk
            }
        }
        return output
    }

    private static func unifiedHunks(for lines: [DiffLine], context: Int) -> [String] {
        let changed = lines.indices.filter { lines[$0].type != .unchanged }
        guard let firstChange = changed.first else {
            return []
        }
        var groups: [ClosedRange<Int>] = []
        var start = firstChange
        var end = firstChange
        for index in changed.dropFirst() {
            if index - end > context * 2 + 1 {
                groups.append(start ... end)
                start = index
            }
            end = index
        }
        groups.append(start ... end)

        return groups.map { group in
            let range = max(0, group.lowerBound - context) ... min(lines.count - 1, group.upperBound + context)
            let slice = lines[range]
            let oldCount = slice.count { $0.type != .added }
            let newCount = slice.count { $0.type != .removed }
            let oldStart = hunkStart(
                in: lines, range: range, count: oldCount, lineNumber: \.oldLineNumber
            )
            let newStart = hunkStart(
                in: lines, range: range, count: newCount, lineNumber: \.newLineNumber
            )
            var hunk = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@\n"
            for line in slice {
                let marker = switch line.type {
                case .unchanged: " "
                case .added: "+"
                case .removed: "-"
                }
                hunk += marker + line.content + "\n"
            }
            return hunk
        }
    }

    /// First line number of the hunk on one side. For an empty side, unified diff
    /// uses the line *before* the insertion point (0 at the top of the file).
    private static func hunkStart(
        in lines: [DiffLine],
        range: ClosedRange<Int>,
        count: Int,
        lineNumber: KeyPath<DiffLine, Int?>
    )
        -> Int
    {
        if count > 0, let first = lines[range].lazy.compactMap({ $0[keyPath: lineNumber] }).first {
            return first
        }
        return lines[..<range.lowerBound].lazy.compactMap { $0[keyPath: lineNumber] }.last ?? 0
    }

    private static func patchPath(for title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let slug = String(title.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "section" : slug
    }
}

// MARK: - DiffFileMerge

/// Hands both sides of a comparison to FileMerge, the diff tool that ships with Xcode.
enum DiffFileMerge {
    static let bundleIdentifier = "com.apple.FileMerge"
    static let opendiffPath = "/usr/bin/opendiff"

    static var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
            && FileManager.default.isExecutableFile(atPath: opendiffPath)
    }

    /// The left and right documents, each section introduced by its title, so FileMerge
    /// aligns the same sections against each other.
    static func documents(for result: DiffResult) -> (left: String, right: String) {
        var left = ""
        var right = ""
        for section in result.sections {
            left += "--- \(section.title) ---\n"
            right += "--- \(section.title) ---\n"
            for line in section.lines {
                switch line.type {
                case .unchanged:
                    left += line.content + "\n"
                    right += line.content + "\n"
                case .removed:
                    left += line.content + "\n"
                case .added:
                    right += line.content + "\n"
                }
            }
            left += "\n"
            right += "\n"
        }
        return (left, right)
    }

    static func open(_ result: DiffResult) throws {
        let (left, right) = documents(for: result)
        Self.purgeStaleDiffDirectories()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-diff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let leftURL = directory.appendingPathComponent("left.txt")
        let rightURL = directory.appendingPathComponent("right.txt")
        try left.write(to: leftURL, atomically: true, encoding: .utf8)
        try right.write(to: rightURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: opendiffPath)
        process.arguments = [leftURL.path, rightURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// FileMerge keeps reading the comparison files after `opendiff` returns, so they cannot be
    /// removed right away. Captured requests can hold credentials, so older comparison
    /// folders are deleted the next time one is created.
    private static func purgeStaleDiffDirectories() {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: temp,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }
        for entry in entries where entry.lastPathComponent.hasPrefix("rockxy-diff-") {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: entry)
            }
        }
    }
}
