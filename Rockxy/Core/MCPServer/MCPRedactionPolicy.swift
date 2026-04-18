import Foundation

// MARK: - MCPRedactionState

/// Thread-safe mutable container for the redaction enabled flag. Shared by
/// reference between the coordinator (writer) and query services (readers)
/// so that toggling "Redact Sensitive Data" in Settings takes effect
/// immediately without restarting the MCP server.
final class MCPRedactionState: @unchecked Sendable {
    // MARK: Lifecycle

    init(isEnabled: Bool) {
        _isEnabled = isEnabled
    }

    // MARK: Internal

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isEnabled
    }

    func update(isEnabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _isEnabled = isEnabled
    }

    // MARK: Private

    private let lock = NSLock()
    private var _isEnabled: Bool
}

// MARK: - MCPRedactionPolicy

/// Deterministic redaction policy for sanitising sensitive data in MCP tool
/// responses. Handles HTTP headers, URL query parameters, JSON body fields,
/// and cURL command strings.
struct MCPRedactionPolicy {
    // MARK: Lifecycle

    init(state: MCPRedactionState) {
        self.state = state
    }

    /// Convenience initializer for simple use cases (tests, one-shot queries).
    init(isEnabled: Bool) {
        state = MCPRedactionState(isEnabled: isEnabled)
    }

    // MARK: Internal

