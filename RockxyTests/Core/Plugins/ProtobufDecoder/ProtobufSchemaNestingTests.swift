import Foundation
@testable import Rockxy
import Testing

// MARK: - ProtobufSchemaNestingTests

/// An uploaded schema is untrusted input: message nesting is bounded so a crafted file cannot
/// exhaust the stack while it is parsed.
@Suite("Protobuf schema nesting limit")
struct ProtobufSchemaNestingTests {
    // MARK: Internal

    @Test("Source with reasonable nesting still parses")
    func moderateNestingParses() throws {
        let schema = try ProtobufSourceParser.parse(nestedSource(depth: 10))
        #expect(schema.messageNames.count == 10)
    }

    @Test("Source nested beyond the limit is rejected with a schema error")
    func deepSourceIsRejected() {
        #expect(throws: ProtobufSchemaParseError.self) {
            try ProtobufSourceParser.parse(nestedSource(depth: ProxyLimits.maxProtobufSchemaNesting + 50))
        }
    }

    @Test("A very deep source does not exhaust the stack")
    func veryDeepSourceIsRejected() {
        #expect(throws: ProtobufSchemaParseError.self) {
            try ProtobufSourceParser.parse(nestedSource(depth: 20_000))
        }
    }

    @Test("Descriptor set with reasonable nesting parses; excessive nesting is rejected")
    func descriptorNesting() throws {
        let ok = try ProtobufDescriptorSetParser.parse(descriptorSet(depth: 10))
        #expect(ok.messageNames.count == 10)
        #expect(throws: ProtobufSchemaParseError.malformedDescriptorSet) {
            try ProtobufDescriptorSetParser.parse(descriptorSet(depth: ProxyLimits.maxProtobufSchemaNesting + 50))
        }
    }

    // MARK: Private

    private func nestedSource(depth: Int) -> String {
        var source = "syntax = \"proto3\";\n"
        for index in 0 ..< depth {
            source += "message M\(index) {\n"
        }
        source += String(repeating: "}\n", count: depth)
        return source
    }

    private func varint(_ value: Int) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private func field(_ number: Int, _ payload: [UInt8]) -> [UInt8] {
        varint((number << 3) | 2) + varint(payload.count) + payload
    }

    /// FileDescriptorSet { file { package, message_type { name, nested_type { ... } } } }
    private func descriptorSet(depth: Int) -> Data {
        var message: [UInt8] = field(1, Array("M\(depth - 1)".utf8))
        for index in stride(from: depth - 2, through: 0, by: -1) {
            message = field(1, Array("M\(index)".utf8)) + field(3, message)
        }
        let file = field(2, Array("demo".utf8)) + field(4, message)
        return Data(field(1, file))
    }
}
