import Foundation

// JSON value model for the jq filter: keeps object keys in document order, orders values the
// way jq does, and reads and writes JSON text without Foundation reordering keys.

// MARK: - JQValue

indirect enum JQValue: Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JQValue])
    case object(JQObject)

    // MARK: Internal

    var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .number: "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    /// jq truthiness: only `false` and `null` are false.
    var isTruthy: Bool {
        switch self {
        case .null: false
        case let .bool(value): value
        default: true
        }
    }

    var arrayValue: [JQValue]? {
        if case let .array(items) = self {
            return items
        }
        return nil
    }

    var objectValue: JQObject? {
        if case let .object(object) = self {
            return object
        }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    static func compare(_ lhs: JQValue, _ rhs: JQValue) -> Int {
        if lhs.orderRank != rhs.orderRank {
            return lhs.orderRank < rhs.orderRank ? -1 : 1
        }
        switch (lhs, rhs) {
        case let (.number(left), .number(right)):
            return left == right ? 0 : (left < right ? -1 : 1)
        case let (.string(left), .string(right)):
            return compareCodepoints(left, right)
        case let (.array(left), .array(right)):
            for (leftItem, rightItem) in zip(left, right) {
                let result = compare(leftItem, rightItem)
                if result != 0 {
                    return result
                }
            }
            return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1)
        case let (.object(left), .object(right)):
            let leftKeys = JQValue.array(left.sortedKeys.map(JQValue.string))
            let rightKeys = JQValue.array(right.sortedKeys.map(JQValue.string))
            let keyOrder = compare(leftKeys, rightKeys)
            if keyOrder != 0 {
                return keyOrder
            }
            for key in left.sortedKeys {
                let result = compare(left[key] ?? .null, right[key] ?? .null)
                if result != 0 {
                    return result
                }
            }
            return 0
        default:
            return 0
        }
    }

    static func compareCodepoints(_ lhs: String, _ rhs: String) -> Int {
        var left = lhs.unicodeScalars.makeIterator()
        var right = rhs.unicodeScalars.makeIterator()
        while true {
            switch (left.next(), right.next()) {
            case (nil, nil):
                return 0
            case (nil, _):
                return -1
            case (_, nil):
                return 1
            case let (leftScalar?, rightScalar?):
                if leftScalar.value != rightScalar.value {
                    return leftScalar.value < rightScalar.value ? -1 : 1
                }
            }
        }
    }

    static func == (lhs: JQValue, rhs: JQValue) -> Bool {
        compare(lhs, rhs) == 0
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .null:
            hasher.combine(0)
        case let .bool(value):
            hasher.combine(value)
        case let .number(value):
            hasher.combine(value)
        case let .string(value):
            hasher.combine(value)
        case let .array(items):
            hasher.combine(items)
        case let .object(object):
            for key in object.sortedKeys {
                hasher.combine(key)
                hasher.combine(object[key])
            }
        }
    }

    // MARK: Private

    /// Rank used by jq's total order: null < false < true < numbers < strings < arrays < objects.
    private var orderRank: Int {
        switch self {
        case .null: 0
        case let .bool(value): value ? 2 : 1
        case .number: 3
        case .string: 4
        case .array: 5
        case .object: 6
        }
    }
}

// MARK: - JQObject

/// Object whose keys keep insertion order, as jq prints them.
struct JQObject: Sendable, Equatable, Hashable {
    // MARK: Lifecycle

    init() {}

    init(_ pairs: [(String, JQValue)]) {
        for (key, value) in pairs {
            self[key] = value
        }
    }

    // MARK: Internal

    private(set) var keys: [String] = []

    var count: Int {
        keys.count
    }

    var isEmpty: Bool {
        keys.isEmpty
    }

    var sortedKeys: [String] {
        keys.sorted { JQValue.compareCodepoints($0, $1) < 0 }
    }

    var values: [JQValue] {
        keys.map { storage[$0] ?? .null }
    }

    var pairs: [(key: String, value: JQValue)] {
        keys.map { ($0, storage[$0] ?? .null) }
    }

    static func == (lhs: JQObject, rhs: JQObject) -> Bool {
        JQValue.compare(.object(lhs), .object(rhs)) == 0
    }

