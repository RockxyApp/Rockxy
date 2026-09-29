import Foundation

// Tokenizer and recursive-descent parser for the jq filter language subset Rockxy evaluates.

// MARK: - JQError

enum JQError: Error, LocalizedError, Equatable {
    /// A syntax error in the filter.
    case syntax(String)
    /// A runtime error that `try` and `?` can catch; carries jq's error value.
    case runtime(String)
    /// A resource limit was hit; never caught by `try`.
    case limit(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .syntax(message),
             let .runtime(message),
             let .limit(message):
            message
        }
    }
}

// MARK: - JQNode

indirect enum JQNode: Sendable {
    case identity
    case recurseAll
    case literal(JQValue)
    case string([StringPart], format: String?)
    case format(String)
    case index(JQNode, JQNode)
    case slice(JQNode, JQNode?, JQNode?)
    case iterate(JQNode)
    case array(JQNode?)
    case object([(key: ObjectKey, value: JQNode?)])
    case pipe(JQNode, JQNode)
    case comma(JQNode, JQNode)
    case negate(JQNode)
    case binary(BinaryOperator, JQNode, JQNode)
    case and(JQNode, JQNode)
    case or(JQNode, JQNode)
    case alternative(JQNode, JQNode)
    case assign(AssignOperator, JQNode, JQNode)
    case conditional([(condition: JQNode, then: JQNode)], otherwise: JQNode?)
    case tryCatch(JQNode, JQNode?)
    case reduce(JQNode, String, JQNode, JQNode)
    case foreach(JQNode, String, JQNode, JQNode, JQNode?)
    case bind(JQNode, String, JQNode)
    case variable(String)
    case call(String, [JQNode])

    // MARK: Internal

    enum StringPart: Sendable {
        case literal(String)
        case interpolation(JQNode)
    }

    enum ObjectKey: Sendable {
        case literal(String)
        case interpolated([StringPart])
        case computed(JQNode)
        case variable(String)
    }

    enum BinaryOperator: String, Sendable {
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"
        case modulo = "%"
        case equal = "=="
        case notEqual = "!="
        case less = "<"
        case lessOrEqual = "<="
        case greater = ">"
        case greaterOrEqual = ">="
    }

    enum AssignOperator: String, Sendable {
        case set = "="
        case update = "|="
        case add = "+="
        case subtract = "-="
        case multiply = "*="
        case divide = "/="
        case modulo = "%="
        case alternative = "//="
    }
}

// MARK: - JQToken

enum JQToken: Equatable {
    case dot
    case recurse
    case field(String)
    case identifier(String)
    case keyword(String)
    case variable(String)
    case format(String)
    case number(Double)
    case string([JQRawStringPart])
    case symbol(String)
    case end
}

// MARK: - JQRawStringPart

enum JQRawStringPart: Equatable {
    case literal(String)
    case interpolation(String)
}

// MARK: - JQLexer

struct JQLexer {
    // MARK: Lifecycle

    init(_ source: String) {
        scalars = Array(source.unicodeScalars)
    }

    // MARK: Internal

    static let keywords: Set<String> = [
        "if", "then", "elif", "else", "end", "as", "reduce", "foreach", "try", "catch",
        "and", "or", "def", "label", "import", "include",
    ]

    mutating func tokenize() throws -> [JQToken] {
        var tokens: [JQToken] = []
        while true {
            let token = try next()
            tokens.append(token)
            if token == .end {
                return tokens
            }
        }
    }

    // MARK: Private

    private static let symbols = [
        "?//", "//=", "|=", "+=", "-=", "*=", "/=", "%=", "==", "!=", "<=", ">=", "//",
        "|", ",", "=", "<", ">", "+", "-", "*", "/", "%", "(", ")", "[", "]", "{", "}", ":", ";", "?",
    ]

    private let scalars: [Unicode.Scalar]
    private var position = 0

