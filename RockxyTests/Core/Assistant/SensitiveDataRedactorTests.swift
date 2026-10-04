import Foundation
@testable import Rockxy
import Testing

// Direct coverage for `SensitiveDataRedactor`, the shared vocabulary that scrubs
// captured traffic before it leaves Rockxy. These tests exercise the real public
// methods (no copied regexes) and assert both that secrets disappear and that
// ordinary, non-sensitive data survives untouched.

struct SensitiveDataRedactorTests {
    // MARK: Internal

    // MARK: - JSON body

    @Test("Echoed Authorization and API-key headers, URL tokens, and Bearer values in JSON are redacted")
    func echoedCredentialsInJSONAreRedacted() {
        let redactor = SensitiveDataRedactor()
        let source = """
        {"url":"https://api.example.com/v1?access_token=qs-secret&page=2","headers":{"authorization":"Basic dXNlcjpwYXNz",\
        "x-api-key":"key-abc"},"csrfToken":"csrf-1","session_count":3,"usage":{"prompt_tokens":7}}
        """

        let redacted = redactor.redactBodyText(source, contentType: .json)

        for secret in ["qs-secret", "dXNlcjpwYXNz", "key-abc", "csrf-1"] {
            #expect(!redacted.contains(secret), "\(secret) leaked: \(redacted)")
        }
        #expect(redacted.contains("page=2"))
        #expect(redacted.contains("\"session_count\":3"))
        #expect(redacted.contains("\"prompt_tokens\":7"))
    }

    @Test("Nested JSON redacts the AI payload vocabulary while keeping ordinary fields")
    func nestedJSONRedactsAIVocabulary() throws {
        let redactor = SensitiveDataRedactor()
        let source = """
        {
          "model": "gpt-5",
          "temperature": 0.5,
          "messages": [{"role": "user", "content": "my SSN is 123-45-6789"}],
          "input": "user secret input text",
          "instructions": "hidden system prompt copy",
          "tools": [{"type": "function", "function": {"name": "lookup", "key": "tool-secret"}}],
          "embeddings": [0.11, 0.22, 0.33],
          "metadata": {"trace_id": "abc-123", "details": {"region": "us-east-1"}}
        }
        """

        let redactedText = redactor.redactBodyText(source, contentType: .json)
        let object = try decodeJSON(redactedText)

        for key in ["messages", "input", "instructions", "tools", "embeddings"] {
            #expect(object[key] as? String == "[REDACTED]", "\(key) should collapse to the placeholder")
        }

        #expect(object["model"] as? String == "gpt-5")
        #expect(object["temperature"] as? Double == 0.5)
        let metadata = try #require(object["metadata"] as? [String: Any])
        #expect(metadata["trace_id"] as? String == "abc-123")
        let details = try #require(metadata["details"] as? [String: Any])
        #expect(details["region"] as? String == "us-east-1")

        for secret in [
            "123-45-6789",
            "user secret input text",
            "hidden system prompt copy",
            "tool-secret",
            "0.22",
        ] {
            #expect(!redactedText.contains(secret), "\(secret) must not survive redaction")
        }
    }

    // MARK: - Form body

    @Test("Transaction redaction decodes a compressed response so secrets inside it are redacted")
    func transactionRedactionDecodesCompressedResponse() throws {
        let redactor = SensitiveDataRedactor()
        let plain = Data(#"{"user":"stephen","access_token":"secret-token"}"#.utf8)
        let compressed = try (plain as NSData).compressed(using: .zlib) as Data
        let transaction = TestFixtures.makeTransaction(statusCode: 200)
        transaction.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Content-Encoding", value: "deflate"),
                HTTPHeader(name: "Content-Length", value: "\(compressed.count)"),
            ],
            body: compressed,
            contentType: .json
        )

        let redacted = try #require(redactor.redactTransaction(transaction).response)
        let body = try #require(redacted.body.flatMap { String(data: $0, encoding: .utf8) })

