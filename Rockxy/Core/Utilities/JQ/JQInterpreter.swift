import Foundation

// Evaluates a parsed jq filter against a JSON value. Every step is counted so a runaway filter
// (`range(1e9)`, deep `recurse`) stops at a limit instead of hanging the inspector.

// MARK: - JQLimits

struct JQLimits: Sendable {
    static let `default` = JQLimits()

    var maxSteps = 2_000_000
    var maxOutputs = 10_000
    var maxDepth = 256
    var maxRegexPatternLength = 1_024
}

// MARK: - JQFilter

/// A compiled jq filter. `run` returns every output of the filter for one input.
struct JQFilter: Sendable {
    // MARK: Lifecycle

    init(_ source: String) throws {
        root = try JQParser.parse(source)
    }

    // MARK: Internal

    struct Output: Sendable {
        var values: [JQValue]
        var isTruncated: Bool
    }

    /// Runs the filter and blocks until it finishes. Evaluation happens on a thread with a
    /// large stack, because deep filters recurse further than a Swift concurrency thread allows.
    func run(_ input: JQValue, limits: JQLimits = .default, cancellation: JQCancellation? = nil) throws -> Output {
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        let root = root
        let thread = Thread {
            box.result = Result { try Self.evaluate(root, input, limits, cancellation) }
            done.signal()
        }
        thread.stackSize = Self.stackSize
        thread.name = "jq filter"
        thread.start()
        done.wait()
        return try box.result.get()
    }

    /// Runs the filter off the caller's thread; cancelling the task stops the filter.
    func run(_ input: JQValue, limits: JQLimits = .default) async throws -> Output {
        try await run(limits: limits) { input }
    }

    /// Parses `json` and runs the filter on it, both off the caller's thread.
    func run(json: Data, limits: JQLimits = .default) async throws -> Output {
        try await run(limits: limits) { try JQValue.parse(json) }
    }

    // MARK: Private

    private final class ResultBox: @unchecked Sendable {
        var result: Result<Output, Error> = .success(Output(values: [], isTruncated: false))
    }

    private static let stackSize = 64 * 1_024 * 1_024

    private let root: JQNode

    private static func evaluate(
        _ root: JQNode,
        _ input: JQValue,
        _ limits: JQLimits,
        _ cancellation: JQCancellation?
    )
        throws -> Output
    {
        let interpreter = JQInterpreter(limits: limits, cancellation: cancellation)
        var values: [JQValue] = []
        var isTruncated = false
        // Stopping at the output cap keeps what was produced.
        try interpreter.withStop { stop in
            try interpreter.evaluate(root, input, JQEnvironment()) { value in
                values.append(value)
                if values.count >= limits.maxOutputs {
                    isTruncated = true
                    throw stop
                }
            }
        }
        return Output(values: values, isTruncated: isTruncated)
    }

