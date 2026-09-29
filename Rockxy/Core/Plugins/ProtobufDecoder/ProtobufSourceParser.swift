import Foundation

// MARK: - ProtobufSourceParser

/// Reads message and enum definitions from `.proto` source (proto2, proto3, and editions syntax).
/// Services, extensions, options, and reserved ranges are skipped; they do not affect decoding.
/// Imported files are not loaded here — import them as separate schemas and the decoder resolves
/// types across every imported schema.
nonisolated enum ProtobufSourceParser {
    // MARK: Internal

    static func parse(_ source: String) throws -> ProtobufSchema {
        var parser = try Parser(tokens: Tokenizer.tokenize(source))
        let schema = try parser.parseFile()
        guard !schema.messageNames.isEmpty || !schema.enums.isEmpty else {
            throw ProtobufSchemaParseError.noMessages
        }
        return schema
    }

    // MARK: Private

    private struct Token: Equatable {
        enum Kind: Equatable {
            case identifier
            case number
            case string
            case symbol
        }

        let kind: Kind
        let text: String
        let line: Int
    }

    private enum Tokenizer {
        // MARK: Internal

        static func tokenize(_ source: String) throws -> [Token] {
            var tokens: [Token] = []
            let scalars = Array(source.unicodeScalars)
            var index = 0
            var line = 1

            func peek(_ offset: Int = 0) -> Unicode.Scalar? {
                index + offset < scalars.count ? scalars[index + offset] : nil
            }

            while let scalar = peek() {
                if scalar == "\n" {
                    line += 1
                    index += 1
                } else if CharacterSet.whitespaces.contains(scalar) || scalar == "\r" {
                    index += 1
                } else if scalar == "/", peek(1) == "/" {
                    while let next = peek(), next != "\n" {
                        index += 1
                    }
                } else if scalar == "/", peek(1) == "*" {
                    index += 2
                    while let next = peek(), !(next == "*" && peek(1) == "/") {
                        if next == "\n" {
                            line += 1
                        }
                        index += 1
                    }
                    guard peek() != nil else {
                        throw ProtobufSchemaParseError.syntax(line: line, message: "Unterminated comment")
                    }
                    index += 2
                } else if scalar == "\"" || scalar == "'" {
                    let quote = scalar
                    var text = ""
                    index += 1
                    while let next = peek(), next != quote {
                        if next == "\n" {
                            throw ProtobufSchemaParseError.syntax(line: line, message: "Unterminated string")
                        }
                        if next == "\\", let escaped = peek(1) {
                            text.unicodeScalars.append(escaped)
                            index += 2
                        } else {
                            text.unicodeScalars.append(next)
                            index += 1
                        }
                    }
                    guard peek() == quote else {
                        throw ProtobufSchemaParseError.syntax(line: line, message: "Unterminated string")
                    }
                    index += 1
                    tokens.append(Token(kind: .string, text: text, line: line))
                } else if isIdentifierStart(scalar) || scalar == "." && peek(1).map(isIdentifierStart) == true {
                    var text = ""
                    while let next = peek(), isIdentifierPart(next) || next == "." {
                        text.unicodeScalars.append(next)
                        index += 1
                    }
                    tokens.append(Token(kind: .identifier, text: text, line: line))
                } else if CharacterSet.decimalDigits.contains(scalar) || scalar == "-" || scalar == "+" {
                    var text = ""
                    while let next = peek(),
                          CharacterSet.alphanumerics.contains(next) || next == "." || next == "-" || next == "+"
                    {
                        text.unicodeScalars.append(next)
                        index += 1
                    }
                    tokens.append(Token(kind: .number, text: text, line: line))
                } else {
                    tokens.append(Token(kind: .symbol, text: String(scalar), line: line))
                    index += 1
                }
            }
            return tokens
        }

        // MARK: Private

        private static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
            scalar == "_" || ("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar)
        }

        private static func isIdentifierPart(_ scalar: Unicode.Scalar) -> Bool {
            isIdentifierStart(scalar) || ("0" ... "9").contains(scalar)
        }
    }

    private struct Parser {
        // MARK: Internal

        let tokens: [Token]
        var position = 0
        var schema = ProtobufSchema()
        var package = ""

        mutating func parseFile() throws -> ProtobufSchema {
            while let token = current {
                switch token.text {
                case "syntax",
                     "edition":
                    try skipStatement()
                case "package":
                    advance()
                    package = try expectIdentifier()
                    try expect(";")
                case "import",
                     "option":
                    try skipStatement()
                case "message":
                    try parseMessage(scope: package)
                case "enum":
                    try parseEnum(scope: package)
                case "service":
                    try parseService()
                case "extend":
                    try skipDeclarationWithBody()
                case ";":
                    advance()
                default:
                    throw error("Unexpected \"\(token.text)\"")
                }
            }
            return schema.resolvingReferences()
        }

        // MARK: Private

        private var current: Token? {
            position < tokens.count ? tokens[position] : nil
        }

        /// `map<string, int32> counters` compiles to a nested `CountersEntry` message.
        private static func mapEntryName(for fieldName: String) -> String {
            let camel = fieldName.split(separator: "_").map { part in
                part.prefix(1).uppercased() + part.dropFirst()
            }.joined()
            return camel + "Entry"
        }

        private mutating func advance() {
            position += 1
        }

        private func error(_ message: String) -> ProtobufSchemaParseError {
            .syntax(line: current?.line ?? tokens.last?.line ?? 1, message: message)
        }

        private mutating func expect(_ symbol: String) throws {
            guard current?.text == symbol else {
                throw error("Expected \"\(symbol)\"")
            }
            advance()
        }

        private mutating func expectIdentifier() throws -> String {
            guard let token = current, token.kind == .identifier else {
                throw error("Expected a name")
            }
            advance()
            return token.text
        }

        private mutating func expectNumber() throws -> Int {
            guard let token = current, token.kind == .number else {
                throw error("Expected a number")
            }
            advance()
            let text = token.text.lowercased()
            let value: Int? = if text.hasPrefix("0x") {
                Int(text.dropFirst(2), radix: 16)
            } else if text.hasPrefix("-0x") {
                Int(text.dropFirst(3), radix: 16).map { -$0 }
            } else {
                Int(text)
            }
            guard let value else {
                throw error("Invalid number \"\(token.text)\"")
            }
            return value
        }

        /// Skips to the end of the current statement, including any bracketed option values.
        private mutating func skipStatement() throws {
            var depth = 0
            while let token = current {
                advance()
                switch token.text {
                case "{",
                     "[",
                     "(": depth += 1
                case "}",
                     "]",
                     ")": depth -= 1
                case ";" where depth == 0: return
                default: break
                }
            }
            throw error("Expected \";\"")
        }

        private mutating func skipDeclarationWithBody() throws {
            while let token = current, token.text != "{" {
                if token.text == ";" {
                    advance()
                    return
                }
                advance()
            }
            try skipBlock()
        }

        private mutating func skipBlock() throws {
            try expect("{")
            var depth = 1
            while let token = current {
                advance()
                if token.text == "{" {
                    depth += 1
                } else if token.text == "}" {
                    depth -= 1
                    if depth == 0 {
                        return
                    }
                }
            }
            throw error("Expected \"}\"")
        }

        /// Records `rpc Name(Request) returns (Response)` so gRPC paths map to message types.
        /// Streaming markers and method options are skipped.
        private mutating func parseService() throws {
            advance()
            let name = try expectIdentifier()
            let serviceName = package.isEmpty ? name : "\(package).\(name)"
            try expect("{")
            while let token = current, token.text != "}" {
                guard token.text == "rpc" else {
                    if token.text == ";" {
                        advance()
                    } else {
                        try skipStatement()
                    }
                    continue
                }
                advance()
                let method = try expectIdentifier()
                let input = try parseRPCType()
                guard current?.text == "returns" else {
                    throw error("Expected \"returns\"")
                }
                advance()
                let output = try parseRPCType()
                if current?.text == "{" {
                    try skipBlock()
                } else {
                    try expect(";")
                }
                schema.methods["\(serviceName)/\(method)"] = ProtobufMethodSchema(
                    inputType: input,
                    outputType: output,
                    unresolvedScope: package
                )
            }
            try expect("}")
        }

        private mutating func parseRPCType() throws -> String {
            try expect("(")
            if current?.text == "stream" {
                advance()
            }
            let type = try expectIdentifier()
            try expect(")")
            return type
        }

        private mutating func parseMessage(scope: String) throws {
            advance()
            let name = try expectIdentifier()
            let fullName = scope.isEmpty ? name : "\(scope).\(name)"
            schema.messages[fullName] = ProtobufMessageSchema(fullName: fullName, fields: [:])
            try expect("{")
            while let token = current, token.text != "}" {
                switch token.text {
                case "message":
                    try parseMessage(scope: fullName)
                case "enum":
                    try parseEnum(scope: fullName)
                case "oneof":
                    advance()
                    _ = try expectIdentifier()
                    try expect("{")
                    while let inner = current, inner.text != "}" {
                        if inner.text == ";" {
                            advance()
                        } else if inner.text == "option" {
                            try skipStatement()
                        } else {
                            try parseField(in: fullName, label: nil)
                        }
                    }
                    try expect("}")
                case "option",
                     "reserved",
                     "extensions":
                    try skipStatement()
                case "extend":
                    try skipDeclarationWithBody()
                case ";":
                    advance()
                case "repeated",
                     "optional",
                     "required":
                    advance()
                    try parseField(in: fullName, label: token.text)
                default:
                    try parseField(in: fullName, label: nil)
                }
            }
            try expect("}")
        }

        private mutating func parseField(in messageName: String, label: String?) throws {
            if current?.text == "map", position + 1 < tokens.count, tokens[position + 1].text == "<" {
                try parseMapField(in: messageName)
                return
            }
            if current?.text == "group" {
                throw error("Groups are not supported")
            }
            let typeText = try expectIdentifier()
            let name = try expectIdentifier()
            try expect("=")
            let number = try expectNumber()
            if current?.text == "[" {
                try skipBracketedOptions()
            }
            try expect(";")
            guard number > 0 else {
                throw error("Field numbers must be positive")
            }
            let scalar = ProtobufFieldType(scalarName: typeText)
            schema.messages[messageName]?.fields[number] = ProtobufFieldSchema(
                name: name,
                number: number,
                type: scalar ?? .message,
                isRepeated: label == "repeated",
                typeName: nil,
                unresolvedReference: scalar == nil ? typeText : nil
            )
        }

        private mutating func parseMapField(in messageName: String) throws {
            advance()
            try expect("<")
            let keyType = try expectIdentifier()
            try expect(",")
            let valueType = try expectIdentifier()
            try expect(">")
            let name = try expectIdentifier()
            try expect("=")
            let number = try expectNumber()
            if current?.text == "[" {
                try skipBracketedOptions()
            }
            try expect(";")
            guard let keyScalar = ProtobufFieldType(scalarName: keyType) else {
                throw error("Map keys must be a scalar type")
            }

            let entryName = "\(messageName).\(Self.mapEntryName(for: name))"
            let valueScalar = ProtobufFieldType(scalarName: valueType)
            schema.messages[entryName] = ProtobufMessageSchema(
                fullName: entryName,
                fields: [
                    1: ProtobufFieldSchema(name: "key", number: 1, type: keyScalar, isRepeated: false),
                    2: ProtobufFieldSchema(
                        name: "value",
                        number: 2,
                        type: valueScalar ?? .message,
                        isRepeated: false,
                        unresolvedReference: valueScalar == nil ? valueType : nil
                    ),
                ],
                isMapEntry: true
            )
            schema.messages[messageName]?.fields[number] = ProtobufFieldSchema(
                name: name,
                number: number,
                type: .message,
                isRepeated: true,
                typeName: entryName
            )
        }

        private mutating func skipBracketedOptions() throws {
            try expect("[")
            var depth = 1
            while let token = current {
                advance()
                if token.text == "[" {
                    depth += 1
                } else if token.text == "]" {
                    depth -= 1
                    if depth == 0 {
                        return
                    }
                }
            }
            throw error("Expected \"]\"")
        }

        private mutating func parseEnum(scope: String) throws {
            advance()
            let name = try expectIdentifier()
            let fullName = scope.isEmpty ? name : "\(scope).\(name)"
            var values: [Int32: String] = [:]
            try expect("{")
            while let token = current, token.text != "}" {
                switch token.text {
                case "option",
                     "reserved":
                    try skipStatement()
                case ";":
                    advance()
                default:
                    let valueName = try expectIdentifier()
                    try expect("=")
                    let number = try expectNumber()
                    if current?.text == "[" {
                        try skipBracketedOptions()
                    }
                    try expect(";")
                    guard let value = Int32(exactly: number) else {
                        throw error("Enum value out of range")
                    }
                    if values[value] == nil {
                        values[value] = valueName
                    }
                }
            }
            try expect("}")
            schema.enums[fullName] = ProtobufEnumSchema(fullName: fullName, values: values)
        }
    }
}
