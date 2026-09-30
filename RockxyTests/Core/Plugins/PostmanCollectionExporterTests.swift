import Foundation
@testable import Rockxy
import Testing

@MainActor
struct PostmanCollectionExporterTests {
    @Test("Requests become v2.1 items grouped by host with their response as an example")
    func collectionShape() throws {
        let post = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com:8443/v1/users?page=2&q=a%20b")
        post.request.headers = [
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "Authorization", value: "Bearer t"),
            HTTPHeader(name: "Content-Length", value: "13"),
            HTTPHeader(name: "Host", value: "api.example.com:8443"),
        ]
        post.request.body = Data(#"{"name":"a"}"#.utf8)
        post.response = HTTPResponseData(
            statusCode: 201,
            statusMessage: "Created",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"id":1}"#.utf8)
        )
        let other = TestFixtures.makeTransaction(url: "http://cdn.example.org/a.png")
        let tunnel = TestFixtures.makeTransaction(method: "CONNECT", url: "https://secure.example.com:443")

        let data = try PostmanCollectionExporter.export(transactions: [post, other, tunnel], name: "Test")
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let info = try #require(root["info"] as? [String: Any])
        #expect(info["schema"] as? String == PostmanCollectionExporter.schemaURL)
        #expect(info["name"] as? String == "Test")

        let folders = try #require(root["item"] as? [[String: Any]])
        #expect(folders.map { $0["name"] as? String } == ["api.example.com", "cdn.example.org"])

        let item = try #require((folders[0]["item"] as? [[String: Any]])?.first)
        #expect(item["name"] as? String == "POST /v1/users")
        let request = try #require(item["request"] as? [String: Any])
        #expect(request["method"] as? String == "POST")
        let headerKeys = (request["header"] as? [[String: Any]])?.compactMap { $0["key"] as? String }
        #expect(headerKeys == ["Content-Type", "Authorization"])
        let body = try #require(request["body"] as? [String: Any])
        #expect(body["mode"] as? String == "raw")
        #expect(body["raw"] as? String == #"{"name":"a"}"#)
        let url = try #require(request["url"] as? [String: Any])
        #expect(url["port"] as? String == "8443")
        #expect(url["path"] as? [String] == ["v1", "users"])
        #expect(url["host"] as? [String] == ["api", "example", "com"])
        let query = try #require(url["query"] as? [[String: Any]])
        #expect(query.last?["value"] as? String == "a b")

        let example = try #require((item["response"] as? [[String: Any]])?.first)
        #expect(example["code"] as? Int == 201)
        #expect(example["body"] as? String == #"{"id":1}"#)
        #expect(!PostmanCollectionExporter.isEligible(tunnel))
    }

    @Test("A binary request body is described instead of written as corrupt text")
    func binaryBody() throws {
        let upload = TestFixtures.makeTransaction(method: "PUT", url: "https://api.example.com/blob")
        upload.request.body = Data([0xFF, 0xFE, 0x00, 0x81])
        let data = try PostmanCollectionExporter.export(transactions: [upload])
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let item = try #require(((root["item"] as? [[String: Any]])?.first?["item"] as? [[String: Any]])?.first)
        let request = try #require(item["request"] as? [String: Any])
        #expect(request["body"] == nil)
        #expect((request["description"] as? String)?.contains("4 bytes") == true)
    }
}
