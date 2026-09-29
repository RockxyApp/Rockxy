import Foundation

// jq built-ins whose arguments are values (has, split, join, test, sub, …), including the
// regular-expression family.

// MARK: - Value-argument builtins

extension JQInterpreter {
    // MARK: Internal

    /// Handles built-ins that take value arguments. Returns `false` for unknown names.
    func callValueBuiltin(
        _ name: String,
        _ args: [JQNode],
        _ input: JQValue,
        _ env: JQEnvironment,
        _ emit: Emit
    )
        throws -> Bool
    {
        switch (name, args.count) {
        case ("sub", 2),
             ("sub", 3),
             ("gsub", 2),
             ("gsub", 3):
            try substitute(name == "gsub", args, input, env, emit)
            return true
        default:
            break
        }
        let key = "\(name)/\(args.count)"
        let isGenerator = Self.generatingBuiltins.contains(key)
        guard isGenerator || Self.valueBuiltins.contains(key) else {
            return false
        }
        try combinations(args, input, env) { values in
            if isGenerator {
                try self.applyGeneratingBuiltin(name, values, input, emit)
            } else {
                try emit(self.applyValueBuiltin(name, values, input))
            }
        }
        return true
    }

    // MARK: Private

    private static let valueBuiltins: Set<String> = [
        "has/1", "in/1", "inside/1", "contains/1", "startswith/1", "endswith/1", "ltrimstr/1", "rtrimstr/1",
        "split/1", "split/2", "join/1", "test/1", "test/2", "capture/1", "capture/2", "index/1", "rindex/1",
        "indices/1", "flatten/1", "pow/2", "tostring/1",
    ]

    private static let generatingBuiltins: Set<String> = [
        "match/1", "match/2", "scan/1", "scan/2", "splits/1", "splits/2",
    ]

