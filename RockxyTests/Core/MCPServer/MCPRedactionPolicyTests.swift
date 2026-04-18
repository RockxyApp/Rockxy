import Foundation
@testable import Rockxy
import Testing

// MARK: - MCPRedactionPolicyTests

@Suite("MCP Redaction Policy")
struct MCPRedactionPolicyTests {
    let enabledPolicy = MCPRedactionPolicy(isEnabled: true)
    let disabledPolicy = MCPRedactionPolicy(isEnabled: false)

    // MARK: - Header Redaction

    @Test("Redacts authorization header when enabled")
    func redactAuthHeader() {
        let headers: [(name: String, value: String)] = [
            (name: "Authorization", value: "Bearer super-secret-token"),
            (name: "Accept", value: "application/json"),
        ]

        let redacted = enabledPolicy.redactHeaders(headers)

        #expect(redacted[0].value == "[REDACTED]")
        #expect(redacted[1].value == "application/json")
    }

    @Test("Passes through non-sensitive headers")
    func passThroughNonSensitive() {
        let headers: [(name: String, value: String)] = [
            (name: "Content-Type", value: "application/json"),
            (name: "Accept", value: "*/*"),
            (name: "User-Agent", value: "TestAgent/1.0"),
        ]

        let redacted = enabledPolicy.redactHeaders(headers)

        #expect(redacted[0].value == "application/json")
        #expect(redacted[1].value == "*/*")
        #expect(redacted[2].value == "TestAgent/1.0")
    }

    @Test("Disabled policy passes all headers through")
    func disabledPassesThrough() {
        let headers: [(name: String, value: String)] = [
            (name: "Authorization", value: "Bearer my-token"),
            (name: "Cookie", value: "session=abc123"),
            (name: "X-Api-Key", value: "key-456"),
        ]

        let redacted = disabledPolicy.redactHeaders(headers)

        #expect(redacted[0].value == "Bearer my-token")
        #expect(redacted[1].value == "session=abc123")
        #expect(redacted[2].value == "key-456")
    }

    @Test("Case-insensitive header matching")
    func caseInsensitive() {
        let headers: [(name: String, value: String)] = [
            (name: "AUTHORIZATION", value: "Bearer token1"),
            (name: "cookie", value: "session=xyz"),
            (name: "X-API-KEY", value: "secret-key"),
            (name: "x-csrf-token", value: "csrf-value"),
        ]

        let redacted = enabledPolicy.redactHeaders(headers)

        for header in redacted {
            #expect(header.value == "[REDACTED]")
        }
    }

    // MARK: - URL Redaction

    @Test("Redacts sensitive URL query parameters")
    func redactURLParams() {
        let url = "https://api.example.com/data?api_key=secret123&format=json&token=mytoken"

        let redacted = enabledPolicy.redactURL(url)

        #expect(redacted.contains("%5BREDACTED%5D") || redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("secret123"))
        #expect(!redacted.contains("mytoken"))
        #expect(redacted.contains("format=json"))
    }

    @Test("Preserves non-sensitive URL query parameters")
    func preserveNonSensitiveParams() {
        let url = "https://api.example.com/search?q=swift&page=1&limit=20"

        let redacted = enabledPolicy.redactURL(url)

        #expect(redacted.contains("q=swift"))
        #expect(redacted.contains("page=1"))
        #expect(redacted.contains("limit=20"))
        #expect(!redacted.contains("[REDACTED]"))
    }

