import AppKit
import Foundation
@testable import Rockxy
import Testing

struct SoftwareUpdateReleaseNotesTests {
    @Test("static display fallback turns loading into unavailable content")
    func staticDisplayFallbackResolvesLoading() {
        let content = SoftwareUpdateReleaseNotesContent.loading
            .resolvedForStaticDisplay(fallbackMessage: "Unavailable")

        #expect(content == .unavailable("Unavailable"))
    }

    @Test("static display fallback preserves concrete release notes")
    func staticDisplayFallbackPreservesConcreteNotes() {
        let html = SoftwareUpdateReleaseNotesContent.html("<h1>Notes</h1>", baseURL: nil)
        let plainText = SoftwareUpdateReleaseNotesContent.plainText("Notes")

        #expect(
            html.resolvedForStaticDisplay(fallbackMessage: "Unavailable")
                == .html("<h1>Notes</h1>", baseURL: nil)
        )
        #expect(
            plainText.resolvedForStaticDisplay(fallbackMessage: "Unavailable")
                == .plainText("Notes")
        )
    }

    @Test("html release notes are converted into native plain text for update UI")
    func htmlReleaseNotesProduceNativePlainText() {
        let content = SoftwareUpdateReleaseNotesContent.html(
            """
            <h1>Rockxy 0.12.0</h1>
            <p>Bug fixes and helper improvements.</p>
            <ul><li>Native update dialog</li><li>Better onboarding flow</li></ul>
            """,
            baseURL: nil
        )

        let text = content.nativeDisplayText()

        #expect(text?.contains("Rockxy 0.12.0") == true)
        #expect(text?.contains("Bug fixes and helper improvements.") == true)
        #expect(text?.contains("Native update dialog") == true)
        #expect(text?.contains("<h1>") == false)
    }

    @Test("html release notes preserve native emphasis and list formatting")
    func htmlReleaseNotesProduceNativeAttributedText() throws {
        let content = SoftwareUpdateReleaseNotesContent.html(
            """
            <h3>Fixed</h3>
            <ul>
              <li><strong>Helper install:</strong> Reads the embedded launchd plist correctly.</li>
              <li><em>Update dialog:</em> Shows native release notes inline.</li>
            </ul>
            """,
            baseURL: nil
        )

        let attributed = try #require(content.nativeDisplayAttributedString())
        let fullString = attributed.string

        #expect(fullString.contains("Fixed"))
        #expect(fullString.contains("Helper install:"))
        #expect(fullString.contains("Shows native release notes inline."))

        let helperSubstringRange = try #require(fullString.range(of: "Helper install:"))
        let helperRange = NSRange(helperSubstringRange, in: fullString)
        let helperFont = attributed.attribute(.font, at: helperRange.location, effectiveRange: nil) as? NSFont
        #expect(helperFont?.fontDescriptor.symbolicTraits.contains(NSFontDescriptor.SymbolicTraits.bold) == true)

        let paragraphStyle = attributed.attribute(.paragraphStyle, at: helperRange.location, effectiveRange: nil) as? NSParagraphStyle
        #expect(paragraphStyle?.lineBreakMode == .byWordWrapping)
    }
}
