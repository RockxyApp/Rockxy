import Foundation
@testable import Rockxy
import Testing

// Guards the cheap tests `GraphQLDetector.detect` runs before it parses a request body. They
// exist to keep ordinary REST traffic from being expanded into an object graph on a NIO event
// loop, so what matters here is that they admit everything the parse would have accepted.

// MARK: - GraphQLDetectorGateTests

struct GraphQLDetectorGateTests {
    // MARK: Internal

    @Test("A GraphQL document on a path without graphql is still detected")
    func documentOnNonGraphQLPathStillDetected() throws {
        for document in [
            "query GetUser($id: ID!) { user(id: $id) { name } }",
            "mutation { createUser(name: \"a\") { id } }",
            "subscription OnPost { id }",
            "{ me { id } }",
        ] {
            let request = try Self.postRequest(path: "/api/v1/rpc", body: ["query": document])
            let info = try #require(
                GraphQLDetector.detect(request: request),
                "cheap pre-test rejected a GraphQL body on a non-graphql path: \(document)"
            )
            #expect(info.query == document)
        }
    }

    @Test("Whitespace before the JSON object does not hide the document")
    func leadingWhitespaceStillDetected() throws {
        let body = Data("\n\t  {\"query\": \"{ me { id } }\"}".utf8)
        let request = try Self.postRequest(path: "/api", rawBody: body)

        #expect(GraphQLDetector.detect(request: request)?.query == "{ me { id } }")
    }

    @Test("A mixed-case graphql path is matched without lowercasing the path")
    func mixedCasePathStillMatches() throws {
        let request = try Self.postRequest(path: "/API/GraphQL", body: ["query": "running shoes"])

        // The path decides on its own; the body does not have to look like a document.
        #expect(GraphQLDetector.detect(request: request) != nil)
    }

    @Test("A non-GraphQL JSON POST is not reported as an operation")
    func restPayloadIsNotAnOperation() throws {
        let bodies: [[String: Any]] = [
            ["search": "query the database"],
            ["name": "Ada", "age": 36],
            ["variables": ["id": 1]],
        ]
        for body in bodies {
            let request = try Self.postRequest(path: "/api/v1/users", body: body)
            #expect(GraphQLDetector.detect(request: request) == nil)
        }
    }

    @Test("The method decides before the body: only POST and GET can carry an operation")
    func onlyPostAndGetAreInspected() throws {
        let body = try JSONSerialization.data(withJSONObject: ["query": "{ me { id } }"])
        for method in ["HEAD", "OPTIONS", "PUT", "PATCH", "DELETE"] {
            let request = try Self.request(method: method, path: "/graphql", rawBody: body)
            #expect(GraphQLDetector.detect(request: request) == nil)
        }
    }

    @Test("A batched array body stays with the generic inspectors")
    func batchedArrayBodyIsNotASingleOperation() throws {
        let body = try JSONSerialization.data(withJSONObject: [["query": "{ me { id } }"]])
        let request = try Self.postRequest(path: "/graphql", rawBody: body)

        #expect(GraphQLDetector.detect(request: request) == nil)
    }

    @Test("A body in an encoding JSONSerialization accepts is still detected")
    func nonUTF8BodyMatchesTheParser() throws {
        // `JSONSerialization` sniffs UTF-16/32 as well, and those bytes carry no literal
        // `"query"` key: detection must follow whatever the parser itself can read.
        let document = "{\"query\": \"{ me { id } }\"}"
        for encoding: String.Encoding in [.utf16, .utf16BigEndian, .utf32LittleEndian] {
            let body = try #require(document.data(using: encoding))
            let request = try Self.postRequest(path: "/api", rawBody: body)
            let parsed = (try? JSONSerialization.jsonObject(with: body)).flatMap { $0 as? [String: Any] }

            #expect(
                (GraphQLDetector.detect(request: request) != nil) == (parsed != nil),
                "detection diverged from the parser for \(encoding)"
            )
        }
    }

    @Test("An automatic persisted query on a graphql path keeps its operation name")
    func persistedQueryStillDetected() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "operationName": "GetUser",
            "extensions": ["persistedQuery": ["version": 1, "sha256Hash": "abc"]],
        ])
        let request = try Self.postRequest(path: "/graphql", rawBody: body)

        #expect(GraphQLDetector.detect(request: request)?.operationName == "GetUser")
    }

    // MARK: Private

    private static func postRequest(path: String, body: [String: Any]) throws -> HTTPRequestData {
        try postRequest(path: path, rawBody: JSONSerialization.data(withJSONObject: body))
    }

    private static func postRequest(path: String, rawBody: Data) throws -> HTTPRequestData {
        try request(method: "POST", path: path, rawBody: rawBody)
    }

    private static func request(method: String, path: String, rawBody: Data) throws -> HTTPRequestData {
        try HTTPRequestData(
            method: method,
            url: #require(URL(string: "https://api.example.com\(path)")),
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: rawBody
        )
    }
}
