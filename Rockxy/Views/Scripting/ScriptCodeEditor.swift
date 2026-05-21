import AppKit
import SwiftUI

// MARK: - ScriptCodeEditor

/// NSTextView-backed code editor with a line-number ruler. Monospaced 13pt,
/// find-bar enabled, automatic substitutions disabled so JS syntax characters
/// aren't mangled. Used by `ScriptEditorWindowView`.
struct ScriptCodeEditor: NSViewRepresentable {
    final class Coordinator: NSObject, NSTextViewDelegate {
        // MARK: Lifecycle

        init(text: Binding<String>) {
            self.text = text
        }

        // MARK: Internal

        var highlightTask: Task<Void, Never>?

        deinit {
            highlightTask?.cancel()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
            if let scrollView = textView.enclosingScrollView {
                scheduleHighlight(text: textView.string, in: scrollView)
            }
        }

        @MainActor
        func scheduleHighlight(text: String, in scrollView: NSScrollView) {
            highlightTask?.cancel()

            highlightTask = Task { [weak scrollView] in
                let spans = await Task.detached(priority: .utility) {
                    ScriptCodeHighlighting.spans(for: text)
                }.value

                guard !Task.isCancelled,
                      let scrollView,
                      let textView = scrollView.documentView as? NSTextView,
                      textView.string == text else
                {
                    return
                }

                let selectedRange = textView.selectedRange()
                let highlighted = ScriptCodeHighlighting.highlightedString(text, spans: spans)
                textView.undoManager?.disableUndoRegistration()
                textView.textStorage?.setAttributedString(highlighted)
                textView.undoManager?.enableUndoRegistration()
                textView.typingAttributes = ScriptCodeHighlighting.baseAttributes
                textView.setSelectedRange(ScriptCodeEditorRulerLayout.clamped(
                    range: selectedRange,
                    length: highlighted.length
                ))
                (scrollView.verticalRulerView as? ScriptCodeEditorRulerView)?.invalidateLineNumbers()
            }
        }

        // MARK: Private

        private var text: Binding<String>
    }

    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = false
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = ScriptCodeTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = ScriptCodeHighlighting.font
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.typingAttributes = ScriptCodeHighlighting.baseAttributes
        textView.delegate = context.coordinator
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        let ruler = ScriptCodeEditorRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        textView.string = text
        context.coordinator.scheduleHighlight(text: text, in: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            textView.string = text
            context.coordinator.scheduleHighlight(text: text, in: nsView)
            (nsView.verticalRulerView as? ScriptCodeEditorRulerView)?.invalidateLineNumbers()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
}

// MARK: - ScriptCodeTextView

final class ScriptCodeTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command,
              let key = event.charactersIgnoringModifiers
        else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "/":
            toggleLineComment()
            return true
        case "[":
            outdentSelection()
            return true
        case "]":
            indentSelection()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func toggleLineComment() {
        replaceSelectedLines { lines in
            let codeLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let shouldUncomment = !codeLines.isEmpty && codeLines.allSatisfy {
                $0.range(of: #"^[ \t]*//"#, options: .regularExpression) != nil
            }

            return lines.map { line in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return line
                }
                if shouldUncomment {
                    return Self.uncommented(line)
                }
                return Self.commented(line)
            }
        }
    }

    private func indentSelection() {
        replaceSelectedLines { lines in
            lines.map { "  " + $0 }
        }
    }

    private func outdentSelection() {
        replaceSelectedLines { lines in
            lines.map(Self.outdented)
        }
    }