    private func run(limits: JQLimits, input: @escaping @Sendable () throws -> JQValue) async throws -> Output {
        let cancellation = JQCancellation()
        let root = root
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
                let thread = Thread {
                    continuation.resume(with: Result { try Self.evaluate(root, input(), limits, cancellation) })
                }
                thread.stackSize = Self.stackSize
                thread.name = "jq filter"
                thread.start()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

// MARK: - JQCancellation

/// Thread-safe flag the interpreter polls so a cancelled inspector query stops promptly.
final class JQCancellation: @unchecked Sendable {
    // MARK: Internal

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    // MARK: Private

    private let lock = NSLock()
    private var cancelled = false
}

// MARK: - JQEnvironment

struct JQEnvironment {
    var variables: [String: JQValue] = [:]

    func binding(_ name: String, _ value: JQValue) -> JQEnvironment {
        var copy = self
        copy.variables[name] = value
        return copy
    }
}

// MARK: - JQInterpreter

final class JQInterpreter {
    // MARK: Lifecycle

    init(limits: JQLimits, cancellation: JQCancellation? = nil) {
        self.limits = limits
        self.cancellation = cancellation
    }

    // MARK: Internal

    typealias Emit = (JQValue) throws -> Void
    typealias PathEmit = ([JQValue], JQValue) throws -> Void

    /// Ends one generator early (`first`, `limit`, output cap). Each use gets its own token,
    /// so an inner `limit` never swallows an outer stop. Never visible to filters.
    struct StopSignal: Error {
        let token: ObjectIdentifier
    }

    /// A caught-able error raised by `error(value)`, carrying the value itself.
    struct RaisedError: Error {
        let value: JQValue
    }

    let limits: JQLimits
    let cancellation: JQCancellation?

    static func text(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: RockxyLocalization.bundle)
    }

    static func isCatchable(_ error: Error) -> Bool {
        switch error {
        case is RaisedError:
            true
        case let error as JQError:
            if case .runtime = error {
                true
            } else {
                false
            }
        default:
            false
        }
    }

    static func errorValue(_ error: Error) -> JQValue {
        if let raised = error as? RaisedError {
            return raised.value
        }
        if let jqError = error as? JQError {
            return .string(jqError.localizedDescription)
        }
        return .null
    }

    static func describe(_ value: JQValue) -> String {
        let text = value.jsonText()
        let prefix = text.count > 40 ? String(text.prefix(37)) + "..." : text
        return "\(value.typeName) (\(prefix))"
    }

    static func clampedInteger(_ value: Double) -> Int64 {
        let truncated = value.rounded(.towardZero)
        if truncated >= 9.2e18 {
            return Int64.max
        }
        if truncated <= -9.2e18 {
            return Int64.min + 1
        }
        return Int64(truncated)
    }

    /// Runs `body`, ending quietly when it throws the signal handed to it.
    func withStop(_ body: (StopSignal) throws -> Void) throws {
        final class Token {}
        let token = Token()
        let signal = StopSignal(token: ObjectIdentifier(token))
        do {
            try body(signal)
        } catch let caught as StopSignal where caught.token == signal.token {}
        withExtendedLifetime(token) {}
    }

    /// First output of `node`, or `nil` when it produces none.
    func first(_ node: JQNode, _ input: JQValue, _ env: JQEnvironment) throws -> JQValue? {
        var result: JQValue?
        try withStop { stop in
            try evaluate(node, input, env) { value in
                result = value
                throw stop
            }
        }
        return result
    }

    /// Every output of `node`.
    func all(_ node: JQNode, _ input: JQValue, _ env: JQEnvironment) throws -> [JQValue] {
        var results: [JQValue] = []
        try evaluate(node, input, env) { results.append($0) }
        return results
    }

    func evaluate(_ node: JQNode, _ input: JQValue, _ env: JQEnvironment, _ emit: Emit) throws {
        try step()
        depth += 1
        defer { depth -= 1 }
        guard depth <= limits.maxDepth else {
            throw JQError.limit(Self.text("The filter recursed too deeply."))
        }

        switch node {
        case .identity:
            try emit(input)

        case .recurseAll:
            try recurseValues(input, emit)

        case let .literal(value):
            try emit(value)

        case let .string(parts, format):
            try evaluateString(parts, format: format, input, env, prefix: "", emit)

        case let .format(name):
            try emit(.string(format(input, as: name)))

        case let .index(target, indexNode):
            try evaluate(indexNode, input, env) { key in
                try self.evaluate(target, input, env) { container in
                    try emit(self.index(container, key))
                }
            }

        case let .slice(target, lower, upper):
            try evaluateOptional(lower, input, env) { from in
                try self.evaluateOptional(upper, input, env) { to in
                    try self.evaluate(target, input, env) { container in
                        try emit(self.slice(container, from, to))
                    }
                }
            }

        case let .iterate(target):
            try evaluate(target, input, env) { container in
                try self.iterate(container, emit)
            }

        case let .array(inner):
            var items: [JQValue] = []
            if let inner {
                try evaluate(inner, input, env) { items.append($0) }
            }
            try emit(.array(items))

        case let .object(entries):
            try buildObject(entries[...], input, env, JQObject(), emit)

        case let .pipe(lhs, rhs):
            try evaluate(lhs, input, env) { value in
                try self.evaluate(rhs, value, env, emit)
            }

        case let .comma(lhs, rhs):
            try evaluate(lhs, input, env, emit)
            try evaluate(rhs, input, env, emit)

        case let .negate(inner):
            try evaluate(inner, input, env) { value in
                guard case let .number(number) = value else {
                    throw JQError.runtime(Self.text("\(value.typeName) cannot be negated."))
                }
                try emit(.number(-number))
            }

        case let .binary(op, lhs, rhs):
            try evaluate(rhs, input, env) { right in
                try self.evaluate(lhs, input, env) { left in
                    try emit(self.apply(op, left, right))
                }
            }

        case let .and(lhs, rhs):
            try evaluate(lhs, input, env) { left in
                guard left.isTruthy else {
                    try emit(.bool(false))
                    return
                }
                try self.evaluate(rhs, input, env) { try emit(.bool($0.isTruthy)) }
            }

        case let .or(lhs, rhs):
            try evaluate(lhs, input, env) { left in
                guard !left.isTruthy else {
                    try emit(.bool(true))
                    return
                }
                try self.evaluate(rhs, input, env) { try emit(.bool($0.isTruthy)) }
            }

        case let .alternative(lhs, rhs):
            var produced = false
            do {
                try evaluate(lhs, input, env) { value in
                    if value.isTruthy {
                        produced = true
                        try emit(value)
                    }
                }
            } catch let error where Self.isCatchable(error) {
                // Errors on the left behave like no output.
            }
            if !produced {
                try evaluate(rhs, input, env, emit)
            }

        case let .assign(op, lhs, rhs):
            try evaluateAssignment(op, lhs, rhs, input, env, emit)

        case let .conditional(branches, otherwise):
            try evaluateBranches(branches[...], otherwise, input, env, emit)

        case let .tryCatch(body, handler):
            do {
                try evaluate(body, input, env, emit)
            } catch let error where Self.isCatchable(error) {
                if let handler {
                    try evaluate(handler, Self.errorValue(error), env, emit)
                }
            }

        case let .reduce(source, name, initial, update):
            try evaluate(initial, input, env) { start in
                var accumulator: JQValue? = start
                try self.evaluate(source, input, env) { item in
                    let scoped = env.binding(name, item)
                    var last: JQValue?
                    if let current = accumulator {
                        try self.evaluate(update, current, scoped) { last = $0 }
                    }
                    accumulator = last
                }
                try emit(accumulator ?? .null)
            }

        case let .foreach(source, name, initial, update, extract):
            try evaluate(initial, input, env) { start in
                var accumulator = start
                try self.evaluate(source, input, env) { item in
                    let scoped = env.binding(name, item)
                    try self.evaluate(update, accumulator, scoped) { state in
                        accumulator = state
                        if let extract {
                            try self.evaluate(extract, state, scoped, emit)
                        } else {
                            try emit(state)
                        }
                    }
                }
            }

        case let .bind(source, name, body):
            try evaluate(source, input, env) { value in
                try self.evaluate(body, input, env.binding(name, value), emit)
            }

        case let .variable(name):
            if name == "ENV" || name == "__prog_args" {
                // Never expose the app's process environment to a filter.
                try emit(.object(JQObject()))
                return
            }
            guard let value = env.variables[name] else {
                throw JQError.runtime(Self.text("$\(name) is not defined."))
            }
            try emit(value)

        case let .call(name, arguments):
            try callBuiltin(name, arguments, input, env, emit)
        }
    }

    // MARK: - Paths

    func paths(
        _ node: JQNode,
        _ input: JQValue,
        _ path: [JQValue],
        _ env: JQEnvironment,
        _ emit: PathEmit
    )
        throws
    {
        try step()
        switch node {
        case .identity:
            try emit(path, input)

        case .recurseAll:
            try recursePaths(input, path, emit)

        case let .index(target, indexNode):
            try evaluate(indexNode, input, env) { key in
                try self.paths(target, input, path, env) { targetPath, container in
                    try emit(targetPath + [key], self.index(container, key))
                }
            }

        case let .slice(target, lower, upper):
            try evaluateOptional(lower, input, env) { from in
                try self.evaluateOptional(upper, input, env) { to in
                    try self.paths(target, input, path, env) { targetPath, container in
                        let key = JQValue.object(JQObject([("start", from ?? .null), ("end", to ?? .null)]))
                        try emit(targetPath + [key], self.slice(container, from, to))
                    }
                }
            }

        case let .iterate(target):
            try paths(target, input, path, env) { targetPath, container in
                switch container {
                case let .array(items):
                    for (offset, item) in items.enumerated() {
                        try emit(targetPath + [.number(Double(offset))], item)
                    }
                case let .object(object):
                    for (key, value) in object.pairs {
                        try emit(targetPath + [.string(key)], value)
                    }
                case .null:
                    break
                default:
                    throw JQError.runtime(Self.text("Cannot iterate over \(container.typeName)."))
                }
            }

        case let .pipe(lhs, rhs):
            try paths(lhs, input, path, env) { lhsPath, value in
                try self.paths(rhs, value, lhsPath, env, emit)
            }

        case let .comma(lhs, rhs):
            try paths(lhs, input, path, env, emit)
            try paths(rhs, input, path, env, emit)

        case let .conditional(branches, otherwise):
            try pathBranches(branches[...], otherwise, input, path, env, emit)

        case let .alternative(lhs, rhs):
            var produced = false
            do {
                try paths(lhs, input, path, env) { lhsPath, value in
                    if value.isTruthy {
                        produced = true
                        try emit(lhsPath, value)
                    }
                }
            } catch let error where Self.isCatchable(error) {}
            if !produced {
                try paths(rhs, input, path, env, emit)
            }

        case let .tryCatch(body, _):
            do {
                try paths(body, input, path, env, emit)
            } catch let error where Self.isCatchable(error) {}

        case let .bind(source, name, body):
            try evaluate(source, input, env) { value in
                try self.paths(body, input, path, env.binding(name, value), emit)
            }

        case let .call(name, arguments):
            try callPathBuiltin(name, arguments, input, path, env, emit)

        case .literal(.null):
            try emit(path, .null)

        default:
            throw JQError.runtime(Self.text("This filter cannot be used as a path expression."))
        }
    }

    func step() throws {
        steps += 1
        guard steps <= limits.maxSteps else {
            throw JQError.limit(Self.text("The filter did too much work and was stopped."))
        }
        if steps & 0x3FF == 0, cancellation?.isCancelled == true {
            throw CancellationError()
        }
    }

    // MARK: - Value helpers

    func index(_ container: JQValue, _ key: JQValue) throws -> JQValue {
        switch (container, key) {
        case (.null, .string),
             (.null, .number),
             (.null, .null):
            return .null
        case let (.object(object), .string(name)):
            return object[name] ?? .null
        case let (.array(items), .number(number)):
            guard number.isFinite else {
                return .null
            }
            var offset = Int(number.rounded(.down))
            if offset < 0 {
                offset += items.count
            }
            return items.indices.contains(offset) ? items[offset] : .null
        case let (.array, .object(range)):
            return try slice(container, range["start"], range["end"])
        case let (.array(items), .array(needle)):
            return .array(indices(of: needle, in: items).map { .number(Double($0)) })
        default:
            throw JQError.runtime(Self.text("Cannot index \(container.typeName) with \(Self.describe(key))."))
        }
    }

    func slice(_ container: JQValue, _ from: JQValue?, _ to: JQValue?) throws -> JQValue {
        func bounds(_ count: Int) throws -> (Int, Int) {
            func resolve(_ value: JQValue?, _ fallback: Int) throws -> Int {
                guard let value, value != .null else {
                    return fallback
                }
                guard case let .number(number) = value, number.isFinite else {
                    throw JQError.runtime(Self.text("Slice indices must be numbers."))
                }
                var offset = Int(number.rounded(.down))
                if offset < 0 {
                    offset += count
                }
                return min(max(offset, 0), count)
            }
            let start = try resolve(from, 0)
            let end = try resolve(to, count)
            return (start, max(start, end))
        }
        switch container {
        case .null:
            return .null
        case let .array(items):
            let (start, end) = try bounds(items.count)
            return .array(Array(items[start ..< end]))
        case let .string(text):
            let scalars = Array(text.unicodeScalars)
            let (start, end) = try bounds(scalars.count)
            return .string(String(String.UnicodeScalarView(scalars[start ..< end])))
        default:
            throw JQError.runtime(Self.text("Cannot slice \(container.typeName)."))
        }
    }

    func iterate(_ container: JQValue, _ emit: Emit) throws {
        switch container {
        case let .array(items):
            for item in items {
                try emit(item)
            }
        case let .object(object):
            for value in object.values {
                try emit(value)
            }
        default:
            throw JQError.runtime(Self.text("Cannot iterate over \(container.typeName)."))
        }
    }

    func apply(_ op: JQNode.BinaryOperator, _ left: JQValue, _ right: JQValue) throws -> JQValue {
        switch op {
        case .equal: .bool(left == right)
        case .notEqual: .bool(left != right)
        case .less: .bool(JQValue.compare(left, right) < 0)
        case .lessOrEqual: .bool(JQValue.compare(left, right) <= 0)
        case .greater: .bool(JQValue.compare(left, right) > 0)
        case .greaterOrEqual: .bool(JQValue.compare(left, right) >= 0)
        case .add: try add(left, right)
        case .subtract: try subtract(left, right)
        case .multiply: try multiply(left, right)
        case .divide: try divide(left, right)
        case .modulo: try modulo(left, right)
        }
    }

    func add(_ left: JQValue, _ right: JQValue) throws -> JQValue {
        switch (left, right) {
        case (.null, _): return right
        case (_, .null): return left
        case let (.number(lhs), .number(rhs)): return .number(lhs + rhs)
        case let (.string(lhs), .string(rhs)): return .string(lhs + rhs)
        case let (.array(lhs), .array(rhs)): return .array(lhs + rhs)
        case let (.object(lhs), .object(rhs)):
            var merged = lhs
            for (key, value) in rhs.pairs {
                merged[key] = value
            }
            return .object(merged)
        default:
            throw operandError(left, right, .add)
        }
    }

    func split(_ text: String, by separator: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }
        guard !separator.isEmpty else {
            return text.unicodeScalars.map { String($0) }
        }
        return text.components(separatedBy: separator)
    }

