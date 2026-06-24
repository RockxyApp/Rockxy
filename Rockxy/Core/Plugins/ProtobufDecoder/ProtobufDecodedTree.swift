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
        rawBytes: Data
    ) {
        self.id = id
        self.fieldNumber = fieldNumber
        self.wireType = wireType
        self.value = value
        self.rawBytes = rawBytes
    }

    // MARK: Internal

    let id: UUID
    let fieldNumber: Int
    let wireType: ProtobufWireType
    let value: ProtobufDecodedValue
    let rawBytes: Data
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