    /// Calls `body` for every combination of the arguments' outputs, as jq does for `$arg` parameters.
    private func combinations(
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

    private func applyValueBuiltin(_ name: String, _ values: [JQValue], _ input: JQValue) throws -> JQValue {
        let argument = values.first ?? .null
        switch name {
        case "has":
            switch (input, argument) {
            case let (.object(object), .string(key)):
                return .bool(object[key] != nil)
            case let (.array(items), .number(offset)):
                return .bool(offset >= 0 && offset < Double(items.count))
            default:
                throw JQError
                    .runtime(Self.text("Cannot check whether \(input.typeName) has a \(argument.typeName) key."))
            }
        case "in":
            return try applyValueBuiltin("has", [input], argument)
        case "contains":
            return try .bool(contains(input, argument))
        case "inside":
            return try .bool(contains(argument, input))
        case "startswith",
             "endswith":
            guard case let .string(text) = input, case let .string(affix) = argument else {
                throw JQError.runtime(Self.text("\(name) needs string input and argument."))
            }
            return .bool(name == "startswith" ? text.hasPrefix(affix) : text.hasSuffix(affix))
        case "ltrimstr",
             "rtrimstr":
            guard case let .string(text) = input, case let .string(affix) = argument, !affix.isEmpty else {
                return input
            }
            if name == "ltrimstr", text.hasPrefix(affix) {
                return .string(String(text.dropFirst(affix.count)))
            }
            if name == "rtrimstr", text.hasSuffix(affix) {
                return .string(String(text.dropLast(affix.count)))
            }
            return input
        case "split":
            guard case let .string(text) = input else {
                throw JQError.runtime(Self.text("split needs a string."))
            }
            if values.count == 2 {
                return try .array(regexSplit(text, argument, values[1]).map(JQValue.string))
            }
            guard case let .string(separator) = argument else {
                throw JQError.runtime(Self.text("split needs a string separator."))
            }
            return .array(split(text, by: separator).map(JQValue.string))
        case "join":
            guard case let .array(items) = input else {
                throw JQError.runtime(Self.text("join needs an array."))
            }
            let separator = tostring(argument)
            let pieces = try items.map { item -> String in
                switch item {
                case .null: return ""
                case let .string(text): return text
                case .number,
                     .bool: return item.jsonText()
                default: throw JQError.runtime(Self.text("\(Self.describe(item)) cannot be joined."))
                }
            }
            return .string(pieces.joined(separator: separator))
        case "test":
            let text = try requireString(input, name)
            let regex = try compile(argument, flags: values.count > 1 ? values[1] : .null)
            let range = NSRange(text.startIndex ..< text.endIndex, in: text)
            return .bool(regex.expression.firstMatch(in: text, range: range) != nil)
        case "capture":
            let text = try requireString(input, name)
            let regex = try compile(argument, flags: values.count > 1 ? values[1] : .null)
            let range = NSRange(text.startIndex ..< text.endIndex, in: text)
            guard let match = regex.expression.firstMatch(in: text, range: range) else {
                return .object(JQObject())
            }
            return .object(captureObject(match, regex, in: text))
        case "index",
             "rindex",
             "indices":
            let found = try indicesOf(argument, in: input)
            switch name {
            case "index": return found.first.map { .number(Double($0)) } ?? .null
            case "rindex": return found.last.map { .number(Double($0)) } ?? .null
            default: return .array(found.map { .number(Double($0)) })
            }
        case "flatten":
            guard case let .number(depth) = argument, depth >= 0 else {
                throw JQError.runtime(Self.text("flatten depth must not be negative."))
            }
            guard case let .array(items) = input else {
                throw JQError.runtime(Self.text("flatten needs an array."))
            }
            return try .array(flattenArray(items, depth: Int(min(depth, 10_000))))
        case "pow":
            guard case let .number(base) = values[0], case let .number(exponent) = values[1] else {
                throw JQError.runtime(Self.text("pow needs numbers."))
            }
            return .number(Foundation.pow(base, exponent))
        case "tostring":
            return .string(tostring(argument))
        default:
            throw JQError.runtime(Self.text("\(name)/\(values.count) is not a known function."))
        }
    }

    private func applyGeneratingBuiltin(_ name: String, _ values: [JQValue], _ input: JQValue, _ emit: Emit) throws {
        let text = try requireString(input, name)
        let flags = values.count > 1 ? values[1] : .null
        if name == "splits" {
            for piece in try regexSplit(text, values[0], flags) {
                try emit(.string(piece))
            }
            return
        }
        let regex = try compile(values[0], flags: flags)
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        var matches = regex.expression.matches(in: text, range: range)
        if name == "match", !regex.isGlobal {
            matches = Array(matches.prefix(1))
        }
        for match in matches {
            try step()
            if name == "match" {
                try emit(matchObject(match, regex, in: text))
            } else if match.numberOfRanges > 1 {
                // scan with groups yields the captured strings of each match.
                let groups = (1 ..< match.numberOfRanges).map { group -> JQValue in
                    let groupRange = match.range(at: group)
                    guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: text) else {
                        return .null
                    }
                    return .string(String(text[swiftRange]))
                }
                try emit(.array(groups))
            } else if let swiftRange = Range(match.range, in: text) {
                try emit(.string(String(text[swiftRange])))
            }
        }
    }

    private func requireString(_ value: JQValue, _ name: String) throws -> String {
        guard case let .string(text) = value else {
            throw JQError.runtime(Self.text("\(Self.describe(value)) cannot be matched, as it is not a string."))
        }
        return text
    }

    private func flattenArray(_ items: [JQValue], depth: Int) throws -> [JQValue] {
        var result: [JQValue] = []
        for item in items {
            try step()
            if case let .array(nested) = item, depth > 0 {
                result += try flattenArray(nested, depth: depth - 1)
            } else {
                result.append(item)
            }
        }
        return result
    }

    private func contains(_ container: JQValue, _ element: JQValue) throws -> Bool {
        try step()
        switch (container, element) {
        case let (.object(lhs), .object(rhs)):
            for (key, value) in rhs.pairs {
                guard let existing = lhs[key], try contains(existing, value) else {
                    return false
                }
            }
            return true
        case let (.array(lhs), .array(rhs)):
            for needle in rhs {
                var found = false
                for candidate in lhs where try contains(candidate, needle) {
                    found = true
                    break
                }
                if !found {
                    return false
                }
            }
            return true
        case let (.string(lhs), .string(rhs)):
            return rhs.isEmpty || lhs.contains(rhs)
        default:
            guard container.typeName == element.typeName else {
                throw JQError.runtime(Self.text(
                    "\(Self.describe(container)) and \(Self.describe(element)) cannot have their containment checked."
                ))
            }
            return container == element
        }
    }