    func collectPaths(_ node: JQNode, _ input: JQValue, _ env: JQEnvironment) throws -> [[JQValue]] {
        var collected: [[JQValue]] = []
        try paths(node, input, [], env) { path, _ in
            collected.append(path)
        }
        return collected
    }

    // MARK: Private

    private var steps = 0
    private var depth = 0

    private enum Operation {
        case add
        case subtract
        case multiply
        case divide
    }

    private func operandError(_ left: JQValue, _ right: JQValue, _ operation: Operation) -> JQError {
        let lhs = Self.describe(left)
        let rhs = Self.describe(right)
        return switch operation {
        case .add: .runtime(Self.text("\(lhs) and \(rhs) cannot be added."))
        case .subtract: .runtime(Self.text("\(lhs) and \(rhs) cannot be subtracted."))
        case .multiply: .runtime(Self.text("\(lhs) and \(rhs) cannot be multiplied."))
        case .divide: .runtime(Self.text("\(lhs) and \(rhs) cannot be divided."))
        }
    }

    private func subtract(_ left: JQValue, _ right: JQValue) throws -> JQValue {
        switch (left, right) {
        case let (.number(lhs), .number(rhs)): return .number(lhs - rhs)
        case let (.array(lhs), .array(rhs)): return .array(lhs.filter { !rhs.contains($0) })
        default: throw operandError(left, right, .subtract)
        }
    }