    @Test("Preserves URL encoding while redacting sensitive params")
    func preserveURLEncoding() {
        let url = "https://api.example.com/search?redirect=https%3A%2F%2Fexample.com%2Fa%20b&token=abc123"

        let redacted = enabledPolicy.redactURL(url)

        #expect(redacted.contains("redirect=https://example.com/a%20b") || redacted
            .contains("redirect=https%3A%2F%2Fexample.com%2Fa%20b"))
        #expect(redacted.contains("token=%5BREDACTED%5D") || redacted.contains("token=[REDACTED]"))
        #expect(!redacted.contains("abc123"))
    }

    @Test("URL without query params unchanged")
    func urlWithoutParamsUnchanged() {
        let url = "https://api.example.com/users/42"

        let redacted = enabledPolicy.redactURL(url)

        #expect(redacted == url)
    }

    @Test("Disabled policy preserves URL intact")
    func disabledURLPassthrough() {
        let url = "https://api.example.com/data?api_key=secret123&token=mytoken"

        let redacted = disabledPolicy.redactURL(url)

        #expect(redacted == url)
    }

    // MARK: - JSON Body Redaction

    @Test("Redacts JSON body token fields")
    func redactJSONTokens() {
        let body = #"{"access_token": "secret123", "name": "test"}"#

        let redacted = enabledPolicy.redactJSONBody(body)

        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("secret123"))
        #expect(redacted.contains("test"))
    }

    @Test("Redacts JSON body password fields")
    func redactJSONPassword() {
        let body = #"{"username": "admin", "password": "p@ss1234"}"#

        let redacted = enabledPolicy.redactJSONBody(body)

        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("p@ss1234"))
        #expect(redacted.contains("admin"))
    }

    @Test("Redacts JSON values with escaped quotes and keeps valid JSON")
    func redactJSONEscapedQuoteValue() throws {
        let body = #"{"username":"admin","password":"p\"w\"secret"}"#

        let redacted = enabledPolicy.redactJSONBody(body)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(redacted.utf8)) as? [String: Any])

        #expect(object["username"] as? String == "admin")
        #expect(object["password"] as? String == "[REDACTED]")
        #expect(!redacted.contains(#"p\"w\"secret"#))
    }

    @Test("Redacts multiple sensitive JSON fields")
    func redactMultipleJSONFields() {
        let body = #"{"api_key": "key1", "client_secret": "sec2", "data": "public"}"#

        let redacted = enabledPolicy.redactJSONBody(body)

        #expect(!redacted.contains("key1"))
        #expect(!redacted.contains("sec2"))
        #expect(redacted.contains("public"))
    }

    @Test("Leaves generic key fields intact in JSON bodies")
    func preserveGenericJSONKeyField() {
        let body = #"{"items":[{"key":"foo","value":"bar"}]}"#

        let redacted = enabledPolicy.redactJSONBody(body)

        #expect(redacted == body)
    }

    @Test("Disabled policy doesn't redact JSON body")
    func disabledJSONBody() {
        let body = #"{"access_token": "secret123", "password": "hunter2"}"#

        let redacted = disabledPolicy.redactJSONBody(body)

        #expect(redacted == body)
    }

    // MARK: - cURL Redaction

    @Test("Redacts cURL sensitive headers")
    func redactCurlHeaders() {
        let curl = """
        curl 'https://api.example.com/data' \
        -H 'Authorization: Bearer secret-token' \
        -H 'Content-Type: application/json' \
        -H 'Cookie: session=abc123'
        """

        let redacted = enabledPolicy.redactCurlCommand(curl)

        #expect(!redacted.contains("secret-token"))
        #expect(!redacted.contains("session=abc123"))
        #expect(redacted.contains("application/json"))
        #expect(redacted.contains("-H '"))
        #expect(redacted.contains("Authorization: [REDACTED]"))
    }

    @Test("Disabled policy doesn't redact cURL")
    func disabledCurlPassthrough() {
        let curl = "curl 'https://api.example.com' -H 'Authorization: Bearer token'"

        let redacted = disabledPolicy.redactCurlCommand(curl)

        #expect(redacted == curl)
    }

    // MARK: - CodableHeader Redaction

    @Test("Redacts CodableHeader array")
    func redactCodableHeaders() {
        let headers = [
            CodableHeader(from: HTTPHeader(name: "Authorization", value: "Bearer abc")),
            CodableHeader(from: HTTPHeader(name: "Content-Type", value: "application/json")),
            CodableHeader(from: HTTPHeader(name: "X-Api-Key", value: "my-key")),
        ]

        let redacted = enabledPolicy.redactCodableHeaders(headers)

        #expect(redacted[0].value == "[REDACTED]")
        #expect(redacted[1].value == "application/json")
        #expect(redacted[2].value == "[REDACTED]")
    }

    @Test("Disabled policy preserves CodableHeader values")
    func disabledCodableHeaders() {
        let headers = [
            CodableHeader(from: HTTPHeader(name: "Authorization", value: "Bearer abc")),
            CodableHeader(from: HTTPHeader(name: "Cookie", value: "session=xyz")),
        ]

        let redacted = disabledPolicy.redactCodableHeaders(headers)

        #expect(redacted[0].value == "Bearer abc")
        #expect(redacted[1].value == "session=xyz")
    }

    // MARK: - Sensitive Sets

    @Test("Sensitive headers set contains expected entries")
    func sensitiveHeadersSet() {
        let expected: Set = [
            "authorization",
            "proxy-authorization",
            "cookie",
            "set-cookie",
            "x-api-key",
            "x-auth-token",
            "x-csrf-token",
        ]
        for header in expected {
            #expect(MCPRedactionPolicy.sensitiveHeaders.contains(header))
        }
    }

    @Test("Sensitive query params set contains expected entries")
    func sensitiveQueryParamsSet() {
        let expected: Set = [
            "api_key",
            "token",
            "access_token",
            "password",
            "secret",
            "client_secret",
        ]
        for param in expected {
            #expect(MCPRedactionPolicy.sensitiveQueryParams.contains(param))
        }
    }

    // MARK: - Body Format Redaction

    @Test("Redacts form-encoded body sensitive fields")
    func redactFormBody() {
        let policy = MCPRedactionPolicy(isEnabled: true)
        let body = "username=john&password=secret123&token=abc&format=json"
        let redacted = policy.redactFormBody(body)
        #expect(!redacted.contains("secret123"))
        #expect(!redacted.contains("abc"))
        #expect(redacted.contains("username=john"))
        #expect(redacted.contains("format=json"))
    }

    @Test("Redacts percent-encoded form keys")
    func redactPercentEncodedFormKey() {
        let policy = MCPRedactionPolicy(isEnabled: true)
        let body = "client%5Fsecret=topsecret&mode=test"
        let redacted = policy.redactFormBody(body)
        #expect(!redacted.contains("topsecret"))
        #expect(redacted.contains("client%5Fsecret=[REDACTED]"))
        #expect(redacted.contains("mode=test"))
    }

    @Test("Redacts XML body sensitive elements")
    func redactXMLBody() {
        let policy = MCPRedactionPolicy(isEnabled: true)
        let body = "<auth><password>secret</password><user>john</user></auth>"
        let redacted = policy.redactXMLBody(body)
        #expect(!redacted.contains(">secret<"))
        #expect(redacted.contains("[REDACTED]"))
        #expect(redacted.contains("<user>john</user>"))
    }

    @Test("Redacts generic text Bearer tokens")
    func redactGenericBearerToken() {
        let policy = MCPRedactionPolicy(isEnabled: true)
        let text = "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature"
        let redacted = policy.redactGenericText(text)
        #expect(!redacted.contains("eyJhbGci"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Content-type dispatch routes correctly")
    func bodyRedactionDispatch() {
        let policy = MCPRedactionPolicy(isEnabled: true)
        let json = #"{"password": "secret"}"#
        let form = "password=secret"
        let xml = "<password>secret</password>"

        #expect(!policy.redactBody(json, contentType: .json).contains("secret"))
        #expect(!policy.redactBody(form, contentType: .form).contains("secret"))
        #expect(!policy.redactBody(xml, contentType: .xml).contains("secret"))
    }

    // MARK: - Live Toggle

    @Test("MCPRedactionState updates propagate to policy")
    func redactionStateToggle() {
        let state = MCPRedactionState(isEnabled: true)
        let policy = MCPRedactionPolicy(state: state)

        let headers: [(name: String, value: String)] = [
            (name: "Authorization", value: "Bearer token123"),
        ]
        let redacted1 = policy.redactHeaders(headers)
        #expect(redacted1[0].value == "[REDACTED]")

        state.update(isEnabled: false)
        let redacted2 = policy.redactHeaders(headers)
        #expect(redacted2[0].value == "Bearer token123")

        state.update(isEnabled: true)
        let redacted3 = policy.redactHeaders(headers)
        #expect(redacted3[0].value == "[REDACTED]")
    }
}
