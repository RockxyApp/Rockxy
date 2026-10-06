import Foundation
@testable import Rockxy
import Testing

// MARK: - ProtobufSchemaDecoderTests

/// Fixtures were produced by protoc 31.1 (`--descriptor_set_out --include_imports`) and the
/// reference Python runtime, so they exercise real compiler and encoder output.
@Suite("Protobuf schema decoding")
struct ProtobufSchemaDecoderTests {
    // MARK: Internal

    @Test("Descriptor set lists packaged message types, excluding map entries")
    func descriptorSetListsMessageTypes() throws {
        let schema = try ProtobufDescriptorSetParser.parse(Self.descriptorSet)

        #expect(schema.messageNames.contains("demo.chat.NewMessage"))
        #expect(schema.messageNames.contains("demo.chat.NewMessage.Attachment"))
        #expect(schema.messageNames.contains("demo.common.Author"))
        #expect(schema.messageNames.contains("google.protobuf.Timestamp"))
        #expect(!schema.messageNames.contains("demo.chat.NewMessage.CountersEntry"))
        #expect(schema.enums["demo.common.Priority"]?.values[2] == "PRIORITY_HIGH")
    }

    @Test("Decoding with the descriptor set names every field and renders typed values")
    func decodesWithDescriptorSet() throws {
        let schema = try ProtobufDescriptorSetParser.parse(Self.descriptorSet)
        let tree = try ProtobufSchemaDecoder.decode(
            Self.message,
            messageType: "demo.chat.NewMessage",
            schema: schema
        )
        try assertDecodedMessage(tree)
    }

    @Test("Decoding with parsed .proto sources matches the compiled descriptor")
    func decodesWithSourceSchemas() throws {
        let schema = try ProtobufSourceParser.parse(Self.chatSource)
            .merged(with: ProtobufSourceParser.parse(Self.commonSource))
            .resolvingReferences()
        let tree = try ProtobufSchemaDecoder.decode(
            Self.message,
            messageType: "demo.chat.NewMessage",
            schema: schema
        )
        try assertDecodedMessage(tree)
    }

    @Test("A length-prefixed list decodes as indexed messages")
    func decodesDelimitedList() throws {
        let schema = try ProtobufDescriptorSetParser.parse(Self.descriptorSet)
        var list = Data()
        for _ in 0 ..< 2 {
            var length = UInt64(Self.message.count)
            while length >= 0x80 {
                list.append(UInt8(length & 0x7F) | 0x80)
                length >>= 7
            }
            list.append(UInt8(length))
            list.append(Self.message)
        }

        let tree = try ProtobufSchemaDecoder.decode(list, messageType: "demo.chat.NewMessage", schema: schema)

        #expect(tree.fields.map(\.name) == ["[0]", "[1]"])
        #expect(tree.fields.allSatisfy { $0.typeName == "demo.chat.NewMessage" })
    }

