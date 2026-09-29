import Foundation

// jq's built-in functions and @formats.

// MARK: - Builtins

extension JQInterpreter {
    // MARK: Internal

    // swiftlint:disable:next function_body_length
    func callBuiltin(_ name: String, _ args: [JQNode], _ input: JQValue, _ env: JQEnvironment, _ emit: Emit) throws {
        if args.isEmpty, let result = try simpleBuiltin(name, input) {
            try emit(result)
            return
        }
        switch (name, args.count) {
        case ("empty", 0):
            return
        case ("objects", 0),
             ("arrays", 0),
             ("strings", 0),
             ("numbers", 0),
             ("booleans", 0),
             ("nulls", 0),
             ("iterables", 0),
             ("scalars", 0):
            if Self.matchesTypeFilter(name, input) {
                try emit(input)
            }
        case ("error", 0):
            throw RaisedError(value: input)
        case ("error", 1):
            try evaluate(args[0], input, env) { throw RaisedError(value: $0) }
        case ("not", 0):
            try emit(.bool(!input.isTruthy))
        case ("recurse", 0):
            try evaluate(.recurseAll, input, env, emit)
        case ("recurse", 1):
            try recurse(args[0], input, env, emit)
        case ("recurse", 2):
            try recurse(args[0], input, env, condition: args[1], emit)
        case ("values", 0):
            if input != .null {
                try emit(input)
            }
        case ("paths", 0):
            try recursePathsExcludingRoot(input) { path, _ in try emit(.array(path)) }
        case ("paths", 1):
            try recursePathsExcludingRoot(input) { path, value in
                if try self.first(args[0], value, env)?.isTruthy == true {
                    try emit(.array(path))
                }
            }
        case ("leaf_paths", 0):
            try recursePathsExcludingRoot(input) { path, value in
                if value.arrayValue == nil, value.objectValue == nil {
                    try emit(.array(path))
                }
            }
        case ("first", 0):
            try emit(index(input, .number(0)))
        case ("last", 0):
            try emit(index(input, .number(-1)))
        case ("input", 0),
             ("inputs", 0):
            throw JQError.runtime(Self.text("input and inputs are not available in the inspector."))
        case ("debug", _),
             ("stderr", 0):
            try emit(input)
        case ("env", 0):
            try emit(.object(JQObject()))
        case ("input_filename", 0):
            try emit(.null)
        case ("now", 0):
            try emit(.number(Date().timeIntervalSince1970))
        case ("map", 1):
            try iterateValues(input) { items in
                var mapped: [JQValue] = []
                for item in items {
                    try self.evaluate(args[0], item, env) { mapped.append($0) }
                }
                try emit(.array(mapped))
            }
        case ("map_values", 1):
            try emit(mapValues(input, args[0], env))
        case ("select", 1):
            try evaluate(args[0], input, env) { condition in
                if condition.isTruthy {
                    try emit(input)
                }
            }
        case ("with_entries", 1):
            let entries = try toEntries(input)
            var mapped: [JQValue] = []
            for entry in entries {
                try evaluate(args[0], entry, env) { mapped.append($0) }
            }
            try emit(fromEntries(mapped))
        case ("walk", 1):
            try walk(input, args[0], env, emit)
        case ("path", 1):
            try paths(args[0], input, [], env) { path, _ in try emit(.array(path)) }
        case ("del", 1):
            try emit(JQPaths.delete(input, collectPaths(args[0], input, env)))
        case ("to_entries", 0):
            try emit(.array(toEntries(input)))
        case ("from_entries", 0):
            try emit(fromEntries(input.arrayValue ?? []))
        case ("getpath", 1):
            try evaluate(args[0], input, env) { path in
                guard case let .array(keys) = path else {
                    throw JQError.runtime(Self.text("Path must be specified as an array."))
                }
                do {
                    try emit(JQPaths.get(input, keys))
                } catch let error where Self.isCatchable(error) {
                    try emit(.null)
                }
            }
        case ("setpath", 2):
            try evaluate(args[1], input, env) { value in
                try self.evaluate(args[0], input, env) { path in
                    guard case let .array(keys) = path else {
                        throw JQError.runtime(Self.text("Path must be specified as an array."))
                    }
                    try emit(JQPaths.set(input, keys, value))
                }
            }
        case ("delpaths", 1):
            try evaluate(args[0], input, env) { list in
                guard case let .array(items) = list else {
                    throw JQError.runtime(Self.text("Paths must be specified as an array."))
                }
                let paths = try items.map { item -> [JQValue] in
                    guard case let .array(keys) = item else {
                        throw JQError.runtime(Self.text("Path must be specified as an array."))
                    }
                    return keys
                }
                try emit(JQPaths.delete(input, paths))
            }
        case ("first", 1):
            if let value = try first(args[0], input, env) {
                try emit(value)
            }
        case ("last", 1):
            var lastValue: JQValue?
            try evaluate(args[0], input, env) { lastValue = $0 }
            if let lastValue {
                try emit(lastValue)
            }
        case ("isempty", 1):
            try emit(.bool(first(args[0], input, env) == nil))
        case ("limit", 2):
            try evaluate(args[0], input, env) { count in
                guard let limit = count.numberValue else {
                    throw JQError.runtime(Self.text("limit needs a number."))
                }
                guard limit > 0 else {
                    return
                }
                var produced = 0
                try self.withStop { stop in
                    try self.evaluate(args[1], input, env) { value in
                        produced += 1
                        try emit(value)
                        if Double(produced) >= limit {
                            throw stop
                        }
                    }
                }
            }
        case ("nth", 1):
            try evaluate(args[0], input, env) { try emit(self.index(input, $0)) }
        case ("nth", 2):
            try evaluate(args[0], input, env) { count in
                guard let target = count.numberValue, target >= 0 else {
                    throw JQError.runtime(Self.text("nth needs a non-negative index."))
                }
                var seen = 0.0
                var match: JQValue?
                try self.withStop { stop in
                    try self.evaluate(args[1], input, env) { value in
                        if seen == target {
                            match = value
                            throw stop
                        }
                        seen += 1
                    }
                }
                if let match {
                    try emit(match)
                }
            }
        case ("until", 2):
            var current = input
            while true {
                try step()
                guard let condition = try first(args[0], current, env) else {
                    return
                }
                if condition.isTruthy {
                    try emit(current)
                    return
                }
                guard let next = try first(args[1], current, env) else {
                    return
                }
                current = next
            }
        case ("while", 2):
            var current = input
            while true {
                try step()
                guard let condition = try first(args[0], current, env), condition.isTruthy else {
                    return
                }
                try emit(current)
                guard let next = try first(args[1], current, env) else {
                    return
                }
                current = next
            }
        case ("repeat", 1):
            try repeatValues(input, args[0], env, emit)
        case ("range", 1):
            try evaluate(args[0], input, env) { upper in
                try self.range(from: .number(0), to: upper, by: .number(1), emit)
            }
        case ("range", 2):
            try withValues(args, input, env) { values in
                try self.range(from: values[0], to: values[1], by: .number(1), emit)
            }
        case ("range", 3):
            try withValues(args, input, env) { values in
                try self.range(from: values[0], to: values[1], by: values[2], emit)
            }
        case ("add", 1):
            var total = JQValue.null
            try evaluate(args[0], input, env) { total = try self.add(total, $0) }
            try emit(total)
        case ("any", 1),
             ("all", 1):
            let isAny = name == "any"
            var result = !isAny
            try withStop { stop in
                try self.iterate(input) { item in
                    let truthy = try self.first(args[0], item, env)?.isTruthy ?? false
                    if truthy == isAny {
                        result = isAny
                        throw stop
                    }
                }
            }
            try emit(.bool(result))
        case ("any", 2),
             ("all", 2):
            let isAny = name == "any"
            var result = !isAny
            try withStop { stop in
                try self.evaluate(args[0], input, env) { item in
                    let truthy = try self.first(args[1], item, env)?.isTruthy ?? false
                    if truthy == isAny {
                        result = isAny
                        throw stop
                    }
                }
            }
            try emit(.bool(result))
        case ("IN", 1):
            var found = false
            try withStop { stop in
                try self.evaluate(args[0], input, env) { candidate in
                    if candidate == input {
                        found = true
                        throw stop
                    }
                }
            }
            try emit(.bool(found))
        case ("IN", 2):
            let candidates = try all(args[1], input, env)
            try evaluate(args[0], input, env) { value in
                try emit(.bool(candidates.contains(value)))
            }
        case ("sort_by", 1),
             ("group_by", 1),
             ("unique_by", 1),
             ("min_by", 1),
             ("max_by", 1):
            try emit(byKey(name, input, args[0], env))
        default:
            if try callValueBuiltin(name, args, input, env, emit) {
                return
            }
            throw JQError.runtime(Self.text("\(name)/\(args.count) is not a known function."))
        }
    }

