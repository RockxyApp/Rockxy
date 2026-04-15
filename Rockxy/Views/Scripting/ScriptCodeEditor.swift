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
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isRichText = false
        textView.delegate = context.coordinator

        let ruler = ScriptCodeEditorRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context _: Context) {
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

// MARK: - ScriptCodeEditorRulerView

/// Draws monospaced line numbers alongside the code editor. Re-renders on
/// text changes via `NSText.didChangeNotification`.
final class ScriptCodeEditorRulerView: NSRulerView {
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
            var lineRect = layoutManager.boundingRect(
                forGlyphRange: layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: lineRange.location, length: 0),
                    actualCharacterRange: nil
                ),
                in: textContainer
            )
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
    private func textDidChange(_: Notification) {
        needsDisplay = true
    }
}