    @Test("Wrong root types and missing types report errors instead of rendering garbage")
    func wrongTypeIsReported() throws {
        let schema = try ProtobufDescriptorSetParser.parse(Self.descriptorSet)

        #expect(throws: ProtobufSchemaDecodeError.doesNotMatch("demo.common.Author")) {
            _ = try ProtobufSchemaDecoder.decode(
                Self.message,
                messageType: "demo.common.Author",
                schema: schema,
                encoding: .singleMessage
            )
        }
        #expect(throws: ProtobufSchemaDecodeError.unknownMessageType("demo.Missing")) {
            _ = try ProtobufSchemaDecoder.decode(Self.message, messageType: "demo.Missing", schema: schema)
        }
        #expect(throws: ProtobufSchemaDecodeError.truncated) {
            _ = try ProtobufSchemaDecoder.decode(
                Self.message.dropLast(1),
                messageType: "demo.chat.NewMessage",
                schema: schema,
                encoding: .singleMessage
            )
        }
    }

    @Test("Unknown field numbers are kept as raw fields")
    func unknownFieldsStayRaw() throws {
        let schema = try ProtobufSourceParser.parse("syntax = \"proto3\"; message Small { int32 a = 1; }")
        let tree = try ProtobufSchemaDecoder.decode(
            Data([0x08, 0x05, 0x10, 0x07]),
            messageType: "Small",
            schema: schema
        )

        #expect(tree.fields.map(\.name) == ["a", nil])
        #expect(tree.fields.last?.value == .varint(7))
    }

    @Test(
        "Malformed schemas are rejected with a clear error",
        arguments: [
            "message { int32 a = 1; }",
            "message A { int32 a = ; }",
            "message A { int32 a = 1 }",
            "message A { /* never closed",
            "enum E { A = 99999999999; }",
        ]
    )
    func malformedSourceIsRejected(source: String) {
        #expect(throws: ProtobufSchemaParseError.self) {
            _ = try ProtobufSourceParser.parse(source)
        }
    }

    @Test("Descriptor parsing rejects arbitrary bytes")
    func malformedDescriptorIsRejected() {
        #expect(throws: ProtobufSchemaParseError.self) {
            _ = try ProtobufDescriptorSetParser.parse(Data("syntax = \"proto3\";".utf8))
        }
        #expect(throws: ProtobufSchemaParseError.self) {
            _ = try ProtobufDescriptorSetParser.parse(Data([0x0A, 0xFF]))
        }
    }

    @Test("Source parser handles comments, options, oneofs, reserved ranges, and services")
    func sourceParserSkipsNonDecodingDeclarations() throws {
        let schema = try ProtobufSourceParser.parse(
            """
            // header
            syntax = "proto3";
            package a.b;
            option java_package = "x.y";
            import "other.proto";
            /* block
               comment */
            message Outer {
              option deprecated = true;
              reserved 5 to 9, 12;
              reserved "old";
              oneof choice {
                string name = 1 [deprecated = true];
                Inner inner = 2;
              }
              message Inner { repeated sint64 values = 1 [packed = true]; }
              map<int32, Inner> by_id = 3;
            }
            service Chat { rpc Send(Outer) returns (Outer) { option idempotency_level = IDEMPOTENT; } }
            """
        )

        let outer = try #require(schema.messages["a.b.Outer"])
        #expect(outer.fields[2]?.typeName == "a.b.Outer.Inner")
        #expect(outer.fields[3]?.typeName == "a.b.Outer.ByIdEntry")
        #expect(schema.messages["a.b.Outer.ByIdEntry"]?.fields[2]?.typeName == "a.b.Outer.Inner")
        #expect(schema.messages["a.b.Outer.Inner"]?.fields[1]?.isRepeated == true)
    }

    @Test("Timestamps render in RFC 3339 like the JSON mapping")
    func timestampFormatting() {
        #expect(ProtobufWellKnownTypes.rfc3339(seconds: 1_700_000_000, nanos: 0) == "2023-11-14T22:13:20Z")
        #expect(ProtobufWellKnownTypes.rfc3339(seconds: 1_700_000_000, nanos: 5) == "2023-11-14T22:13:20.000000005Z")
        #expect(ProtobufWellKnownTypes.rfc3339(seconds: 0, nanos: 500_000_000) == "1970-01-01T00:00:00.500Z")
    }

    // MARK: Private

    private static let descriptorSet = Data(base64Encoded: [
        "CqsBCgxjb21tb24ucHJvdG8SC2RlbW8uY29tbW9uIjsKBkF1dGhvchIOCgJpZBgBIAEoCVICaWQSIQoMZGlzcGxheV9uYW1lGAIg",
        "ASgJUgtkaXNwbGF5TmFtZSpJCghQcmlvcml0eRIYChRQUklPUklUWV9VTlNQRUNJRklFRBAAEhAKDFBSSU9SSVRZX0xPVxABEhEK",
        "DVBSSU9SSVRZX0hJR0gQAmIGcHJvdG8zCv8BCh9nb29nbGUvcHJvdG9idWYvdGltZXN0YW1wLnByb3RvEg9nb29nbGUucHJvdG9i",
        "dWYiOwoJVGltZXN0YW1wEhgKB3NlY29uZHMYASABKANSB3NlY29uZHMSFAoFbmFub3MYAiABKAVSBW5hbm9zQoUBChNjb20uZ29v",
        "Z2xlLnByb3RvYnVmQg5UaW1lc3RhbXBQcm90b1ABWjJnb29nbGUuZ29sYW5nLm9yZy9wcm90b2J1Zi90eXBlcy9rbm93bi90aW1l",
        "c3RhbXBwYvgBAaICA0dQQqoCHkdvb2dsZS5Qcm90b2J1Zi5XZWxsS25vd25UeXBlc2IGcHJvdG8zCvoGCgpjaGF0LnByb3RvEglk",
        "ZW1vLmNoYXQaDGNvbW1vbi5wcm90bxofZ29vZ2xlL3Byb3RvYnVmL3RpbWVzdGFtcC5wcm90byKpBgoKTmV3TWVzc2FnZRIOCgJp",
        "ZBgBIAEoA1ICaWQSEgoEdGV4dBgCIAEoCVIEdGV4dBIrCgZhdXRob3IYAyABKAsyEy5kZW1vLmNvbW1vbi5BdXRob3JSBmF1dGhv",
        "chIcCglyZWFjdGlvbnMYBCADKAVSCXJlYWN0aW9ucxI/Cghjb3VudGVycxgFIAMoCzIjLmRlbW8uY2hhdC5OZXdNZXNzYWdlLkNv",
        "dW50ZXJzRW50cnlSCGNvdW50ZXJzEjEKCHByaW9yaXR5GAYgASgOMhUuZGVtby5jb21tb24uUHJpb3JpdHlSCHByaW9yaXR5Ei4K",
        "BGtpbmQYByABKA4yGi5kZW1vLmNoYXQuTmV3TWVzc2FnZS5LaW5kUgRraW5kEkIKC2F0dGFjaG1lbnRzGAggAygLMiAuZGVtby5j",
        "aGF0Lk5ld01lc3NhZ2UuQXR0YWNobWVudFILYXR0YWNobWVudHMSGQoHcm9vbV9pZBgJIAEoCUgAUgZyb29tSWQSGQoHdXNlcl9p",
        "ZBgKIAEoCUgAUgZ1c2VySWQSFAoFZGVsdGEYCyABKBFSBWRlbHRhEhoKCGNoZWNrc3VtGAwgASgGUghjaGVja3N1bRIUCgVzY29y",
        "ZRgNIAEoAVIFc2NvcmUSFAoFcmF0aW8YDiABKAJSBXJhdGlvEhYKBnBpbm5lZBgPIAEoCFIGcGlubmVkEjMKB3NlbnRfYXQYECAB",
        "KAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgZzZW50QXQSEgoEdGFncxgRIAMoCVIEdGFncxIZCgVyZXRyeRgSIAEoDUgB",
        "UgVyZXRyeYgBARo8CgpBdHRhY2htZW50EhAKA3VybBgBIAEoCVIDdXJsEhwKCXRodW1ibmFpbBgCIAEoDFIJdGh1bWJuYWlsGjsK",
        "DUNvdW50ZXJzRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAVSBXZhbHVlOgI4ASIlCgRLaW5kEg0KCUtJTkRf",
        "VEVYVBAAEg4KCktJTkRfSU1BR0UQAUIICgZ0YXJnZXRCCAoGX3JldHJ5YgZwcm90bzM=",
    ].joined())!

    private static let message = Data(base64Encoded:
        "CMuJ7I/3IxIGaMOpbGxvGgkKAnUxEgNBZGEiBAECrAIqCQoFdmlld3MQZCoJCgVsaWtlcxAHMAI4AUIbChRodHRwczovL3gudGVzdC9pLnBuZxIDAAH/SgRyLTQyWAlh8P////////9pAAAAAAAADEB1AACAPngBggEICIDiz6oGEAWKAQFhigEBYpABAw=="
    )!

    private static let chatSource = #"""
