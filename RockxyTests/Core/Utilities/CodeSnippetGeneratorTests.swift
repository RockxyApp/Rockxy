import Foundation
@testable import Rockxy
import Testing

// MARK: - CodeSnippetGeneratorTests

struct CodeSnippetGeneratorTests {
    // MARK: Internal

    @Test("Every language reproduces method, URL, headers, and body")
    func snippetsCarryTheRequest() throws {
        let request = try makeRequest()

        // HTTPie is a shell command: single quotes carry the text verbatim (tested separately).
        for language in CodeSnippetLanguage.allCases where language != .httpie {
            let snippet = CodeSnippetGenerator.snippet(for: request, language: language)
            #expect(snippet.contains("https://api.example.com/items?page=2"), "\(language)")
            #expect(snippet.contains("POST"), "\(language)")
            #expect(snippet.contains("X-Trace"), "\(language)")
            #expect(snippet.contains("Bearer token\\\"quoted\\\""), "\(language) must escape quotes")
            #expect(snippet.contains(#"{\"name\":\"rockxy\"}"#), "\(language)")
            // Transport-managed headers are derived by every client library.
            #expect(!snippet.contains("Content-Length"), "\(language)")
            #expect(!snippet.contains("Proxy-Connection"), "\(language)")
            #expect(!snippet.contains("\"Host\""), "\(language)")
        }
    }

    @Test("Binary bodies become a comment instead of an invalid literal")
    func binaryBodyIsCommented() throws {
        var request = try makeRequest()
        request.body = Data([0xFF, 0xFE, 0x00, 0x01])

        for language in CodeSnippetLanguage.allCases {
            let snippet = CodeSnippetGenerator.snippet(for: request, language: language)
            #expect(snippet.contains("Binary body omitted (4 bytes)"), "\(language)")
            #expect(!snippet.contains("\u{FFFD}"), "\(language)")
        }
    }

    @Test("Swift uses brace unicode escapes, other languages use the bare form")
    func controlCharacterEscapes() throws {
        var request = try makeRequest()
        request.body = Data([0x61, 0x01, 0x62]) // "a", U+0001, "b"

        let swift = CodeSnippetGenerator.snippet(for: request, language: .swiftURLSession)
        #expect(swift.contains(#"a\u{0001}b"#))
        let js = CodeSnippetGenerator.snippet(for: request, language: .javaScriptFetch)
        #expect(js.contains(#"a\u0001b"#))
    }

    @Test("Python snippet is syntactically valid")
    func pythonSnippetParses() throws {
        let snippet = try CodeSnippetGenerator.snippet(for: makeRequest(), language: .pythonRequests)
        try Self.expectToolAccepts(
            executable: "/usr/bin/python3",
            arguments: { ["-m", "py_compile", $0] },
            source: snippet,
            fileExtension: "py"
        )
    }

    @Test("Swift snippet type-checks")
    func swiftSnippetTypeChecks() throws {
        let snippet = try CodeSnippetGenerator.snippet(for: makeRequest(), language: .swiftURLSession)
        try Self.expectToolAccepts(
            executable: "/usr/bin/swiftc",
            arguments: { ["-typecheck", $0] },
            source: snippet,
            fileExtension: "swift"
        )
    }

    @Test("HTTPie command quotes every word for the shell")
    func httpieQuotesForShell() throws {
        var request = try makeRequest()
        request.headers.append(HTTPHeader(name: "X-Note", value: "it's"))
        let snippet = CodeSnippetGenerator.snippet(for: request, language: .httpie)
        #expect(snippet.hasPrefix(#"printf '%s' '{"name":"rockxy"}' | http --print=hb POST 'https://api.example.com/items?page=2'"#))
        #expect(snippet.contains(#"'X-Note:it'\''s'"#))
        #expect(!snippet.contains("Content-Length"))
        try Self.expectToolAccepts(executable: "/bin/sh", arguments: { ["-n", $0] }, source: snippet, fileExtension: "sh")
    }

    @Test("Ruby snippet parses and does not interpolate #{…} from the captured data")
    func rubySnippetParses() throws {
        var request = try makeRequest()
        request.body = Data(##"{"q":"#{system('x')}"}"##.utf8)
        let snippet = CodeSnippetGenerator.snippet(for: request, language: .rubyNetHTTP)
        #expect(snippet.contains(##"\#{system"##))
        try Self.expectToolAccepts(
            executable: "/opt/homebrew/bin/ruby",
            arguments: { ["-c", $0] },
            source: snippet,
            fileExtension: "rb"
        )
    }

    @Test("Node.js axios snippet parses as an ES module")
    func axiosSnippetParses() throws {
        let snippet = try CodeSnippetGenerator.snippet(for: makeRequest(), language: .nodeAxios)
        let node = ProcessInfo.processInfo.environment["NODE_BINARY"] ?? "/usr/local/bin/node"
        try Self.expectToolAccepts(executable: node, arguments: { ["--check", $0] }, source: snippet, fileExtension: "mjs")
    }

    @Test("Java snippet leaves out headers HttpClient refuses")
    func javaSkipsRestrictedHeaders() throws {
        var request = try makeRequest()
        request.headers.append(HTTPHeader(name: "Connection", value: "keep-alive"))
        let snippet = CodeSnippetGenerator.snippet(for: request, language: .javaHttpClient)
        #expect(!snippet.contains("\"Connection\""))
        #expect(snippet.contains(#".method("POST", HttpRequest.BodyPublishers.ofString("#))
    }

    // MARK: Private

    /// Writes `source` to a temp file and runs the toolchain's syntax/type check over it.
    /// Skips silently when the tool is not installed on the machine running the tests.
    private static func expectToolAccepts(
        executable: String,
        arguments: (String) -> [String],
        source: String,
        fileExtension: String
    )
        throws
    {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippet-\(UUID().uuidString).\(fileExtension)")
        try source.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments(file.path)
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(executable) rejected the generated snippet")
    }

    private func makeRequest() throws -> HTTPRequestData {
        try HTTPRequestData(
            method: "post",
            url: #require(URL(string: "https://api.example.com/items?page=2")),
            httpVersion: "HTTP/1.1",
            headers: [
                HTTPHeader(name: "Host", value: "api.example.com"),
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Content-Length", value: "17"),
                HTTPHeader(name: "Proxy-Connection", value: "Keep-Alive"),
                HTTPHeader(name: "Authorization", value: "Bearer token\"quoted\""),
                HTTPHeader(name: "X-Trace", value: "t1"),
            ],
            body: Data(#"{"name":"rockxy"}"#.utf8),
            contentType: .json
        )
    }
}
