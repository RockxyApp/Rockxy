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
        #expect(ExternalCaptureDocumentKind(url: URL(fileURLWithPath: "/tmp/d.chlsj")) == .har)
        #expect(ExternalCaptureDocumentKind(url: URL(fileURLWithPath: "/tmp/e.CHLS")) == .charlesBinarySession)
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

    @Test("A .chls is converted by Charles after consent, reviewed under its own name, and cleaned up")
    func charlesSessionIsConvertedAfterConsent() async throws {
        let session = try writeTemporaryFile(named: "bug-report.chls", contents: "binary")
        defer { try? FileManager.default.removeItem(at: session.deletingLastPathComponent()) }
        let defaults = try #require(UserDefaults(suiteName: "chls-\(UUID().uuidString)"))
        let runner = ConvertingRunner(har: Self.harJSON)
        let converter = CharlesSessionConverter(runner: runner, locateCharles: { URL(fileURLWithPath: "/bin/echo") })
        let coordinator = MainContentCoordinator()
        var asked = 0

        coordinator.prepareCharlesSessionImport(from: session, converter: converter, defaults: defaults) {
            asked += 1
            return false
        }
        #expect(asked == 1)
        #expect(runner.arguments.isEmpty)
        #expect(!defaults.bool(forKey: MainContentCoordinator.charlesConversionConsentKey))

        coordinator.prepareCharlesSessionImport(from: session, converter: converter, defaults: defaults) {
            asked += 1
            return true
        }
        for _ in 0 ..< 100 where coordinator.importPreview == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let preview = try #require(coordinator.importPreview)
        #expect(asked == 2)
        #expect(defaults.bool(forKey: MainContentCoordinator.charlesConversionConsentKey))
        #expect(runner.arguments.first == ["convert", session.path, preview.sourceURL.path])
        #expect(preview.fileType == .charlesSession)
        #expect(preview.fileName == "bug-report.chls")
        #expect(preview.transactionCount == 1)
        let directory = try #require(preview.temporaryDirectory)
        #expect(FileManager.default.fileExists(atPath: preview.sourceURL.path))

        coordinator.cancelImport()
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        coordinator.prepareCharlesSessionImport(from: session, converter: converter, defaults: defaults) {
            asked += 1
            return true
        }
        #expect(asked == 2)
        for _ in 0 ..< 100 where coordinator.importPreview == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let second = try #require(coordinator.importPreview?.temporaryDirectory)
        coordinator.cancelImport()
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test("Charles conversion failures carry Charles's reason, and a missing Charles is reported")
    func charlesConversionFailures() async {
        let missing = CharlesSessionConverter(runner: ConvertingRunner(har: nil), locateCharles: { nil })
        #expect(!missing.isCharlesInstalled)
        await #expect(throws: CharlesSessionConverterError.charlesNotInstalled) {
            try await missing.convertToHAR(URL(fileURLWithPath: "/tmp/x.chls"))
        }

        let failing = CharlesSessionConverter(
            runner: ConvertingRunner(
                har: nil,
                status: 1,
                log: "INFO Loading Settings\nERROR Unsupported file format\n"
            ),
            locateCharles: { URL(fileURLWithPath: "/bin/echo") }
        )
        await #expect(throws: CharlesSessionConverterError.conversionFailed("ERROR Unsupported file format")) {
            try await failing.convertToHAR(URL(fileURLWithPath: "/tmp/x.chls"))
        }
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

// MARK: - ConvertingRunner

/// Stands in for `Charles convert in out`: writes `har` to the output path.
private final class ConvertingRunner: SimulatorCommandRunning, @unchecked Sendable {
    // MARK: Lifecycle

    init(har: String?, status: Int32 = 0, log: String = "") {
        self.har = har
        self.status = status
        self.log = log
    }

    // MARK: Internal

    var arguments: [[String]] {
        lock.withLock { recorded }
    }

    func run(executable _: URL, arguments: [String]) async throws -> SimulatorCommandOutput {
        lock.withLock { recorded.append(arguments) }
        if let har, arguments.count == 3 {
            try Data(har.utf8).write(to: URL(fileURLWithPath: arguments[2]))
        }
        return SimulatorCommandOutput(status: status, standardOutput: Data(), standardError: Data(log.utf8))
    }

    // MARK: Private

    private let har: String?
    private let status: Int32
    private let log: String
    private let lock = NSLock()
    private var recorded: [[String]] = []
}