syntax = "proto3";
package demo.chat;

import "common.proto";
import "google/protobuf/timestamp.proto";

message NewMessage {
  message Attachment {
    string url = 1;
    bytes thumbnail = 2;
  }
  enum Kind {
    KIND_TEXT = 0;
    KIND_IMAGE = 1;
  }
  int64 id = 1;
  string text = 2;
  demo.common.Author author = 3;
  repeated int32 reactions = 4;
  map<string, int32> counters = 5;
  demo.common.Priority priority = 6;
  Kind kind = 7;
  repeated Attachment attachments = 8;
  oneof target {
    string room_id = 9;
    string user_id = 10;
  }
  sint32 delta = 11;
  fixed64 checksum = 12;
  double score = 13;
  float ratio = 14;
  bool pinned = 15;
  google.protobuf.Timestamp sent_at = 16;
  repeated string tags = 17;
  optional uint32 retry = 18;
}
"""#

    private static let commonSource = #"""
syntax = "proto3";
package demo.common;

enum Priority {
  PRIORITY_UNSPECIFIED = 0;
  PRIORITY_LOW = 1;
  PRIORITY_HIGH = 2;
}

message Author {
  string id = 1;
  string display_name = 2;
}
"""#

    private func assertDecodedMessage(_ tree: ProtobufDecodedTree) throws {
        func field(_ name: String) -> ProtobufDecodedField? {
            tree.fields.first { $0.name == name }
        }

        #expect(field("id")?.displayValue == "1234567890123")
        #expect(field("text")?.value == .string("héllo"))
        #expect(tree.fields.filter { $0.name == "reactions" }.map(\.displayValue) == ["1", "2", "300"])
        #expect(field("priority")?.displayValue == "PRIORITY_HIGH (2)")
        #expect(field("kind")?.displayValue == "KIND_IMAGE (1)")
        #expect(field("room_id")?.value == .string("r-42"))
        #expect(field("delta")?.displayValue == "-5")
        #expect(field("checksum")?.displayValue == "18446744073709551600")
        #expect(field("score")?.displayValue == "3.5")
        #expect(field("ratio")?.displayValue == "0.25")
        #expect(field("pinned")?.displayValue == "true")
        #expect(field("retry")?.displayValue == "3")
        #expect(tree.fields.filter { $0.name == "tags" }.map(\.value) == [.string("a"), .string("b")])
        #expect(field("sent_at")?.displayValue == "2023-11-14T22:13:20.000000005Z")
        #expect(field("sent_at")?.typeName == "google.protobuf.Timestamp")
        #expect(Set(tree.fields.filter { $0.name == "counters" }.compactMap(\.displayValue))
            == ["\"likes\" → 7", "\"views\" → 100"])

        guard case let .message(author) = try #require(field("author")).value else {
            Issue.record("author should decode as a message")
            return
        }
        #expect(author.fields.map(\.name) == ["id", "display_name"])
        #expect(field("author")?.typeName == "demo.common.Author")
        #expect(field("attachments")?.typeName == "repeated demo.chat.NewMessage.Attachment")
    }
}

// MARK: - ProtobufSchemaImportTests

@MainActor
@Suite("Protobuf schema import")
struct ProtobufSchemaImportTests {
    @Test("Importing a source schema records its message types and resolves across imports")
    func importRecordsMessageNamesAndCombines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pb-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProtobufSchemaStore(
            policy: UnlimitedSchemaPolicy(),
            fileStore: ProtobufSchemaFileStore(directoryURL: directory)
        )

        let common = try store.uploadSchema(
            data: Data("syntax = \"proto3\"; package p; message Author { string id = 1; }".utf8),
            fileName: "common.proto",
            hostPattern: "*"
        )
        _ = try store.uploadSchema(
            data: Data(
                """
                syntax = "proto3"; package p;
                import "common.proto";
                message Post { Author author = 1; }
                service Feed { rpc Get(Post) returns (stream Post); }
                """.utf8
            ),
            fileName: "post.proto",
            hostPattern: "*"
        )

        #expect(common.parsedMessageNames == ["p.Author"])
        let combined = store.combinedSchema()
        #expect(combined.messages["p.Post"]?.fields[1]?.typeName == "p.Author")
        #expect(combined.method(forGRPCPath: "/p.Feed/Get") == ProtobufMethodSchema(
            inputType: "p.Post",
            outputType: "p.Post",
            unresolvedScope: "p"
        ))

        let reloaded = ProtobufSchemaStore(
            policy: UnlimitedSchemaPolicy(),
            fileStore: ProtobufSchemaFileStore(directoryURL: directory)
        )
        #expect(reloaded.combinedSchema().messageNames == ["p.Author", "p.Post"])
    }

    @Test("Schemas that do not parse are rejected at import with the parser's reason")
    func invalidSchemaIsRejected() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pb-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProtobufSchemaStore(
            policy: UnlimitedSchemaPolicy(),
            fileStore: ProtobufSchemaFileStore(directoryURL: directory)
        )

        #expect(throws: ProtobufSchemaParseError.self) {
            _ = try store.uploadSchema(data: Data("message {".utf8), fileName: "bad.proto", hostPattern: "*")
        }
        #expect(throws: ProtobufSchemaParseError.self) {
            _ = try store.uploadSchema(data: Data([0x0A, 0x05, 0x01]), fileName: "bad.desc", hostPattern: "*")
        }
        #expect(store.schemas.isEmpty)
    }
}

// MARK: - UnlimitedSchemaPolicy

private struct UnlimitedSchemaPolicy: AppPolicy {
    let maxWorkspaceTabs = Int.max
    let maxDomainFavorites = Int.max
    let maxActiveRulesPerTool = Int.max
    let maxEnabledScripts = Int.max
    let maxLiveHistoryEntries = Int.max
    let protobufDecodingAllowsSchemaUpload = true
    let maxProtobufSchemas = Int.max
}
