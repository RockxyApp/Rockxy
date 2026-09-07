import Foundation
import os

/// Resolves the bytes a Map Local rule loaded from disk into the status, headers, and body a
/// response should carry. Shared by the plain-HTTP and intercepted-HTTPS handlers (and both the
/// single-file and directory serving paths) so every Map Local response is framed identically.
///
/// Two payload shapes are recognized deterministically:
/// - **Full HTTP response message.** When the file begins with an `HTTP/x.y NNN` status line and
///   parses as a complete message (status line, header lines, blank line, body) the file is
///   authoritative: its valid status, ordered/repeated headers, and body are used. Headers are
///   still run through `MapLocalResponseBuilder`, so
///   framing/hop-by-hop headers are dropped and `Content-Length` is recomputed from the body.
/// - **Raw / binary / empty file.** The whole file is the body and the rule's own status +
///   configured headers apply (again framed through `MapLocalResponseBuilder`).
///
/// Safety precedence: a file that *looks* like an HTTP message (starts with `HTTP/`) but does not
/// parse cleanly — bad status line, a header line without a colon, no terminating blank line
/// within the bounded window, or an out-of-range status — is treated as malformed and the caller
/// falls back to the origin rather than serving a half-parsed or literal-message body. Likewise a
/// raw file whose rule carries an out-of-range status (100...599) falls back to the origin.
enum MapLocalResponseResolver {
    // MARK: Internal

    /// The framed values a Map Local response should serve.
    struct Payload: Equatable {
        /// A validated HTTP status in the range 100...599.
        let statusCode: Int
        /// The reason phrase parsed from a full-message file, or `nil` to let the caller derive
        /// the standard phrase for `statusCode`.
        let statusMessage: String?
        /// Sanitized, framing-safe headers with a recomputed `Content-Length`.
        let headers: [HTTPHeader]
        let body: Data
    }

    enum Outcome: Equatable {
        case serve(Payload)
        case fallbackToOrigin
    }

    /// Returns `true` when `code` is a structurally valid HTTP status code Rockxy is willing to
    /// emit. Imported or programmatically constructed rules are validated here at runtime — the
    /// editor clamp alone cannot cover persistence/import paths.
    static func isValidStatusCode(_ code: Int) -> Bool {
        (100 ... 599).contains(code)
    }

    static func resolve(
        fileData: Data,
        actionStatusCode: Int,
        configuredHeaders: [HTTPHeader],
        inferredContentType: String
    )
        -> Outcome
    {
        switch parseFullMessage(fileData) {
        case let .message(status, reason, headers, body):
            let framed = MapLocalResponseBuilder.responseHeaders(
                configured: headers,
                bodyByteCount: body.count,
                inferredContentType: inferredContentType
            )
            return .serve(Payload(statusCode: status, statusMessage: reason, headers: framed, body: body))
        case .malformed:
            return .fallbackToOrigin
        case .notMessage:
            guard isValidStatusCode(actionStatusCode) else {
                logger.warning("SECURITY: Map local rule carries invalid status \(actionStatusCode); serving origin")
                return .fallbackToOrigin
            }
            let framed = MapLocalResponseBuilder.responseHeaders(
                configured: configuredHeaders,
                bodyByteCount: fileData.count,
                inferredContentType: inferredContentType
            )
            return .serve(Payload(
                statusCode: actionStatusCode,
                statusMessage: nil,
                headers: framed,
                body: fileData
            ))
        }
    }

    // MARK: Private

    private enum ParseResult {
        case notMessage
        case malformed
        case message(status: Int, reason: String?, headers: [HTTPHeader], body: Data)
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "MapLocalResponseResolver"
    )

    private static let messageSignature = Data("HTTP/".utf8)
    /// The header section is scanned only within this many leading bytes; a message whose blank
    /// line does not appear inside it is treated as malformed.
    private static let maxHeaderBlockBytes = 64 * 1_024
    private static let maxHeaderCount = 200

    private static func parseFullMessage(_ data: Data) -> ParseResult {
        guard data.starts(with: messageSignature) else {
            return .notMessage
        }
        guard let boundary = headerBodyBoundary(in: data) else {
            return .malformed
        }
        let headerBlock = data.subdata(in: data.startIndex ..< boundary.headerEnd)
        let body = boundary.bodyStart < data.endIndex
            ? data.subdata(in: boundary.bodyStart ..< data.endIndex)
            : Data()
        guard let headerText = String(data: headerBlock, encoding: .utf8) else {
            return .malformed
        }
        let lines = splitLines(headerText)
        guard let statusLine = lines.first,
              let (status, reason) = parseStatusLine(statusLine),
              isValidStatusCode(status) else
        {
            return .malformed
        }
        let headerLines = lines.dropFirst()
        guard headerLines.count <= maxHeaderCount else {
            return .malformed
        }
        var headers: [HTTPHeader] = []
        for line in headerLines where !line.isEmpty {
            guard let header = parseHeaderLine(line) else {
                return .malformed
            }
            headers.append(header)
        }
        return .message(status: status, reason: reason, headers: headers, body: body)
    }

    /// Locates the first blank line (`\r\n\r\n` or `\n\n`) within the bounded window, returning
    /// the index where the header text ends and where the body begins. Scans raw bytes so binary
    /// bodies are never round-tripped through a `String`.
    private static func headerBodyBoundary(in data: Data) -> (headerEnd: Data.Index, bodyStart: Data.Index)? {
        let limit = min(data.count, maxHeaderBlockBytes)
        guard limit > 0 else {
            return nil
        }
        let start = data.startIndex
        let scanEnd = data.index(start, offsetBy: limit)
        var i = start
        while i < scanEnd {
            let byte = data[i]
            if byte == 0x0A {
                let next = data.index(after: i)
                if next < data.endIndex, data[next] == 0x0A {
                    return (headerEnd: i, bodyStart: data.index(i, offsetBy: 2))
                }
            } else if byte == 0x0D {
                let i1 = data.index(after: i)
                if i1 < data.endIndex, data[i1] == 0x0A {
                    let i2 = data.index(after: i1)
                    if i2 < data.endIndex, data[i2] == 0x0D {
                        let i3 = data.index(after: i2)
                        if i3 < data.endIndex, data[i3] == 0x0A {
                            return (headerEnd: i, bodyStart: data.index(i, offsetBy: 4))
                        }
                    }
                }
            }
            i = data.index(after: i)
        }
        return nil
    }

    private static func splitLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func parseStatusLine(_ line: String) -> (Int, String?)? {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, isValidHTTPVersion(parts[0]) else {
            return nil
        }
        let statusToken = parts[1]
        guard statusToken.count == 3, let status = Int(statusToken) else {
            return nil
        }
        let reason = parts.count >= 3
            ? String(parts[2]).trimmingCharacters(in: .whitespaces)
            : nil
        return (status, (reason?.isEmpty ?? true) ? nil : reason)
    }

    private static func isValidHTTPVersion(_ token: Substring) -> Bool {
        guard token.hasPrefix("HTTP/") else {
            return false
        }
        let version = token.dropFirst("HTTP/".count)
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 2
            && components.allSatisfy { component in
                !component.isEmpty && component.allSatisfy(\.isNumber)
            }
    }

    private static func parseHeaderLine(_ line: String) -> HTTPHeader? {
        guard let colon = line.firstIndex(of: ":") else {
            return nil
        }
        let name = String(line[line.startIndex ..< colon]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return nil
        }
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return HTTPHeader(name: name, value: value)
    }
}
