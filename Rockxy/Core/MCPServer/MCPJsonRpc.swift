import Foundation

// MARK: - MCPJSONValue

/// A recursive type that represents any valid JSON value.
enum MCPJSONValue: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([MCPJSONValue])
    case object([String: MCPJSONValue])
}

// MARK: Codable

extension MCPJSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }

        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }

        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
            return
        }

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        if let arrayValue = try? container.decode([MCPJSONValue].self) {
            self = .array(arrayValue)
            return
        }

        if let objectValue = try? container.decode([String: MCPJSONValue].self) {
            self = .object(objectValue)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot decode MCPJSONValue"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

// MARK: ExpressibleByNilLiteral

extension MCPJSONValue: ExpressibleByNilLiteral {
    init(nilLiteral: ()) {
        self = .null
    }
}

// MARK: ExpressibleByBooleanLiteral

extension MCPJSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

// MARK: ExpressibleByIntegerLiteral

extension MCPJSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self = .int(value)
    }
}

// MARK: ExpressibleByFloatLiteral

extension MCPJSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) {
        self = .double(value)
    }
}

// MARK: ExpressibleByStringLiteral

extension MCPJSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: ExpressibleByArrayLiteral

extension MCPJSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: MCPJSONValue...) {
        self = .array(elements)
    }
}

// MARK: ExpressibleByDictionaryLiteral

extension MCPJSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, MCPJSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension MCPJSONValue {
    /// Encodes this value to UTF-8 JSON data.
    func encodeToData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

// MARK: - JsonRpcId

/// JSON-RPC 2.0 request identifier — either an integer or a string.
enum JsonRpcId: Equatable {
    case int(Int)
    case string(String)
}

// MARK: Codable

extension JsonRpcId: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "JsonRpcId must be an integer or string"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        }
    }
}

// MARK: - JsonRpcErrorCode

/// Standard JSON-RPC 2.0 error codes.
enum JsonRpcErrorCode: Int {
    case parseError = -32_700
    case invalidRequest = -32_600
    case methodNotFound = -32_601
    case invalidParams = -32_602
    case internalError = -32_603
}

// MARK: - JsonRpcError

/// JSON-RPC 2.0 error object.
struct JsonRpcError: Codable, Equatable {
    // MARK: Lifecycle

    init(
        code: Int,
        message: String,
        data: MCPJSONValue? = nil
    ) {
        self.code = code
        self.message = message
        self.data = data
    }

    init(
        code: JsonRpcErrorCode,
        message: String,
        data: MCPJSONValue? = nil
    ) {
        self.code = code.rawValue
        self.message = message
        self.data = data
    }

    // MARK: Internal

    let code: Int
    let message: String
    let data: MCPJSONValue?
}

// MARK: - JsonRpcRequest

/// JSON-RPC 2.0 request. When `id` is nil the message is a notification.
struct JsonRpcRequest: Codable, Equatable {
    // MARK: Lifecycle

    init(
        id: JsonRpcId? = nil,
        method: String,
        params: MCPJSONValue? = nil
    ) {
        jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    // MARK: Internal

    let jsonrpc: String
    let id: JsonRpcId?
    let method: String
    let params: MCPJSONValue?
}

// MARK: - JsonRpcResponse

/// JSON-RPC 2.0 response. Exactly one of `result` or `error` should be non-nil.
struct JsonRpcResponse: Codable, Equatable {
    // MARK: Lifecycle

    init(
        id: JsonRpcId?,
        result: MCPJSONValue
    ) {
        jsonrpc = "2.0"
        self.id = id
        self.result = result
        error = nil
    }

    init(
        id: JsonRpcId?,
        error: JsonRpcError
    ) {
        jsonrpc = "2.0"
        self.id = id
        result = nil
        self.error = error
    }

    // MARK: Internal

    let jsonrpc: String
    let id: JsonRpcId?
    let result: MCPJSONValue?
    let error: JsonRpcError?
}
