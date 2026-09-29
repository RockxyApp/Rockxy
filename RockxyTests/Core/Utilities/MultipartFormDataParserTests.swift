import Foundation
@testable import Rockxy
import Testing

// MARK: - MultipartFormDataParserTests

struct MultipartFormDataParserTests {
    // MARK: Internal

    @Test("Boundary is read from quoted and unquoted Content-Type parameters")
    func readsBoundary() {
        #expect(MultipartFormDataParser.boundary(
            fromContentType: "multipart/form-data; boundary=----WebKitFormBoundaryX"
        ) == "----WebKitFormBoundaryX")
        #expect(MultipartFormDataParser.boundary(
            fromContentType: #"multipart/form-data; charset=utf-8; boundary="abc 123""#
        ) == "abc 123")
        #expect(MultipartFormDataParser.boundary(fromContentType: "application/json; boundary=x") == nil)
        #expect(MultipartFormDataParser.boundary(fromContentType: "multipart/form-data") == nil)
    }

    @Test("Fields and file parts keep names, types, and exact bytes")
    func parsesFieldsAndFiles() throws {
        let fileBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x00, 0xFF])
        var body = Data()
        body.append(Data("--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nHello\r\n".utf8))
        body.append(Data(
            "--B\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"me.png\"\r\nContent-Type: image/png\r\n\r\n"
                .utf8
        ))
        body.append(fileBytes)
        body.append(Data("\r\n--B--\r\n".utf8))

        let parts = try #require(MultipartFormDataParser.parse(
            body: body,
            headers: [HTTPHeader(name: "content-type", value: "multipart/form-data; boundary=B")]
        ))

        #expect(parts.count == 2)
        #expect(parts[0].name == "title")
        #expect(parts[0].fileName == nil)
        #expect(parts[0].textValue == "Hello")
        #expect(parts[1].name == "avatar")
        #expect(parts[1].fileName == "me.png")
        #expect(parts[1].contentType == "image/png")
        #expect(parts[1].data == fileBytes)
        #expect(parts[1].textValue == nil)
    }

    @Test("Empty values and bare LF line endings are tolerated")
    func toleratesEmptyValueAndLF() {
        let body = Data("--B\nContent-Disposition: form-data; name=empty\n\n\n--B--\n".utf8)
        let parts = MultipartFormDataParser.parse(body: body, boundary: "B")

        #expect(parts.count == 1)
        #expect(parts[0].name == "empty")
        #expect(parts[0].data.isEmpty)
    }

    @Test("A truncated body yields only the complete parts")
    func truncatedBodyDropsIncompletePart() {
        let body = Data("--B\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--B\r\nContent-Disposition: form".utf8)
        let parts = MultipartFormDataParser.parse(body: body, boundary: "B")

        #expect(parts.count == 1)
        #expect(parts.first?.textValue == "1")
    }

    @Test("Non-multipart requests are not parsed")
    func ignoresOtherContentTypes() {
        #expect(MultipartFormDataParser.parse(
            body: Data("{}".utf8),
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")]
        ) == nil)
    }
}

// MARK: - MultipartResponseTabTests

@MainActor
struct MultipartResponseTabTests {
    @Test("Multipart responses get their own tab; requests keep theirs")
    func responseMultipartIsApplicable() {
        let body = Data("--b\r\nContent-Type: text/plain\r\n\r\nhello\r\n--b--\r\n".utf8)
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(
            headers: [HTTPHeader(name: "Content-Type", value: "multipart/mixed; boundary=b")],
            body: body
        )

        #expect(MultipartInspectorView.isApplicable(to: transaction, direction: .response))
        #expect(!MultipartInspectorView.isApplicable(to: transaction, direction: .request))
        #expect(ResponseInspectorTab.availableTabs(includesMultipart: true).contains(.multipart))
        #expect(!ResponseInspectorTab.availableTabs().contains(.multipart))
        #expect(MultipartFormDataParser.parse(body: body, boundary: "b").count == 1)
    }
}