    private func replaceSelectedLines(_ transform: ([String]) -> [String]) {
        let nsText = string as NSString
        let selection = selectedRange()
        let lineRange = nsText.lineRange(for: selection)
        let original = nsText.substring(with: lineRange)
        let hasTrailingNewline = original.hasSuffix("\n")
        var lines = original.components(separatedBy: "\n")
        if hasTrailingNewline {
            lines.removeLast()
        }

        var replacement = transform(lines).joined(separator: "\n")
        if hasTrailingNewline {
            replacement += "\n"
        }

        guard shouldChangeText(in: lineRange, replacementString: replacement) else {
            return
        }
        textStorage?.replaceCharacters(in: lineRange, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: selection.location, length: 0))
    }

    private static func commented(_ line: String) -> String {
        let prefix = line.prefix { $0 == " " || $0 == "\t" }
        return String(prefix) + "// " + line.dropFirst(prefix.count)
    }

    private static func uncommented(_ line: String) -> String {
        let prefix = line.prefix { $0 == " " || $0 == "\t" }
        let remainder = line.dropFirst(prefix.count)
        if remainder.hasPrefix("// ") {
            return String(prefix) + remainder.dropFirst(3)
        }
        if remainder.hasPrefix("//") {
            return String(prefix) + remainder.dropFirst(2)
        }
        return line
    }

    private static func outdented(_ line: String) -> String {
        if line.hasPrefix("  ") {
            return String(line.dropFirst(2))
        }
        if line.hasPrefix("\t") || line.hasPrefix(" ") {
            return String(line.dropFirst())
        }
        return line
    }
}

// MARK: - ScriptCodeHighlighting

enum ScriptCodeHighlighting {
    struct Span: Sendable, Equatable {
        let range: NSRange
        let role: Role
    }

    enum Role: Sendable, Equatable {
        case comment
        case string
        case keyword
        case function
        case number
        case bool
        case null
        case punctuation

        @MainActor var color: NSColor {
            switch self {
            case .comment:
                .secondaryLabelColor
            case .string:
                Theme.JSON.stringNS
            case .keyword:
                Theme.JSON.boolNS
            case .function:
                Theme.JSON.keyNS
            case .number:
                Theme.JSON.numberNS
            case .bool:
                Theme.JSON.boolNS
            case .null:
                Theme.JSON.nullNS
            case .punctuation:
                Theme.JSON.bracketNS
            }
        }
    }

