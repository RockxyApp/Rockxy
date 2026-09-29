import Foundation
@testable import Rockxy
import Testing

// MARK: - WebSocketFrameSearchTests

struct WebSocketFrameSearchTests {
    @Test("Frame search is case-insensitive over UTF-8 payload text")
    func matchesText() {
        let payload = Data(#"{"type":"chat.message","text":"Hello Rockxy"}"#.utf8)

        #expect(WebSocketFrameSearch.matches(payload, query: "hello rockxy"))
        #expect(WebSocketFrameSearch.matches(payload, query: ""))
        #expect(!WebSocketFrameSearch.matches(payload, query: "presence"))
        #expect(!WebSocketFrameSearch.matches(Data([0xFF, 0xFE, 0x00]), query: "a"))
    }

    @Test("JSON payloads are pretty-printed; other text is left alone")
    func formatsJSON() {
        #expect(WebSocketFrameSearch.prettyJSON(#"{"b":1,"a":[true]}"#) == """
        {
          "a" : [
            true
          ],
          "b" : 1
        }
        """)
        #expect(WebSocketFrameSearch.prettyJSON("ping") == nil)
        #expect(WebSocketFrameSearch.prettyJSON("42") == nil)
    }
}
