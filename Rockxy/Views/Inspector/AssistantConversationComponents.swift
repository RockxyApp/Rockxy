import AppKit
import SwiftUI

enum AssistantClipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - AssistantResponseCard

struct AssistantResponseCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(String(localized: "Rockxy Assistant"))
                    .font(metrics.swiftUIFont(size: metrics.metadataFontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "AI Assistant Response"))
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - AssistantProgressRow

struct AssistantProgressRow: View {
    let title: String
    var systemImage: String?
    var color = Color.secondary
    var showsProgress = false

    var body: some View {
        HStack(spacing: 7) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
            }
            Text(title)
                .font(metrics.swiftUIFont(size: metrics.secondaryFontSize, weight: .medium))
            Spacer(minLength: 0)
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - AssistantResponseActionBar

struct AssistantResponseActionBar: View {
    let canCopy: Bool
    let canRevealRequest: Bool
    let canRetry: Bool
    let onCopy: () -> Void
    let onFollowUp: () -> Void
    let onRevealRequest: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            action(String(localized: "Copy"), systemImage: "doc.on.doc", action: onCopy)
                .disabled(!canCopy)
            action(
                String(localized: "Follow Up"),
                systemImage: "arrowshape.turn.up.left",
                action: onFollowUp
            )
            if canRevealRequest {
                action(String(localized: "Reveal Request"), systemImage: "scope", action: onRevealRequest)
            }
            Spacer(minLength: 0)
            if canRetry {
                action(String(localized: "Review & Retry"), systemImage: "arrow.clockwise", action: onRetry)
            }
        }
        .font(metrics.swiftUIFont(size: metrics.metadataFontSize))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    @Environment(\.appUIDisplayMetrics) private var metrics

    private func action(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.borderless)
        .controlSize(.mini)
    }
}

// MARK: - AssistantMarkdownText

/// Renders common model Markdown as native SwiftUI text without exposing formatting markers.
/// Block parsing runs away from the main actor and is retained by the view's stable message identity.
struct AssistantMarkdownText: View {
    let source: String