    private func multiply(_ left: JQValue, _ right: JQValue) throws -> JQValue {
        switch (left, right) {
        case let (.number(lhs), .number(rhs)):
            return .number(lhs * rhs)
        case let (.string(text), .number(count)),
             let (.number(count), .string(text)):
            guard count > 0 else {
                return .null
            }
            let repeats = Int(count.rounded(.up))
            guard text.utf8.count * repeats <= 10_000_000 else {
                throw JQError.limit(Self.text("The repeated string would be too long."))
            }
            return .string(String(repeating: text, count: repeats))
        case let (.object(lhs), .object(rhs)):
            return .object(deepMerge(lhs, rhs))
        default:
            throw operandError(left, right, .multiply)
        }
    }

    private func deepMerge(_ lhs: JQObject, _ rhs: JQObject) -> JQObject {
        var merged = lhs
        for (key, value) in rhs.pairs {
            if case let .object(existing)? = merged[key], case let .object(incoming) = value {
                merged[key] = .object(deepMerge(existing, incoming))
            } else {
                merged[key] = value
            }
        }
        return merged
    }

    private func divide(_ left: JQValue, _ right: JQValue) throws -> JQValue {
        switch (left, right) {
        case let (.number(lhs), .number(rhs)):
            guard rhs != 0 else {
                throw JQError.runtime(Self.text("\(Self.describe(left)) cannot be divided by zero."))
            }
            return .number(lhs / rhs)
        case let (.string(text), .string(separator)):
            return .array(split(text, by: separator).map(JQValue.string))
        default:
            throw operandError(left, right, .divide)
        }
    }

