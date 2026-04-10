import Foundation
@testable import Rockxy
import Testing

struct ResponseCaptureLimitTests {
    @Test("small body below limit is not truncated")
    func smallBodyNotTruncated() {
        let result = ProxyHandlerShared.shouldTruncateCapture(
            currentBufferSize: 0,
            incomingChunkSize: 1_024,
            maxSize: ProxyLimits.maxResponseBodySize
        )
        #expect(result == false)
    }

    @Test("body exactly at limit is not truncated")
    func exactLimitNotTruncated() {
        let limit = 100
        let result = ProxyHandlerShared.shouldTruncateCapture(
            currentBufferSize: 50,
            incomingChunkSize: 50,
            maxSize: limit
        )
        #expect(result == false)
    }

    @Test("body exceeding limit triggers truncation")
    func exceedingLimitTruncates() {
        let limit = 100
        let result = ProxyHandlerShared.shouldTruncateCapture(
            currentBufferSize: 90,
            incomingChunkSize: 20,
            maxSize: limit
        )
        #expect(result == true)
    }

    @Test("first chunk over limit triggers truncation")
    func firstChunkOverLimit() {
        let limit = 100
        let result = ProxyHandlerShared.shouldTruncateCapture(
            currentBufferSize: 0,
            incomingChunkSize: 101,
            maxSize: limit
        )
        #expect(result == true)
    }

    @Test("already-full buffer rejects any new chunk")
    func fullBufferRejectsMore() {
        let limit = 100
        let result = ProxyHandlerShared.shouldTruncateCapture(
            currentBufferSize: 100,
            incomingChunkSize: 1,
            maxSize: limit
        )
        #expect(result == true)
    }

    @Test("bodyTruncated flag propagates to HTTPResponseData")
    func truncatedFlagPropagates() {
        var response = TestFixtures.makeResponse(statusCode: 200)
        #expect(response.bodyTruncated == false)

        response.bodyTruncated = true
        #expect(response.bodyTruncated == true)
    }

    @Test("maxResponseBodySize constant is defined and positive")
    func maxResponseBodySizeExists() {
        #expect(ProxyLimits.maxResponseBodySize > 0)
        #expect(ProxyLimits.maxResponseBodySize == 100 * 1_024 * 1_024)
    }
}
