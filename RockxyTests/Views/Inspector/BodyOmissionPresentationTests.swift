import Foundation
@testable import Rockxy
import Testing

@Suite("Body omission presentation")
struct BodyOmissionPresentationTests {
    @Test("Request omission metadata marks its body incomplete")
    func requestOmissionMarksBodyIncomplete() throws {
        var request = try HTTPRequestData(
            method: "POST",
            url: #require(URL(string: "https://example.test/upload")),
            httpVersion: "HTTP/2",
            headers: []
        )

        #expect(!request.isBodyIncomplete)
        request.bodyOmission = BodyOmissionMetadata(reason: "bodyLimit", observedBytes: 4_096, originalBytes: 8_192)
        #expect(request.isBodyIncomplete)

        request.bodyOmission = nil
        request.bodyTruncated = true
        #expect(request.isBodyIncomplete)
    }

    @Test("Response omission metadata marks its body incomplete")
    func responseOmissionMarksBodyIncomplete() {
        var response = HTTPResponseData(statusCode: 200, statusMessage: "OK", headers: [])

        #expect(!response.isBodyIncomplete)
        response.bodyOmission = BodyOmissionMetadata(reason: "privacyPolicy", observedBytes: 0, originalBytes: 128)
        #expect(response.isBodyIncomplete)

        response.bodyOmission = nil
        response.bodyTruncated = true
        #expect(response.isBodyIncomplete)
    }
}
