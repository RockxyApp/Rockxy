import Foundation

// MARK: - ProtobufSchemaDecoder

/// Decodes Protobuf wire data against a message type from imported schemas, producing the same
/// tree the heuristic decoder does with field names, declared types, and readable values.
/// Field numbers the schema does not know (for example from a newer server) are kept as raw
/// fields; a declared field arriving with an incompatible wire type means the chosen root type
/// is wrong, which is reported instead of rendering misleading values.
nonisolated enum ProtobufSchemaDecoder {
    // MARK: Internal

    static func decode(
        _ data: Data,
        messageType: String,
        schema: ProtobufSchema,
        encoding: ProtobufPayloadEncoding = .auto,
        maxDepth: Int = ProxyLimits.maxProtobufDecodeDepth,
        maxNodes: Int = ProxyLimits.maxProtobufDecodeNodes
    )
        throws -> ProtobufDecodedTree
    {
        let schema = schema.merged(with: ProtobufWellKnownTypes.schema).resolvingReferences()
        let rootName = messageType.hasPrefix(".") ? String(messageType.dropFirst()) : messageType
        guard let root = schema.messages[rootName] else {
            throw ProtobufSchemaDecodeError.unknownMessageType(rootName)
        }
        var context = Context(schema: schema, maxDepth: maxDepth, maxNodes: maxNodes)

        switch encoding {
        case .singleMessage:
            return try ProtobufDecodedTree(fields: context.decodeMessage(data, as: root, depth: 0))
        case .delimitedList:
            return try context.decodeDelimited(data, as: root)
        case .auto:
            do {
                return try ProtobufDecodedTree(fields: context.decodeMessage(data, as: root, depth: 0))
            } catch {
                var retry = Context(schema: schema, maxDepth: maxDepth, maxNodes: maxNodes)
                if let list = try? retry.decodeDelimited(data, as: root), list.fields.count > 1 {
                    return list
                }
                throw error
            }
        }
    }

    // MARK: Private

    private struct Context {
        // MARK: Internal

        let schema: ProtobufSchema
        let maxDepth: Int
        let maxNodes: Int
        var nodeCount = 0

        mutating func decodeDelimited(_ data: Data, as message: ProtobufMessageSchema) throws -> ProtobufDecodedTree {
            var reader = ProtobufWireReader(data)
            var fields: [ProtobufDecodedField] = []
            while !reader.isAtEnd {
                let start = reader.index
                guard let item = reader.readLengthDelimited() else {
                    throw ProtobufSchemaDecodeError.truncated
                }
                let children = try decodeMessage(item, as: message, depth: 1)
                fields.append(ProtobufDecodedField(
                    fieldNumber: fields.count + 1,
                    wireType: .lengthDelimited,
                    value: .message(ProtobufDecodedTree(fields: children)),
                    rawBytes: Data(data[start ..< reader.index]),
                    name: "[\(fields.count)]",
                    typeName: message.fullName
                ))
            }
            guard !fields.isEmpty else {
                throw ProtobufSchemaDecodeError.truncated
            }
            return ProtobufDecodedTree(fields: fields)
        }

        mutating func decodeMessage(
            _ data: Data,
            as message: ProtobufMessageSchema,
            depth: Int
        )
            throws -> [ProtobufDecodedField]
        {
            guard depth <= maxDepth else {
                throw ProtobufSchemaDecodeError.tooComplex
            }
            var reader = ProtobufWireReader(data)
            var fields: [ProtobufDecodedField] = []
            while !reader.isAtEnd {
                let start = reader.index
                guard let tag = reader.readTag() else {
                    throw ProtobufSchemaDecodeError.doesNotMatch(message.fullName)
                }
                try countNode()

                guard let field = message.fields[tag.fieldNumber] else {
                    try fields.append(unknownField(tag, reader: &reader, data: data, start: start))
                    continue
                }

                if tag.wireType == .lengthDelimited, field.type.isPackable {
                    guard let packed = reader.readLengthDelimited() else {
                        throw ProtobufSchemaDecodeError.truncated
                    }
                    try fields.append(contentsOf: decodePacked(packed, field: field))
                    continue
                }
                guard tag.wireType == field.type.wireType else {
                    throw ProtobufSchemaDecodeError.doesNotMatch(message.fullName)
                }
                let value = try decodeValue(field: field, reader: &reader, depth: depth)
                fields.append(ProtobufDecodedField(
                    fieldNumber: field.number,
                    wireType: tag.wireType,
                    value: value.value,
                    rawBytes: Data(data[start ..< reader.index]),
                    name: field.name,
                    typeName: typeLabel(for: field),
                    displayValue: value.display
                ))
            }
            return fields
        }

        // MARK: Private

        private static func format(_ value: Double) -> String {
            if value.isFinite, value.rounded() == value, abs(value) < 1e15 {
                return String(Int64(value))
            }
            return String(value)
        }

        private mutating func countNode() throws {
            nodeCount += 1
            guard nodeCount <= maxNodes else {
                throw ProtobufSchemaDecodeError.tooComplex
            }
        }

        private func typeLabel(for field: ProtobufFieldSchema) -> String {
            let base: String = switch field.type {
            case .message,
                 .enumeration: field.typeName ?? field.type.displayName
            default: field.type.displayName
            }
            return field.isRepeated && !(schema.messages[field.typeName ?? ""]?.isMapEntry ?? false)
                ? "repeated \(base)"
                : base
        }

        private mutating func decodePacked(_ data: Data, field: ProtobufFieldSchema) throws -> [ProtobufDecodedField] {
            var reader = ProtobufWireReader(data)
            var fields: [ProtobufDecodedField] = []
            while !reader.isAtEnd {
                let start = reader.index
                try countNode()
                let value = try decodeValue(field: field, reader: &reader, depth: 0)
                fields.append(ProtobufDecodedField(
                    fieldNumber: field.number,
                    wireType: field.type.wireType,
                    value: value.value,
                    rawBytes: Data(data[start ..< reader.index]),
                    name: field.name,
                    typeName: typeLabel(for: field),
                    displayValue: value.display
                ))
            }
            return fields
        }

        private mutating func decodeValue(
            field: ProtobufFieldSchema,
            reader: inout ProtobufWireReader,
            depth: Int
        )
            throws -> (value: ProtobufDecodedValue, display: String?)
        {
            switch field.type.wireType {
            case .varint:
                guard let raw = reader.readVarint() else {
                    throw ProtobufSchemaDecodeError.truncated
                }
                return (.varint(raw), varintDisplay(raw, field: field))
            case .fixed64:
                guard let raw = reader.readFixed64() else {
                    throw ProtobufSchemaDecodeError.truncated
                }
                let display: String = switch field.type {
                case .double: Self.format(Double(bitPattern: raw))
                case .sfixed64: String(Int64(bitPattern: raw))
                default: String(raw)
                }
                return (.fixed64(raw), display)
            case .fixed32:
                guard let raw = reader.readFixed32() else {
                    throw ProtobufSchemaDecodeError.truncated
                }
                let display: String = switch field.type {
                case .float: Self.format(Double(Float(bitPattern: raw)))
                case .sfixed32: String(Int32(bitPattern: raw))
                default: String(raw)
                }
                return (.fixed32(raw), display)
            case .lengthDelimited:
                guard let bytes = reader.readLengthDelimited() else {
                    throw ProtobufSchemaDecodeError.truncated
                }
                return try lengthDelimitedValue(bytes, field: field, depth: depth)
            case .startGroup,
                 .endGroup:
                throw ProtobufSchemaDecodeError.doesNotMatch(field.name)
            }
        }

        private mutating func lengthDelimitedValue(
            _ bytes: Data,
            field: ProtobufFieldSchema,
            depth: Int
        )
            throws -> (value: ProtobufDecodedValue, display: String?)
        {
            switch field.type {
            case .string:
                guard let text = String(data: bytes, encoding: .utf8) else {
                    throw ProtobufSchemaDecodeError.doesNotMatch(field.name)
                }
                return (.string(text), nil)
            case .bytes:
                return (.bytes(bytes), nil)
            default:
                guard let typeName = field.typeName, let nested = schema.messages[typeName] else {
                    // A type outside the imported schemas: show its structure without names.
                    if let tree = ProtobufHeuristicDecoder.decode(bytes) {
                        return (.message(tree), nil)
                    }
                    return (.bytes(bytes), nil)
                }
                let children = try decodeMessage(bytes, as: nested, depth: depth + 1)
                let tree = ProtobufDecodedTree(fields: children)
                return (.message(tree), messageDisplay(tree, type: nested))
            }
        }

        private func varintDisplay(_ raw: UInt64, field: ProtobufFieldSchema) -> String {
            switch field.type {
            case .int32: return String(Int32(truncatingIfNeeded: raw))
            case .int64: return String(Int64(bitPattern: raw))
            case .uint32: return String(UInt32(truncatingIfNeeded: raw))
            case .sint32,
                 .sint64: return String(Int64(bitPattern: raw >> 1) ^ -Int64(bitPattern: raw & 1))
            case .bool: return raw == 0 ? "false" : "true"
            case .enumeration:
                let number = Int32(truncatingIfNeeded: raw)
                if let name = field.typeName.flatMap({ schema.enums[$0]?.values[number] }) {
                    return "\(name) (\(number))"
                }
                return String(number)
            default: return String(raw)
            }
        }

        /// A one-line summary for map entries and well-known types; nil keeps the generic summary.
        private func messageDisplay(_ tree: ProtobufDecodedTree, type: ProtobufMessageSchema) -> String? {
            func child(_ number: Int) -> ProtobufDecodedField? {
                tree.fields.last { $0.fieldNumber == number }
            }
            func text(_ field: ProtobufDecodedField?) -> String {
                guard let field else {
                    return ""
                }
                switch field.value {
                case let .string(value): return "\"\(value)\""
                default: return field.displayValue ?? ""
                }
            }

            if type.isMapEntry {
                return "\(text(child(1))) → \(text(child(2)))"
            }
            switch type.fullName {
            case "google.protobuf.Timestamp":
                let seconds = Int64(child(1)?.displayValue ?? "0") ?? 0
                let nanos = Int64(child(2)?.displayValue ?? "0") ?? 0
                return ProtobufWellKnownTypes.rfc3339(seconds: seconds, nanos: nanos)
            case "google.protobuf.Duration":
                let seconds = Double(child(1)?.displayValue ?? "0") ?? 0
                let nanos = Double(child(2)?.displayValue ?? "0") ?? 0
                return "\(Self.format(seconds + nanos / 1e9))s"
            default:
                if type.fullName.hasPrefix("google.protobuf."), type.fullName.hasSuffix("Value"),
                   type.fields.count == 1
                {
                    return text(child(1))
                }
                return nil
            }
        }

        private mutating func unknownField(
            _ tag: (fieldNumber: Int, wireType: ProtobufWireType),
            reader: inout ProtobufWireReader,
            data: Data,
            start: Data.Index
        )
            throws -> ProtobufDecodedField
        {
            let value: ProtobufDecodedValue
            switch tag.wireType {
            case .varint:
                guard let raw = reader.readVarint() else {
                    throw ProtobufSchemaDecodeError.truncated
                }
                value = .varint(raw)
            case .fixed64:
                guard let raw = reader.readFixed64() else {
                    throw ProtobufSchemaDecodeError.truncated
                }
                value = .fixed64(raw)
            case .fixed32:
                guard let raw = reader.readFixed32() else {
                    throw ProtobufSchemaDecodeError.truncated
                }
                value = .fixed32(raw)
            case .lengthDelimited:
                guard let bytes = reader.readLengthDelimited() else {
                    throw ProtobufSchemaDecodeError.truncated
                }
                if let tree = ProtobufHeuristicDecoder.decode(bytes) {
                    value = .message(tree)
                } else if let text = String(data: bytes, encoding: .utf8) {
                    value = .string(text)
                } else {
                    value = .bytes(bytes)
                }
            case .startGroup,
                 .endGroup:
                throw ProtobufSchemaDecodeError.doesNotMatch("group")
            }
            return ProtobufDecodedField(
                fieldNumber: tag.fieldNumber,
                wireType: tag.wireType,
                value: value,
                rawBytes: Data(data[start ..< reader.index])
            )
        }
    }
}

// MARK: - ProtobufSchemaDecodeError

enum ProtobufSchemaDecodeError: LocalizedError, Equatable {
    case unknownMessageType(String)
    case doesNotMatch(String)
    case truncated
    case tooComplex

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .unknownMessageType(name):
            String(
                localized: "The imported schemas do not define \(name). Import the schema that declares it, including its imports.",
                bundle: RockxyLocalization.bundle
            )
        case let .doesNotMatch(name):
            String(
                localized: "This payload does not match \(name). Choose the message type for this direction, or check for a length prefix or compression.",
                bundle: RockxyLocalization.bundle
            )
        case .truncated:
            String(
                localized: "The payload ends in the middle of a field, so it cannot be decoded with this schema.",
                bundle: RockxyLocalization.bundle
            )
        case .tooComplex:
            String(
                localized: "The payload is nested too deeply or has too many fields to decode safely.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}
