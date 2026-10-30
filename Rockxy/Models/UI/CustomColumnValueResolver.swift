import Foundation

// Values for custom table columns that read a query parameter or a JSON body.

// MARK: - CustomColumnValueResolver

enum CustomColumnValueResolver {
    // MARK: Internal

    /// Bodies larger than this are not parsed for a column.
    static let maxBodySize = 2 * 1_024 * 1_024
    /// Longest text shown in a cell.
    static let maxDisplayLength = 300

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
            result += value.prefix(maxDisplayLength + 1)
            if result.count > maxDisplayLength {
                return String(result.prefix(maxDisplayLength)) + "…"
            }
        }
        return result
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
