import Foundation
@testable import Rockxy
import Testing

// MARK: - ProtobufDecodeResolverTests

@MainActor
@Suite("Protobuf decode resolver")
struct ProtobufDecodeResolverTests {
    // MARK: Internal

    @Test("A matching mapping uses its request or response type by direction")
    func mappingPicksTypeByDirection() {
        let rule = ProtobufMappingRule(
            urlPattern: "https://api.example.com/chat/*",
            method: .post,
            messageType: "demo.Fallback",
            requestMessageType: "demo.SendRequest",
            responseMessageType: "",
            payloadEncoding: .delimitedList
        )
        let url = URL(string: "https://api.example.com/chat/send")

        #expect(ProtobufDecodeResolver.automaticChoice(
            url: url, method: "POST", direction: .request, rules: [rule], schema: ProtobufSchema()
        ) == .messageType("demo.SendRequest", encoding: .delimitedList))
        #expect(ProtobufDecodeResolver.automaticChoice(
            url: url, method: "POST", direction: .response, rules: [rule], schema: ProtobufSchema()
        ) == .messageType("demo.Fallback", encoding: .delimitedList))
    }

    @Test("Disabled, method-mismatched, and non-matching definitions are ignored")
    func nonMatchingDefinitionsFallBack() {
        var disabled = ProtobufMappingRule(urlPattern: "https://api.example.com/*", messageType: "demo.A")
        disabled.isEnabled = false
        let getOnly = ProtobufMappingRule(urlPattern: "https://api.example.com/*", method: .get, messageType: "demo.B")
        let otherHost = ProtobufMappingRule(urlPattern: "https://other.example.com/*", messageType: "demo.C")
        let url = URL(string: "https://api.example.com/x")

        #expect(ProtobufDecodeResolver.automaticChoice(
            url: url,
            method: "POST",
            direction: .request,
            rules: [disabled, getOnly, otherHost],
            schema: ProtobufSchema()
        ) == .bestGuess)
    }

    @Test("gRPC request paths resolve through imported service definitions")
    func grpcPathUsesServiceMethod() throws {
        let schema = try ProtobufSourceParser.parse(
            """
            syntax = "proto3"; package demo;
            message Req { int32 id = 1; }
            message Resp { string name = 1; }
            service Users { rpc Get(Req) returns (Resp); }
            """
        )
        let url = URL(string: "https://grpc.example.com/demo.Users/Get")

        #expect(ProtobufDecodeResolver.automaticChoice(
            url: url, method: "POST", direction: .request, rules: [], schema: schema
        ) == .messageType("demo.Req", encoding: .singleMessage))
        #expect(ProtobufDecodeResolver.automaticChoice(
            url: url, method: "POST", direction: .response, rules: [], schema: schema
        ) == .messageType("demo.Resp", encoding: .singleMessage))
    }

    @Test("Best guess reports non-Protobuf bytes instead of an empty tree")
    func bestGuessRejectsNonProtobuf() {
        let result = ProtobufDecodeResolver.decode(Data("{\"a\":1}".utf8), choice: .bestGuess, schema: ProtobufSchema())
        #expect(throws: ProtobufBestGuessError.self) {
            _ = try result.get()
        }
    }

    @Test("Protobuf media types get the tab; gRPC and JSON bodies do not")
    func bodyTabApplicability() {
        let protobuf = TestFixtures.makeTransaction(url: "https://api.example.com/feed")
        protobuf.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "application/x-protobuf")],
            body: Data([0x08, 0x01])
        )
        let grpc = TestFixtures.makeTransaction(url: "https://api.example.com/demo.Users/Get")
        grpc.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "application/grpc+proto")],
            body: Data([0x00, 0x00, 0x00, 0x00, 0x02, 0x08, 0x01])
        )
        let json = TestFixtures.makeTransaction(url: "https://api.example.com/unmapped-\(UUID().uuidString)")
        json.response = TestFixtures.makeResponse(body: Data("{}".utf8))

        #expect(ProtobufBodyInspection.isApplicable(to: protobuf, direction: .response))
        #expect(!ProtobufBodyInspection.isApplicable(to: protobuf, direction: .request))
        #expect(!ProtobufBodyInspection.isApplicable(to: grpc, direction: .response))
        #expect(!ProtobufBodyInspection.isApplicable(to: json, direction: .response))
        #expect(ResponseInspectorTab.availableTabs(includesProtobuf: true).contains(.protobuf))
        #expect(!ResponseInspectorTab.availableTabs().contains(.protobuf))
    }
}
