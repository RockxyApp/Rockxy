import Foundation

// MARK: - ProtobufDescriptorSetParser

/// Reads a compiled `FileDescriptorSet` (`protoc --descriptor_set_out`), using the field numbers
/// of `google/protobuf/descriptor.proto`. Only names, numbers, labels, types, nesting, and
/// map-entry markers are read; options and source info are skipped.
nonisolated enum ProtobufDescriptorSetParser {
    // MARK: Internal

    static let fileExtensions: Set<String> = ["desc", "pb", "protoset", "binpb", "dsc"]

    static func parse(_ data: Data) throws -> ProtobufSchema {
        var schema = ProtobufSchema()
        var reader = ProtobufWireReader(data)
        var fileCount = 0
        while !reader.isAtEnd {
            guard let tag = reader.readTag() else {
                throw ProtobufSchemaParseError.malformedDescriptorSet
            }
            if tag.fieldNumber == 1, tag.wireType == .lengthDelimited {
                guard let file = reader.readLengthDelimited() else {
                    throw ProtobufSchemaParseError.malformedDescriptorSet
                }
                try parseFile(file, into: &schema)
                fileCount += 1
            } else if !reader.skip(tag.wireType) {
                throw ProtobufSchemaParseError.malformedDescriptorSet
            }
        }
        guard fileCount > 0 else {
            throw ProtobufSchemaParseError.malformedDescriptorSet
        }
        guard !schema.messageNames.isEmpty else {
            throw ProtobufSchemaParseError.noMessages
        }
        return schema
    }

    // MARK: Private

    private static func parseFile(_ data: Data, into schema: inout ProtobufSchema) throws {
        var package = ""
        var messages: [Data] = []
        var enums: [Data] = []
        var services: [Data] = []
        try forEachField(in: data) { number, wireType, reader in
            switch (number, wireType) {
            case (2, .lengthDelimited):
                package = try string(from: &reader)
            case (4, .lengthDelimited):
                try messages.append(bytes(from: &reader))
            case (5, .lengthDelimited):
                try enums.append(bytes(from: &reader))
            case (6, .lengthDelimited):
                try services.append(bytes(from: &reader))
            default:
                try skip(wireType, in: &reader)
            }
        }
        for message in messages {
            try parseMessage(message, scope: package, into: &schema)
        }
        for enumeration in enums {
            try parseEnum(enumeration, scope: package, into: &schema)
        }
        for service in services {
            try parseService(service, scope: package, into: &schema)
        }
    }

    private static func parseService(_ data: Data, scope: String, into schema: inout ProtobufSchema) throws {
        var name = ""
        var methods: [(String, String, String)] = []
        try forEachField(in: data) { number, wireType, reader in
            switch (number, wireType) {
            case (1, .lengthDelimited):
                name = try string(from: &reader)
            case (2, .lengthDelimited):
                var methodName = ""
                var input = ""
                var output = ""
                try forEachField(in: bytes(from: &reader)) { field, fieldWire, methodReader in
                    switch (field, fieldWire) {
                    case (1, .lengthDelimited): methodName = try string(from: &methodReader)
                    case (2, .lengthDelimited): input = try string(from: &methodReader)
                    case (3, .lengthDelimited): output = try string(from: &methodReader)
                    default: try skip(fieldWire, in: &methodReader)
                    }
                }
                methods.append((methodName, input, output))
            default:
                try skip(wireType, in: &reader)
            }
        }
        let serviceName = qualified(name, in: scope)
        for (methodName, input, output) in methods where !methodName.isEmpty {
            schema.methods["\(serviceName)/\(methodName)"] = ProtobufMethodSchema(
                inputType: input.hasPrefix(".") ? String(input.dropFirst()) : input,
                outputType: output.hasPrefix(".") ? String(output.dropFirst()) : output
            )
        }
    }

    private static func parseMessage(_ data: Data, scope: String, into schema: inout ProtobufSchema) throws {
        var name = ""
        var fieldData: [Data] = []
        var nested: [Data] = []
        var nestedEnums: [Data] = []
        var isMapEntry = false
        try forEachField(in: data) { number, wireType, reader in
            switch (number, wireType) {
            case (1, .lengthDelimited):
                name = try string(from: &reader)
            case (2, .lengthDelimited):
                try fieldData.append(bytes(from: &reader))
            case (3, .lengthDelimited):
                try nested.append(bytes(from: &reader))
            case (4, .lengthDelimited):
                try nestedEnums.append(bytes(from: &reader))
            case (7, .lengthDelimited):
                isMapEntry = try parseMapEntryOption(bytes(from: &reader))
            default:
                try skip(wireType, in: &reader)
            }
        }
        guard !name.isEmpty else {
            throw ProtobufSchemaParseError.malformedDescriptorSet
        }
        let fullName = qualified(name, in: scope)
        var fields: [Int: ProtobufFieldSchema] = [:]
        for field in fieldData {
            let parsed = try parseField(field)
            fields[parsed.number] = parsed
        }
        schema.messages[fullName] = ProtobufMessageSchema(fullName: fullName, fields: fields, isMapEntry: isMapEntry)
        for message in nested {
            try parseMessage(message, scope: fullName, into: &schema)
        }
        for enumeration in nestedEnums {
            try parseEnum(enumeration, scope: fullName, into: &schema)
        }
    }

    private static func parseField(_ data: Data) throws -> ProtobufFieldSchema {
        var name = ""
        var number = 0
        var label = 1
        var typeValue = 0
        var typeName: String?
        try forEachField(in: data) { fieldNumber, wireType, reader in
            switch (fieldNumber, wireType) {
            case (1, .lengthDelimited):
                name = try string(from: &reader)
            case (3, .varint):
                number = try Int(truncatingIfNeeded: varint(from: &reader))
            case (4, .varint):
                label = try Int(truncatingIfNeeded: varint(from: &reader))
            case (5, .varint):
                typeValue = try Int(truncatingIfNeeded: varint(from: &reader))
            case (6, .lengthDelimited):
                let raw = try string(from: &reader)
                typeName = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
            default:
                try skip(wireType, in: &reader)
            }
        }
        guard !name.isEmpty, number > 0, let type = ProtobufFieldType(rawValue: typeValue) else {
            throw ProtobufSchemaParseError.malformedDescriptorSet
        }
        return ProtobufFieldSchema(
            name: name,
            number: number,
            type: type,
            isRepeated: label == 3,
            typeName: typeName
        )
    }

    private static func parseEnum(_ data: Data, scope: String, into schema: inout ProtobufSchema) throws {
        var name = ""
        var values: [Int32: String] = [:]
        try forEachField(in: data) { number, wireType, reader in
            switch (number, wireType) {
            case (1, .lengthDelimited):
                name = try string(from: &reader)
            case (2, .lengthDelimited):
                var valueName = ""
                var valueNumber: Int32 = 0
                try forEachField(in: bytes(from: &reader)) { field, fieldWire, valueReader in
                    switch (field, fieldWire) {
                    case (1, .lengthDelimited):
                        valueName = try string(from: &valueReader)
                    case (2, .varint):
                        valueNumber = try Int32(truncatingIfNeeded: varint(from: &valueReader))
                    default:
                        try skip(fieldWire, in: &valueReader)
                    }
                }
                if values[valueNumber] == nil {
                    values[valueNumber] = valueName
                }
            default:
                try skip(wireType, in: &reader)
            }
        }
        guard !name.isEmpty else {
            throw ProtobufSchemaParseError.malformedDescriptorSet
        }
        let fullName = qualified(name, in: scope)
        schema.enums[fullName] = ProtobufEnumSchema(fullName: fullName, values: values)
    }

    private static func parseMapEntryOption(_ data: Data) throws -> Bool {
        var isMapEntry = false
        try forEachField(in: data) { number, wireType, reader in
            if number == 7, wireType == .varint {
                isMapEntry = try varint(from: &reader) != 0
            } else {
                try skip(wireType, in: &reader)
            }
        }
        return isMapEntry
    }

    private static func forEachField(
        in data: Data,
        _ body: (Int, ProtobufWireType, inout ProtobufWireReader) throws -> Void
    )
        throws
    {
        var reader = ProtobufWireReader(data)
        while !reader.isAtEnd {
            guard let tag = reader.readTag() else {
                throw ProtobufSchemaParseError.malformedDescriptorSet
            }
            try body(tag.fieldNumber, tag.wireType, &reader)
        }
    }

    private static func string(from reader: inout ProtobufWireReader) throws -> String {
        guard let data = reader.readLengthDelimited(), let value = String(data: data, encoding: .utf8) else {
            throw ProtobufSchemaParseError.malformedDescriptorSet
        }
        return value
    }

    private static func bytes(from reader: inout ProtobufWireReader) throws -> Data {
        guard let data = reader.readLengthDelimited() else {
            throw ProtobufSchemaParseError.malformedDescriptorSet
        }
        return data
    }

    private static func varint(from reader: inout ProtobufWireReader) throws -> UInt64 {
        guard let value = reader.readVarint() else {
            throw ProtobufSchemaParseError.malformedDescriptorSet
        }
        return value
    }

    private static func skip(_ wireType: ProtobufWireType, in reader: inout ProtobufWireReader) throws {
        guard reader.skip(wireType) else {
            throw ProtobufSchemaParseError.malformedDescriptorSet
        }
    }

    private static func qualified(_ name: String, in scope: String) -> String {
        scope.isEmpty ? name : "\(scope).\(name)"
    }
}