    subscript(key: String) -> JQValue? {
        get {
            storage[key]
        }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil {
                    keys.append(key)
                }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    func hash(into hasher: inout Hasher) {
        JQValue.object(self).hash(into: &hasher)
    }

    // MARK: Private

    private var storage: [String: JQValue] = [:]
}

// MARK: - JSON reading

extension JQValue {
    /// Parses JSON text, keeping object keys in document order.
    static func parse(_ data: Data, maxDepth: Int = 512) throws -> JQValue {
        var reader = JQJSONReader(bytes: Array(data), maxDepth: maxDepth)
        return try reader.readDocument()
    }

    static func parse(_ text: String, maxDepth: Int = 512) throws -> JQValue {
        try parse(Data(text.utf8), maxDepth: maxDepth)
    }
}

// MARK: - JQJSONReader

private struct JQJSONReader {
    // MARK: Lifecycle

    init(bytes: [UInt8], maxDepth: Int) {
        self.bytes = bytes
        self.maxDepth = maxDepth
    }

    // MARK: Internal

    mutating func readDocument() throws -> JQValue {
        skipWhitespace()
        if position + 2 < bytes.count, bytes[position] == 0xEF, bytes[position + 1] == 0xBB,
           bytes[position + 2] == 0xBF
        {
            position += 3
        }
        let value = try readValue(depth: 0)
        skipWhitespace()
        guard position == bytes.count else {
            throw invalid()
        }
        return value
    }

    // MARK: Private

    private let bytes: [UInt8]
    private let maxDepth: Int
    private var position = 0

    private func invalid() -> JQError {
        .runtime(String(localized: "The body is not valid JSON.", bundle: RockxyLocalization.bundle))
    }

    private mutating func skipWhitespace() {
        while position < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[position]) {
            position += 1
        }
    }

    private mutating func readValue(depth: Int) throws -> JQValue {
        guard depth <= maxDepth else {
            throw JQError.limit(String(localized: "JSON is nested too deeply.", bundle: RockxyLocalization.bundle))
        }
        skipWhitespace()
        guard position < bytes.count else {
            throw invalid()
        }
        switch bytes[position] {
        case UInt8(ascii: "{"):
            return try readObject(depth: depth)
        case UInt8(ascii: "["):
            return try readArray(depth: depth)
        case UInt8(ascii: "\""):
            return try .string(readString())
        case UInt8(ascii: "t"):
            try expect("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try expect("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try expect("null")
            return .null
        default:
            return try readNumber()
        }
    }

    private mutating func expect(_ literal: String) throws {
        for byte in literal.utf8 {
            guard position < bytes.count, bytes[position] == byte else {
                throw invalid()
            }
            position += 1
        }
    }

    private mutating func readObject(depth: Int) throws -> JQValue {
        position += 1
        var object = JQObject()
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
            position += 1
            return .object(object)
        }
        while true {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else {
                throw invalid()
            }
            let key = try readString()
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else {
                throw invalid()
            }
            position += 1
            object[key] = try readValue(depth: depth + 1)
            skipWhitespace()
            guard position < bytes.count else {
                throw invalid()
            }
            if bytes[position] == UInt8(ascii: ",") {
                position += 1
                continue
            }
            guard bytes[position] == UInt8(ascii: "}") else {
                throw invalid()
            }
            position += 1
            return .object(object)
        }
    }