    private func indicesOf(_ needle: JQValue, in haystack: JQValue) throws -> [Int] {
        switch (haystack, needle) {
        case (.null, _),
             (_, .null):
            return []
        case let (.string(text), .string(target)):
            guard !target.isEmpty else {
                return []
            }
            let scalars = Array(text.unicodeScalars)
            let pattern = Array(target.unicodeScalars)
            guard pattern.count <= scalars.count else {
                return []
            }
            return (0 ... scalars.count - pattern.count).filter { start in
                Array(scalars[start ..< start + pattern.count]) == pattern
            }
        case let (.array(items), .array(pattern)):
            guard !pattern.isEmpty, pattern.count <= items.count else {
                return []
            }
            return (0 ... items.count - pattern.count).filter { start in
                Array(items[start ..< start + pattern.count]) == pattern
            }
        case let (.array(items), _):
            return items.indices.filter { items[$0] == needle }
        default:
            throw JQError.runtime(Self.text("Cannot find \(needle.typeName) in \(haystack.typeName)."))
        }
    }
}

// MARK: - Regular expressions

extension JQInterpreter {
    struct CompiledRegex {
        let expression: NSRegularExpression
        let isGlobal: Bool
        let groupNames: [String?]
    }

    func compile(_ pattern: JQValue, flags: JQValue) throws -> CompiledRegex {
        guard case let .string(source) = pattern else {
            throw JQError.runtime(Self.text("\(Self.describe(pattern)) cannot be used as a regular expression."))
        }
        guard source.count <= limits.maxRegexPatternLength else {
            throw JQError.limit(Self.text("The regular expression is too long."))
        }
        var options: NSRegularExpression.Options = []
        var isGlobal = false
        if case let .string(flagText) = flags {
            for flag in flagText {
                switch flag {
                case "g": isGlobal = true
                case "i": options.insert(.caseInsensitive)
                case "x": options.insert(.allowCommentsAndWhitespace)
                case "s": options.insert(.dotMatchesLineSeparators)
                case "n",
                     "p",
                     "l": break
                default:
                    throw JQError.runtime(Self.text("\(String(flag)) is not a valid regular expression flag."))
                }
            }
        } else if flags != .null {
            throw JQError.runtime(Self.text("Regular expression flags must be a string."))
        }
        do {
            let expression = try NSRegularExpression(pattern: source, options: options)
            return CompiledRegex(expression: expression, isGlobal: isGlobal, groupNames: Self.groupNames(in: source))
        } catch {
            throw JQError.runtime(Self.text("\(source) is not a valid regular expression."))
        }
    }

