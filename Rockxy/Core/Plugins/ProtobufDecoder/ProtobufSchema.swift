import Foundation

// MARK: - ProtobufSchema

/// Message and enum definitions compiled from `.desc` descriptor sets or `.proto` sources.
/// Names are fully qualified without a leading dot, e.g. `demo.chat.NewMessage`.
nonisolated struct ProtobufSchema: Equatable, Sendable {
    // MARK: Lifecycle

    init(
        messages: [String: ProtobufMessageSchema] = [:],
        enums: [String: ProtobufEnumSchema] = [:],
        methods: [String: ProtobufMethodSchema] = [:]
    ) {
        self.messages = messages
        self.enums = enums
        self.methods = methods
    }

    // MARK: Internal

    var messages: [String: ProtobufMessageSchema]
    var enums: [String: ProtobufEnumSchema]
    /// gRPC methods keyed by request path without the leading slash, e.g. `demo.Chat/Send`.
    var methods: [String: ProtobufMethodSchema]

    /// Message types a user can pick as a root, sorted, excluding synthetic map entries.
    var messageNames: [String] {
        messages.values.filter { !$0.isMapEntry }.map(\.fullName).sorted()
    }

    /// Combines schemas so types defined in one file resolve from another. Later definitions win.
    func merged(with other: ProtobufSchema) -> ProtobufSchema {
        ProtobufSchema(
            messages: messages.merging(other.messages) { _, new in new },
            enums: enums.merging(other.enums) { _, new in new },
            methods: methods.merging(other.methods) { _, new in new }
        )
    }

    /// Resolves named field types that source parsing could not classify, following protobuf
    /// scoping: the innermost enclosing scope is searched first, then each parent package.
    func resolvingReferences() -> ProtobufSchema {
        var resolved = self
        for (messageName, message) in messages {
            var fields = message.fields
            for (number, field) in message.fields {
                guard let reference = field.unresolvedReference else {
                    continue
                }
                // Unresolved references stay pending: the defining schema may be imported later.
                guard let target = resolve(reference, fromScope: messageName) else {
                    continue
                }
                var updated = field
                updated.unresolvedReference = nil
                updated.typeName = target.name
                updated.type = target.isEnum ? .enumeration : .message
                fields[number] = updated
            }
            resolved.messages[messageName]?.fields = fields
        }
        for (path, method) in methods {
            var updated = method
            if let input = method.unresolvedScope.flatMap({ resolve(method.inputType, fromScope: $0) }) {
                updated.inputType = input.name
            }
            if let output = method.unresolvedScope.flatMap({ resolve(method.outputType, fromScope: $0) }) {
                updated.outputType = output.name
            }
            resolved.methods[path] = updated
        }
        return resolved
    }

    /// The gRPC method for a request path such as `/demo.Chat/Send`.
    func method(forGRPCPath path: String) -> ProtobufMethodSchema? {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return methods[trimmed.split(separator: "?", maxSplits: 1).first.map(String.init) ?? trimmed]
    }

    // MARK: Private

    private func resolve(_ reference: String, fromScope scope: String) -> (name: String, isEnum: Bool)? {
        if reference.hasPrefix(".") {
            let name = String(reference.dropFirst())
            return lookup(name)
        }
        var components = scope.split(separator: ".").map(String.init)
        while true {
            let candidate = (components + [reference]).joined(separator: ".")
            if let found = lookup(candidate) {
                return found
            }
            guard !components.isEmpty else {
                return nil
            }
            components.removeLast()
        }
    }

    private func lookup(_ name: String) -> (name: String, isEnum: Bool)? {
        if messages[name] != nil {
            return (name, false)
        }
        if enums[name] != nil {
            return (name, true)
        }
        return nil
    }
}

// MARK: - ProtobufMethodSchema

nonisolated struct ProtobufMethodSchema: Equatable, Sendable {
    var inputType: String
    var outputType: String
    /// Package scope for `.proto` sources whose request/response names are not yet qualified.
    var unresolvedScope: String?
}

// MARK: - ProtobufMessageSchema

nonisolated struct ProtobufMessageSchema: Equatable, Sendable {
    let fullName: String
    var fields: [Int: ProtobufFieldSchema]
    var isMapEntry = false
}

// MARK: - ProtobufFieldSchema

nonisolated struct ProtobufFieldSchema: Equatable, Sendable {
    let name: String
    let number: Int
    var type: ProtobufFieldType
    var isRepeated: Bool
    /// Fully qualified message or enum name for `.message`/`.enumeration` fields.
    var typeName: String?
    /// A type reference from `.proto` source awaiting `ProtobufSchema.resolvingReferences()`.
    var unresolvedReference: String?
}

// MARK: - ProtobufFieldType

