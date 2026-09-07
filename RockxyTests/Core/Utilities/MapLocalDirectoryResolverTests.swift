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

    // MARK: - Root Path / Directory Targets (no index synthesis)

    @Test("Empty suffix (mapped root) does not synthesize index.html and fails to the origin")
    func rootPathDoesNotSynthesizeIndex() {
        // A request for the mapped root (`/static/`) is not rewritten to `index.html`.
        // The resolver returns a failure so the handler forwards the origin.
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case .success:
            Issue.record("Empty suffix must not synthesize an index file")
        case .failure(.fileNotFound):
            break
        case let .failure(other):
            Issue.record("Expected .fileNotFound, got \(other)")
        }
    }

    @Test("Subdirectory target does not synthesize its index.html and fails to the origin")
    func subdirDoesNotSynthesizeIndex() {
        let result = MapLocalDirectoryResolver.resolve(
            requestPath: "/static/subdir/",
            urlPattern: "https://cdn.example.com/static/.*",
            directoryPath: testDir.path
        )
        switch result {
        case .success:
            Issue.record("Directory target must not synthesize an index file")
        case .failure(.fileNotFound):
            break
        case let .failure(other):
            Issue.record("Expected .fileNotFound, got \(other)")
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

    // MARK: - Authored Match Context Resolution

    @Test("Wildcard authored pattern maps the suffix after the authored prefix")
    func wildcardAuthoredSuffix() {
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn.example.com/static/*",
            compiledURLPattern: "https://cdn\\.example\\.com/static/.*",
            matchType: .wildcard,
            includeSubpaths: false
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/static/api/users.json",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "application/json")
            #expect(String(data: file.data, encoding: .utf8)?.contains("Alice") == true)
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Query string is stripped before filesystem resolution")
    func queryStrippedFromSubpath() {
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn.example.com/static/*",
            compiledURLPattern: nil,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/static/js/app.js?v=123&cache=false",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "application/javascript")
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Regex authored pattern uses the first capture group as the subpath")
    func regexCaptureSubpath() {
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn\\.example\\.com/static/(.*)",
            compiledURLPattern: "https://cdn\\.example\\.com/static/(.*)",
            matchType: .regex,
            includeSubpaths: nil
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/static/css/style.css",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "text/css")
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Question-mark wildcard is the prefix boundary and never confuses query or fragment")
    func questionMarkWildcardBoundary() {
        // `?` is a single-character wildcard in authored wildcard syntax and appears before the
        // `*` here, so it is the earliest wildcard boundary — the literal prefix is everything
        // up to it. The request's own query and fragment must be stripped before resolution.
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn.example.com/?*",
            compiledURLPattern: nil,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/api/users.json?v=9&cache=false#section",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "application/json")
            #expect(String(data: file.data, encoding: .utf8)?.contains("Alice") == true)
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Regex capture group strips a trailing query before filesystem resolution")
    func regexCaptureStripsQuery() {
        // A greedy `(.*)` capture swallows the query too; the resolver must strip it so the
        // query never becomes part of the served file path.
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn\\.example\\.com/static/(.*)",
            compiledURLPattern: "https://cdn\\.example\\.com/static/(.*)",
            matchType: .regex,
            includeSubpaths: nil
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/static/js/app.js?v=42",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "application/javascript")
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Invalid regex directory pattern fails so the handler falls back to the origin")
    func invalidRegexDirectoryFails() {
        // An unbalanced group cannot compile; the resolver must fail (never serve) so the
        // caller degrades to the upstream request.
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn.example.com/static/([",
            compiledURLPattern: "https://cdn.example.com/static/([",
            matchType: .regex,
            includeSubpaths: nil
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/static/js/app.js",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case .success:
            Issue.record("Invalid regex must not resolve to a served file")
        case .failure:
            break
        }
    }

    @Test("Regex without a capture group fails safely instead of reinterpreting the request path")
    func regexNoCaptureGroupFailsSafely() {
        // A regex directory mapping without a capture group must fail rather than serve.
        // The handler can then forward the request to the origin.
        // origin. The request path here (`/css/style.css`) maps to a real fixture under the
        // root, so the previous docroot-relative behavior WOULD have served it — this proves
        // that reinterpretation is gone.
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn\\.example\\.com/.*",
            compiledURLPattern: "https://cdn\\.example\\.com/.*",
            matchType: .regex,
            includeSubpaths: nil
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/css/style.css",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case .success:
            Issue.record("No-capture regex must not resolve to a served file")
        case .failure(.fileNotFound):
            break
        case let .failure(other):
            Issue.record("Expected .fileNotFound, got \(other)")
        }
    }

    @Test("Fragment is stripped before filesystem resolution")
    func fragmentStrippedFromSubpath() {
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn.example.com/static/*",
            compiledURLPattern: nil,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/static/css/style.css#section",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "text/css")
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Authored wildcard root request does not synthesize index.html and fails to the origin")
    func wildcardRootDoesNotServeIndex() {
        // The mapped root reached through an authored wildcard behaves the same as the legacy
        // entry point: no implicit index, so the handler falls back to the origin.
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn.example.com/static/*",
            compiledURLPattern: nil,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/static/",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case .success:
            Issue.record("Empty suffix must not synthesize an index file")
        case .failure(.fileNotFound):
            break
        case let .failure(other):
            Issue.record("Expected .fileNotFound, got \(other)")
        }
    }

    @Test("Binary file resolved through a directory mapping is served byte-for-byte")
    func binaryFileServedExactly() {
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn.example.com/static/*",
            compiledURLPattern: nil,
            matchType: .wildcard,
            includeSubpaths: true
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/static/images/logo.png",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case let .success(file):
            #expect(file.mimeType == "image/png")
            #expect(Array(file.data) == [0x89, 0x50, 0x4E, 0x47])
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test("Authored wildcard still blocks path traversal")
    func authoredWildcardBlocksTraversal() {
        let context = MapLocalMatchContext(
            authoredPattern: "https://cdn.example.com/static/*",
            compiledURLPattern: nil,
            matchType: .wildcard,
            includeSubpaths: false
        )
        let result = MapLocalDirectoryResolver.resolve(
            requestURL: "https://cdn.example.com/static/../../../etc/passwd",
            matchContext: context,
            directoryPath: testDir.path
        )
        switch result {
        case .success:
            Issue.record("Expected traversal rejection")
        case .failure(.pathTraversal),
             .failure(.fileNotFound):
            break
        case let .failure(other):
            Issue.record("Expected .pathTraversal or .fileNotFound, got \(other)")
        }
    }

    // MARK: Private

    // MARK: - Test Helpers

    private let testDir: URL
}
