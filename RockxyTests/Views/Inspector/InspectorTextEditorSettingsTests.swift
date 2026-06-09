import AppKit
@testable import Rockxy
import Testing

@MainActor
struct InspectorTextEditorSettingsTests {
    @Test("Inspector editor settings configure word wrap and horizontal scrolling")
    func configureWordWrapAndHorizontalScrolling() throws {
        let scrollView = makeEditorScrollView()
        let settings = InspectorTextEditorSettings(fontSize: 16, wordWrap: true)

        InspectorBodyTextEditor.applyEditorSettings(settings, to: scrollView)

        let textView = try #require(scrollView.documentView as? NSTextView)
        #expect(scrollView.hasHorizontalScroller == false)
        #expect(textView.isHorizontallyResizable == false)
        #expect(textView.textContainer?.widthTracksTextView == true)
    }

    @Test("Inspector editor settings configure tab width invisibles and bottom inset")
    func configureTabWidthInvisiblesAndBottomInset() throws {
        let scrollView = makeEditorScrollView()
        let settings = InspectorTextEditorSettings(
            fontSize: 18,
            tabWidth: 4,
            useMonospacedFont: true,
            wordWrap: false,
            showInvisibles: true,
            scrollBeyondLastLine: true
        )

        InspectorBodyTextEditor.applyEditorSettings(settings, to: scrollView)

        let textView = try #require(scrollView.documentView as? NSTextView)
        #expect(scrollView.hasHorizontalScroller == true)
        #expect(scrollView.contentInsets.bottom == 160)
        #expect(textView.isHorizontallyResizable == true)
        #expect(textView.textContainer?.widthTracksTextView == false)
        #expect(textView.layoutManager?.showsInvisibleCharacters == true)
        #expect(textView.layoutManager?.showsControlCharacters == true)
        #expect(settings.tabInterval > 0)
    }

    @Test("Inspector editor settings update existing attributed text storage")
    func updateExistingAttributedTextStorage() throws {
        let scrollView = makeEditorScrollView(text: "alpha\tbeta")
        let settings = InspectorTextEditorSettings(fontSize: 17, tabWidth: 4, useMonospacedFont: true)

        InspectorBodyTextEditor.applyEditorSettings(settings, to: scrollView)

        let textView = try #require(scrollView.documentView as? NSTextView)
        let font = try #require(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let paragraphStyle = try #require(
            textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        #expect(font.pointSize == 17)
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(paragraphStyle.defaultTabInterval == settings.tabInterval)
    }

    @Test("Inspector editor settings can switch body display options live")
    func switchBodyDisplayOptionsLive() throws {
        let scrollView = makeEditorScrollView(text: "alpha\tbeta")
        let wrapped = InspectorTextEditorSettings(wordWrap: true, showInvisibles: false, scrollBeyondLastLine: false)
        let expanded = InspectorTextEditorSettings(wordWrap: false, showInvisibles: true, scrollBeyondLastLine: true)

        InspectorBodyTextEditor.applyEditorSettings(wrapped, to: scrollView)
        InspectorBodyTextEditor.applyEditorSettings(expanded, to: scrollView)

        let textView = try #require(scrollView.documentView as? NSTextView)
        #expect(scrollView.hasHorizontalScroller == true)
        #expect(scrollView.contentInsets.bottom == 160)
        #expect(textView.isHorizontallyResizable == true)
        #expect(textView.textContainer?.widthTracksTextView == false)
        #expect(textView.layoutManager?.showsInvisibleCharacters == true)
        #expect(textView.layoutManager?.showsControlCharacters == true)
    }

    private func makeEditorScrollView() -> NSScrollView {
        makeEditorScrollView(text: "")
    }

    private func makeEditorScrollView(text: String) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: scrollView.contentSize)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize), textContainer: textContainer)
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }
}
