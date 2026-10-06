import Foundation

// Command-line, Node.js, Java, and Ruby snippets for `CodeSnippetGenerator`.

extension CodeSnippetGenerator {
    static func httpie(_ input: SnippetInput) -> String {
        var command = ["http", "--print=hb", input.method, shellQuoted(input.url)]
        command += input.headers.map { shellQuoted("\($0.name):\($0.value)") }
        switch input.body {
        case let .text(text):
            return "printf '%s' \(shellQuoted(text)) | \(command.joined(separator: " "))"
        case let .binary(byteCount):
            return "# Binary body omitted (\(byteCount) bytes); pipe the file in: http ... < body.bin\n"
                + command.joined(separator: " ")
        case nil:
            return command.joined(separator: " ")
        }
    }

    static func axios(_ input: SnippetInput) -> String {
        var lines = [
            "import axios from \"axios\";",
            "",
            "const response = await axios.request({",
            "  method: \(quoted(input.method)),",
            "  url: \(quoted(input.url)),",
        ]
        if !input.headers.isEmpty {
            lines.append("  headers: {")
            lines += input.headers.map { "    \(quoted($0.name)): \(quoted($0.value))," }
            lines.append("  },")
        }
        switch input.body {
        case let .text(text):
            lines.append("  data: \(quoted(text)),")
        case let .binary(byteCount):
            lines.append("  // Binary body omitted (\(byteCount) bytes); pass a Buffer as `data`.")
        case nil:
            break
        }
        lines += [
            "  // Resolve for every status so error responses print too.",
            "  validateStatus: () => true,",
            "});",
            "console.log(response.status);",
            "console.log(response.data);",
        ]
        return lines.joined(separator: "\n")
    }

    static func java(_ input: SnippetInput) -> String {
        let publisher = switch input.body {
        case let .text(text):
            "HttpRequest.BodyPublishers.ofString(\(quoted(text)))"
        default:
            "HttpRequest.BodyPublishers.noBody()"
        }
        var lines = [
            "import java.net.URI;",
            "import java.net.http.HttpClient;",
            "import java.net.http.HttpRequest;",
            "import java.net.http.HttpResponse;",
            "",
            "public class Main {",
            "    public static void main(String[] args) throws Exception {",
        ]
        if case let .binary(byteCount) = input.body {
            lines.append("        // Binary body omitted (\(byteCount) bytes); use BodyPublishers.ofFile(Path.of(\"body.bin\")).")
        }
        lines += [
            "        HttpRequest request = HttpRequest.newBuilder()",
            "            .uri(URI.create(\(quoted(input.url))))",
        ]
        // HttpClient refuses to let callers set these; it manages them itself.
        let restricted: Set<String> = ["connection", "expect", "upgrade"]
        for header in input.headers where !restricted.contains(header.name.lowercased()) {
            lines.append("            .header(\(quoted(header.name)), \(quoted(header.value)))")
        }
        lines += [
            "            .method(\(quoted(input.method)), \(publisher))",
            "            .build();",
            "        HttpResponse<String> response = HttpClient.newHttpClient()",
            "            .send(request, HttpResponse.BodyHandlers.ofString());",
            "        System.out.println(response.statusCode());",
            "        System.out.println(response.body());",
            "    }",
            "}",
        ]
        return lines.joined(separator: "\n")
    }

    static func ruby(_ input: SnippetInput) -> String {
        var hasBody = false
        var lines = [
            "require \"net/http\"",
            "require \"uri\"",
            "",
            "uri = URI(\(rubyQuoted(input.url)))",
            "http = Net::HTTP.new(uri.host, uri.port)",
            "http.use_ssl = uri.scheme == \"https\"",
        ]
        var bodyLines: [String] = []
        switch input.body {
        case let .text(text):
            hasBody = true
            bodyLines.append("request.body = \(rubyQuoted(text))")
        case let .binary(byteCount):
            hasBody = true
            bodyLines.append("# Binary body omitted (\(byteCount) bytes); use File.binread(\"body.bin\").")
        case nil:
            break
        }
        lines.append(
            "request = Net::HTTPGenericRequest.new(\(rubyQuoted(input.method)), \(hasBody), true, uri.request_uri)"
        )
        lines += input.headers.map { "request[\(rubyQuoted($0.name))] = \(rubyQuoted($0.value))" }
        lines += bodyLines
        lines += ["", "response = http.request(request)", "puts response.code", "puts response.body"]
        return lines.joined(separator: "\n")
    }

    /// POSIX single-quoted word; an embedded quote closes, escapes, and reopens it.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Ruby double-quoted literal; `#{` would otherwise start interpolation.
    static func rubyQuoted(_ value: String) -> String {
        quoted(value).replacingOccurrences(of: "#", with: "\\#")
    }
}
