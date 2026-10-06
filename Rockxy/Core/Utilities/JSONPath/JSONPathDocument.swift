import Foundation

// MARK: - JSONPathDocument

struct JSONPathDocument: Sendable, Equatable {
    // MARK: Lifecycle

    init(data: Data, limits: JSONPathEvaluationLimits = .default) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        var counter = 0
        root = try JSONPathNode(
            object: object,
            key: nil,
            path: "$",
            keyPath: "",
            depth: 0,
            counter: &counter,
            limits: limits
        )
    }

    init(root: JSONPathNode) {
        self.root = root
    }

    // MARK: Internal

    let root: JSONPathNode

    var flattenedNodes: [JSONPathNode] {
        root.flattened()
    }
}

// MARK: - JSONPathNode

struct JSONPathNode: Identifiable, Sendable, Equatable {
    // MARK: Lifecycle

    init(
        object: Any,
        key: String?,
        path: String,
        keyPath: String,
        depth: Int,
        counter: inout Int,
        limits: JSONPathEvaluationLimits
    )
        throws
    {
        counter += 1
        guard counter <= limits.maxVisitedNodes else {
            throw JSONPathError.limitExceeded(String(
                localized: "JSON contains too many nodes.",
                bundle: RockxyLocalization.bundle
            ))
        }
        guard depth <= limits.maxTreeDepth else {
            throw JSONPathError.limitExceeded(String(
                localized: "JSON is nested too deeply.",
                bundle: RockxyLocalization.bundle
            ))
        }

        self.id = path
        self.key = key
        self.path = path
        self.keyPath = keyPath
        self.value = try JSONPathValue(
            object: object,
            path: path,
            keyPath: keyPath,
            depth: depth,
            counter: &counter,
            limits: limits
        )
    }

    // MARK: Internal

    let id: String
    let key: String?
    let path: String
    let keyPath: String
    let value: JSONPathValue

    var childCount: Int {
        children.count
    }

    var children: [JSONPathNode] {
        switch value {
        case let .object(pairs):
            pairs.map(\.value)
        case let .array(items):
            items
        default:
            []
        }
    }

    var isContainer: Bool {
        switch value {
        case .object,
             .array:
            true
        default:
            false
        }
    }

    var scalarDescription: String {
        switch value {
        case let .string(value):
            value
        case let .number(value):
            value
        case let .bool(value):
            value ? "true" : "false"
        case .null:
            "null"
        case let .object(pairs):
            "Object(\(pairs.count) items)"
        case let .array(items):
            "Array(\(items.count) items)"
        }
    }

    func flattened() -> [JSONPathNode] {
        [self] + children.flatMap { $0.flattened() }
    }

    func node(withPath path: String) -> JSONPathNode? {
        if self.path == path {
            return self
        }
        for child in children {
            if let match = child.node(withPath: path) {
                return match
            }
        }
        return nil
    }
}

// MARK: - JSONPathValue

indirect enum JSONPathValue: Sendable, Equatable {
    case string(String)
    case number(String)
    case bool(Bool)
    case null
    case array([JSONPathNode])
    case object([(key: String, value: JSONPathNode)])

    // MARK: Lifecycle

    init(
        object: Any,
        path: String,
        keyPath: String,
        depth: Int,
        counter: inout Int,
        limits: JSONPathEvaluationLimits
    )
        throws
    {
        switch object {
        case let dict as [String: Any]:
            let pairs = try dict.keys.sorted().map { key -> (key: String, value: JSONPathNode) in
                let childPath = "\(path)['\(Self.escapedPathKey(key))']"
                let childKeyPath = keyPath.isEmpty ? Self.keyPathComponent(key) : "\(keyPath).\(Self.keyPathComponent(key))"
                let child = try JSONPathNode(
                    object: dict[key] as Any,
                    key: key,
                    path: childPath,
                    keyPath: childKeyPath,
                    depth: depth + 1,
                    counter: &counter,
                    limits: limits
                )
                return (key, child)
            }
            self = .object(pairs)
        case let array as [Any]:
            let children = try array.enumerated().map { index, item in
                let childPath = "\(path)[\(index)]"
                let childKeyPath = "\(keyPath)[\(index)]"
                return try JSONPathNode(
                    object: item,
                    key: nil,
                    path: childPath,
                    keyPath: childKeyPath,
                    depth: depth + 1,
                    counter: &counter,
                    limits: limits
                )
            }
            self = .array(children)
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(number) {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.stringValue)
            }
        case is NSNull:
            self = .null
        default:
            throw JSONPathError.unsupportedValue
        }
    }

    // MARK: Internal

    var doubleValue: Double? {
        switch self {
        case let .number(value):
            Double(value)
        default:
            nil
        }
    }

    var stringValue: String? {
        switch self {
        case let .string(value):
            value
        default:
            nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case let .bool(value):
            value
        default:
            nil
        }
    }

    var children: [JSONPathNode] {
        switch self {
        case let .array(items):
            items
        case let .object(pairs):
            pairs.map(\.value)
        default:
            []
        }
    }

    var typeName: String {
        switch self {
        case .string: "string"
        case .number: "number"
        case .bool: "boolean"
        case .null: "null"
        case .array: "array"
        case .object: "object"
        }
    }

    static func == (lhs: JSONPathValue, rhs: JSONPathValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(left), .string(right)):
            left == right
        case let (.number(left), .number(right)):
            left == right
        case let (.bool(left), .bool(right)):
            left == right
        case (.null, .null):
            true
        case let (.array(left), .array(right)):
            left == right
        case let (.object(left), .object(right)):
            left.map(\.key) == right.map(\.key) && left.map(\.value) == right.map(\.value)
        default:
            false
        }
    }

    // MARK: Private

    private static func escapedPathKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    private static func keyPathComponent(_ key: String) -> String {
        key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) == nil
            ? "['\(escapedPathKey(key))']"
            : key
    }
}