    private static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || (scalar.value < 128 && CharacterSet.letters.contains(scalar))
    }

    private static func isIdentifierPart(_ scalar: Unicode.Scalar) -> Bool {
        isIdentifierStart(scalar) || ("0" ... "9").contains(scalar)
    }

    private static func message(_ text: String.LocalizationValue) -> String {
        String(localized: text, bundle: RockxyLocalization.bundle)
    }

    private func peek(_ offset: Int = 0) -> Unicode.Scalar? {
        position + offset < scalars.count ? scalars[position + offset] : nil
    }

    private mutating func readIdentifier() -> String {
        var name = String.UnicodeScalarView()
        while let scalar = peek(), Self.isIdentifierPart(scalar) {
            name.append(scalar)
            position += 1
        }
        // Allow jq's module-qualified names such as `ltrimstr` inside `a::b` form.
        return String(name)
    }

    private mutating func next() throws -> JQToken {
        while let scalar = peek() {
            if scalar == "#" {
                while let comment = peek(), comment != "\n" {
                    position += 1
                }
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                position += 1
            } else {
                break
            }
        }
        guard let scalar = peek() else {
            return .end
        }

        if scalar == "." {
            if peek(1) == "." {
                position += 2
                return .recurse
            }
            if let following = peek(1), Self.isIdentifierStart(following) {
                position += 1
                return .field(readIdentifier())
            }
            if let following = peek(1), ("0" ... "9").contains(following) {
                return try .number(readNumber())
            }
            position += 1
            return .dot
        }
        if scalar == "$" {
            position += 1
            guard let following = peek(), Self.isIdentifierStart(following) else {
                throw JQError.syntax(Self.message("Expected a variable name after $."))
            }
            return .variable(readIdentifier())
        }
        if scalar == "@" {
            position += 1
            return .format(readIdentifier())
        }
        if ("0" ... "9").contains(scalar) {
            return try .number(readNumber())
        }
        if scalar == "\"" {
            return try .string(readString())
        }
        if Self.isIdentifierStart(scalar) {
            let name = readIdentifier()
            return Self.keywords.contains(name) ? .keyword(name) : .identifier(name)
        }
        for symbol in Self.symbols {
            let symbolScalars = Array(symbol.unicodeScalars)
            if position + symbolScalars.count <= scalars.count,
               Array(scalars[position ..< position + symbolScalars.count]) == symbolScalars
            {
                position += symbolScalars.count
                return .symbol(symbol)
            }
        }
        throw JQError.syntax(String(
            localized: "Unexpected character “\(String(scalar))” in the filter.",
            bundle: RockxyLocalization.bundle
        ))
    }

    private mutating func readNumber() throws -> Double {
        var text = ""
        while let scalar = peek(), ("0" ... "9").contains(scalar) || scalar == "." {
            text.unicodeScalars.append(scalar)
            position += 1
        }
        if let scalar = peek(), scalar == "e" || scalar == "E" {
            text.unicodeScalars.append(scalar)
            position += 1
            if let sign = peek(), sign == "+" || sign == "-" {
                text.unicodeScalars.append(sign)
                position += 1
            }
            while let digit = peek(), ("0" ... "9").contains(digit) {
                text.unicodeScalars.append(digit)
                position += 1
            }
        }
        guard let value = Double(text) else {
            throw JQError.syntax(String(
                localized: "“\(text)” is not a number.",
                bundle: RockxyLocalization.bundle
            ))
        }
        return value
    }

    private mutating func readString() throws -> [JQRawStringPart] {
        position += 1
        var parts: [JQRawStringPart] = []
        var literal = String.UnicodeScalarView()
        while let scalar = peek() {
            position += 1
            if scalar == "\"" {
                if !literal.isEmpty || parts.isEmpty {
                    parts.append(.literal(String(literal)))
                }
                return parts
            }
            guard scalar == "\\" else {
                literal.append(scalar)
                continue
            }
            guard let escape = peek() else {
                break
            }
            position += 1
            switch escape {
            case "n": literal.append("\n")
            case "t": literal.append("\t")
            case "r": literal.append("\r")
            case "b": literal.append("\u{08}")
            case "f": literal.append("\u{0C}")
            case "\"",
                 "\\",
                 "/": literal.append(escape)
            case "u":
                guard position + 4 <= scalars.count,
                      let code = UInt32(
                          String(String.UnicodeScalarView(scalars[position ..< position + 4])),
                          radix: 16
                      ),
                      let decoded = Unicode.Scalar(code) else
                {
                    throw JQError.syntax(Self.message("Invalid \\u escape in a string."))
                }
                position += 4
                literal.append(decoded)
            case "(":
                if !literal.isEmpty {
                    parts.append(.literal(String(literal)))
                    literal = String.UnicodeScalarView()
                }
                try parts.append(.interpolation(readInterpolation()))
            default:
                throw JQError.syntax(Self.message("Invalid escape in a string."))
            }
        }
        throw JQError.syntax(Self.message("A string is missing its closing quote."))
    }

    /// Reads the source of `\( … )` up to its matching parenthesis, skipping nested strings.
    private mutating func readInterpolation() throws -> String {
        var depth = 1
        var source = String.UnicodeScalarView()
        var inString = false
        while let scalar = peek() {
            position += 1
            if inString {
                source.append(scalar)
                if scalar == "\\", let escaped = peek() {
                    source.append(escaped)
                    position += 1
                } else if scalar == "\"" {
                    inString = false
                }
                continue
            }
            switch scalar {
            case "\"":
                inString = true
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    return String(source)
                }
            default:
                break
            }
            source.append(scalar)
        }
        throw JQError.syntax(Self.message("A string interpolation is missing its closing parenthesis."))
    }
}

