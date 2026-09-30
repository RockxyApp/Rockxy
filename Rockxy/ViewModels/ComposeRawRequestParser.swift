import Foundation

// MARK: - ComposeRawRequest

/// A raw HTTP/1.1 request as typed in Compose's Raw tab.
struct ComposeRawRequest: Equatable {
    let method: String
    let url: String
    let headers: [(name: String, value: String)]
    let body: String

    static func == (lhs: ComposeRawRequest, rhs: ComposeRawRequest) -> Bool {
        lhs.method == rhs.method && lhs.url == rhs.url && lhs.body == rhs.body
            && lhs.headers.map(\.name) == rhs.headers.map(\.name)
            && lhs.headers.map(\.value) == rhs.headers.map(\.value)
    }
}

// MARK: - ComposeRawRequestError

enum ComposeRawRequestError: LocalizedError, Equatable {
    case missingRequestLine
    case missingHost
    case malformedHeader(String)

    var errorDescription: String? {
        switch self {
        case .missingRequestLine:
            String(
                localized: "The first line must be a request line, such as GET /path HTTP/1.1.",
                bundle: RockxyLocalization.bundle
            )
        case .missingHost:
            String(
                localized: "Add a Host header or use a full URL in the request line.",
                bundle: RockxyLocalization.bundle
            )
        case let .malformedHeader(line):
            String(localized: "This header has no colon: \(line)", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ComposeRawRequestParser

enum ComposeRawRequestParser {
    /// Parses "METHOD target HTTP/x" + headers + blank line + body. A path-only target is
    /// joined with the Host header and `defaultScheme`; the Host header itself is dropped
    /// because the client derives it from the URL.
    static func parse(_ text: String, defaultScheme: String) throws -> ComposeRawRequest {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        guard let requestLine = lines.first else {
            throw ComposeRawRequestError.missingRequestLine
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].allSatisfy({ $0.isLetter }) else {
            throw ComposeRawRequestError.missingRequestLine
        }
        let method = parts[0].uppercased()
        let target = String(parts[1])

        var headers: [(name: String, value: String)] = []
        var host: String?
        var index = 1
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            let line = lines[index]
            guard let colon = line.firstIndex(of: ":") else {
                throw ComposeRawRequestError.malformedHeader(line)
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name.caseInsensitiveCompare("Host") == .orderedSame {
                host = value
            } else {
                headers.append((name, value))
            }
            index += 1
        }
        let body = index + 1 < lines.count ? lines[(index + 1)...].joined(separator: "\n") : ""

        let url: String
        if target.lowercased().hasPrefix("http://") || target.lowercased().hasPrefix("https://") {
            url = target
        } else {
            guard let host, !host.isEmpty else {
                throw ComposeRawRequestError.missingHost
            }
            url = "\(defaultScheme)://\(host)\(target.hasPrefix("/") ? target : "/" + target)"
        }
        return ComposeRawRequest(method: method, url: url, headers: headers, body: body)
    }
}

// MARK: - ComposeViewModel + Raw

extension ComposeViewModel {
    /// Replaces method, URL, headers, and body with the edited raw request.
    func applyRawRequest(_ text: String) throws {
        let scheme = URL(string: url)?.scheme?.lowercased() ?? "https"
        let parsed = try ComposeRawRequestParser.parse(text, defaultScheme: scheme)
        method = parsed.method
        url = parsed.url
        headers = parsed.headers.map { EditableReplayHeader(name: $0.name, value: $0.value) }
        // An untouched body keeps a binary or truncated source's guard in place.
        if parsed.body != body {
            replaceUnavailableBody(with: parsed.body)
        }
        syncURLToQuery(force: true)
        syncUnsupportedState()
    }
}
