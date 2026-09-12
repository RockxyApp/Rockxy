import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

struct BreakpointResponseBuilderTests {
    @Test("Non-editable response body is preserved while status and headers can change")
    func nonEditableBodyPreserved() {
        let binary = Data([0x1F, 0x8B, 0x08, 0x00])
        var originalHead = HTTPResponseHead(version: .http1_1, status: .ok)
        originalHead.headers.add(name: "Content-Encoding", value: "gzip")
        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/data",
            headers: [
                EditableHeader(name: "Content-Encoding", value: "gzip"),
                EditableHeader(name: "X-Debug", value: "true"),
            ],
            body: "",
            statusCode: 201,
            phase: .response,
            isBodyEditable: false
        )

        let result = BreakpointResponseBuilder.build(
            modifiedData: modified,
            originalHead: originalHead,
            originalBody: binary
        )

        #expect(result.head.status == .created)
        #expect(result.head.headers.first(name: "X-Debug") == "true")
        #expect(result.head.headers.first(name: "Content-Length") == "4")
        #expect(result.body == binary)
    }

    @Test("Editable response body recomputes framing headers")
    func editableBodyRecomputesFraming() {
        var originalHead = HTTPResponseHead(version: .http1_1, status: .ok)
        originalHead.headers.add(name: "Transfer-Encoding", value: "chunked")
        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/data",
            headers: [EditableHeader(name: "Transfer-Encoding", value: "chunked")],
            body: "updated",
            statusCode: 200,
            phase: .response
        )

        let result = BreakpointResponseBuilder.build(modifiedData: modified, originalHead: originalHead)

        #expect(!result.head.headers.contains(name: "Transfer-Encoding"))
        #expect(result.head.headers.first(name: "Content-Length") == "7")
        #expect(result.body == Data("updated".utf8))
    }

    @Test("Empty editable response uses explicit zero-length framing")
    func emptyEditableBodyUsesZeroLengthFraming() {
        var originalHead = HTTPResponseHead(version: .http1_1, status: .ok)
        originalHead.headers.add(name: "Transfer-Encoding", value: "chunked")
        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/data",
            headers: [EditableHeader(name: "Transfer-Encoding", value: "chunked")],
            body: "",
            statusCode: 200,
            phase: .response
        )

        let result = BreakpointResponseBuilder.build(modifiedData: modified, originalHead: originalHead)

        #expect(result.head.headers.first(name: "Content-Length") == "0")
        #expect(!result.head.headers.contains(name: "Transfer-Encoding"))
        #expect(result.body == nil)
    }

    @Test("Missing non-editable response body uses explicit zero-length framing")
    func missingNonEditableBodyUsesZeroLengthFraming() {
        let originalHead = HTTPResponseHead(version: .http1_1, status: .ok)
        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/data",
            headers: [],
            body: "",
            statusCode: 200,
            phase: .response,
            isBodyEditable: false
        )

        let result = BreakpointResponseBuilder.build(
            modifiedData: modified,
            originalHead: originalHead,
            originalBody: nil
        )

        #expect(result.head.headers.first(name: "Content-Length") == "0")
        #expect(result.body == nil)
    }

    @Test("Clearing editable response body removes stale framing headers")
    func clearingBodyRemovesFraming() {
        var originalHead = HTTPResponseHead(version: .http1_1, status: .ok)
        originalHead.headers.add(name: "Content-Length", value: "10")
        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/data",
            headers: [
                EditableHeader(name: "Content-Length", value: "10"),
                EditableHeader(name: "Transfer-Encoding", value: "chunked"),
            ],
            body: "",
            statusCode: 204,
            phase: .response
        )

        let result = BreakpointResponseBuilder.build(modifiedData: modified, originalHead: originalHead)

        #expect(result.head.status == .noContent)
        #expect(!result.head.headers.contains(name: "Content-Length"))
        #expect(!result.head.headers.contains(name: "Transfer-Encoding"))
        #expect(result.body == nil)
    }

    @Test(arguments: [101, 199, 204, 205, 304])
    func bodyForbiddenStatusRemovesBodyAndFraming(statusCode: Int) {
        var originalHead = HTTPResponseHead(version: .http1_1, status: .ok)
        originalHead.headers.add(name: "Content-Length", value: "8")
        let modified = BreakpointRequestData(
            method: "GET",
            url: "https://api.example.com/data",
            headers: [
                EditableHeader(name: "Content-Length", value: "8"),
                EditableHeader(name: "Transfer-Encoding", value: "chunked"),
            ],
            body: "retained",
            statusCode: statusCode,
            phase: .response
        )

        let result = BreakpointResponseBuilder.build(modifiedData: modified, originalHead: originalHead)

        #expect(result.body == nil)
        #expect(!result.head.headers.contains(name: "Content-Length"))
        #expect(!result.head.headers.contains(name: "Transfer-Encoding"))
    }

    @Test("HEAD response removes edited body and framing")
    func headResponseRemovesBodyAndFraming() {
        let originalHead = HTTPResponseHead(version: .http1_1, status: .ok)
        let modified = BreakpointRequestData(
            method: "HEAD",
            url: "https://api.example.com/data",
            headers: [EditableHeader(name: "Content-Length", value: "7")],
            body: "ignored",
            statusCode: 200,
            phase: .response
        )

        let result = BreakpointResponseBuilder.build(modifiedData: modified, originalHead: originalHead)

        #expect(result.body == nil)
        #expect(!result.head.headers.contains(name: "Content-Length"))
    }
}