    private mutating func readArray(depth: Int) throws -> JQValue {
        position += 1
        var items: [JQValue] = []
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
            position += 1
            return .array(items)
        }
        while true {
            try items.append(readValue(depth: depth + 1))
            skipWhitespace()
            guard position < bytes.count else {
                throw invalid()
            }
            if bytes[position] == UInt8(ascii: ",") {
                position += 1
                continue
            }
            guard bytes[position] == UInt8(ascii: "]") else {
                throw invalid()
            }
            position += 1
            return .array(items)
        }
    }

    private mutating func readString() throws -> String {
        position += 1
        var scalars = String.UnicodeScalarView()
        var raw: [UInt8] = []
        func flushRaw() throws {
            guard !raw.isEmpty else {
                return
            }
            guard let text = String(bytes: raw, encoding: .utf8) else {
                throw invalid()
            }
            scalars.append(contentsOf: text.unicodeScalars)
            raw.removeAll(keepingCapacity: true)
        }
        while position < bytes.count {
            let byte = bytes[position]
            if byte == UInt8(ascii: "\"") {
                position += 1
                try flushRaw()
                return String(scalars)
            }
            if byte == UInt8(ascii: "\\") {
                try flushRaw()
                position += 1
                guard position < bytes.count else {
                    throw invalid()
                }
                let escape = bytes[position]
                position += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    var code = try readHex4()
                    if (0xD800 ... 0xDBFF).contains(code), position + 1 < bytes.count,
                       bytes[position] == UInt8(ascii: "\\"), bytes[position + 1] == UInt8(ascii: "u")
                    {
                        position += 2
                        let low = try readHex4()
                        if (0xDC00 ... 0xDFFF).contains(low) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                    }
                    scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                default:
                    throw invalid()
                }
                continue
            }
            guard byte >= 0x20 else {
                throw invalid()
            }
            raw.append(byte)
            position += 1
        }
        throw invalid()
    }

    private mutating func readHex4() throws -> UInt32 {
        guard position + 4 <= bytes.count,
              let text = String(bytes: bytes[position ..< position + 4], encoding: .ascii),
              let value = UInt32(text, radix: 16) else
        {
            throw invalid()
        }
        position += 4
        return value
    }

    private mutating func readNumber() throws -> JQValue {
        let start = position
        while position < bytes.count,
              let scalar = Optional(bytes[position]),
              (scalar >= UInt8(ascii: "0") && scalar <= UInt8(ascii: "9"))
              || [UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E")]
              .contains(scalar)
        {
            position += 1
        }
        guard position > start,
              let text = String(bytes: bytes[start ..< position], encoding: .ascii),
              let value = Double(text) else
        {
            throw invalid()
        }
        return .number(value)
    }
}

// MARK: - JSON writing

extension JQValue {
    /// jq-style JSON text: two-space indentation when `pretty`, keys in object order.
    func jsonText(pretty: Bool = false, sortKeys: Bool = false) -> String {
        var output = ""
        write(to: &output, pretty: pretty, sortKeys: sortKeys, indent: 0)
        return output
    }

    static func formatNumber(_ value: Double) -> String {
        if value.isNaN {
            return "null"
        }
        if value.isInfinite {
            return value > 0 ? "1.7976931348623157e+308" : "-1.7976931348623157e+308"
        }
        if value == value.rounded(), abs(value) < 1e17 {
            return String(Int64(value))
        }
        return "\(value)"
    }

    static func quoted(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        return output + "\""
    }

    private func write(to output: inout String, pretty: Bool, sortKeys: Bool, indent: Int) {
        switch self {
        case .null:
            output += "null"
        case let .bool(value):
            output += value ? "true" : "false"
        case let .number(value):
            output += Self.formatNumber(value)
        case let .string(value):
            output += Self.quoted(value)
        case let .array(items):
            guard !items.isEmpty else {
                output += "[]"
                return
            }
            output += "["
            for (index, item) in items.enumerated() {
                if index > 0 {
                    output += ","
                }
                if pretty {
                    output += "\n" + String(repeating: "  ", count: indent + 1)
                }
                item.write(to: &output, pretty: pretty, sortKeys: sortKeys, indent: indent + 1)
            }
            if pretty {
                output += "\n" + String(repeating: "  ", count: indent)
            }
            output += "]"
        case let .object(object):
            guard !object.isEmpty else {
                output += "{}"
                return
            }
            output += "{"
            let keys = sortKeys ? object.sortedKeys : object.keys
            for (index, key) in keys.enumerated() {
                if index > 0 {
                    output += ","
                }
                if pretty {
                    output += "\n" + String(repeating: "  ", count: indent + 1)
                }
                output += Self.quoted(key)
                output += pretty ? ": " : ":"
                (object[key] ?? .null).write(to: &output, pretty: pretty, sortKeys: sortKeys, indent: indent + 1)
            }
            if pretty {
                output += "\n" + String(repeating: "  ", count: indent)
            }
            output += "}"
        }
    }
}