    @MainActor
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    @MainActor
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.textBackgroundColor,
        ]
    }

    @MainActor
    static func highlightedString(_ text: String, spans: [Span]) -> NSMutableAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
        for span in spans where NSMaxRange(span.range) <= attributed.length {
            attributed.addAttribute(.foregroundColor, value: span.role.color, range: span.range)
        }
        return attributed
    }

    nonisolated static func spans(for text: String) -> [Span] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var spans: [Span] = []
        appendSpans(#""(?:\\.|[^"\\])*""#, role: .string, text: text, range: fullRange, spans: &spans)
        appendSpans(
            #"\b(?:async|await|break|case|catch|class|const|continue|default|else|export|for|function|if|import|let|return|switch|throw|try|var|while)\b"#,
            role: .keyword,
            text: text,
            range: fullRange,
            spans: &spans
        )
        appendSpans(#"\b[A-Za-z_$][A-Za-z0-9_$]*(?=\s*\()"#, role: .function, text: text, range: fullRange, spans: &spans)
        appendSpans(#"(?<![\w.])-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, role: .number, text: text, range: fullRange, spans: &spans)
        appendSpans(#"\b(?:true|false)\b"#, role: .bool, text: text, range: fullRange, spans: &spans)
        appendSpans(#"\b(?:null|undefined)\b"#, role: .null, text: text, range: fullRange, spans: &spans)
        appendSpans(#"[\{\}\[\]\(\),.;:]"#, role: .punctuation, text: text, range: fullRange, spans: &spans)
        appendSpans(#"(?m)//.*$"#, role: .comment, text: text, range: fullRange, spans: &spans)
        appendSpans(#"/\*[\s\S]*?\*/"#, role: .comment, text: text, range: fullRange, spans: &spans)
        return spans
    }

    nonisolated private static func appendSpans(
        _ pattern: String,
        role: Role,
        text: String,
        range: NSRange,
        spans: inout [Span]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else {
                return
            }
            spans.append(Span(range: match.range, role: role))
        }
    }
}

// MARK: - ScriptCodeEditorRulerView

/// Draws monospaced line numbers alongside the code editor. Re-renders on
/// text changes, scroll bounds changes, and text view layout changes.
final class ScriptCodeEditorRulerView: NSRulerView {
    // MARK: Lifecycle

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.ruleThickness = 40
        self.clientView = textView
        scrollView?.contentView.postsBoundsChangedNotifications = true
        textView.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateLineNumbers),
            name: NSText.didChangeNotification,
            object: textView
        )
        if let contentView = scrollView?.contentView {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(invalidateLineNumbers),
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateLineNumbers),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Internal

    override func drawHashMarksAndLabels(in rect: NSRect) {
        let dirtyRect = bounds.intersection(rect)
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        NSGraphicsContext.current?.saveGraphicsState()
        dirtyRect.clip()
        defer {
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let contentView = scrollView?.contentView else
        {
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let content = textView.string as NSString
        let visibleRect = ScriptCodeEditorRulerLayout.visibleTextContainerRect(
            contentBounds: contentView.bounds,
            textContainerOrigin: textView.textContainerOrigin
        )
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        var glyphIndex = visibleGlyphRange.location
        var lastLineRange = NSRange(location: NSNotFound, length: 0)
        while glyphIndex < NSMaxRange(visibleGlyphRange) {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineRange = content.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            if lineRange.location == lastLineRange.location, lineRange.length == lastLineRange.length {
                glyphIndex = max(NSMaxRange(lineGlyphRange), glyphIndex + 1)
                continue
            }
            lastLineRange = lineRange

            var effectiveGlyphRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &effectiveGlyphRange,
                withoutAdditionalLayout: true
            )
            let lineNumber = ScriptCodeEditorRulerLayout.lineNumber(
                in: content,
                forCharacterAt: lineRange.location
            )

            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            let y = ScriptCodeEditorRulerLayout.rulerY(
                lineFragmentY: lineRect.origin.y,
                textContainerOriginY: textView.textContainerOrigin.y,
                contentOffsetY: contentView.bounds.origin.y
            )
            str.draw(
                at: NSPoint(
                    x: ScriptCodeEditorRulerLayout.labelX(ruleThickness: ruleThickness, labelWidth: size.width),
                    y: y
                ),
                withAttributes: attrs
            )

            let nextGlyphIndex = max(NSMaxRange(lineGlyphRange), NSMaxRange(effectiveGlyphRange), glyphIndex + 1)
            glyphIndex = nextGlyphIndex
        }
    }

    @objc
    func invalidateLineNumbers() {
        needsDisplay = true
        setNeedsDisplay(bounds)
    }

    // MARK: Private

    private weak var textView: NSTextView?
}

// MARK: - ScriptCodeEditorRulerLayout

enum ScriptCodeEditorRulerLayout {
    static let labelTrailingPadding: CGFloat = 4

    static func clamped(range: NSRange, length: Int) -> NSRange {
        guard range.location != NSNotFound else {
            return NSRange(location: 0, length: 0)
        }
        let location = min(range.location, length)
        let upperBound = min(range.location + range.length, length)
        return NSRange(location: location, length: max(0, upperBound - location))
    }

    static func visibleTextContainerRect(contentBounds: NSRect, textContainerOrigin: NSPoint) -> NSRect {
        NSRect(
            x: contentBounds.origin.x - textContainerOrigin.x,
            y: contentBounds.origin.y - textContainerOrigin.y,
            width: contentBounds.width,
            height: contentBounds.height
        )
    }

    static func lineNumber(in content: NSString, forCharacterAt characterIndex: Int) -> Int {
        let end = min(max(characterIndex, 0), content.length)
        guard end > 0 else {
            return 1
        }

        var lineNumber = 1
        var index = 0
        while index < end {
            if content.character(at: index) == 0x0A {
                lineNumber += 1
            }
            index += 1
        }
        return lineNumber
    }

    static func rulerY(lineFragmentY: CGFloat, textContainerOriginY: CGFloat, contentOffsetY: CGFloat) -> CGFloat {
        lineFragmentY + textContainerOriginY - contentOffsetY
    }

    static func labelX(ruleThickness: CGFloat, labelWidth: CGFloat) -> CGFloat {
        max(0, ruleThickness - labelWidth - labelTrailingPadding)
    }
}