    func callPathBuiltin(
        _ name: String,
        _ args: [JQNode],
        _ input: JQValue,
        _ path: [JQValue],
        _ env: JQEnvironment,
        _ emit: PathEmit
    )
        throws
    {
        switch (name, args.count) {
        case ("empty", 0):
            return
        case ("error", _):
            try callBuiltin(name, args, input, env) { _ in }
        case ("select", 1):
            try evaluate(args[0], input, env) { condition in
                if condition.isTruthy {
                    try emit(path, input)
                }
            }
        case ("recurse", 0):
            try paths(.recurseAll, input, path, env, emit)
        case ("recurse", 1):
            try recursePathsWith(args[0], input, path, env, emit)
        case ("first", 0):
            try emit(path + [.number(0)], index(input, .number(0)))
        case ("last", 0):
            try emit(path + [.number(-1)], index(input, .number(-1)))
        case ("first", 1):
            var found: ([JQValue], JQValue)?
            try withStop { stop in
                try self.paths(args[0], input, path, env) { foundPath, value in
                    found = (foundPath, value)
                    throw stop
                }
            }
            if let found {
                try emit(found.0, found.1)
            }
        case ("last", 1):
            var found: ([JQValue], JQValue)?
            try paths(args[0], input, path, env) { found = ($0, $1) }
            if let found {
                try emit(found.0, found.1)
            }
        case ("getpath", 1):
            try evaluate(args[0], input, env) { keys in
                guard case let .array(extra) = keys else {
                    throw JQError.runtime(Self.text("Path must be specified as an array."))
                }
                try emit(path + extra, JQPaths.get(input, extra))
            }
        case ("limit", 2):
            try evaluate(args[0], input, env) { count in
                guard let limit = count.numberValue, limit > 0 else {
                    return
                }
                var produced = 0.0
                try self.withStop { stop in
                    try self.paths(args[1], input, path, env) { foundPath, value in
                        produced += 1
                        try emit(foundPath, value)
                        if produced >= limit {
                            throw stop
                        }
                    }
                }
            }
        default:
            throw JQError.runtime(Self.text("\(name)/\(args.count) cannot be used as a path expression."))
        }
    }