    private func modulo(_ left: JQValue, _ right: JQValue) throws -> JQValue {
        guard case let .number(lhs) = left, case let .number(rhs) = right,
              lhs.isFinite, rhs.isFinite else
        {
            throw operandError(left, right, .divide)
        }
        let divisor = Self.clampedInteger(rhs)
        guard divisor != 0 else {
            throw JQError.runtime(Self.text("\(Self.describe(left)) cannot be divided by zero."))
        }
        let dividend = Self.clampedInteger(lhs)
        return .number(Double(dividend % abs(divisor)))
    }

    private func indices(of needle: [JQValue], in items: [JQValue]) -> [Int] {
        guard !needle.isEmpty, needle.count <= items.count else {
            return []
        }
        return (0 ... items.count - needle.count).filter { start in
            Array(items[start ..< start + needle.count]) == needle
        }
    }

    private func evaluateOptional(
        _ node: JQNode?,
        _ input: JQValue,
        _ env: JQEnvironment,
        _ emit: (JQValue?) throws -> Void
    )
        throws
    {
        guard let node else {
            try emit(nil)
            return
        }
        try evaluate(node, input, env) { try emit($0) }
    }

    private func recurseValues(_ value: JQValue, _ emit: Emit) throws {
        try step()
        try emit(value)
        switch value {
        case let .array(items):
            for item in items {
                try recurseValues(item, emit)
            }
        case let .object(object):
            for item in object.values {
                try recurseValues(item, emit)
            }
        default:
            break
        }
    }

