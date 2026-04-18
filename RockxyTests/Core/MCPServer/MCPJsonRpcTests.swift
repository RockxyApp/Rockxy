import Foundation
@testable import Rockxy
import Testing

// MARK: - MCPJsonRpcTests

@Suite("MCP JSON-RPC 2.0")
struct MCPJsonRpcTests {
    // MARK: - MCPJSONValue

    @Test("MCPJSONValue encodes null")
    func encodeNull() throws {
        let value: MCPJSONValue = .null
        let data = try value.encodeToData()
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json == "null")
    }

    @Test("MCPJSONValue round-trips complex nested object")
    func roundTripComplex() throws {
        let original: MCPJSONValue = .object([
            "name": .string("Rockxy"),
            "version": .int(1),
            "beta": .bool(false),
            "score": .double(9.5),
            "tags": .array([.string("proxy"), .string("debug")]),
            "metadata": .object([
                "nested": .null,
            ]),
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MCPJSONValue.self, from: data)
        #expect(decoded == original)
    }

    @Test("MCPJSONValue ExpressibleByLiteral conformances")
    func literals() {
        let nilVal: MCPJSONValue = nil
        #expect(nilVal == .null)

        let boolVal: MCPJSONValue = true
        #expect(boolVal == .bool(true))

        let intVal: MCPJSONValue = 42
        #expect(intVal == .int(42))

        let doubleVal: MCPJSONValue = 3.14
        #expect(doubleVal == .double(3.14))

        let stringVal: MCPJSONValue = "hello"
        #expect(stringVal == .string("hello"))

        let arrayVal: MCPJSONValue = [1, 2, 3]
        #expect(arrayVal == .array([.int(1), .int(2), .int(3)]))

        let dictVal: MCPJSONValue = ["key": "value"]
        #expect(dictVal == .object(["key": .string("value")]))
    }

    // MARK: - JsonRpcId

    @Test("JsonRpcId integer type")
    func idInteger() throws {
        let id = JsonRpcId.int(42)
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(JsonRpcId.self, from: data)
        #expect(decoded == .int(42))
    }

    @Test("JsonRpcId string type")
    func idString() throws {
        let id = JsonRpcId.string("req-001")
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(JsonRpcId.self, from: data)
        #expect(decoded == .string("req-001"))
    }

    // MARK: - JsonRpcRequest

    @Test("JsonRpcRequest encodes correctly")
    func requestEncoding() throws {
        let request = JsonRpcRequest(
            id: .int(1),
            method: "tools/list",
            params: .object(["cursor": .string("abc")])
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JsonRpcRequest.self, from: data)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(1))
        #expect(decoded.method == "tools/list")
        #expect(decoded.params == .object(["cursor": .string("abc")]))
    }

    @Test("JsonRpcRequest notification has nil id")
    func notification() throws {
        let notification = JsonRpcRequest(method: "notifications/initialized")

        #expect(notification.id == nil)
        #expect(notification.method == "notifications/initialized")

        let data = try JSONEncoder().encode(notification)
        let decoded = try JSONDecoder().decode(JsonRpcRequest.self, from: data)
        #expect(decoded.id == nil)
    }

    // MARK: - JsonRpcResponse

    @Test("JsonRpcResponse success")
    func responseSuccess() throws {
        let response = JsonRpcResponse(
            id: .int(1),
            result: .object(["status": .string("ok")])
        )

        #expect(response.result != nil)
        #expect(response.error == nil)

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JsonRpcResponse.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(1))
        #expect(decoded.result == .object(["status": .string("ok")]))
        #expect(decoded.error == nil)
    }

    @Test("JsonRpcResponse error")
    func responseError() throws {
        let rpcError = JsonRpcError(
            code: .methodNotFound,
            message: "Method not found",
            data: .string("unknown/method")
        )
        let response = JsonRpcResponse(id: .string("req-2"), error: rpcError)

        #expect(response.result == nil)
        #expect(response.error != nil)

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JsonRpcResponse.self, from: data)
        #expect(decoded.error?.code == JsonRpcErrorCode.methodNotFound.rawValue)
        #expect(decoded.error?.message == "Method not found")
        #expect(decoded.error?.data == .string("unknown/method"))
    }

    // MARK: - JsonRpcErrorCode

    @Test("JsonRpcErrorCode standard codes")
    func errorCodes() {
        #expect(JsonRpcErrorCode.parseError.rawValue == -32_700)
        #expect(JsonRpcErrorCode.invalidRequest.rawValue == -32_600)
        #expect(JsonRpcErrorCode.methodNotFound.rawValue == -32_601)
        #expect(JsonRpcErrorCode.invalidParams.rawValue == -32_602)
        #expect(JsonRpcErrorCode.internalError.rawValue == -32_603)
    }
}