    func matchObject(_ match: NSTextCheckingResult, _ regex: CompiledRegex, in text: String) -> JQValue {
        func span(_ range: NSRange) -> (offset: Double, length: Double, string: JQValue) {
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
                return (-1, 0, .null)
            }
            let offset = text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: swiftRange.lowerBound)
            let substring = String(text[swiftRange])
            return (Double(offset), Double(substring.unicodeScalars.count), .string(substring))
        }
        let whole = span(match.range)
        var captures: [JQValue] = []
        if match.numberOfRanges > 1 {
            for group in 1 ..< match.numberOfRanges {
                let part = span(match.range(at: group))
                let name = group - 1 < regex.groupNames.count ? regex.groupNames[group - 1] : nil
                captures.append(.object(JQObject([
                    ("offset", .number(part.offset)),
                    ("length", .number(part.length)),
                    ("string", part.string),
                    ("name", name.map(JQValue.string) ?? .null),
                ])))
            }
        }
        return .object(JQObject([
            ("offset", .number(whole.offset)),
            ("length", .number(whole.length)),
            ("string", whole.string),
            ("captures", .array(captures)),
        ]))
    }

    func captureObject(_ match: NSTextCheckingResult, _ regex: CompiledRegex, in text: String) -> JQObject {
        var object = JQObject()
        guard match.numberOfRanges > 1 else {
            return object
        }
        for group in 1 ..< match.numberOfRanges {
            guard group - 1 < regex.groupNames.count, let name = regex.groupNames[group - 1] else {
                continue
            }
            let range = match.range(at: group)
            if range.location != NSNotFound, let swiftRange = Range(range, in: text) {
                object[name] = .string(String(text[swiftRange]))
            } else {
                object[name] = .null
            }
        }
        return object
    }

    func regexSplit(_ text: String, _ pattern: JQValue, _ flags: JQValue) throws -> [String] {
        let regex = try compile(pattern, flags: flags)
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        var pieces: [String] = []
        var cursor = text.startIndex
        for match in regex.expression.matches(in: text, range: range) {
            try step()
            guard let matchRange = Range(match.range, in: text) else {
                continue
            }
            pieces.append(String(text[cursor ..< matchRange.lowerBound]))
            cursor = matchRange.upperBound
        }
        pieces.append(String(text[cursor...]))
        return pieces
    }

    func substitute(_ global: Bool, _ args: [JQNode], _ input: JQValue, _ env: JQEnvironment, _ emit: Emit) throws {
        guard case let .string(text) = input else {
            throw JQError.runtime(Self.text("\(Self.describe(input)) cannot be matched, as it is not a string."))
        }
        let flagNode = args.count > 2 ? args[2] : JQNode.literal(.null)
        try evaluate(flagNode, input, env) { flags in
            try self.evaluate(args[0], input, env) { pattern in
                let regex = try self.compile(pattern, flags: flags)
                let range = NSRange(text.startIndex ..< text.endIndex, in: text)
                var matches = regex.expression.matches(in: text, range: range)
                if !(global || regex.isGlobal) {
                    matches = Array(matches.prefix(1))
                }
                var result = ""
                var cursor = text.startIndex
                for match in matches {
                    try self.step()
                    guard let matchRange = Range(match.range, in: text) else {
                        continue
                    }
                    result += text[cursor ..< matchRange.lowerBound]
                    let captures = JQValue.object(self.captureObject(match, regex, in: text))
                    guard let replacement = try self.first(args[1], captures, env) else {
                        throw JQError.runtime(Self.text("The replacement produced no string."))
                    }
                    guard case let .string(piece) = replacement else {
                        throw JQError.runtime(Self.text("\(Self.describe(replacement)) cannot be added to a string."))
                    }
                    result += piece
                    cursor = matchRange.upperBound
                }
                result += text[cursor...]
                try emit(.string(result))
            }
        }
    }

    /// Names of capturing groups in order (`nil` for unnamed groups).
    static func groupNames(in pattern: String) -> [String?] {
        let scalars = Array(pattern.unicodeScalars)
        var names: [String?] = []
        var index = 0
        var inClass = false
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\\" {
                index += 2
                continue
            }
            if inClass {
                if scalar == "]" {
                    inClass = false
                }
                index += 1
                continue
            }
            if scalar == "[" {
                inClass = true
            } else if scalar == "(" {
                if index + 1 < scalars.count, scalars[index + 1] == "?" {
                    if index + 2 < scalars.count,
                       scalars[index + 2] == "<" || scalars[index + 2] == "P" || scalars[index + 2] == "'"
                    {
                        var cursor = index + 3
                        if scalars[index + 2] == "P", cursor < scalars.count, scalars[cursor] == "<" {
                            cursor += 1
                        }
                        if cursor < scalars.count, scalars[cursor] != "=", scalars[cursor] != "!" {
                            var name = String.UnicodeScalarView()
                            while cursor < scalars.count, scalars[cursor] != ">", scalars[cursor] != "'" {
                                name.append(scalars[cursor])
                                cursor += 1
                            }
                            names.append(String(name))
                        }
                    }
                } else {
                    names.append(nil)
                }
            }
            index += 1
        }
        return names
    }
}