// MARK: - JSONPathError

enum JSONPathError: LocalizedError, Equatable, Sendable {
    case invalidQuery(String)
    case evaluationFailed(String)
    case limitExceeded(String)
    case unsupportedValue

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .invalidQuery(message),
             let .evaluationFailed(message),
             let .limitExceeded(message):
            message
        case .unsupportedValue:
            String(localized: "JSON contains an unsupported value.", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - JSONPathEvaluationLimits

struct JSONPathEvaluationLimits: Sendable, Equatable {
    static let `default` = JSONPathEvaluationLimits(
        maxQueryLength: 2 * 1_024,
        maxLiveFilterBodyBytes: 10 * 1_024 * 1_024,
        maxVisitedNodes: 100_000,
        maxResultNodes: 5_000,
        maxTreeDepth: 256,
        maxASTDepth: 128,
        maxRegexPatternLength: 512
    )

    let maxQueryLength: Int
    let maxLiveFilterBodyBytes: Int
    let maxVisitedNodes: Int
    let maxResultNodes: Int
    let maxTreeDepth: Int
    let maxASTDepth: Int
    let maxRegexPatternLength: Int
}

// MARK: - JSONPathQueryResult

struct JSONPathQueryResult: Sendable, Equatable {
    static let empty = JSONPathQueryResult(
        matches: [],
        includedPaths: [],
        selectedIndex: 0,
        diagnostic: nil,
        isTruncated: false
    )

    let matches: [JSONPathNode]
    let includedPaths: Set<String>
    let selectedIndex: Int
    let diagnostic: String?
    let isTruncated: Bool
}

// MARK: - JSONPathNode + JSON text

extension JSONPathNode {
    /// The node's value as JSON text, keeping the document's key order. Strings copy without
    /// quotes when `unquotedStrings` is set, which is what a single value is usually pasted as.
    func jsonText(unquotedStrings: Bool = false) -> String {
        if unquotedStrings, case let .string(value) = value {
            return value
        }
        var output = ""
        Self.write(self, indent: 0, into: &output)
        return output
    }

    private static func write(_ node: JSONPathNode, indent: Int, into output: inout String) {
        let pad = String(repeating: "  ", count: indent + 1)
        let closingPad = String(repeating: "  ", count: indent)
        switch node.value {
        case let .object(pairs):
            guard !pairs.isEmpty else {
                output += "{}"
                return
            }
            output += "{\n"
            for (index, pair) in pairs.enumerated() {
                output += pad + quoted(pair.key) + ": "
                write(pair.value, indent: indent + 1, into: &output)
                output += index == pairs.count - 1 ? "\n" : ",\n"
            }
            output += closingPad + "}"
        case let .array(items):
            guard !items.isEmpty else {
                output += "[]"
                return
            }
            output += "[\n"
            for (index, item) in items.enumerated() {
                output += pad
                write(item, indent: indent + 1, into: &output)
                output += index == items.count - 1 ? "\n" : ",\n"
            }
            output += closingPad + "]"
        case let .string(value):
            output += quoted(value)
        case let .number(value):
            output += value
        case let .bool(value):
            output += value ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    static func quoted(_ string: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(string), let text = String(data: data, encoding: .utf8) else {
            return "\"\(string)\""
        }
        return text
    }
}