    static let sensitiveHeaders: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "www-authenticate",
        "proxy-authenticate",
        "x-api-key",
        "x-auth-token",
        "x-access-token",
        "x-csrf-token",
        "x-xsrf-token",
    ]

    static let sensitiveQueryParams: Set<String> = [
        "api_key",
        "apikey",
        "api-key",
        "token",
        "access_token",
        "auth_token",
        "refresh_token",
        "secret",
        "password",
        "passwd",
        "pwd",
        "private_key",
        "client_secret",
        "key",
    ]

    static let sensitiveBodyKeys: Set<String> = sensitiveQueryParams
        .subtracting(["key"])
        .union([
            "credentials",
            "id_token",
        ])

    let state: MCPRedactionState

    var isEnabled: Bool {
        state.isEnabled
    }

    func redactHeaders(_ headers: [(name: String, value: String)]) -> [(name: String, value: String)] {
        guard isEnabled else {
            return headers
        }
        return headers.map { header in
            if Self.sensitiveHeaders.contains(header.name.lowercased()) {
                return (name: header.name, value: redactedPlaceholder)
            }
            return header
        }
    }

    func redactCodableHeaders(_ headers: [CodableHeader]) -> [CodableHeader] {
        guard isEnabled else {
            return headers
        }
        return headers.map { header in
            if Self.sensitiveHeaders.contains(header.name.lowercased()) {
                return CodableHeader(redactedName: header.name)
            }
            return header
        }
    }

    func redactURL(_ urlString: String) -> String {
        guard isEnabled else {
            return urlString
        }
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }
        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            return urlString
        }

        components.queryItems = queryItems.map { item in
            if Self.sensitiveQueryParams.contains(item.name.lowercased()) {
                return URLQueryItem(name: item.name, value: redactedPlaceholder)
            }
            return item
        }
        return components.string ?? urlString
    }

    func redactBody(_ text: String, contentType: ContentType?) -> String {
        guard isEnabled else {
            return text
        }

        switch contentType {
        case .json:
            return redactJSONBody(text)
        case .form:
            return redactFormBody(text)
        case .xml:
            return redactXMLBody(text)
        default:
            return redactGenericText(text)
        }
    }

    func redactJSONBody(_ body: String) -> String {
        guard isEnabled else {
            return body
        }

        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object)
        {
            let redactedObject = redactJSONObject(object)
            if JSONSerialization.isValidJSONObject(redactedObject),
               let redactedData = try? JSONSerialization.data(withJSONObject: redactedObject),
               let redactedBody = String(data: redactedData, encoding: .utf8)
            {
                return redactedBody
            }
        }

        var result = body
        result = applyRegex(bodyTokenPattern, to: result)
        result = applyRegex(bodySecretPattern, to: result)
        return result
    }

    func redactFormBody(_ body: String) -> String {
        guard isEnabled else {
            return body
        }
        let pairs = body.components(separatedBy: "&")
        let redacted = pairs.map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                return pair
            }
            let key = String(parts[0])
            let decodedKey = key.removingPercentEncoding ?? key
            if Self.sensitiveQueryParams.contains(decodedKey.lowercased()) {
                return "\(key)=\(redactedPlaceholder)"
            }
            return pair
        }
        return redacted.joined(separator: "&")
    }

    func redactXMLBody(_ body: String) -> String {
        guard isEnabled else {
            return body
        }
        let range = NSRange(body.startIndex ..< body.endIndex, in: body)
        return Self.xmlSensitivePatternRegex.stringByReplacingMatches(
            in: body,
            range: range,
            withTemplate: "<$1>[REDACTED]</"
        )
    }

    func redactGenericText(_ body: String) -> String {
        guard isEnabled else {
            return body
        }
        var result = body
        let range = NSRange(result.startIndex ..< result.endIndex, in: result)
        result = Self.genericBearerPatternRegex.stringByReplacingMatches(
            in: result,
            range: range,
            withTemplate: "$1[REDACTED]"
        )
        let range2 = NSRange(result.startIndex ..< result.endIndex, in: result)
        result = Self.genericKeyValuePatternRegex.stringByReplacingMatches(
            in: result,
            range: range2,
            withTemplate: "$1[REDACTED]"
        )
        return result
    }

    func redactCurlCommand(_ curl: String) -> String {
        guard isEnabled else {
            return curl
        }
        var result = curl
        result = applyRegex(
            curlHeaderPattern,
            to: result,
            replacement: "-H $1$2: \(redactedPlaceholder)$1"
        )
        return result
    }

    // MARK: Private

    // swiftlint:disable force_try
    private static let jsonScalarPattern =
        #""(?:\\.|[^"\\])*"|true|false|null|-?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?"#

    private static let bodyTokenPatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"("(?:token|access_token|auth_token|refresh_token|id_token|api_key|apikey|api_token)")\s*:\s*\#(jsonScalarPattern)"#,
        options: [.caseInsensitive]
    )

    private static let bodySecretPatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"("(?:password|passwd|pwd|secret|client_secret|private_key|credentials)")\s*:\s*\#(jsonScalarPattern)"#,
        options: [.caseInsensitive]
    )

    private static let curlHeaderPatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"-H\s+(['"])(\#(sensitiveHeaderAlternation))\s*:\s*[^'"]*\1"#,
        options: [.caseInsensitive]
    )

    private static let xmlSensitivePatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: """
        <(password|passwd|secret|token|access_token|api_key|apikey\
        |client_secret|private_key|credentials)>([^<]*)</
        """,
        options: [.caseInsensitive]
    )

    private static let genericBearerPatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(Bearer\s+)\S+"#,
        options: [.caseInsensitive]
    )

    private static let genericKeyValuePatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(?i)((?:password|passwd|secret|token|api_key|apikey)[\s]*[:=][\s]*)\S+"#,
        options: []
    )
    // swiftlint:enable force_try

    private static let sensitiveHeaderAlternation: String = sensitiveHeaders
        .map { NSRegularExpression.escapedPattern(for: $0) }
        .joined(separator: "|")

    private let redactedPlaceholder = "[REDACTED]"

    private var bodyTokenPattern: NSRegularExpression {
        Self.bodyTokenPatternRegex
    }

    private var bodySecretPattern: NSRegularExpression {
        Self.bodySecretPatternRegex
    }

    private var curlHeaderPattern: NSRegularExpression {
        Self.curlHeaderPatternRegex
    }

    private func redactJSONObject(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            let entries: [(String, Any)] = dictionary.map { element in
                let (key, value) = element
                if Self.sensitiveBodyKeys.contains(key.lowercased()) {
                    return (key, redactedPlaceholder)
                }
                return (key, redactJSONObject(value))
            }
            return Dictionary(uniqueKeysWithValues: entries)
        }

        if let array = object as? [Any] {
            return array.map { redactJSONObject($0) }
        }

        return object
    }

    private func applyRegex(
        _ regex: NSRegularExpression,
        to input: String,
        replacement: String? = nil
    )
        -> String
    {
        let range = NSRange(input.startIndex ..< input.endIndex, in: input)
        return regex.stringByReplacingMatches(
            in: input,
            range: range,
            withTemplate: replacement ?? "$1: \"\(redactedPlaceholder)\""
        )
    }
}

// MARK: - CodableHeader + Redaction

private extension CodableHeader {
    init(redactedName name: String) {
        self.init(from: HTTPHeader(name: name, value: "[REDACTED]"))
    }
}