// MARK: - JQParser

struct JQParser {
    // MARK: Lifecycle

    init(_ source: String, maxDepth: Int = 128) throws {
        var lexer = JQLexer(source)
        tokens = try lexer.tokenize()
        self.maxDepth = maxDepth
    }

    // MARK: Internal

    static func parse(_ source: String) throws -> JQNode {
        var parser = try JQParser(source)
        let node = try parser.parsePipe()
        guard parser.current == .end else {
            throw JQError.syntax(parser.unexpected())
        }
        return node
    }

    mutating func parsePipe() throws -> JQNode {
        try enter()
        defer { leave() }
        if isKeyword("def") {
            throw JQError.syntax(String(
                localized: "Function definitions (def) are not supported in this filter.",
                bundle: RockxyLocalization.bundle
            ))
        }
        let lhs = try parseComma()
        if isKeyword("as") {
            advance()
            guard case let .variable(name) = current else {
                throw JQError.syntax(String(
                    localized: "Expected a $variable after “as”.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            advance()
            try expectSymbol("|")
            return try .bind(lhs, name, parsePipe())
        }
        if isSymbol("|") {
            advance()
            return try .pipe(lhs, parsePipe())
        }
        return lhs
    }

    // MARK: Private

    private static let assignOperators: [String: JQNode.AssignOperator] = [
        "=": .set, "|=": .update, "+=": .add, "-=": .subtract, "*=": .multiply,
        "/=": .divide, "%=": .modulo, "//=": .alternative,
    ]

    private let tokens: [JQToken]
    private let maxDepth: Int
    private var position = 0
    private var depth = 0

    private var current: JQToken {
        tokens[position]
    }

    private mutating func advance() {
        if position < tokens.count - 1 {
            position += 1
        }
    }

    private func isSymbol(_ symbol: String) -> Bool {
        current == .symbol(symbol)
    }

    private func isKeyword(_ keyword: String) -> Bool {
        current == .keyword(keyword)
    }

    private mutating func expectSymbol(_ symbol: String) throws {
        guard isSymbol(symbol) else {
            throw JQError.syntax(String(
                localized: "Expected “\(symbol)” \(describe(current)).",
                bundle: RockxyLocalization.bundle
            ))
        }
        advance()
    }

    private mutating func expectKeyword(_ keyword: String) throws {
        guard isKeyword(keyword) else {
            throw JQError.syntax(String(
                localized: "Expected “\(keyword)” \(describe(current)).",
                bundle: RockxyLocalization.bundle
            ))
        }
        advance()
    }

    private func describe(_ token: JQToken) -> String {
        switch token {
        case .end:
            String(localized: "at the end of the filter", bundle: RockxyLocalization.bundle)
        default:
            String(localized: "before “\(spelling(token))”", bundle: RockxyLocalization.bundle)
        }
    }

    private func spelling(_ token: JQToken) -> String {
        switch token {
        case .dot: "."
        case .recurse: ".."
        case let .field(name): "." + name
        case let .identifier(name),
             let .keyword(name): name
        case let .variable(name): "$" + name
        case let .format(name): "@" + name
        case let .number(value): JQValue.formatNumber(value)
        case .string: "\"…\""
        case let .symbol(symbol): symbol
        case .end: ""
        }
    }

    private func unexpected() -> String {
        if current == .end {
            return String(localized: "The filter ends before it is complete.", bundle: RockxyLocalization.bundle)
        }
        if case .string = current {
            return String(localized: "Unexpected string in the filter.", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "Unexpected “\(spelling(current))” in the filter.", bundle: RockxyLocalization.bundle)
    }

    private mutating func enter() throws {
        depth += 1
        guard depth <= maxDepth else {
            throw JQError.limit(String(
                localized: "The filter is nested too deeply.",
                bundle: RockxyLocalization.bundle
            ))
        }
    }

    private mutating func leave() {
        depth -= 1
    }

    private mutating func parseComma() throws -> JQNode {
        var lhs = try parseAlternative()
        while isSymbol(",") {
            advance()
            lhs = try .comma(lhs, parseAlternative())
        }
        return lhs
    }

    private mutating func parseAlternative() throws -> JQNode {
        let lhs = try parseAssignment()
        if isSymbol("//") {
            advance()
            return try .alternative(lhs, parseAlternative())
        }
        return lhs
    }

    private mutating func parseAssignment() throws -> JQNode {
        let lhs = try parseOr()
        if case let .symbol(symbol) = current, let op = Self.assignOperators[symbol] {
            advance()
            return try .assign(op, lhs, parseAlternative())
        }
        return lhs
    }

    private mutating func parseOr() throws -> JQNode {
        var lhs = try parseAnd()
        while isKeyword("or") {
            advance()
            lhs = try .or(lhs, parseAnd())
        }
        return lhs
    }

    private mutating func parseAnd() throws -> JQNode {
        var lhs = try parseComparison()
        while isKeyword("and") {
            advance()
            lhs = try .and(lhs, parseComparison())
        }
        return lhs
    }

    private mutating func parseComparison() throws -> JQNode {
        let lhs = try parseAdditive()
        let comparisons: [String: JQNode.BinaryOperator] = [
            "==": .equal, "!=": .notEqual, "<": .less, "<=": .lessOrEqual, ">": .greater, ">=": .greaterOrEqual,
        ]
        if case let .symbol(symbol) = current, let op = comparisons[symbol] {
            advance()
            return try .binary(op, lhs, parseAdditive())
        }
        return lhs
    }

    private mutating func parseAdditive() throws -> JQNode {
        var lhs = try parseMultiplicative()
        while true {
            if isSymbol("+") {
                advance()
                lhs = try .binary(.add, lhs, parseMultiplicative())
            } else if isSymbol("-") {
                advance()
                lhs = try .binary(.subtract, lhs, parseMultiplicative())
            } else {
                return lhs
            }
        }
    }

    private mutating func parseMultiplicative() throws -> JQNode {
        var lhs = try parseUnary()
        while true {
            if isSymbol("*") {
                advance()
                lhs = try .binary(.multiply, lhs, parseUnary())
            } else if isSymbol("/") {
                advance()
                lhs = try .binary(.divide, lhs, parseUnary())
            } else if isSymbol("%") {
                advance()
                lhs = try .binary(.modulo, lhs, parseUnary())
            } else {
                return lhs
            }
        }
    }

    private mutating func parseUnary() throws -> JQNode {
        if isSymbol("-") {
            advance()
            return try .negate(parseUnary())
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> JQNode {
        var node = try parseTerm()
        while true {
            switch current {
            case let .field(name):
                advance()
                node = .index(node, .literal(.string(name)))
            case .dot:
                // `.a."b"` and `.a.[0]` forms.
                advance()
                if case let .string(parts) = current {
                    advance()
                    node = try .index(node, stringNode(parts, format: nil))
                } else if isSymbol("[") {
                    node = try parseBracketSuffix(on: node)
                } else {
                    throw JQError.syntax(unexpected())
                }
            case .symbol("["):
                node = try parseBracketSuffix(on: node)
            case .symbol("?"):
                advance()
                node = .tryCatch(node, nil)
            default:
                return node
            }
        }
    }

    private mutating func parseBracketSuffix(on node: JQNode) throws -> JQNode {
        try expectSymbol("[")
        if isSymbol("]") {
            advance()
            return .iterate(node)
        }
        if isSymbol(":") {
            advance()
            let upper = try parsePipe()
            try expectSymbol("]")
            return .slice(node, nil, upper)
        }
        let first = try parsePipe()
        if isSymbol(":") {
            advance()
            if isSymbol("]") {
                advance()
                return .slice(node, first, nil)
            }
            let upper = try parsePipe()
            try expectSymbol("]")
            return .slice(node, first, upper)
        }
        try expectSymbol("]")
        return .index(node, first)
    }

    private mutating func parseTerm() throws -> JQNode {
        try enter()
        defer { leave() }
        switch current {
        case .dot:
            advance()
            if case let .string(parts) = current {
                advance()
                return try .index(.identity, stringNode(parts, format: nil))
            }
            return .identity
        case let .field(name):
            advance()
            return .index(.identity, .literal(.string(name)))
        case .recurse:
            advance()
            return .recurseAll
        case let .number(value):
            advance()
            return .literal(.number(value))
        case let .string(parts):
            advance()
            return try stringNode(parts, format: nil)
        case let .format(name):
            advance()
            if case let .string(parts) = current {
                advance()
                return try stringNode(parts, format: name)
            }
            return .format(name)
        case let .variable(name):
            advance()
            return .variable(name)
        case .symbol("("):
            advance()
            let inner = try parsePipe()
            try expectSymbol(")")
            return inner
        case .symbol("["):
            advance()
            if isSymbol("]") {
                advance()
                return .array(nil)
            }
            let inner = try parsePipe()
            try expectSymbol("]")
            return .array(inner)
        case .symbol("{"):
            return try parseObject()
        case .keyword("if"):
            return try parseConditional()
        case .keyword("try"):
            advance()
            let body = try parsePostfixBody()
            if isKeyword("catch") {
                advance()
                return try .tryCatch(body, parsePostfixBody())
            }
            return .tryCatch(body, nil)
        case .keyword("reduce"):
            advance()
            let source = try parsePostfix()
            try expectKeyword("as")
            let name = try expectVariable()
            try expectSymbol("(")
            let initial = try parsePipe()
            try expectSymbol(";")
            let update = try parsePipe()
            try expectSymbol(")")
            return .reduce(source, name, initial, update)
        case .keyword("foreach"):
            advance()
            let source = try parsePostfix()
            try expectKeyword("as")
            let name = try expectVariable()
            try expectSymbol("(")
            let initial = try parsePipe()
            try expectSymbol(";")
            let update = try parsePipe()
            var extract: JQNode?
            if isSymbol(";") {
                advance()
                extract = try parsePipe()
            }
            try expectSymbol(")")
            return .foreach(source, name, initial, update, extract)
        case let .identifier(name):
            advance()
            switch name {
            case "null": return .literal(.null)
            case "true": return .literal(.bool(true))
            case "false": return .literal(.bool(false))
            default: break
            }
            var arguments: [JQNode] = []
            if isSymbol("(") {
                advance()
                try arguments.append(parsePipe())
                while isSymbol(";") {
                    advance()
                    try arguments.append(parsePipe())
                }
                try expectSymbol(")")
            }
            return .call(name, arguments)
        default:
            throw JQError.syntax(unexpected())
        }
    }

    /// `try` binds to a postfix term, like jq.
    private mutating func parsePostfixBody() throws -> JQNode {
        try parsePostfix()
    }

    private mutating func expectVariable() throws -> String {
        guard case let .variable(name) = current else {
            throw JQError.syntax(String(localized: "Expected a $variable.", bundle: RockxyLocalization.bundle))
        }
        advance()
        return name
    }

    private mutating func parseConditional() throws -> JQNode {
        try expectKeyword("if")
        var branches: [(condition: JQNode, then: JQNode)] = []
        let condition = try parsePipe()
        try expectKeyword("then")
        try branches.append((condition, parsePipe()))
        while isKeyword("elif") {
            advance()
            let elifCondition = try parsePipe()
            try expectKeyword("then")
            try branches.append((elifCondition, parsePipe()))
        }
        var otherwise: JQNode?
        if isKeyword("else") {
            advance()
            otherwise = try parsePipe()
        }
        try expectKeyword("end")
        return .conditional(branches, otherwise: otherwise)
    }

    private mutating func parseObject() throws -> JQNode {
        try expectSymbol("{")
        var entries: [(key: JQNode.ObjectKey, value: JQNode?)] = []
        while !isSymbol("}") {
            let key: JQNode.ObjectKey
            switch current {
            case let .identifier(name),
                 let .keyword(name):
                advance()
                key = .literal(name)
            case let .variable(name):
                advance()
                key = .variable(name)
            case let .string(parts):
                advance()
                key = try .interpolated(stringParts(parts))
            case let .format(name):
                advance()
                guard case let .string(parts) = current else {
                    throw JQError.syntax(unexpected())
                }
                advance()
                key = try .computed(stringNode(parts, format: name))
            case .symbol("("):
                advance()
                let expression = try parsePipe()
                try expectSymbol(")")
                key = .computed(expression)
            default:
                throw JQError.syntax(unexpected())
            }
            var value: JQNode?
            if isSymbol(":") {
                advance()
                var objectValue = try parseAlternative()
                while isSymbol("|") {
                    advance()
                    objectValue = try .pipe(objectValue, parseAlternative())
                }
                value = objectValue
            } else if case .computed = key {
                throw JQError.syntax(String(
                    localized: "A computed object key needs a value.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            entries.append((key, value))
            if isSymbol(",") {
                advance()
                continue
            }
            guard isSymbol("}") else {
                throw JQError.syntax(unexpected())
            }
        }
        advance()
        return .object(entries)
    }

    private func stringParts(_ parts: [JQRawStringPart]) throws -> [JQNode.StringPart] {
        try parts.map { part in
            switch part {
            case let .literal(text):
                return .literal(text)
            case let .interpolation(source):
                var parser = try JQParser(source, maxDepth: maxDepth - depth)
                let node = try parser.parsePipe()
                guard parser.current == .end else {
                    throw JQError.syntax(parser.unexpected())
                }
                return .interpolation(node)
            }
        }
    }

    private func stringNode(_ parts: [JQRawStringPart], format: String?) throws -> JQNode {
        let converted = try stringParts(parts)
        if format == nil, converted.count == 1, case let .literal(text) = converted[0] {
            return .literal(.string(text))
        }
        return .string(converted, format: format)
    }
}
