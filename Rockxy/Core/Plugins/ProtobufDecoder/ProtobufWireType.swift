import Foundation

// MARK: - ProtobufWireType

enum ProtobufWireType: Int, Codable, CaseIterable, Sendable {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case startGroup = 3
    case endGroup = 4
    case fixed32 = 5

    // MARK: Internal

    static func decodeTag(_ value: UInt64) -> (fieldNumber: Int, wireType: ProtobufWireType)? {
        let fieldNumber = Int(value >> 3)
        guard fieldNumber > 0,
              let wireType = ProtobufWireType(rawValue: Int(value & 0x07)) else
        {
            return nil
        }
        return (fieldNumber, wireType)
    }

    static func encodeTag(fieldNumber: Int, wireType: ProtobufWireType) -> UInt64 {
        UInt64(fieldNumber << 3) | UInt64(wireType.rawValue)
    }
}
