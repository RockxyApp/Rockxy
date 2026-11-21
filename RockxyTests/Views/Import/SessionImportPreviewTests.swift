import Foundation
@testable import Rockxy
import Testing

/// The session preview used to be built with a synchronous `Data(contentsOf:)` and a full decode
/// on the `@MainActor` coordinator, for a file bounded only by `ImportSizePolicy`'s 200 MB. These
/// run the extracted builder from a detached task, which is the shape the fix depends on: if it
/// were still main-actor-isolated these would not compile.
struct SessionImportPreviewTests {
    // MARK: Internal

    @Test("a preview is built off the main actor from the file's own metadata")
    func buildsPreviewOffTheMainActor() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(60)
        let data = try SessionSerializer.serialize(
            transactions: [],
            metadata: SessionSerializer.makeMetadata(
                transactionCount: 0, captureStartDate: start, captureEndDate: end
            )
        )
        let url = try Self.write(data, extension: "rockxysession")
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try await Task.detached {
            try MainContentCoordinator.makeSessionPreview(from: url)
        }.value

        #expect(preview.fileName == url.lastPathComponent)
        #expect(preview.fileType == .rockxysession)
        #expect(preview.transactionCount == 0)
        #expect(preview.logEntryCount == 0)
        #expect(preview.fileSize == Int64(data.count))
        #expect(preview.captureStartDate == start)
        #expect(preview.captureEndDate == end)
        #expect(preview.sourceURL == url)
    }

    @Test("an unreadable session still surfaces a serializer error for the sheet to report")
    func reportsSerializerFailure() async throws {
        let url = try Self.write(Data("not a session".utf8), extension: "rockxysession")
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: SessionSerializerError.self) {
            try await Task.detached {
                try MainContentCoordinator.makeSessionPreview(from: url)
            }.value
        }
    }

    @Test("the inline parse threshold matches the HAR sibling it was aligned with")
    func inlineThresholdMatchesTheHARSibling() {
        #expect(MainContentCoordinator.inlineSessionParseLimit == MainContentCoordinator.inlineHARParseLimit)
    }

    // MARK: Private

    private static func write(_ data: Data, extension pathExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-preview-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        try data.write(to: url)
        return url
    }
}
