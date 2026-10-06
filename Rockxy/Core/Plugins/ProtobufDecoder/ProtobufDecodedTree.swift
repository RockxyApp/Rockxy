import Foundation

// MARK: - ProtobufDecodedTree

struct ProtobufDecodedTree: Codable, Equatable, Sendable {
    let fields: [ProtobufDecodedField]
}

// MARK: - ProtobufDecodedField

struct ProtobufDecodedField: Codable, Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        fieldNumber: Int,
        wireType: ProtobufWireType,
        value: ProtobufDecodedValue,
        rawBytes: Data,
        name: String? = nil,
        typeName: String? = nil,
        displayValue: String? = nil
    ) {
        self.id = id
        self.fieldNumber = fieldNumber
        self.wireType = wireType
        self.value = value
        self.rawBytes = rawBytes
        self.name = name
        self.typeName = typeName
        self.displayValue = displayValue
    }

    // MARK: Internal

    let id: UUID
    let fieldNumber: Int
    let wireType: ProtobufWireType
    let value: ProtobufDecodedValue
    let rawBytes: Data
    /// Field name from an imported schema; nil for heuristic decoding and unknown fields.
    let name: String?
    /// Declared type, e.g. `int64`, `repeated string`, or `demo.chat.Author`.
    let typeName: String?
    /// Typed rendering of the value (signed, floating point, bool, enum name, timestamp).
    let displayValue: String?
}

// MARK: - ProtobufDecodedValue

enum ProtobufDecodedValue: Codable, Equatable, Sendable {
    case varint(UInt64)
    case fixed64(UInt64)
    case fixed32(UInt32)
    case string(String)
    case bytes(Data)
    case message(ProtobufDecodedTree)
}
