import Foundation
@testable import Rockxy
import Testing

// MARK: - ExternalCaptureDocumentTests

@MainActor
struct ExternalCaptureDocumentTests {
    // MARK: Internal

    @Test("Session, HAR, and JSON files are recognized regardless of extension case")
    func classifiesSupportedExtensions() {
        #expect(ExternalCaptureDocumentKind(url: URL(fileURLWithPath: "/tmp/a.rockxysession")) == .session)
        #expect(ExternalCaptureDocumentKind(url: URL(fileURLWithPath: "/tmp/b.HAR")) == .har)
        #expect(ExternalCaptureDocumentKind(url: URL(fileURLWithPath: "/tmp/c.json")) == .har)
    }

    @Test("Unsupported files and remote URLs are rejected")
    func rejectsUnsupportedURLs() throws {
        #expect(ExternalCaptureDocumentKind(url: URL(fileURLWithPath: "/tmp/a.txt")) == nil)
        #expect(ExternalCaptureDocumentKind(url: URL(fileURLWithPath: "/tmp/project.rockxyproject")) == nil)
        let remote = try #require(URL(string: "https://example.com/capture.har"))
        #expect(ExternalCaptureDocumentKind(url: remote) == nil)
    }

    @Test("Dropping a HAR presents the import review with its entry count")
    func openingHARPresentsReview() throws {
        let url = try writeTemporaryFile(named: "dropped.har", contents: Self.harJSON)
        defer { try? FileManager.default.removeItem(at: url) }
        let coordinator = MainContentCoordinator()

        let handled = coordinator.openExternalDocuments([
            URL(fileURLWithPath: "/tmp/notes.txt"),
            url,
        ])

        #expect(handled)
        let preview = try #require(coordinator.importPreview)
        #expect(preview.fileType == .har)
        #expect(preview.transactionCount == 1)
        #expect(preview.sourceURL == url)
    }

    @Test("Unsupported drops leave the session untouched")
    func unsupportedDropIsIgnored() {
        let coordinator = MainContentCoordinator()

        let handled = coordinator.openExternalDocuments([URL(fileURLWithPath: "/tmp/readme.md")])

        #expect(!handled)
        #expect(coordinator.importPreview == nil)
    }

    // MARK: Private

    private static let harJSON = """
    {"log":{"version":"1.2","creator":{"name":"test","version":"1"},"entries":[{
      "startedDateTime":"2026-09-29T10:00:00.000Z","time":12,
      "request":{"method":"GET","url":"https://example.com/api","httpVersion":"HTTP/1.1",
        "headers":[],"queryString":[],"cookies":[],"headersSize":-1,"bodySize":0},
      "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","headers":[],"cookies":[],
        "content":{"size":2,"mimeType":"application/json","text":"{}"},"redirectURL":"","headersSize":-1,"bodySize":2},
      "cache":{},"timings":{"send":0,"wait":12,"receive":0}}]}}
    """

    private func writeTemporaryFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
}