        // Without decoding, the compressed bytes would have carried the secret through unredacted.
        #expect(body.contains("stephen"))
        #expect(!body.contains("secret-token"))
        #expect(!redacted.headers.contains { $0.name.lowercased() == "content-encoding" })
        #expect(!redacted.headers.contains { $0.name.lowercased() == "content-length" })
        #expect(redacted.headers.contains { $0.name == "Content-Type" })
    }

    @Test("Transaction redaction decodes compressed requests before export")
    func transactionRedactionDecodesCompressedRequest() throws {
        let plain = Data(#"{"access_token":"synthetic-secret","user":"stephen"}"#.utf8)
        let compressed = try (plain as NSData).compressed(using: .zlib) as Data
        let transaction = TestFixtures.makeTransaction(statusCode: 200)
        transaction.request.body = compressed
        transaction.request.headers.append(HTTPHeader(name: "Content-Encoding", value: "deflate"))
        transaction.request.headers.append(HTTPHeader(name: "Content-Length", value: "\(compressed.count)"))

        let redacted = SensitiveDataRedactor().redactTransaction(transaction).request
        let body = try #require(redacted.body.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("stephen"))
        #expect(!body.contains("synthetic-secret"))
        #expect(!redacted.headers.contains { ["content-encoding", "content-length"].contains($0.name.lowercased()) })
    }

    @Test("Undecodable encoded response body is omitted from redacted exports")
    func undecodableEncodedResponseIsOmitted() throws {
        let transaction = TestFixtures.makeTransaction(statusCode: 200)
        let encoded = Data(#"{"access_token":"synthetic-secret"}"#.utf8)
        transaction.response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Content-Encoding", value: "deflate"),
                HTTPHeader(name: "Content-Length", value: "\(encoded.count)"),
            ],
            body: encoded,
            contentType: .json
        )

        let redacted = try #require(SensitiveDataRedactor().redactTransaction(transaction).response)
        #expect(redacted.body == nil)
        #expect(redacted.bodyTruncated)
        #expect(!redacted.headers.contains { ["content-encoding", "content-length"].contains($0.name.lowercased()) })
        #expect(SensitiveDataRedactor(isEnabled: false).redactTransaction(transaction).response?.body == encoded)

        transaction.response?.body = Data(repeating: 0x41, count: SensitiveDataRedactor.maxDecodableBodyBytes + 1)
        let oversized = try #require(SensitiveDataRedactor().redactTransaction(transaction).response)
        #expect(oversized.body == nil)

        transaction.request.body = encoded
        transaction.request.headers.append(HTTPHeader(name: "Content-Encoding", value: "deflate"))
        let redactedRequest = SensitiveDataRedactor().redactTransaction(transaction).request
        #expect(redactedRequest.body == nil)
        #expect(!redactedRequest.headers.contains { $0.name.lowercased() == "content-encoding" })
    }

    @Test("Form body redacts a sensitive key and keeps an ordinary field")
    func formBodyRedaction() {
        let redactor = SensitiveDataRedactor()
        let redacted = redactor.redactBodyText(
            "username=alice&access_token=super-secret-value&scope=read",
            contentType: .form
        )

        #expect(redacted.contains("username=alice"))
        #expect(redacted.contains("scope=read"))
        #expect(redacted.contains("access_token=[REDACTED]"))
        #expect(!redacted.contains("super-secret-value"))
    }

    // MARK: - XML body

    @Test("XML body redacts a sensitive element and keeps an ordinary element")
    func xmlBodyRedaction() {
        let redactor = SensitiveDataRedactor()
        let redacted = redactor.redactBodyText(
            "<config><password>hunter2</password><host>example.com</host></config>",
            contentType: .xml
        )

        #expect(redacted.contains("<password>[REDACTED]</password>"))
        #expect(redacted.contains("<host>example.com</host>"))
        #expect(!redacted.contains("hunter2"))
    }

    // MARK: - URL

    @Test("URL drops userinfo and sensitive query while keeping safe host, path, and query")
    func urlRedaction() throws {
        let redactor = SensitiveDataRedactor()
        let url = try #require(URL(
            string: "https://user:pass@api.example.com/v1/models?api_key=secret123&model=gpt-5"
        ))

        let redacted = redactor.redactURL(url)
        let components = try #require(URLComponents(url: redacted, resolvingAgainstBaseURL: false))

        #expect(components.user == nil)
        #expect(components.password == nil)
        #expect(components.host == "api.example.com")
        #expect(components.path == "/v1/models")

        let queryItems = try #require(components.queryItems)
        #expect(queryItems.first { $0.name == "api_key" }?.value == "[REDACTED]")
        #expect(queryItems.first { $0.name == "model" }?.value == "gpt-5")
    }

    // MARK: - Headers

    @Test("Headers redact provider credentials while keeping safe metadata")
    func headerRedaction() {
        let redactor = SensitiveDataRedactor()
        let redacted = redactor.redactHeaders([
            HTTPHeader(name: "Authorization", value: "Bearer sk-live-secret"),
            HTTPHeader(name: "X-Api-Key", value: "provider-key-123"),
            HTTPHeader(name: "x-goog-api-key", value: "google-secret"),
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "User-Agent", value: "Rockxy/1.0"),
        ])

        func value(_ name: String) -> String? {
            redacted.first { $0.name == name }?.value
        }

        #expect(value("Authorization") == "[REDACTED]")
        #expect(value("X-Api-Key") == "[REDACTED]")
        #expect(value("x-goog-api-key") == "[REDACTED]")
        #expect(value("Content-Type") == "application/json")
        #expect(value("User-Agent") == "Rockxy/1.0")
    }

    // MARK: - Opt-out

    @Test("Disabled redactor passes body, URL, and headers through untouched")
    func disabledRedactionPassthrough() throws {
        let redactor = SensitiveDataRedactor(isEnabled: false)
        let body = #"{"messages":[{"content":"still visible"}],"access_token":"still-secret"}"#

        #expect(redactor.redactBodyText(body, contentType: .json) == body)

        let url = try #require(URL(string: "https://user:pass@api.example.com/v1?api_key=secret"))
        #expect(redactor.redactURL(url) == url)

        let headers = [HTTPHeader(name: "Authorization", value: "Bearer sk-secret")]
        #expect(redactor.redactHeaders(headers) == headers)
    }

    // MARK: Private

    // MARK: - Helpers

    private func decodeJSON(_ text: String) throws -> [String: Any] {
        let data = try #require(text.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