    private func recursePaths(_ value: JQValue, _ path: [JQValue], _ emit: PathEmit) throws {
        try step()
        try emit(path, value)
        switch value {
        case let .array(items):
            for (offset, item) in items.enumerated() {
                try recursePaths(item, path + [.number(Double(offset))], emit)
            }
        case let .object(object):
            for (key, item) in object.pairs {
                try recursePaths(item, path + [.string(key)], emit)
            }
        default:
            break
        }
    }

    private func evaluateString(
        _ parts: [JQNode.StringPart],
        format: String?,
        _ input: JQValue,
        _ env: JQEnvironment,
        prefix: String,
        _ emit: Emit
    )
        throws
    {
        guard let first = parts.first else {
            try emit(.string(prefix))
            return
        }
        let rest = Array(parts.dropFirst())
        switch first {
        case let .literal(text):
            try evaluateString(rest, format: format, input, env, prefix: prefix + text, emit)
        case let .interpolation(node):
            try evaluate(node, input, env) { value in
                let piece: String = if let format {
                    try self.format(value, as: format)
                } else if case let .string(text) = value {
                    text
                } else {
                    value.jsonText()
                }
                try self.evaluateString(rest, format: format, input, env, prefix: prefix + piece, emit)
            }
        }
    }

    private func buildObject(
        _ entries: ArraySlice<(key: JQNode.ObjectKey, value: JQNode?)>,
        _ input: JQValue,
        _ env: JQEnvironment,
        _ partial: JQObject,
        _ emit: Emit
    )
        throws
    {
        guard let entry = entries.first else {
            try emit(.object(partial))
            return
        }
        let remaining = entries.dropFirst()
        func withValue(_ key: String) throws {
            if let valueNode = entry.value {
                try self.evaluate(valueNode, input, env) { value in
                    var next = partial
                    next[key] = value
                    try self.buildObject(remaining, input, env, next, emit)
                }
            } else {
                var next = partial
                next[key] = try self.index(input, .string(key))
                try self.buildObject(remaining, input, env, next, emit)
            }
        }
        switch entry.key {
        case let .literal(key):
            try withValue(key)
        case let .variable(name):
            guard let bound = env.variables[name] else {
                throw JQError.runtime(Self.text("$\(name) is not defined."))
            }
            if let valueNode = entry.value {
                guard case let .string(key) = bound else {
                    throw JQError.runtime(Self.text("Object keys must be strings."))
                }
                try evaluate(valueNode, input, env) { value in
                    var next = partial
                    next[key] = value
                    try self.buildObject(remaining, input, env, next, emit)
                }
            } else {
                var next = partial
                next[name] = bound
                try buildObject(remaining, input, env, next, emit)
            }
        case let .interpolated(parts):
            try evaluateString(parts, format: nil, input, env, prefix: "") { key in
                guard case let .string(text) = key else {
                    return
                }
                try withValue(text)
            }
        case let .computed(node):
            try evaluate(node, input, env) { key in
                guard case let .string(text) = key else {
                    throw JQError.runtime(Self.text("Object keys must be strings."))
                }
                try withValue(text)
            }
        }
    }

