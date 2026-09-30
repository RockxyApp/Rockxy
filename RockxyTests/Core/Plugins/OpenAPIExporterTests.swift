import Foundation
@testable import Rockxy
import Testing

// MARK: - OpenAPIExporterTests

struct OpenAPIExporterTests {
    @Test("Exports valid OpenAPI 3.0.3 root structure")
    func exportsRootStructure() throws {
        let transaction = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/v1/users/42",
            responseBody: ["id": 42, "name": "Ada"]
        )

        let result = try OpenAPIExporter().export(
            transactions: [transaction],
            options: OpenAPIExportOptions(format: .json)
        )

        #expect(result.exportedTransactionCount == 1)
        #expect(result.skippedTransactionCount == 0)
        #expect(result.document["openapi"] as? String == "3.0.3")
        #expect(result.document["info"] is [String: Any])
        #expect(result.document["paths"] is [String: Any])
    }

    @Test("YAML output is deterministic and quotes response status codes")
    func yamlOutputQuotesStatusCodes() throws {
        let transaction = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/v1/users/42",
            responseBody: ["id": 42]
        )

        let first = try OpenAPIExporter().export(
            transactions: [transaction],
            options: OpenAPIExportOptions(format: .yaml)
        ).data
        let second = try OpenAPIExporter().export(
            transactions: [transaction],
            options: OpenAPIExportOptions(format: .yaml)
        ).data
        let yaml = try #require(String(data: first, encoding: .utf8))

        #expect(first == second)
        #expect(yaml.contains(#""200":"#))
        #expect(yaml.contains(#""openapi": "3.0.3""#))
    }

    @Test("Path parameter names keep singular words and skip version segments")
    func pathParameterNaming() throws {
        let status = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/status/5",
            responseBody: ["ok": true]
        )
        let versioned = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/v1/123",
            responseBody: ["ok": true]
        )

        let paths = try paths(from: [status, versioned])

        #expect(paths["/status/{statusId}"] is [String: Any])
        #expect(paths["/v1/{id}"] is [String: Any])
    }

    @Test("Infers path parameters while preserving static slugs")
    func pathParameterInference() throws {
        let users = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/users/42",
            responseBody: ["id": 42]
        )
        let me = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/users/me",
            responseBody: ["id": "me"]
        )

        let paths = try paths(from: [users, me])
        let userPath = try #require(paths["/users/{userId}"] as? [String: Any])
        let operation = try #require(userPath["get"] as? [String: Any])
        let parameters = try #require(operation["parameters"] as? [[String: Any]])

        #expect(paths["/users/me"] is [String: Any])
        #expect(parameters.contains { $0["name"] as? String == "userId" && $0["in"] as? String == "path" })
    }

    @Test("Infers query parameters and repeated query arrays")
    func queryParameters() throws {
        let transaction = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/search?q=swift&page=2&tag=mac&tag=proxy&token=secret",
            responseBody: ["ok": true]
        )

        let operation = try operation(from: [transaction], path: "/search", method: "get")
        let parameters = try #require(operation["parameters"] as? [[String: Any]])
        let names = parameters.compactMap { $0["name"] as? String }
        let tag = try #require(parameters.first { $0["name"] as? String == "tag" })
        let schema = try #require(tag["schema"] as? [String: Any])

        #expect(names.contains("q"))
        #expect(names.contains("page"))
        #expect(names.contains("token"))
        #expect(schema["type"] as? String == "array")
        // The credential parameter is documented by name only; its captured value never appears.
        let serialized = String(data: try JSONSerialization.data(withJSONObject: operation), encoding: .utf8) ?? ""
        #expect(!serialized.contains("secret"))
    }

    @Test("Merges JSON schemas and intersects required keys")
    func mergesJSONSchemas() throws {
        let first = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/users/1",
            responseBody: ["id": 1, "name": "Ada"]
        )
        let second = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/users/2",
            responseBody: ["id": 2, "email": "ada@example.com"]
        )

        let operation = try operation(from: [first, second], path: "/users/{userId}", method: "get")
        let schema = try responseSchema(operation: operation, status: "200")
        let properties = try #require(schema["properties"] as? [String: Any])
        let required = schema["required"] as? [String] ?? []

        #expect(properties["id"] is [String: Any])
        #expect(properties["name"] is [String: Any])
        #expect(properties["email"] is [String: Any])
        #expect(required == ["id"])
    }

    @Test("Emits multiple response status codes")
    func multipleResponseStatuses() throws {
        let ok = jsonTransaction(
            method: "POST",
            url: "https://api.example.com/users",
            statusCode: 201,
            responseBody: ["id": 1]
        )
        let bad = jsonTransaction(
            method: "POST",
            url: "https://api.example.com/users",
            statusCode: 400,
            responseBody: ["error": "invalid"]
        )

        let operation = try operation(from: [ok, bad], path: "/users", method: "post")
        let responses = try #require(operation["responses"] as? [String: Any])

        #expect(responses["201"] is [String: Any])
        #expect(responses["400"] is [String: Any])
    }

    @Test("Handles missing responses with default response")
    func missingResponseDefault() throws {
        let request = TestFixtures.makeRequest(method: "GET", url: "https://api.example.com/pending")
        let transaction = HTTPTransaction(request: request, state: .pending)

        let operation = try operation(from: [transaction], path: "/pending", method: "get")
        let responses = try #require(operation["responses"] as? [String: Any])
        let defaultResponse = try #require(responses["default"] as? [String: Any])

        #expect(defaultResponse["description"] as? String == "No response captured")
    }

    @Test("Uses binary schema for binary responses and skips truncated body inference")
    func binaryAndTruncatedBodies() throws {
        let binary = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/image.png")
        binary.response = TestFixtures.makeResponse(
            statusCode: 200,
            headers: [HTTPHeader(name: "Content-Type", value: "image/png")],
            body: Data([0x89, 0x50, 0x4E, 0x47])
        )
        binary.response?.contentType = .image

        let truncated = jsonTransaction(
            method: "GET",
            url: "https://api.example.com/truncated",
            responseBody: ["partial": true]
        )
        truncated.response?.bodyTruncated = true

        let binarySchema = try responseSchema(
            operation: operation(from: [binary], path: "/image.png", method: "get"),
            status: "200",
            mediaType: "image/png"
        )
        let truncatedOperation = try operation(from: [truncated], path: "/truncated", method: "get")
        let truncatedResponse = try #require((truncatedOperation["responses"] as? [String: Any])?["200"] as? [String: Any])

        #expect(binarySchema["format"] as? String == "binary")
        #expect(truncatedResponse["content"] == nil)
    }

    @Test("Skips WebSocket transactions")
    func skipsWebSocketTransactions() throws {
        let websocket = TestFixtures.makeWebSocketTransaction()
        let http = jsonTransaction(method: "GET", url: "https://api.example.com/users", responseBody: ["ok": true])

        let result = try OpenAPIExporter().export(
            transactions: [websocket, http],
            options: OpenAPIExportOptions(format: .json)
        )

        #expect(result.exportedTransactionCount == 1)
        #expect(result.skippedTransactionCount == 1)
    }

    @Test("Omits sensitive query and body fields and detects bearer auth")
    func redactsSensitiveFields() throws {
        let body: [String: Any] = [
            "username": "ada",
            "password": "secret",
            "profile": ["token": "nested", "displayName": "Ada"]
        ]
        let transaction = jsonTransaction(
            method: "POST",
            url: "https://api.example.com/login?api_key=secret&mode=json",
            requestBody: body,
            responseBody: ["access_token": "secret", "ok": true],
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "Authorization", value: "Bearer secret-token")
            ]
        )

        let result = try OpenAPIExporter().export(
            transactions: [transaction],
            options: OpenAPIExportOptions(format: .json)
        )
        let serialized = try #require(String(data: result.data, encoding: .utf8))
        let operation = try self.operation(from: [transaction], path: "/login", method: "post")
        let parameters = try #require(operation["parameters"] as? [[String: Any]])

        #expect(!serialized.contains("secret-token"))
        // Credential fields stay in the documented contract; only their values are dropped.
        #expect(serialized.contains("password"))
        #expect(parameters.contains { $0["name"] as? String == "api_key" })
        #expect(serialized.contains("bearerAuth"))
    }

    @Test("HTML output is offline and disables validator and submit methods")
    func htmlOutputOfflineSettings() throws {
        let transaction = jsonTransaction(method: "GET", url: "https://api.example.com/users", responseBody: ["ok": true])

        let result = try OpenAPIExporter().export(
            transactions: [transaction],
            options: OpenAPIExportOptions(format: .html)
        )
        let html = try #require(String(data: result.data, encoding: .utf8))

        #expect(html.contains("SwaggerUIBundle"))
        #expect(html.contains("validatorUrl: null"))
        #expect(html.contains("supportedSubmitMethods: []"))
        #expect(!html.contains("unpkg.com"))
        #expect(!html.contains("petstore"))
    }

    @Test("PluginManager registers OpenAPI exporter")
    func pluginManagerRegistersOpenAPIExporter() {
        let manager = PluginManager()
        manager.loadPlugins()

        let exporter = manager.allExporters().first { $0.name == "OpenAPI Exporter" }

        #expect(exporter != nil)
        #expect(exporter?.fileExtension == "yaml")
    }

    // MARK: Private

    private func paths(from transactions: [HTTPTransaction]) throws -> [String: Any] {
        let result = try OpenAPIExporter().export(
            transactions: transactions,
            options: OpenAPIExportOptions(format: .json)
        )
        return try #require(result.document["paths"] as? [String: Any])
    }

    private func operation(
        from transactions: [HTTPTransaction],
        path: String,
        method: String
    ) throws -> [String: Any] {
        let paths = try paths(from: transactions)
        let pathItem = try #require(paths[path] as? [String: Any])
        return try #require(pathItem[method] as? [String: Any])
    }

    private func responseSchema(
        operation: [String: Any],
        status: String,
        mediaType: String = "application/json"
    ) throws -> [String: Any] {
        let responses = try #require(operation["responses"] as? [String: Any])
        let response = try #require(responses[status] as? [String: Any])
        let content = try #require(response["content"] as? [String: Any])
        let media = try #require(content[mediaType] as? [String: Any])
        return try #require(media["schema"] as? [String: Any])
    }

    private func jsonTransaction(
        method: String,
        url: String,
        statusCode: Int = 200,
        requestBody: [String: Any]? = nil,
        responseBody: [String: Any],
        headers: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")]
    ) -> HTTPTransaction {
        let requestData = requestBody.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        let request = HTTPRequestData(
            method: method,
            url: URL(string: url) ?? URL(fileURLWithPath: "/"),
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: requestData,
            contentType: requestBody == nil ? nil : .json
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        let responseData = try? JSONSerialization.data(withJSONObject: responseBody)
        transaction.response = HTTPResponseData(
            statusCode: statusCode,
            statusMessage: statusCode < 400 ? "OK" : "Error",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: responseData,
            contentType: .json
        )
        return transaction
    }
}
