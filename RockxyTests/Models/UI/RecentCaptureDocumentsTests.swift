import AppKit
@testable import Rockxy
import Testing

@MainActor
struct RecentCaptureDocumentsTests {
    /// Keeps recents in memory so tests never touch the real app's recent-documents list.
    private final class MemoryDocumentController: NSDocumentController {
        var stored: [URL] = []

        override var recentDocumentURLs: [URL] {
            stored
        }

        override func noteNewRecentDocumentURL(_ url: URL) {
            stored.removeAll { $0 == url }
            stored.insert(url, at: 0)
        }

        override func clearRecentDocuments(_ sender: Any?) {
            stored = []
        }
    }

    @Test("Only existing sessions and HAR files are listed, newest first")
    func listsSupportedExistingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = directory.appendingPathComponent("a.rockxysession")
        let har = directory.appendingPathComponent("b.har")
        let text = directory.appendingPathComponent("c.txt")
        for url in [session, har, text] {
            try Data("{}".utf8).write(to: url)
        }

        let recents = RecentCaptureDocuments(controller: MemoryDocumentController())
        recents.note(session)
        recents.note(text)
        recents.note(har)
        #expect(recents.urls.map(\.lastPathComponent) == ["b.har", "a.rockxysession"])

        try FileManager.default.removeItem(at: har)
        recents.refresh()
        #expect(recents.urls.map(\.lastPathComponent) == ["a.rockxysession"])

        recents.clear()
        #expect(recents.urls.isEmpty)
    }
}