    private func evaluateBranches(
        _ branches: ArraySlice<(condition: JQNode, then: JQNode)>,
        _ otherwise: JQNode?,
        _ input: JQValue,
        _ env: JQEnvironment,
        _ emit: Emit
    )
        throws
    {
        guard let branch = branches.first else {
            if let otherwise {
                try evaluate(otherwise, input, env, emit)
            } else {
                try emit(input)
            }
            return
        }
        try evaluate(branch.condition, input, env) { condition in
            if condition.isTruthy {
                try self.evaluate(branch.then, input, env, emit)
            } else {
                try self.evaluateBranches(branches.dropFirst(), otherwise, input, env, emit)
            }
        }
    }

    private func pathBranches(
        _ branches: ArraySlice<(condition: JQNode, then: JQNode)>,
        _ otherwise: JQNode?,
        _ input: JQValue,
        _ path: [JQValue],
        _ env: JQEnvironment,
        _ emit: PathEmit
    )
        throws
    {
        guard let branch = branches.first else {
            if let otherwise {
                try paths(otherwise, input, path, env, emit)
            } else {
                try emit(path, input)
            }
            return
        }
        try evaluate(branch.condition, input, env) { condition in
            if condition.isTruthy {
                try self.paths(branch.then, input, path, env, emit)
            } else {
                try self.pathBranches(branches.dropFirst(), otherwise, input, path, env, emit)
            }
        }
    }

    private func evaluateAssignment(
        _ op: JQNode.AssignOperator,
        _ lhs: JQNode,
        _ rhs: JQNode,
        _ input: JQValue,
        _ env: JQEnvironment,
        _ emit: Emit
    )
        throws
    {
        let targets = try collectPaths(lhs, input, env)
        switch op {
        case .update:
            var result = input
            var deletions: [[JQValue]] = []
            for path in targets {
                let old = try JQPaths.get(result, path)
                let replacement = try first(rhs, old, env)
                if let replacement {
                    result = try JQPaths.set(result, path, replacement)
                } else {
                    deletions.append(path)
                }
            }
            try emit(JQPaths.delete(result, deletions))
        case .set:
            try evaluate(rhs, input, env) { value in
                var result = input
                for path in targets {
                    result = try JQPaths.set(result, path, value)
                }
                try emit(result)
            }
        default:
            try evaluate(rhs, input, env) { operand in
                var result = input
                for path in targets {
                    let old = try JQPaths.get(result, path)
                    let updated: JQValue = switch op {
                    case .add: try self.add(old, operand)
                    case .subtract: try self.subtract(old, operand)
                    case .multiply: try self.multiply(old, operand)
                    case .divide: try self.divide(old, operand)
                    case .modulo: try self.modulo(old, operand)
                    default: old.isTruthy ? old : operand
                    }
                    result = try JQPaths.set(result, path, updated)
                }
                try emit(result)
            }
        }
    }
}

// MARK: - JQPaths

enum JQPaths {
    // MARK: Internal

    static func get(_ value: JQValue, _ path: [JQValue]) throws -> JQValue {
        var current = value
        for key in path {
            if current == .null {
                return .null
            }
            current = try JQInterpreter(limits: .default).index(current, key)
        }
        return current
    }

