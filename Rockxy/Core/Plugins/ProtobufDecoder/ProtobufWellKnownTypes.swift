import Foundation

// MARK: - ProtobufWellKnownTypes

/// Definitions of the `google.protobuf` well-known types, so schemas that reference them decode
/// with names even when the descriptor was compiled without `--include_imports`.
nonisolated enum ProtobufWellKnownTypes {
    // MARK: Internal

    static let schema: ProtobufSchema = {
        var messages: [String: ProtobufMessageSchema] = [:]
        func add(_ name: String, _ fields: [Field]) {
            let fullName = "google.protobuf.\(name)"
            var map: [Int: ProtobufFieldSchema] = [:]
            for field in fields {
                map[field.number] = ProtobufFieldSchema(
                    name: field.name,
                    number: field.number,
                    type: field.type,
                    isRepeated: field.isRepeated,
                    typeName: field.typeName
                )
            }
            messages[fullName] = ProtobufMessageSchema(fullName: fullName, fields: map)
        }

        add("Timestamp", [Field("seconds", 1, .int64, false, nil), Field("nanos", 2, .int32, false, nil)])
        add("Duration", [Field("seconds", 1, .int64, false, nil), Field("nanos", 2, .int32, false, nil)])
        add("Empty", [])
        add("Any", [Field("type_url", 1, .string, false, nil), Field("value", 2, .bytes, false, nil)])
        add("FieldMask", [Field("paths", 1, .string, true, nil)])
        add("DoubleValue", [Field("value", 1, .double, false, nil)])
        add("FloatValue", [Field("value", 1, .float, false, nil)])
        add("Int64Value", [Field("value", 1, .int64, false, nil)])
        add("UInt64Value", [Field("value", 1, .uint64, false, nil)])
        add("Int32Value", [Field("value", 1, .int32, false, nil)])
        add("UInt32Value", [Field("value", 1, .uint32, false, nil)])
        add("BoolValue", [Field("value", 1, .bool, false, nil)])
        add("StringValue", [Field("value", 1, .string, false, nil)])
        add("BytesValue", [Field("value", 1, .bytes, false, nil)])
        add("Struct", [Field("fields", 1, .message, true, "google.protobuf.Struct.FieldsEntry")])
        add("Value", [
            Field("null_value", 1, .enumeration, false, "google.protobuf.NullValue"),
            Field("number_value", 2, .double, false, nil),
            Field("string_value", 3, .string, false, nil),
            Field("bool_value", 4, .bool, false, nil),
            Field("struct_value", 5, .message, false, "google.protobuf.Struct"),
            Field("list_value", 6, .message, false, "google.protobuf.ListValue"),
        ])
        add("ListValue", [Field("values", 1, .message, true, "google.protobuf.Value")])
        messages["google.protobuf.Struct.FieldsEntry"] = ProtobufMessageSchema(
            fullName: "google.protobuf.Struct.FieldsEntry",
            fields: [
                1: ProtobufFieldSchema(name: "key", number: 1, type: .string, isRepeated: false),
                2: ProtobufFieldSchema(
                    name: "value",
                    number: 2,
                    type: .message,
                    isRepeated: false,
                    typeName: "google.protobuf.Value"
                ),
            ],
            isMapEntry: true
        )
        return ProtobufSchema(
            messages: messages,
            enums: [
                "google.protobuf.NullValue": ProtobufEnumSchema(
                    fullName: "google.protobuf.NullValue",
                    values: [0: "NULL_VALUE"]
                ),
            ]
        )
    }()

    // MARK: Private

    private struct Field {
        // MARK: Lifecycle

        init(_ name: String, _ number: Int, _ type: ProtobufFieldType, _ isRepeated: Bool, _ typeName: String?) {
            self.name = name
            self.number = number
            self.type = type
            self.isRepeated = isRepeated
            self.typeName = typeName
        }

        // MARK: Internal

        let name: String
        let number: Int
        let type: ProtobufFieldType
        let isRepeated: Bool
        let typeName: String?
    }

    /// RFC 3339 text in UTC, as the Protobuf JSON mapping prints a Timestamp.
    static func rfc3339(seconds: Int64, nanos: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        var text = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        guard nanos > 0, nanos < 1_000_000_000, text.hasSuffix("Z") else {
            return text
        }
        var fraction = String(format: "%09lld", nanos)
        while fraction.hasSuffix("000") {
            fraction.removeLast(3)
        }
        text.removeLast()
        return "\(text).\(fraction)Z"
    }
}
