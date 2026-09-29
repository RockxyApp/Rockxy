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

    @Test("JSON detection covers text and binary frames and rejects scalars")
    func jsonDetection() {
        #expect(WebSocketFrameSearch.jsonData(Data(#"  {"type":"ping"}"#.utf8)) != nil)
        #expect(WebSocketFrameSearch.jsonData(Data("[1,2]".utf8)) != nil)
        #expect(WebSocketFrameSearch.jsonData(Data("42".utf8)) == nil)
        #expect(WebSocketFrameSearch.jsonData(Data("{broken".utf8)) == nil)
        #expect(WebSocketFrameSearch.jsonData(Data([0x08, 0x96, 0x01])) == nil)

        let binaryJSON = WebSocketFrameData(direction: .received, opcode: .binary, payload: Data(#"{"a":1}"#.utf8))
        let binaryProto = WebSocketFrameData(direction: .received, opcode: .binary, payload: Data([0x08, 0x96, 0x01]))
        let text = WebSocketFrameData(direction: .sent, opcode: .text, payload: Data("hello".utf8))
        let ping = WebSocketFrameData(direction: .sent, opcode: .ping, payload: Data("x".utf8))
        #expect(WebSocketFrameSearch.isTextual(binaryJSON))
        #expect(!WebSocketFrameSearch.isTextual(binaryProto))
        #expect(WebSocketFrameSearch.isTextual(text))
        #expect(!WebSocketFrameSearch.isTextual(ping))
    }
}