    static func set(_ value: JQValue, _ path: [JQValue], _ newValue: JQValue) throws -> JQValue {
        guard let key = path.first else {
            return newValue
        }
        let rest = Array(path.dropFirst())
        switch (value, key) {
        case let (.object(object), .string(name)):
            var copy = object
            copy[name] = try set(object[name] ?? .null, rest, newValue)
            return .object(copy)
        case let (.null, .string(name)):
            var object = JQObject()
            object[name] = try set(.null, rest, newValue)
            return .object(object)
        case let (.array(items), .number(number)):
            return try .array(setIndex(items, number, rest, newValue))
        case let (.null, .number(number)):
            return try .array(setIndex([], number, rest, newValue))
        case let (_, .object(range)) where value == .null || value.arrayValue != nil:
            let source = value.arrayValue ?? []
            let start = sliceBound(range["start"], source.count, fallback: 0)
            let end = max(start, sliceBound(range["end"], source.count, fallback: source.count))
            let current = JQValue.array(Array(source[start ..< end]))
            guard case let .array(replacement) = try set(current, rest, newValue) else {
                throw JQError.runtime(JQInterpreter.text("A slice can only be replaced with an array."))
            }
            return .array(Array(source[..<start]) + replacement + Array(source[end...]))
        default:
            throw JQError.runtime(JQInterpreter.text(
                "Cannot set \(JQInterpreter.describe(key)) on \(value.typeName)."
            ))
        }
    }

    static func delete(_ value: JQValue, _ paths: [[JQValue]]) throws -> JQValue {
        // Delete deepest and highest-indexed paths first so earlier deletions do not shift later ones.
        let ordered = paths.sorted { JQValue.compare(.array($0), .array($1)) > 0 }
        var result = value
        for path in ordered where !path.isEmpty {
            result = try deleteOne(result, path)
        }
        if paths.contains(where: \.isEmpty) {
            return .null
        }
        return result
    }

    // MARK: Private

    private static func setIndex(
        _ items: [JQValue],
        _ number: Double,
        _ rest: [JQValue],
        _ newValue: JQValue
    )
        throws -> [JQValue]
    {
        guard number.isFinite else {
            throw JQError.runtime(JQInterpreter.text("Array indices must be finite numbers."))
        }
        var offset = Int(number.rounded(.down))
        if offset < 0 {
            offset += items.count
            guard offset >= 0 else {
                throw JQError.runtime(JQInterpreter.text("Out of bounds negative array index."))
            }
        }
        guard offset <= 1_000_000 else {
            throw JQError.limit(JQInterpreter.text("The array index is too large."))
        }
        var copy = items
        while copy.count <= offset {
            copy.append(.null)
        }
        copy[offset] = try set(copy[offset], rest, newValue)
        return copy
    }

    private static func sliceBound(_ value: JQValue?, _ count: Int, fallback: Int) -> Int {
        guard case let .number(number)? = value, number.isFinite else {
            return fallback
        }
        var offset = Int(number.rounded(.down))
        if offset < 0 {
            offset += count
        }
        return min(max(offset, 0), count)
    }

    private static func deleteOne(_ value: JQValue, _ path: [JQValue]) throws -> JQValue {
        guard let key = path.first else {
            return value
        }
        if path.count == 1 {
            switch (value, key) {
            case (.null, _):
                return .null
            case let (.object(object), .string(name)):
                var copy = object
                copy[name] = nil
                return .object(copy)
            case let (.array(items), .number(number)):
                var offset = Int(number.rounded(.down))
                if offset < 0 {
                    offset += items.count
                }
                guard items.indices.contains(offset) else {
                    return value
                }
                var copy = items
                copy.remove(at: offset)
                return .array(copy)
            case let (.array(items), .object(range)):
                let start = sliceBound(range["start"], items.count, fallback: 0)
                let end = max(start, sliceBound(range["end"], items.count, fallback: items.count))
                return .array(Array(items[..<start]) + Array(items[end...]))
            default:
                throw JQError
                    .runtime(JQInterpreter.text("Cannot delete \(JQInterpreter.describe(key)) from \(value.typeName)."))
            }
        }
        let child = try get(value, [key])
        guard child != .null else {
            return value
        }
        return try set(value, [key], deleteOne(child, Array(path.dropFirst())))
    }
}
