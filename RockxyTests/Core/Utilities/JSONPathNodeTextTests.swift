import Foundation
@testable import Rockxy
import Testing

struct JSONPathNodeTextTests {
    @Test("A copied subtree is valid JSON equal to the original value")
    func subtreeRoundTrips() throws {
        let data = Data(#"{"user":{"name":"Ada \"A\" L","tags":["x",1,true,null],"empty":{},"none":[],"url":"https://a/b"}}"#.utf8)
        let root = try JSONPathDocument(data: data).root
        let user = try #require(root.children.first)

        let text = user.jsonText()
        let reparsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary
        let original = try (JSONSerialization.jsonObject(with: data) as? [String: Any])?["user"] as? NSDictionary
        #expect(reparsed == original)
        #expect(text.contains(#""url": "https://a/b""#))
        #expect(text.hasPrefix("{\n  "))
    }

    @Test("A string value copies without quotes unless asked for JSON")
    func stringValues() throws {
        let root = try JSONPathDocument(data: Data(#"{"name":"Ada \"A\""}"#.utf8)).root
        let name = try #require(root.children.first)
        #expect(name.jsonText(unquotedStrings: true) == #"Ada "A""#)
        #expect(name.jsonText() == #""Ada \"A\"""#)
        #expect(JSONPathNode.quoted("k\n") == #""k\n""#)
    }
}
