import Foundation

// Values for custom table columns that read a query parameter or a JSON body.

// MARK: - CustomColumnValueResolver

enum CustomColumnValueResolver {
    // MARK: Internal

    /// Bodies larger than this are not parsed for a column.
    static let maxBodySize = 2 * 1_024 * 1_024
    /// Longest text shown in a cell.
    static let maxDisplayLength = 300
    /// UTF-8 bytes retained by a cell before its truncation marker. A single grapheme
    /// can contain arbitrarily many combining scalars despite the character cap.
    static let maxDisplayBytes = 8_192

    static func queryValue(named name: String, in url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.first { $0.name == name }?.value ?? ""
    }

    /// Evaluates `expression` against a transaction's JSON body. The result is cached on the
    /// transaction until its request or response evidence changes.
    static func bodyValue(expression: String, response: Bool, transaction: HTTPTransaction) -> String {
        let cacheKey = (response ? "res:" : "req:") + expression
        if let cached = transaction.customColumnValueCache.value(for: cacheKey) {
            return cached
        }
        let body: Data? = response
            ? transaction.response.flatMap { $0.decodedBody(limit: maxBodySize) ?? $0.body }
            : transaction.request.body
        let value = body.map { evaluate(expression, on: $0) } ?? ""
        transaction.customColumnValueCache.store(value, for: cacheKey)
        return value
    }

    /// Evaluates JSONPath (starting with `$`) or a jq filter against JSON `data`. Anything that
    /// is not JSON, fails, or matches nothing shows as an empty cell.
    static func evaluate(_ expression: String, on data: Data) -> String {
        guard data.count <= maxBodySize, looksLikeJSON(data) else {
            return ""
        }
        if expression.hasPrefix("$") {
            guard let document = try? JSONPathDocument(data: data),
                  let result = try? JSONPathEvaluator(document: document).evaluate(expression) else
            {
                return ""
            }
            return displayValue(result.matches.lazy.map(\.scalarDescription))
        } else {
            guard let filter = try? JQFilter(expression),
                  let output = try? filter.run(JQValue.parse(data), limits: columnLimits) else
            {
                return ""
            }
            return displayValue(output.values.lazy.map { value in
                if case let .string(text) = value {
                    return text
                }
                return value.jsonText()
            })
        }
    }

    // MARK: Private

    private static let columnLimits = JQLimits(maxSteps: 200_000, maxOutputs: 50, maxDepth: 128)

    /// Stop formatting matches as soon as the cell is full. A wildcard can otherwise
    /// serialize thousands of objects just to discard almost all of the joined text.
    private static func displayValue(_ values: some Sequence<String>) -> String {
        var result = ""
        var isFirst = true
        for value in values {
            if !isFirst {
                result += ", "
            }
            isFirst = false
            let bounded = byteBoundedPrefix(value, limit: max(0, maxDisplayBytes - result.utf8.count))
            result += bounded.text.prefix(maxDisplayLength + 1)
            if bounded.isTruncated || result.utf8.count > maxDisplayBytes || result.count > maxDisplayLength {
                let preview = result.utf8.count > maxDisplayBytes
                    ? byteBoundedPrefix(result, limit: maxDisplayBytes).text
                    : result
                return String(preview.prefix(maxDisplayLength)) + "…"
            }
        }
        return result
    }

    /// Inspect only a bounded prefix plus one complete scalar of lookahead. If that
    /// scalar extends the last grapheme beyond the byte budget, omit that grapheme
    /// entirely rather than displaying a broken combining sequence or emoji cluster.
    private static func byteBoundedPrefix(_ text: String, limit: Int) -> (text: String, isTruncated: Bool) {
        let bytes = Array(text.utf8.prefix(limit + 4))
        guard bytes.count > limit else {
            return (text, false)
        }
        var end = limit
        while end > 0, bytes[end] & 0xC0 == 0x80 {
            end -= 1
        }
        let scalarLength = switch bytes[end] {
        case ..<0x80: 1
        case ..<0xE0: 2
        case ..<0xF0: 3
        default: 4
        }
        guard end + scalarLength <= bytes.count,
              let prefix = String(bytes: bytes[..<end], encoding: .utf8),
              let next = String(bytes: bytes[end ..< (end + scalarLength)], encoding: .utf8)?.unicodeScalars.first else
        {
            return ("", true)
        }
        var probe = prefix
        probe.unicodeScalars.append(next)
        if probe.count == prefix.count {
            return (String(prefix.dropLast()), true)
        }
        return (prefix, true)
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        for byte in data.prefix(64) {
            switch byte {
            case 0x20,
                 0x09,
                 0x0A,
                 0x0D,
                 0xEF,
                 0xBB,
                 0xBF:
                continue
            case UInt8(ascii: "{"),
                 UInt8(ascii: "["):
                return true
            default:
                return false
            }
        }
        return false
    }
}

// MARK: - CustomColumnValueCache

/// Thread-safe cache of a transaction's body-column values.
final class CustomColumnValueCache: @unchecked Sendable {
    // MARK: Internal

    func value(for key: String) -> String? {
        lock.withLock { values[key] }
    }

    func store(_ value: String, for key: String) {
        lock.withLock { values[key] = value }
    }

    func removeAll() {
        lock.withLock { values.removeAll() }
    }

    // MARK: Private

    private let lock = NSLock()
    private var values: [String: String] = [:]
}
