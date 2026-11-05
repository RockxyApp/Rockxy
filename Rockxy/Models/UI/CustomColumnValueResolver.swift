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

    /// The production evaluator; named so the default argument stays one line.
    static let defaultEvaluator: @Sendable (String, Data) async -> String = { expression, data in
        await evaluate(expression, on: data)
    }

    static func queryValue(named name: String, in url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.first { $0.name == name }?.value ?? ""
    }

    /// Caches on the transaction exactly as `bodyValue` does. A query column resolves per
    /// cell, per redraw, and `URLComponents` has to parse the whole URL and allocate every
    /// query item just to read one name -- so a long capture paid that for every visible row
    /// on every pass while a body column beside it was already cached. The value is a pure
    /// function of `request.url`, and the cache is dropped whenever request evidence changes,
    /// so the invalidation is the same and needs no extra bookkeeping.
    static func queryValue(named name: String, in transaction: HTTPTransaction) -> String {
        let cacheKey = "qry:" + name
        if let cached = transaction.customColumnValueCache.value(for: cacheKey) {
            return cached
        }
        let value = queryValue(named: name, in: transaction.request.url)
        transaction.customColumnValueCache.store(value, for: cacheKey)
        return value
    }

    /// Evaluates `expression` against a transaction's JSON body. The result is cached on the
    /// transaction until its request or response evidence changes.
    ///
    /// This blocks the caller until the filter finishes, so it belongs to callers that need the
    /// value in hand: sorting a column, and copying or exporting a row. A table cell drawing a
    /// body column must not use it -- see `cachedBodyValue` and `resolveBodyValue`.
    static func bodyValue(expression: String, response: Bool, transaction: HTTPTransaction) -> String {
        let cacheKey = cacheKey(expression: expression, response: response)
        if let cached = transaction.customColumnValueCache.value(for: cacheKey) {
            return cached
        }
        let value = bodyData(response: response, transaction: transaction)
            .map { evaluate(expression, on: $0) } ?? ""
        transaction.customColumnValueCache.store(value, for: cacheKey)
        return value
    }

    /// The value already resolved for this column, or `nil` when it has not been evaluated yet.
    ///
    /// A cell drawing a body column reads this and shows nothing while it is `nil`, because
    /// evaluating the filter inline blocked the thread doing the drawing -- the main thread --
    /// once for every newly visible row. Each transaction is still paid for exactly once: the
    /// cache below is the same one `bodyValue` fills, and is dropped on the same evidence change.
    static func cachedBodyValue(expression: String, response: Bool, transaction: HTTPTransaction) -> String? {
        transaction.customColumnValueCache.value(for: cacheKey(expression: expression, response: response))
    }

    /// Evaluates the column off the caller's actor and caches the result, returning it. A column
    /// that is already cached returns without reaching the interpreter, so a caller may call this
    /// for every visible row without rationing it.
    @discardableResult
    static func resolveBodyValue(
        expression: String,
        response: Bool,
        transaction: HTTPTransaction,
        evaluator: @escaping @Sendable (String, Data) async -> String = defaultEvaluator
    )
        async -> String
    {
        let cacheKey = cacheKey(expression: expression, response: response)
        if let cached = transaction.customColumnValueCache.value(for: cacheKey) {
            return cached
        }
        // A table cell trusts the cache, so a value computed from evidence that has since
        // changed must never be stored. The generation is read before the body is, the store is
        // refused if it moved, and the evaluation then starts over against the new evidence.
        var value = ""
        for _ in 0 ..< maxStaleRetries {
            let generation = transaction.customColumnValueCache.generation
            // Body decoding is itself unbounded work on a 2 MB cap, so it stays off the caller
            // alongside the evaluation rather than being read here first.
            value = await Task.detached(priority: .userInitiated) {
                guard let body = bodyData(response: response, transaction: transaction) else {
                    return ""
                }
                return await evaluator(expression, body)
            }.value
            if transaction.customColumnValueCache.store(value, for: cacheKey, ifGeneration: generation) {
                return value
            }
        }
        return value
    }

    /// Evaluates JSONPath (starting with `$`) or a jq filter against JSON `data`. Anything that
    /// is not JSON, fails, or matches nothing shows as an empty cell.
    static func evaluate(_ expression: String, on data: Data) -> String {
        guard data.count <= maxBodySize, looksLikeJSON(data) else {
            return ""
        }
        if expression.hasPrefix("$") {
            return jsonPathValue(expression, on: data)
        }
        guard let filter = try? JQFilter(expression),
              let output = try? filter.run(JQValue.parse(data), limits: columnLimits) else
        {
            return ""
        }
        return displayValue(output.values.lazy.map(cellText))
    }

    /// `evaluate` without blocking on the filter: the interpreter still runs on its own
    /// large-stack thread, but this awaits it instead of parking the caller's thread on a
    /// semaphore until it finishes. `run(json:)` also moves the JSON parse off the caller.
    static func evaluate(_ expression: String, on data: Data) async -> String {
        guard data.count <= maxBodySize, looksLikeJSON(data) else {
            return ""
        }
        guard !expression.hasPrefix("$") else {
            // JSONPath has no off-thread entry point, and this caller is already off the main
            // actor. Calling the synchronous `evaluate` here would resolve to this overload
            // instead and recurse, so the shared branch is named rather than overloaded.
            return jsonPathValue(expression, on: data)
        }
        guard let filter = try? JQFilter(expression),
              let output = try? await filter.run(json: data, limits: columnLimits) else
        {
            return ""
        }
        return displayValue(output.values.lazy.map(cellText))
    }

    // MARK: Private

    /// Evidence changing this many times mid-evaluation returns the last value uncached.
    private static let maxStaleRetries = 3

    private static let columnLimits = JQLimits(maxSteps: 200_000, maxOutputs: 50, maxDepth: 128)

    private static func cacheKey(expression: String, response: Bool) -> String {
        (response ? "res:" : "req:") + expression
    }

    private static func bodyData(response: Bool, transaction: HTTPTransaction) -> Data? {
        response
            ? transaction.response.flatMap { $0.decodedBody(limit: maxBodySize) ?? $0.body }
            : transaction.request.body
    }

    private static func jsonPathValue(_ expression: String, on data: Data) -> String {
        guard let document = try? JSONPathDocument(data: data),
              let result = try? JSONPathEvaluator(document: document).evaluate(expression) else
        {
            return ""
        }
        return displayValue(result.matches.lazy.map(\.scalarDescription))
    }

    /// A jq string output is shown as its own characters; anything else as its JSON text.
    private static func cellText(_ value: JQValue) -> String {
        if case let .string(text) = value {
            return text
        }
        return value.jsonText()
    }

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

    /// Bumped by every `removeAll`. An evaluation captures it before reading the evidence.
    var generation: Int {
        lock.withLock { currentGeneration }
    }

    func value(for key: String) -> String? {
        lock.withLock { values[key] }
    }

    func store(_ value: String, for key: String) {
        lock.withLock { values[key] = value }
    }

    /// Stores only if no `removeAll` happened since `generation` was read, i.e. the evidence the
    /// value was computed from is still the transaction's evidence. Returns whether it stored.
    @discardableResult
    func store(_ value: String, for key: String, ifGeneration generation: Int) -> Bool {
        lock.withLock {
            guard generation == currentGeneration else {
                return false
            }
            values[key] = value
            return true
        }
    }

    func removeAll() {
        lock.withLock {
            currentGeneration += 1
            values.removeAll()
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var currentGeneration = 0
}

// MARK: - CustomColumnCellValue

/// What a table cell may show for a custom column right now.
enum CustomColumnCellValue: Equatable {
    /// The final text. Empty is a real answer here: the header is absent or the filter matched nothing.
    case resolved(String)
    /// A JSON body column that has not been evaluated yet. The cell shows a placeholder and
    /// asks `CustomColumnCellScheduler` to fill it in.
    case pending

    // MARK: Internal

    /// What a cell shows while a value is outstanding. Fixed width-neutral glyph, so the arrival
    /// of the value changes text only and never the layout.
    static let placeholder = "…"

    /// What VoiceOver reads instead of the glyph.
    static var pendingAccessibilityValue: String {
        String(localized: "Calculating value", bundle: RockxyLocalization.bundle)
    }

    /// What the cell shows for this state.
    var displayText: String {
        switch self {
        case let .resolved(text): text
        case .pending: Self.placeholder
        }
    }
}

// MARK: - CustomColumnCellKey

/// Identity of one cell's worth of work: the transaction row and the column, never a row index.
/// An index names whatever transaction currently sits there; this names the transaction.
struct CustomColumnCellKey: Hashable {
    let rowID: UUID
    let columnID: String
}

// MARK: - CustomColumnCellResolution

/// The decision a cell callback needs, free of AppKit so it can be tested directly.
enum CustomColumnCellResolution {
    /// Never evaluates anything. Headers and query values are cheap and cached; a JSON body
    /// column reads only the cache and reports `.pending` when nothing is cached.
    static func value(columnID: String, row: RequestListRow) -> CustomColumnCellValue {
        guard let (source, name) = HeaderColumn.parse(columnID: columnID) else {
            return .resolved("")
        }
        switch source {
        case .request,
             .response,
             .query:
            return .resolved(RequestListRow.resolveHeaderValue(for: columnID, row: row))
        case .requestBody,
             .responseBody:
            guard let transaction = row.source else {
                return .resolved("")
            }
            return CustomColumnValueResolver
                .cachedBodyValue(expression: name, response: source == .responseBody, transaction: transaction)
                .map(CustomColumnCellValue.resolved) ?? .pending
        }
    }

    /// The row currently showing `rowID`, searched only among the rows on screen. `nil` means the
    /// row was recycled away, removed, or scrolled out, and the late value must not be written.
    static func visibleRowIndex(
        of rowID: UUID,
        among visible: Range<Int>,
        rowIDAt: (Int) -> UUID?
    )
        -> Int?
    {
        visible.first { rowIDAt($0) == rowID }
    }
}

// MARK: - CustomColumnCellScheduler

/// Fills pending body-column cells without blocking drawing. One evaluation per (row, column)
/// at a time, results reported with the key they were requested for.
@MainActor
final class CustomColumnCellScheduler {
    // MARK: Lifecycle

    /// - Parameters:
    ///   - evaluate: Produces the value off the main actor. Defaults to the shared resolver, which
    ///     also stores the result in the transaction's cache.
    ///   - isStillWanted: Asked just before evaluating; a row scrolled away meanwhile is skipped.
    ///   - deliver: Receives the value with the key it was requested for. The receiver must
    ///     re-locate the key's row before writing anything.
    init(
        evaluate: @escaping @Sendable (String, Bool, HTTPTransaction) async -> String =
            { expression, response, transaction in
                await CustomColumnValueResolver.resolveBodyValue(
                    expression: expression,
                    response: response,
                    transaction: transaction
                )
            },
        isStillWanted: @escaping @MainActor (CustomColumnCellKey) -> Bool,
        deliver: @escaping @MainActor (CustomColumnCellKey, String) -> Void
    ) {
        self.evaluate = evaluate
        self.isStillWanted = isStillWanted
        self.deliver = deliver
    }

    // MARK: Internal

    private(set) var inFlight: Set<CustomColumnCellKey> = []

    /// Starts resolving a pending body cell. Does nothing for other columns, for a cell already
    /// in flight, or for a value that is already cached.
    func request(columnID: String, row: RequestListRow) {
        guard let (source, name) = HeaderColumn.parse(columnID: columnID),
              source == .requestBody || source == .responseBody,
              let transaction = row.source else
        {
            return
        }
        let response = source == .responseBody
        guard CustomColumnValueResolver
            .cachedBodyValue(expression: name, response: response, transaction: transaction) == nil else
        {
            return
        }
        let key = CustomColumnCellKey(rowID: row.id, columnID: columnID)
        guard inFlight.insert(key).inserted else {
            return
        }
        let evaluate = evaluate
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            guard isStillWanted(key) else {
                inFlight.remove(key)
                return
            }
            let value = await evaluate(name, response, transaction)
            inFlight.remove(key)
            deliver(key, value)
        }
    }

    // MARK: Private

    private let evaluate: @Sendable (String, Bool, HTTPTransaction) async -> String
    private let isStillWanted: @MainActor (CustomColumnCellKey) -> Bool
    private let deliver: @MainActor (CustomColumnCellKey, String) -> Void
}