/// Field types numbered as in `google/protobuf/descriptor.proto`.
nonisolated enum ProtobufFieldType: Int, Sendable {
    case double = 1
    case float = 2
    case int64 = 3
    case uint64 = 4
    case int32 = 5
    case fixed64 = 6
    case fixed32 = 7
    case bool = 8
    case string = 9
    case group = 10
    case message = 11
    case bytes = 12
    case uint32 = 13
    case enumeration = 14
    case sfixed32 = 15
    case sfixed64 = 16
    case sint32 = 17
    case sint64 = 18

    // MARK: Lifecycle

    init?(scalarName: String) {
        switch scalarName {
        case "double": self = .double
        case "float": self = .float
        case "int64": self = .int64
        case "uint64": self = .uint64
        case "int32": self = .int32
        case "fixed64": self = .fixed64
        case "fixed32": self = .fixed32
        case "bool": self = .bool
        case "string": self = .string
        case "bytes": self = .bytes
        case "uint32": self = .uint32
        case "sfixed32": self = .sfixed32
        case "sfixed64": self = .sfixed64
        case "sint32": self = .sint32
        case "sint64": self = .sint64
        default: return nil
        }
    }

    // MARK: Internal

    var displayName: String {
        switch self {
        case .double: "double"
        case .float: "float"
        case .int64: "int64"
        case .uint64: "uint64"
        case .int32: "int32"
        case .fixed64: "fixed64"
        case .fixed32: "fixed32"
        case .bool: "bool"
        case .string: "string"
        case .group: "group"
        case .message: "message"
        case .bytes: "bytes"
        case .uint32: "uint32"
        case .enumeration: "enum"
        case .sfixed32: "sfixed32"
        case .sfixed64: "sfixed64"
        case .sint32: "sint32"
        case .sint64: "sint64"
        }
    }

    /// The wire type a single (unpacked) value of this field uses.
    var wireType: ProtobufWireType {
        switch self {
        case .int32,
             .int64,
             .uint32,
             .uint64,
             .sint32,
             .sint64,
             .bool,
             .enumeration: .varint
        case .fixed64,
             .sfixed64,
             .double: .fixed64
        case .fixed32,
             .sfixed32,
             .float: .fixed32
        case .string,
             .bytes,
             .message: .lengthDelimited
        case .group: .startGroup
        }
    }

    /// Scalar numeric types may arrive packed in one length-delimited field.
    var isPackable: Bool {
        wireType == .varint || wireType == .fixed32 || wireType == .fixed64
    }
}

// MARK: - ProtobufEnumSchema

nonisolated struct ProtobufEnumSchema: Equatable, Sendable {
    let fullName: String
    var values: [Int32: String]
}

// MARK: - ProtobufSchemaParseError

enum ProtobufSchemaParseError: LocalizedError, Equatable {
    case malformedDescriptorSet
    case syntax(line: Int, message: String)
    case noMessages

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .malformedDescriptorSet:
            String(
                localized: "The file is not a valid Protobuf descriptor set. Generate it with protoc --descriptor_set_out --include_imports.",
                bundle: RockxyLocalization.bundle
            )
        case let .syntax(line, message):
            String(
                localized: "Protobuf schema error on line \(String(line)): \(message)",
                bundle: RockxyLocalization.bundle
            )
        case .noMessages:
            String(localized: "The schema does not define any message types.", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ProtobufWireReader

/// Bounds-checked reader for protobuf wire format.
nonisolated struct ProtobufWireReader {
    // MARK: Lifecycle

    init(_ data: Data) {
        self.data = data
        index = data.startIndex
    }

    // MARK: Internal

    let data: Data
    private(set) var index: Data.Index

    var isAtEnd: Bool {
        index >= data.endIndex
    }

    mutating func readVarint() -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0 ..< 10 {
            guard !isAtEnd else {
                return nil
            }
            let byte = data[index]
            index = data.index(after: index)
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return value
            }
            shift += 7
        }
        return nil
    }

    mutating func readTag() -> (fieldNumber: Int, wireType: ProtobufWireType)? {
        guard let value = readVarint() else {
            return nil
        }
        return ProtobufWireType.decodeTag(value)
    }

    mutating func readFixed32() -> UInt32? {
        readBytes(4).map { $0.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian } }
    }

    mutating func readFixed64() -> UInt64? {
        readBytes(8).map { $0.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian } }
    }

    mutating func readLengthDelimited() -> Data? {
        guard let length = readVarint(), length <= UInt64(Int32.max) else {
            return nil
        }
        return readBytes(Int(length))
    }

    mutating func readBytes(_ count: Int) -> Data? {
        guard count >= 0, data.distance(from: index, to: data.endIndex) >= count else {
            return nil
        }
        let end = data.index(index, offsetBy: count)
        let slice = Data(data[index ..< end])
        index = end
        return slice
    }

    /// Skips one value of the given wire type. Groups are not supported.
    mutating func skip(_ wireType: ProtobufWireType) -> Bool {
        switch wireType {
        case .varint: readVarint() != nil
        case .fixed64: readBytes(8) != nil
        case .fixed32: readBytes(4) != nil
        case .lengthDelimited: readLengthDelimited() != nil
        case .startGroup,
             .endGroup: false
        }
    }
}
