import Foundation
@testable import Rockxy
import Testing

struct AssistantMarkdownDocumentParserTests {
    @Test("Assistant Markdown is split into native semantic blocks")
    func parsesCommonResponseBlocks() {
        let document = AssistantMarkdownDocumentParser.parse(
            """
            # Diagnosis

            The request is **valid**.

            1. Inspect the response
            2. Verify the payload

            ```json
            {"status": 200}
            ```
            """
        )

        #expect(document.blocks == [
            .heading(level: 1, text: "Diagnosis"),
            .paragraph("The request is **valid**."),
            .orderedList([
                AssistantMarkdownListItem(number: 1, text: "Inspect the response"),
                AssistantMarkdownListItem(number: 2, text: "Verify the payload"),
            ]),
            .code(language: "json", text: #"{"status": 200}"#),
        ])
    }

    @Test("Inline Markdown punctuation is removed from reader-facing text")
    func rendersInlineFormatting() {
        let rendered = AssistantMarkdownInlineRenderer.render(
            "**Diagnosis:** inspect `CONNECT`."
        )

        #expect(String(rendered.characters) == "Diagnosis: inspect CONNECT.")
    }
}
