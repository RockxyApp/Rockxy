import Foundation
@testable import Rockxy
import Testing

// MARK: - WebSocketInspectorLayoutTests

/// Source-level contract for the WebSocket inspector layout in a short bottom inspector: the
/// connection header must never be pushed out of view, and a selected frame keeps a readable
/// payload area while the frame list keeps a couple of rows.
struct WebSocketInspectorLayoutTests {
    // MARK: Internal

    @Test("WebSocket inspector top-aligns overflow and bounds list/detail heights")
    func layoutKeepsHeaderAndDetailReadable() throws {
        let source = try Self.projectFile("Rockxy/Views/Inspector/WebSocketInspectorView.swift")

        // The tab scrolls as a whole so its fixed-height sections can never push the
        // inspector's URL bar and tab strip out of a short bottom pane; the frame list keeps a
        // bounded height and scrolls on its own inside it.
        #expect(source.contains("ScrollView(.vertical) {"))
        #expect(source.contains(".frame(height: frameListHeight(for: connection))"))
        #expect(source.contains("private func frameListHeight(for connection: WebSocketConnection) -> CGFloat"))
        #expect(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"))
        #expect(!source.contains("minHeight:"))
        // Inside the scroll view a max-only height collapses to zero, so payload views take a
        // fixed height instead.
        #expect(Self.occurrences(of: ".frame(height: 200)", in: source) == 2)
        #expect(!source.contains(".frame(maxHeight: 200)"))
    }

    // MARK: Private

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func projectFile(_ path: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }
}
