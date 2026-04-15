import Foundation
@testable import Rockxy
import Testing

struct ScriptResponseBodyLoaderTests {
    @Test("Symlink under home cannot escape the home-directory sandbox")
    func symlinkEscapeRejected() throws {
        let targetURL = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("rockxy-body-\(UUID().uuidString).txt")
        let symlinkURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("rockxy-body-link-\(UUID().uuidString)")

        try Data("outside".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)
        defer {
            try? FileManager.default.removeItem(at: symlinkURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        #expect(throws: ScriptResponseBodyLoader.LoadError.self) {
            _ = try ScriptResponseBodyLoader.load(path: symlinkURL.path, limit: 1_024)
        }
    }
}
