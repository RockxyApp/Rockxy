import Foundation
@testable import Rockxy
import Testing

// Regression tests for `MapLocalDirectoryResolver` in the core utilities layer.

struct MapLocalDirectoryResolverTests {
    // MARK: Lifecycle

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalDir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        try Data("<!DOCTYPE html><html></html>".utf8).write(to: base.appendingPathComponent("index.html"))

        let apiDir = base.appendingPathComponent("api")
        try FileManager.default.createDirectory(at: apiDir, withIntermediateDirectories: true)
        try Data(#"[{"id":1,"name":"Alice"}]"#.utf8).write(to: apiDir.appendingPathComponent("users.json"))

        let jsDir = base.appendingPathComponent("js")
        try FileManager.default.createDirectory(at: jsDir, withIntermediateDirectories: true)
        try Data("console.log('app');".utf8).write(to: jsDir.appendingPathComponent("app.js"))

        let cssDir = base.appendingPathComponent("css")
        try FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true)
        try Data("body { margin: 0; }".utf8).write(to: cssDir.appendingPathComponent("style.css"))

        let imgDir = base.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imgDir.appendingPathComponent("logo.png"))

        let subDir = base.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try Data("<html>subdir</html>".utf8).write(to: subDir.appendingPathComponent("index.html"))

        testDir = base
    }

    // MARK: Internal

    // MARK: - Basic Path Resolution

    @Test("Resolves nested file path")
    func resolvesNestedFile() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/api/users.json",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "application/json")
            let content = String(data: file.data, encoding: .utf8)
            #expect(content?.contains("Alice") == true)
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Resolves JS file with correct MIME type")
    func resolvesJSFile() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/assets/js/app.js",
            urlPattern: "https://example.com/assets/.*",
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "application/javascript")
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Resolves CSS file with correct MIME type")
    func resolvesCSSFile() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/css/style.css",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "text/css")
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Resolves PNG file with correct MIME type")
    func resolvesPNGFile() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/images/logo.png",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "image/png")
            #expect(file.data.count == 4)
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    // MARK: - Root Path / Index Fallback

    @Test("Root path falls back to index.html")
    func rootPathFallback() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "text/html")
            let content = String(data: file.data, encoding: .utf8)
            #expect(content?.contains("<!DOCTYPE html>") == true)
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Subdirectory path falls back to its index.html")
    func subdirIndexFallback() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/subdir/",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "text/html")
            let content = String(data: file.data, encoding: .utf8)
            #expect(content?.contains("subdir") == true)
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    // MARK: - Security: Path Traversal

    @Test("Rejects path traversal with ..")
    func rejectsPathTraversal() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/../../../etc/passwd",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case .success:
            Issue.record("Expected path traversal rejection")
        case let .failure(error):
            if case .pathTraversal = error {
                // Expected
            } else {
                Issue.record("Expected .pathTraversal, got \(error)")
            }
        }
    }

    @Test("Rejects encoded path traversal")
    func rejectsEncodedTraversal() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/%2e%2e/%2e%2e/etc/passwd",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case .failure(.pathTraversal):
            break
        case let .failure(other):
            Issue.record("Expected .pathTraversal but got \(other)")
        case .success:
            Issue.record("Expected rejection for encoded traversal attack")
        }
    }

    // MARK: - Missing Files

    @Test("Returns fileNotFound for missing file")
    func missingFile() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/nonexistent.js",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case .success:
            Issue.record("Expected fileNotFound error")
        case let .failure(error):
            if case .fileNotFound = error {
                // expected
            } else {
                Issue.record("Expected fileNotFound, got \(error)")
            }
        }
    }

    @Test("Returns directoryNotFound for nonexistent directory")
    func missingDirectory() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/file.js",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: "/nonexistent/directory/path"
        )
        switch result {
        case .success:
            Issue.record("Expected directoryNotFound error")
        case let .failure(error):
            if case .directoryNotFound = error {
                // expected
            } else {
                Issue.record("Expected directoryNotFound, got \(error)")
            }
        }
    }

    // MARK: - MIME Type Detection

    @Test("Detects common MIME types from file extensions")
    func mimeTypeDetection() {
        let htmlResult = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/index.html",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        if case let .success(file) = htmlResult {
            #expect(file.mimeType == "text/html")
        }

        let jsonResult = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/api/users.json",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        if case let .success(file) = jsonResult {
            #expect(file.mimeType == "application/json")
        }
    }

    // MARK: - Symlink Resolution

    @Test("Resolves symlinks within directory root")
    func symlinkWithinRoot() throws {
        let linkPath = testDir.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(
            at: linkPath,
            withDestinationURL: testDir.appendingPathComponent("api/users.json")
        )

        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/link.json",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "application/json")
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    // MARK: - Security: Sibling Prefix Escape

    @Test("Sibling directory with shared prefix is rejected")
    func siblingPrefixRejected() throws {
        let evil = URL(fileURLWithPath: testDir.path + "-evil")
        try FileManager.default.createDirectory(at: evil, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: evil) }

        let evilFile = evil.appendingPathComponent("secret.txt")
        try "secret".write(to: evilFile, atomically: true, encoding: .utf8)

        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/-evil/secret.txt",
            urlPattern: "/*",
            directoryPath: testDir.path
        )
        // Sibling prefix must be rejected. The resolver should detect that the resolved path
        // is outside the root directory via the trailing-slash containment check. If the subpath
        // extraction yields a path that doesn't exist inside the root, fileNotFound is the expected
        // safe outcome. pathTraversal is also acceptable if the containment check catches it first.
        // Both are safe — the key assertion is that .success never occurs.
        switch result {
        case .success:
            Issue.record("Sibling prefix escape should be rejected — file must not be served")
        case .failure(.pathTraversal):
            break
        case .failure(.fileNotFound):
            break
        case let .failure(other):
            Issue.record("Expected .pathTraversal or .fileNotFound, got \(other)")
        }
    }

    @Test("Sibling prefix via symlink is rejected")
    func siblingPrefixSymlinkRejected() throws {
        let evil = URL(fileURLWithPath: testDir.path + "-evil")
        try FileManager.default.createDirectory(at: evil, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: evil) }

        let secretFile = evil.appendingPathComponent("secret.txt")
        try "secret".write(to: secretFile, atomically: true, encoding: .utf8)

        let symlink = testDir.appendingPathComponent("escape-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: secretFile)

        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/escape-link",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        // Symlink points outside root. pathTraversal is the intended result from the loadFile
        // containment check. fileNotFound is also safe if the symlink resolution changes behavior.
        switch result {
        case .success:
            Issue.record("Symlink to sibling directory should be rejected — file must not be served")
        case .failure(.pathTraversal):
            break
        case .failure(.fileNotFound):
            break
        case let .failure(other):
            Issue.record("Expected .pathTraversal or .fileNotFound, got \(other)")
        }
    }

    // MARK: - File Size Limit

    @Test("Rejects files larger than 10 MB")
    func fileSizeLimit() throws {
        let largeFile = testDir.appendingPathComponent("large.bin")
        let data = Data(count: 11 * 1_024 * 1_024)
        try data.write(to: largeFile)

        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/large.bin",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case .success:
            Issue.record("Expected fileTooLarge error")
        case let .failure(error):
            if case .fileTooLarge = error {
                // expected
            } else {
                Issue.record("Expected fileTooLarge, got \(error)")
            }
        }
    }

    // MARK: Private

    // MARK: - Test Helpers

    private let testDir: URL
}