    var body: some View {
        Group {
            if let document {
                AssistantMarkdownDocumentView(document: document)
            } else {
                Text(AssistantMarkdownInlineRenderer.render(source))
                    .font(metrics.swiftUIFont(size: metrics.primaryFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .task(id: source) {
            let parsed = await Task.detached(priority: .utility) {
                AssistantMarkdownDocumentParser.parse(source)
            }.value
            guard !Task.isCancelled else {
                return
            }
            document = parsed
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var document: AssistantMarkdownDocument?
}

/// Streaming output keeps its layout lightweight while still hiding inline Markdown punctuation.
struct AssistantStreamingText: View {
    let source: String

    var body: some View {
        Text(AssistantMarkdownInlineRenderer.render(source))
            .font(metrics.swiftUIFont(size: metrics.primaryFontSize))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - AssistantMarkdownDocument

struct AssistantMarkdownDocument: Equatable, Sendable {
    let blocks: [AssistantMarkdownBlock]
}

enum AssistantMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([AssistantMarkdownListItem])
    case code(language: String?, text: String)
    case quote(String)
    case separator
}

struct AssistantMarkdownListItem: Equatable, Sendable {
    let number: Int
    let text: String
}

// MARK: - AssistantMarkdownDocumentParser

enum AssistantMarkdownDocumentParser {
    static func parse(_ source: String) -> AssistantMarkdownDocument {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [AssistantMarkdownBlock] = []
        var paragraph: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [AssistantMarkdownListItem] = []
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInsideCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else {
                return
            }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else {
                return
            }
            blocks.append(.unorderedList(unorderedItems))
            unorderedItems.removeAll(keepingCapacity: true)
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else {
                return
            }
            blocks.append(.orderedList(orderedItems))
            orderedItems.removeAll(keepingCapacity: true)
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else {
                return
            }
            blocks.append(.quote(quoteLines.joined(separator: "\n")))
            quoteLines.removeAll(keepingCapacity: true)
        }

        func flushTextBlocks() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
            flushQuote()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isInsideCodeBlock {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(
                        language: codeLanguage?.isEmpty == false ? codeLanguage : nil,
                        text: codeLines.joined(separator: "\n")
                    ))
                    codeLines.removeAll(keepingCapacity: true)
                    codeLanguage = nil
                    isInsideCodeBlock = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushTextBlocks()
                codeLanguage = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                isInsideCodeBlock = true
                continue
            }

            if trimmed.isEmpty {
                flushTextBlocks()
                continue
            }

            if let heading = heading(from: trimmed) {
                flushTextBlocks()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if isSeparator(trimmed) {
                flushTextBlocks()
                blocks.append(.separator)
                continue
            }

            if let item = unorderedItem(from: trimmed) {
                flushParagraph()
                flushOrderedList()
                flushQuote()
                unorderedItems.append(item)
                continue
            }

            if let item = orderedItem(from: trimmed) {
                flushParagraph()
                flushUnorderedList()
                flushQuote()
                orderedItems.append(item)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushUnorderedList()
                flushOrderedList()
                quoteLines.append(
                    String(trimmed.dropFirst())
                        .trimmingCharacters(in: .whitespaces)
                )
                continue
            }

            flushUnorderedList()
            flushOrderedList()
            flushQuote()
            paragraph.append(line)
        }

        if isInsideCodeBlock {
            blocks.append(.code(
                language: codeLanguage?.isEmpty == false ? codeLanguage : nil,
                text: codeLines.joined(separator: "\n")
            ))
        }
        flushTextBlocks()
        return AssistantMarkdownDocument(blocks: blocks)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1 ... 6).contains(markerCount),
              line.dropFirst(markerCount).first == " " else
        {
            return nil
        }
        return (
            markerCount,
            String(line.dropFirst(markerCount + 1))
        )
    }

    private static func unorderedItem(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedItem(from line: String) -> AssistantMarkdownListItem? {
        guard let period = line.firstIndex(of: "."),
              period != line.startIndex,
              line.index(after: period) < line.endIndex,
              line[line.index(after: period)] == " ",
              let number = Int(line[..<period]) else
        {
            return nil
        }
        return AssistantMarkdownListItem(
            number: number,
            text: String(line[line.index(period, offsetBy: 2)...])
        )
    }

    private static func isSeparator(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first else {
            return false
        }
        return ["-", "*", "_"].contains(String(marker))
            && compact.allSatisfy { $0 == marker }
    }
}

// MARK: - AssistantMarkdownDocumentView

private struct AssistantMarkdownDocumentView: View {
    let document: AssistantMarkdownDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @Environment(\.appUIDisplayMetrics) private var metrics

    @ViewBuilder
    private func blockView(_ block: AssistantMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(AssistantMarkdownInlineRenderer.render(text))
                .font(metrics.swiftUIFont(
                    size: headingFontSize(level),
                    weight: .semibold
                ))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 2 : 0)
        case let .paragraph(text):
            Text(AssistantMarkdownInlineRenderer.render(text))
                .font(metrics.swiftUIFont(size: metrics.primaryFontSize))
                .fixedSize(horizontal: false, vertical: true)
        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(AssistantMarkdownInlineRenderer.render(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(metrics.swiftUIFont(size: metrics.primaryFontSize))
            .padding(.leading, 4)
        case let .orderedList(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(item.number).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(AssistantMarkdownInlineRenderer.render(item.text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(metrics.swiftUIFont(size: metrics.primaryFontSize))
        case let .code(language, text):
            VStack(alignment: .leading, spacing: 5) {
                if let language {
                    Text(language.uppercased())
                        .font(metrics.swiftUIFont(size: metrics.metadataFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(text)
                        .font(metrics.swiftUIFont(size: metrics.secondaryFontSize, monospaced: true))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 2)
                Text(AssistantMarkdownInlineRenderer.render(text))
                    .font(metrics.swiftUIFont(size: metrics.primaryFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .separator:
            Divider()
        }
    }

    private func headingFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:
            metrics.primaryFontSize + 2
        case 2:
            metrics.primaryFontSize + 1
        default:
            metrics.primaryFontSize
        }
    }
}

// MARK: - AssistantMarkdownInlineRenderer

enum AssistantMarkdownInlineRenderer {
    static func render(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }
}