    func format(_ value: JQValue, as name: String) throws -> String {
        switch name {
        case "text":
            return tostring(value)
        case "json":
            return value.jsonText()
        case "html":
            return tostring(value)
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "'", with: "&#39;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        case "uri":
            var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: "\u{0}" ... "\u{7F}"))
            allowed.insert(charactersIn: "-_.~")
            return tostring(value).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        case "csv",
             "tsv":
            guard case let .array(items) = value else {
                throw JQError.runtime(Self.text("@\(name) needs an array."))
            }
            let fields = try items.map { item -> String in
                switch item {
                case let .number(number):
                    return JQValue.formatNumber(number)
                case let .bool(flag):
                    return flag ? "true" : "false"
                case .null:
                    return ""
                case let .string(text):
                    if name == "csv" {
                        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    }
                    return text
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\t", with: "\\t")
                        .replacingOccurrences(of: "\n", with: "\\n")
                        .replacingOccurrences(of: "\r", with: "\\r")
                default:
                    throw JQError.runtime(Self.text("\(item.typeName) is not valid in @\(name)."))
                }
            }
            return fields.joined(separator: name == "csv" ? "," : "\t")
        case "sh":
            let quote: (JQValue) throws -> String = { item in
                switch item {
                case let .string(text):
                    return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
                case .array,
                     .object:
                    throw JQError.runtime(Self.text("\(item.typeName) cannot be escaped for a shell."))
                default:
                    return item.jsonText()
                }
            }
            if case let .array(items) = value {
                return try items.map(quote).joined(separator: " ")
            }
            return try quote(value)
        case "base64":
            return Data(tostring(value).utf8).base64EncodedString()
        case "base64d":
            let text = tostring(value)
            var padded = text.trimmingCharacters(in: .whitespacesAndNewlines)
            while padded.count % 4 != 0 {
                padded += "="
            }
            guard let data = Data(base64Encoded: padded) else {
                throw JQError.runtime(Self.text("The string is not valid base64."))
            }
            guard let decoded = String(bytes: data, encoding: .utf8) else {
                throw JQError.runtime(Self.text("The decoded base64 is not UTF-8 text."))
            }
            return decoded
        default:
            throw JQError.runtime(Self.text("@\(name) is not a known format."))
        }
    }

    func tostring(_ value: JQValue) -> String {
        if case let .string(text) = value {
            return text
        }
        return value.jsonText()
    }

    // MARK: Private

    private static let mathFunctions: [String: (Double) -> Double] = [
        "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) }, "round": { $0.rounded(.toNearestOrAwayFromZero) },
        "trunc": { $0.rounded(.towardZero) }, "sqrt": { $0.squareRoot() }, "fabs": { abs($0) },
        "log": { Foundation.log($0) }, "log2": { Foundation.log2($0) }, "log10": { Foundation.log10($0) },
        "exp": { Foundation.exp($0) }, "exp2": { Foundation.exp2($0) }, "exp10": { Foundation.pow(10, $0) },
        "sin": { Foundation.sin($0) }, "cos": { Foundation.cos($0) }, "tan": { Foundation.tan($0) },
    ]

    // swiftlint:disable:next function_body_length
    private func simpleBuiltin(_ name: String, _ input: JQValue) throws -> JQValue? {
        if let math = Self.mathFunctions[name] {
            guard case let .number(number) = input else {
                throw JQError.runtime(Self.text("\(Self.describe(input)) has no \(name)."))
            }
            return .number(math(number))
        }
        switch name {
        case "length":
            switch input {
            case .null: return .number(0)
            case .bool: throw JQError.runtime(Self.text("boolean has no length."))
            case let .number(number): return .number(abs(number))
            case let .string(text): return .number(Double(text.unicodeScalars.count))
            case let .array(items): return .number(Double(items.count))
            case let .object(object): return .number(Double(object.count))
            }
        case "utf8bytelength":
            guard case let .string(text) = input else {
                throw JQError.runtime(Self.text("\(Self.describe(input)) has no UTF-8 byte length; only strings do."))
            }
            return .number(Double(text.utf8.count))
        case "abs":
            guard case let .number(number) = input else {
                throw JQError.runtime(Self.text("\(Self.describe(input)) has no absolute value."))
            }
            return .number(abs(number))
        case "keys",
             "keys_unsorted":
            switch input {
            case let .object(object):
                return .array((name == "keys" ? object.sortedKeys : object.keys).map(JQValue.string))
            case let .array(items):
                return .array(items.indices.map { .number(Double($0)) })
            default:
                throw JQError.runtime(Self.text("\(Self.describe(input)) has no keys."))
            }
        case "add":
            var total = JQValue.null
            try iterate(input) { total = try self.add(total, $0) }
            return total
        case "any",
             "all":
            var values: [JQValue] = []
            try iterate(input) { values.append($0) }
            return .bool(name == "any" ? values.contains(where: \.isTruthy) : values.allSatisfy(\.isTruthy))
        case "flatten":
            return try .array(flatten(requireArray(input, name), depth: .max))
        case "type":
            return .string(input.typeName)
        case "tostring":
            return .string(tostring(input))
        case "tonumber":
            switch input {
            case .number:
                return input
            case let .string(text):
                guard let number = Double(text.trimmingCharacters(in: .whitespaces)) else {
                    throw JQError.runtime(Self.text("Cannot parse “\(text)” as a number."))
                }
                return .number(number)
            default:
                throw JQError.runtime(Self.text("\(Self.describe(input)) cannot be parsed as a number."))
            }
        case "tojson":
            return .string(input.jsonText())
        case "fromjson":
            guard case let .string(text) = input else {
                throw JQError.runtime(Self.text("\(Self.describe(input)) cannot be parsed as JSON."))
            }
            return try JQValue.parse(text)
        case "infinite":
            return .number(.infinity)
        case "nan":
            return .number(.nan)
        case "isinfinite":
            return .bool(input.numberValue?.isInfinite ?? false)
        case "isnan":
            return .bool(input.numberValue?.isNaN ?? false)
        case "isnormal":
            return .bool(input.numberValue?.isNormal ?? false)
        case "sort":
            return try .array(requireArray(input, name).sorted { JQValue.compare($0, $1) < 0 })
        case "unique":
            let sorted = try requireArray(input, name).sorted { JQValue.compare($0, $1) < 0 }
            return .array(sorted.reduce(into: []) { result, item in
                if result.last != item {
                    result.append(item)
                }
            })
        case "min",
             "max":
            let items = try requireArray(input, name)
            let best = items.dropFirst().reduce(items.first) { best, item in
                guard let best else {
                    return item
                }
                let order = JQValue.compare(item, best)
                return (name == "min" ? order < 0 : order >= 0) ? item : best
            }
            return best ?? .null
        case "reverse":
            switch input {
            case .null: return .array([])
            case let .string(text): return .string(String(text.reversed()))
            case let .array(items): return .array(items.reversed())
            default: throw JQError.runtime(Self.text("\(Self.describe(input)) cannot be reversed."))
            }
        case "ascii_downcase",
             "ascii_upcase":
            guard case let .string(text) = input else {
                throw JQError.runtime(Self.text("\(name) needs a string."))
            }
            let scalars = text.unicodeScalars.map { scalar -> Unicode.Scalar in
                let isUpper = ("A" ... "Z").contains(scalar)
                let isLower = ("a" ... "z").contains(scalar)
                if name == "ascii_downcase", isUpper {
                    return Unicode.Scalar(scalar.value + 32) ?? scalar
                }
                if name == "ascii_upcase", isLower {
                    return Unicode.Scalar(scalar.value - 32) ?? scalar
                }
                return scalar
            }
            return .string(String(String.UnicodeScalarView(scalars)))
        case "trim",
             "ltrim",
             "rtrim":
            guard case let .string(text) = input else {
                throw JQError.runtime(Self.text("\(name) needs a string."))
            }
            var scalars = Substring(text).unicodeScalars[...]
            if name != "rtrim" {
                while let first = scalars.first, CharacterSet.whitespacesAndNewlines.contains(first) {
                    scalars = scalars.dropFirst()
                }
            }
            if name != "ltrim" {
                while let last = scalars.last, CharacterSet.whitespacesAndNewlines.contains(last) {
                    scalars = scalars.dropLast()
                }
            }
            return .string(String(String.UnicodeScalarView(scalars)))
        case "explode":
            guard case let .string(text) = input else {
                throw JQError.runtime(Self.text("explode needs a string."))
            }
            return .array(text.unicodeScalars.map { .number(Double($0.value)) })
        case "implode":
            let items = try requireArray(input, name)
            let scalars = try items.map { item -> Unicode.Scalar in
                guard case let .number(code) = item, let scalar = Unicode.Scalar(UInt32(clamping: Int(code))) else {
                    throw JQError.runtime(Self.text("implode needs an array of codepoints."))
                }
                return scalar
            }
            return .string(String(String.UnicodeScalarView(scalars)))
        case "ascii":
            guard case let .number(code) = input, let scalar = Unicode.Scalar(UInt32(clamping: Int(code))) else {
                throw JQError.runtime(Self.text("ascii needs a codepoint."))
            }
            return .string(String(scalar))
        case "toarray":
            return input.arrayValue == nil ? .array([input]) : input
        case "transpose":
            let rows = try requireArray(input, name).map { $0.arrayValue ?? [] }
            let width = rows.map(\.count).max() ?? 0
            return .array((0 ..< width).map { column in
                .array(rows.map { column < $0.count ? $0[column] : .null })
            })
        case "todate",
             "todateiso8601":
            guard case let .number(seconds) = input else {
                throw JQError.runtime(Self.text("\(name) needs a number of seconds."))
            }
            return .string(Self.isoFormatter.string(from: Date(timeIntervalSince1970: seconds.rounded(.down))))
        case "fromdate",
             "fromdateiso8601":
            guard case let .string(text) = input, let date = Self.isoFormatter.date(from: text) else {
                throw JQError.runtime(Self.text("\(Self.describe(input)) does not match the date format."))
            }
            return .number(date.timeIntervalSince1970)
        default:
            return nil
        }
    }

    private static func matchesTypeFilter(_ name: String, _ input: JQValue) -> Bool {
        switch (name, input) {
        case ("objects", .object),
             ("arrays", .array),
             ("strings", .string),
             ("numbers", .number),
             ("booleans", .bool),
             ("nulls", .null),
             ("iterables", .array),
             ("iterables", .object):
            true
        case ("scalars", .array),
             ("scalars", .object):
            false
        case ("scalars", _):
            true
        default:
            false
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func requireArray(_ value: JQValue, _ name: String) throws -> [JQValue] {
        guard case let .array(items) = value else {
            throw JQError.runtime(Self.text("\(Self.describe(value)) cannot be used with \(name); it needs an array."))
        }
        return items
    }

    private func flatten(_ items: [JQValue], depth: Int) throws -> [JQValue] {
        var result: [JQValue] = []
        for item in items {
            try step()
            if case let .array(nested) = item, depth > 0 {
                result += try flatten(nested, depth: depth - 1)
            } else {
                result.append(item)
            }
        }
        return result
    }

    private func iterateValues(_ input: JQValue, _ body: ([JQValue]) throws -> Void) throws {
        switch input {
        case let .array(items): try body(items)
        case let .object(object): try body(object.values)
        default: throw JQError.runtime(Self.text("Cannot iterate over \(input.typeName)."))
        }
    }

    private func mapValues(_ input: JQValue, _ transform: JQNode, _ env: JQEnvironment) throws -> JQValue {
        switch input {
        case let .array(items):
            var mapped: [JQValue] = []
            for item in items {
                if let value = try first(transform, item, env) {
                    mapped.append(value)
                }
            }
            return .array(mapped)
        case let .object(object):
            var mapped = JQObject()
            for (key, value) in object.pairs {
                if let transformed = try first(transform, value, env) {
                    mapped[key] = transformed
                }
            }
            return .object(mapped)
        default:
            throw JQError.runtime(Self.text("Cannot iterate over \(input.typeName)."))
        }
    }

    private func toEntries(_ input: JQValue) throws -> [JQValue] {
        switch input {
        case let .object(object):
            return object.pairs.map { .object(JQObject([("key", .string($0.key)), ("value", $0.value)])) }
        case let .array(items):
            return items.enumerated().map { entry in
                .object(JQObject([("key", .number(Double(entry.offset))), ("value", entry.element)]))
            }
        default:
            throw JQError.runtime(Self.text("\(Self.describe(input)) has no keys."))
        }
    }

    private func fromEntries(_ entries: [JQValue]) throws -> JQValue {
        var object = JQObject()
        for entry in entries {
            guard case let .object(fields) = entry else {
                throw JQError.runtime(Self.text("from_entries needs objects with key and value."))
            }
            let rawKey = ["key", "k", "name", "Name", "Key", "K"].lazy.compactMap { fields[$0] }
                .first { $0 != .null } ?? .null
            let value = ["value", "v", "Value", "V"].lazy.compactMap { fields[$0] }.first ?? .null
            let key: String = switch rawKey {
            case let .string(text): text
            case .null: "null"
            case .number,
                 .bool: rawKey.jsonText()
            default:
                throw JQError.runtime(Self.text("Object keys must be strings."))
            }
            object[key] = value
        }
        return .object(object)
    }

    private func walk(_ value: JQValue, _ transform: JQNode, _ env: JQEnvironment, _ emit: Emit) throws {
        try step()
        let rebuilt: JQValue
        switch value {
        case let .array(items):
            var mapped: [JQValue] = []
            for item in items {
                try walk(item, transform, env) { mapped.append($0) }
            }
            rebuilt = .array(mapped)
        case let .object(object):
            var mapped = JQObject()
            for (key, item) in object.pairs {
                var firstValue: JQValue?
                try walk(item, transform, env) { walked in
                    if firstValue == nil {
                        firstValue = walked
                    }
                }
                if let firstValue {
                    mapped[key] = firstValue
                }
            }
            rebuilt = .object(mapped)
        default:
            rebuilt = value
        }
        try evaluate(transform, rebuilt, env, emit)
    }

    private func recurse(
        _ next: JQNode,
        _ input: JQValue,
        _ env: JQEnvironment,
        condition: JQNode? = nil,
        _ emit: Emit
    )
        throws
    {
        try step()
        try emit(input)
        try evaluate(next, input, env) { child in
            if let condition, try self.first(condition, child, env)?.isTruthy != true {
                return
            }
            try self.recurse(next, child, env, condition: condition, emit)
        }
    }

    private func recursePathsWith(
        _ next: JQNode,
        _ input: JQValue,
        _ path: [JQValue],
        _ env: JQEnvironment,
        _ emit: PathEmit
    )
        throws
    {
        try step()
        try emit(path, input)
        try paths(next, input, path, env) { childPath, child in
            try self.recursePathsWith(next, child, childPath, env, emit)
        }
    }

    private func recursePathsExcludingRoot(_ input: JQValue, _ emit: PathEmit) throws {
        try paths(.recurseAll, input, [], JQEnvironment()) { path, value in
            if !path.isEmpty {
                try emit(path, value)
            }
        }
    }

    private func repeatValues(_ input: JQValue, _ next: JQNode, _ env: JQEnvironment, _ emit: Emit) throws {
        try step()
        try emit(input)
        try evaluate(next, input, env) { child in
            try self.repeatValues(child, next, env, emit)
        }
    }

    private func range(from start: JQValue, to end: JQValue, by increment: JQValue, _ emit: Emit) throws {
        guard case let .number(lower) = start, case let .number(upper) = end,
              case let .number(stride) = increment else
        {
            throw JQError.runtime(Self.text("range needs numbers."))
        }
        guard stride != 0 else {
            return
        }
        var value = lower
        while stride > 0 ? value < upper : value > upper {
            try step()
            try emit(.number(value))
            value += stride
        }
    }

    /// Evaluates each argument and calls `body` for every combination of their outputs.
    private func withValues(
        _ args: [JQNode],
        _ input: JQValue,
        _ env: JQEnvironment,
        _ body: ([JQValue]) throws -> Void
    )
        throws
    {
        func combine(_ index: Int, _ collected: [JQValue]) throws {
            guard index < args.count else {
                try body(collected)
                return
            }
            try evaluate(args[index], input, env) { value in
                try combine(index + 1, collected + [value])
            }
        }
        try combine(0, [])
    }

    private func byKey(_ name: String, _ input: JQValue, _ keyNode: JQNode, _ env: JQEnvironment) throws -> JQValue {
        let items = try requireArray(input, name)
        let keyed = try items.map { item in
            try (key: JQValue.array(all(keyNode, item, env)), item: item)
        }
        let sorted = keyed.enumerated().sorted { lhs, rhs in
            let order = JQValue.compare(lhs.element.key, rhs.element.key)
            return order == 0 ? lhs.offset < rhs.offset : order < 0
        }.map(\.element)
        switch name {
        case "sort_by":
            return .array(sorted.map(\.item))
        case "min_by":
            return sorted.first?.item ?? .null
        case "max_by":
            return sorted.last?.item ?? .null
        default:
            var groups: [[JQValue]] = []
            var lastKey: JQValue?
            for entry in sorted {
                if let lastKey, lastKey == entry.key {
                    groups[groups.count - 1].append(entry.item)
                } else {
                    groups.append([entry.item])
                }
                lastKey = entry.key
            }
            if name == "unique_by" {
                return .array(groups.compactMap(\.first))
            }
            return .array(groups.map { .array($0) })
        }
    }
}
