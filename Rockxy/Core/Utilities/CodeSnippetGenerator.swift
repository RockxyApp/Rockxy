import Foundation

// Renders a captured request as a ready-to-run client snippet in common languages.

// MARK: - CodeSnippetLanguage

enum CodeSnippetLanguage: String, CaseIterable, Identifiable, Sendable {
    case swiftURLSession
    case pythonRequests
    case javaScriptFetch
    case goNetHTTP
    case httpie
    case nodeAxios
    case javaHttpClient
    case rubyNetHTTP

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .swiftURLSession:
            String(localized: "Swift (URLSession)", bundle: RockxyLocalization.bundle)
        case .pythonRequests:
            String(localized: "Python (requests)", bundle: RockxyLocalization.bundle)
        case .javaScriptFetch:
            String(localized: "JavaScript (fetch)", bundle: RockxyLocalization.bundle)
        case .goNetHTTP:
            String(localized: "Go (net/http)", bundle: RockxyLocalization.bundle)
        case .httpie:
            "HTTPie"
        case .nodeAxios:
            String(localized: "Node.js (axios)", bundle: RockxyLocalization.bundle)
        case .javaHttpClient:
            String(localized: "Java (HttpClient)", bundle: RockxyLocalization.bundle)
        case .rubyNetHTTP:
            String(localized: "Ruby (Net::HTTP)", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - CodeSnippetGenerator

/// Turns a captured request into source that reproduces it. Transport-managed headers
/// (`Host`, `Content-Length`, `Proxy-*`) are left out because every client library derives
/// them itself; a binary body is replaced by a comment so the snippet still compiles.
enum CodeSnippetGenerator {
    // MARK: Internal

    static func snippet(for request: HTTPRequestData, language: CodeSnippetLanguage) -> String {
        let headers = request.headers.filter { !RequestReplay.isTransportManagedHeader($0.name) }
        let body = request.body.map { data -> SnippetBody in
            if let text = String(data: data, encoding: .utf8) {
                return .text(text)
            }
            return .binary(byteCount: data.count)
        }
        let input = SnippetInput(
            method: request.method.uppercased(),
            url: request.url.absoluteString,
            headers: headers.map { (name: $0.name, value: $0.value) },
            body: body
        )
        switch language {
        case .swiftURLSession:
            return swift(input)
        case .pythonRequests:
            return python(input)
        case .javaScriptFetch:
            return javaScript(input)
        case .goNetHTTP:
            return go(input)
        case .httpie:
            return httpie(input)
        case .nodeAxios:
            return axios(input)
        case .javaHttpClient:
            return java(input)
        case .rubyNetHTTP:
            return ruby(input)
        }
    }

    // MARK: Private

    enum SnippetBody {
        case text(String)
        case binary(byteCount: Int)
    }

    struct SnippetInput {
        let method: String
        let url: String
        let headers: [(name: String, value: String)]
        let body: SnippetBody?
    }

    private static func swift(_ input: SnippetInput) -> String {
        var lines = [
            "import Foundation",
            "",
            "var request = URLRequest(url: URL(string: \(swiftQuoted(input.url)))!)",
            "request.httpMethod = \(swiftQuoted(input.method))",
        ]
        for header in input.headers {
            lines
                .append(
                    "request.setValue(\(swiftQuoted(header.value)), forHTTPHeaderField: \(swiftQuoted(header.name)))"
                )
        }
        switch input.body {
        case let .text(text):
            lines.append("request.httpBody = Data(\(swiftQuoted(text)).utf8)")
        case let .binary(byteCount):
            // Generated source code, not UI: the exact byte count is what a developer pasting
            // this needs, so it is deliberately not grouped, scaled, or localized.
            lines.append("// Binary body omitted (\(byteCount) bytes). Load it from a file:")
            lines.append("// request.httpBody = try Data(contentsOf: URL(fileURLWithPath: \"body.bin\"))")
        case nil:
            break
        }
        lines.append(contentsOf: [
            "",
            "let (data, response) = try await URLSession.shared.data(for: request)",
            "print((response as? HTTPURLResponse)?.statusCode ?? 0)",
            "print(String(decoding: data, as: UTF8.self))",
        ])
        return lines.joined(separator: "\n")
    }

    private static func python(_ input: SnippetInput) -> String {
        var lines = ["import requests", ""]
        if input.headers.isEmpty {
            lines.append("headers = {}")
        } else {
            lines.append("headers = {")
            for header in input.headers {
                lines.append("    \(pythonQuoted(header.name)): \(pythonQuoted(header.value)),")
            }
            lines.append("}")
        }
        var arguments = ["headers=headers"]
        switch input.body {
        case let .text(text):
            lines.append("data = \(pythonQuoted(text))")
            arguments.append("data=data")
        case let .binary(byteCount):
            lines.append("# Binary body omitted (\(byteCount) bytes). Load it from a file:")
            lines.append("# data = open(\"body.bin\", \"rb\").read()")
        case nil:
            break
        }
        lines.append(contentsOf: [
            "",
            "response = requests.request(\(pythonQuoted(input.method)), \(pythonQuoted(input.url)), \(arguments.joined(separator: ", ")))",
            "print(response.status_code)",
            "print(response.text)",
        ])
        return lines.joined(separator: "\n")
    }

    private static func javaScript(_ input: SnippetInput) -> String {
        var lines = ["const response = await fetch(\(quoted(input.url)), {", "  method: \(quoted(input.method)),"]
        if !input.headers.isEmpty {
            lines.append("  headers: {")
            for header in input.headers {
                lines.append("    \(quoted(header.name)): \(quoted(header.value)),")
            }
            lines.append("  },")
        }
        switch input.body {
        case let .text(text):
            lines.append("  body: \(quoted(text)),")
        case let .binary(byteCount):
            lines.append("  // Binary body omitted (\(byteCount) bytes); pass a Blob or ArrayBuffer as `body`.")
        case nil:
            break
        }
        lines.append(contentsOf: [
            "});",
            "console.log(response.status);",
            "console.log(await response.text());",
        ])
        return lines.joined(separator: "\n")
    }

    private static func go(_ input: SnippetInput) -> String {
        var imports = ["\"fmt\"", "\"io\"", "\"net/http\""]
        var bodyExpression = "nil"
        var bodyLines: [String] = []
        switch input.body {
        case let .text(text):
            imports.append("\"strings\"")
            bodyLines.append("\tbody := strings.NewReader(\(quoted(text)))")
            bodyExpression = "body"
        case let .binary(byteCount):
            bodyLines.append("\t// Binary body omitted (\(byteCount) bytes); open the file and pass it as the body.")
        case nil:
            break
        }
        var lines = ["package main", "", "import ("]
        for name in imports.sorted() {
            lines.append("\t\(name)")
        }
        lines.append(contentsOf: [")", "", "func main() {"])
        lines.append(contentsOf: bodyLines)
        lines.append("\treq, err := http.NewRequest(\(quoted(input.method)), \(quoted(input.url)), \(bodyExpression))")
        lines.append(contentsOf: ["\tif err != nil {", "\t\tpanic(err)", "\t}"])
        for header in input.headers {
            lines.append("\treq.Header.Set(\(quoted(header.name)), \(quoted(header.value)))")
        }
        lines.append(contentsOf: [
            "",
            "\tresp, err := http.DefaultClient.Do(req)",
            "\tif err != nil {",
            "\t\tpanic(err)",
            "\t}",
            "\tdefer resp.Body.Close()",
            "\tdata, _ := io.ReadAll(resp.Body)",
            "\tfmt.Println(resp.StatusCode)",
            "\tfmt.Println(string(data))",
            "}",
        ])
        return lines.joined(separator: "\n")
    }

    /// Double-quoted literal with C-style escapes. Swift spells unicode escapes as `\u{XXXX}`;
    /// JavaScript, Go, and Python use `\uXXXX`.
    static func quoted(_ value: String, swiftUnicodeEscapes: Bool = false) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if scalar.value < 0x20 {
                    escaped += swiftUnicodeEscapes
                        ? String(format: "\\u{%04X}", scalar.value)
                        : String(format: "\\u%04X", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return "\"\(escaped)\""
    }

    private static func swiftQuoted(_ value: String) -> String {
        quoted(value, swiftUnicodeEscapes: true)
    }

    private static func pythonQuoted(_ value: String) -> String {
        quoted(value)
    }
}
