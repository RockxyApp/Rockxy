import Foundation
@testable import Rockxy

/// Shared factory methods for constructing test data across all test suites.
/// Provides pre-configured `HTTPTransaction`, `HTTPRequestData`, `HTTPResponseData`,
/// `LogEntry`, `ProxyRule`, and specialized variants (GraphQL, WebSocket, bulk).
enum TestFixtures {
    /// Isolated plugin environment: directory, defaults, and manager all in one.
    struct IsolatedPluginEnv {
        let pluginsDir: URL
        let defaults: UserDefaults
        let defaultsSuiteName: String
        let manager: ScriptPluginManager

        func cleanup() {
            try? FileManager.default.removeItem(at: pluginsDir)
            // Also clear the ephemeral UserDefaults suite so plugin-enabled keys
            // and other stored values do not leak into sibling tests.
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
    }

    static func makeTransaction(
        method: String = "GET",
        url: String = "https://api.example.com/test",
        statusCode: Int? = 200,
        state: TransactionState = .completed,
        comment: String? = nil,
        highlightColor: HighlightColor? = nil
    )
        -> HTTPTransaction
    {
        let request = makeRequest(method: method, url: url)
        let transaction = HTTPTransaction(request: request, state: state)
        if let statusCode {
            transaction.response = makeResponse(statusCode: statusCode)
        }
        transaction.comment = comment
        transaction.highlightColor = highlightColor
        return transaction
    }

    static func makeRequest(
        method: String = "GET",
        url: String = "https://api.example.com/test",
        headers: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")]
    )
        -> HTTPRequestData
    {
        guard let url = URL(string: url) else {
            preconditionFailure("Expected valid fixture URL")
        }
        return HTTPRequestData(
            method: method,
            url: url,
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: nil
        )
    }

    static func makeResponse(
        statusCode: Int = 200,
        headers: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")],
        body: Data? = nil
    )
        -> HTTPResponseData
    {
        HTTPResponseData(
            statusCode: statusCode,
            statusMessage: statusCode == 200 ? "OK" : "Error",
            headers: headers,
            body: body
        )
    }

    static func makeLogEntry(
        level: LogLevel = .info,
        message: String = "Test log message",
        source: LogSource = .oslog(subsystem: "com.test.app")
    )
        -> LogEntry
    {
        LogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            message: message,
            source: source,
            processName: nil,
            subsystem: nil,
            category: nil,
            metadata: [:]
        )
    }

    static func makeRule(
        name: String = "Test Rule",
        isEnabled: Bool = true,
        action: RuleAction = .block(statusCode: 403)
    )
        -> ProxyRule
    {
        ProxyRule(
            name: name,
            isEnabled: isEnabled,
            matchCondition: RuleMatchCondition(urlPattern: "*.example.com"),
            action: action
        )
    }

    static func makeTransactionWithTiming(
        method: String = "GET",
        url: String = "https://api.example.com/test",
        statusCode: Int = 200,
        dns: TimeInterval = 0.01,
        tcp: TimeInterval = 0.02,
        tls: TimeInterval = 0.03,
        ttfb: TimeInterval = 0.1,
        transfer: TimeInterval = 0.05
    )
        -> HTTPTransaction
    {
        let transaction = makeTransaction(method: method, url: url, statusCode: statusCode)
        transaction.timingInfo = TimingInfo(
            dnsLookup: dns, tcpConnection: tcp, tlsHandshake: tls,
            timeToFirstByte: ttfb, contentTransfer: transfer
        )
        return transaction
    }

    static func makeTransactionWithBody(
        method: String = "GET",
        url: String = "https://api.example.com/test",
        statusCode: Int = 200,
        responseJSON: [String: Any]
    )
        -> HTTPTransaction
    {
        let transaction = makeTransaction(method: method, url: url, statusCode: statusCode)
        if let jsonData = try? JSONSerialization.data(withJSONObject: responseJSON) {
            transaction.response = makeResponse(
                statusCode: statusCode,
                headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
                body: jsonData
            )
            transaction.response?.contentType = .json
        }
        return transaction
    }

    static func makeGraphQLTransaction(
        operationName: String? = "GetUsers",
        operationType: GraphQLOperationType = .query,
        query: String = "{ users { id name } }"
    )
        -> HTTPTransaction
    {
        let queryBody: [String: Any] = [
            "query": query,
            "operationName": operationName as Any
        ]
        let bodyData = try? JSONSerialization.data(withJSONObject: queryBody)
        guard let url = URL(string: "https://api.example.com/graphql") else {
            preconditionFailure("Expected valid GraphQL fixture URL")
        }
        let request = HTTPRequestData(
            method: "POST",
            url: url,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: bodyData,
            contentType: .json
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        transaction.response = makeResponse(statusCode: 200)
        transaction.graphQLInfo = GraphQLInfo(
            operationName: operationName,
            operationType: operationType,
            query: query,
            variables: nil
        )
        return transaction
    }

    static func makeWeb3RPCTransaction(
        method: String? = "eth_blockNumber",
        batch: Web3RPCBatchSummary? = nil,
        error: Web3RPCError? = nil,
        requestBody: Data? = Data(#"{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}"#.utf8),
        responseBody: Data? = Data(#"{"jsonrpc":"2.0","id":1,"result":"0x1"}"#.utf8)
    )
        -> HTTPTransaction
    {
        guard let url = URL(string: "https://rpc.example.com") else {
            preconditionFailure("Expected valid Web3 RPC fixture URL")
        }
        let request = HTTPRequestData(
            method: "POST",
            url: url,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: requestBody,
            contentType: .json
        )
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: responseBody,
            contentType: .json
        )
        return HTTPTransaction(
            request: request,
            response: response,
            state: .completed,
            web3RPCInfo: Web3RPCInfo(
                family: .evm,
                providerHost: "rpc.example.com",
                method: method,
                requestID: batch == nil ? "1" : nil,
                batch: batch,
                error: error,
                chainHint: Web3RPCChainHint(chainID: "0x1"),
                transactionHash: nil,
                blockIdentifier: nil,
                requestPayloadSize: requestBody?.count,
                responsePayloadSize: responseBody?.count
            )
        )
    }

    static func makeGRPCTransaction(
        requestBody: Data? = grpcFrame(payload: Data([0x08, 0x96, 0x01])),
        responseBody: Data? = grpcFrame(payload: Data([0x12, 0x07]) + Data("Stephen".utf8))
    )
        -> HTTPTransaction
    {
        guard let url = URL(string: "https://api.example.com/user.v1.UserService/GetProfile") else {
            preconditionFailure("Expected valid gRPC fixture URL")
        }
        let request = HTTPRequestData(
            method: "POST",
            url: url,
            httpVersion: "HTTP/2",
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/grpc+proto"),
                HTTPHeader(name: "TE", value: "trailers"),
            ],
            body: requestBody,
            contentType: .protobuf
        )
        let response = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/grpc+proto"),
                HTTPHeader(name: "grpc-status", value: "0"),
                HTTPHeader(name: "grpc-message", value: "OK"),
            ],
            body: responseBody,
            contentType: .protobuf
        )
        return HTTPTransaction(request: request, response: response, state: .completed)
    }

    static func grpcFrame(compressedFlag: UInt8 = 0, payload: Data) -> Data {
        var frame = Data([compressedFlag])
        let length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: length) { bytes in
            frame.append(contentsOf: bytes)
        }
        frame.append(payload)
        return frame
    }

    static func makeWebSocketTransaction() -> HTTPTransaction {
        let request = makeRequest(url: "wss://ws.example.com/stream")
        let connection = WebSocketConnection(upgradeRequest: request)
        for i in 0 ..< 5 {
            let frame = WebSocketFrameData(
                direction: i % 2 == 0 ? .sent : .received,
                opcode: .text,
                payload: Data("Frame \(i)".utf8)
            )
            connection.addFrame(frame)
        }
        let transaction = HTTPTransaction(
            request: request, state: .completed, webSocketConnection: connection
        )
        transaction.response = makeResponse(statusCode: 101)
        return transaction
    }

    static func makeBypassDomain(
        domain: String = "localhost",
        isEnabled: Bool = true
    )
        -> BypassDomain
    {
        BypassDomain(domain: domain, isEnabled: isEnabled)
    }

    static func makeHARJSON(
        entryCount: Int = 2,
        includeTimings: Bool = true,
        includeBase64Body: Bool = false
    )
        -> Data
    {
        var entries = [[String: Any]]()
        for i in 0 ..< entryCount {
            var entry: [String: Any] = [
                "startedDateTime": "2025-01-15T10:00:0\(i).000Z",
                "time": 150.0,
                "request": [
                    "method": i % 2 == 0 ? "GET" : "POST",
                    "url": "https://api.example.com/items/\(i)",
                    "httpVersion": "HTTP/1.1",
                    "headers": [
                        ["name": "Content-Type", "value": "application/json"],
                        ["name": "Accept", "value": "*/*"]
                    ],
                    "cookies": [] as [[String: Any]],
                    "queryString": [] as [[String: Any]],
                    "headersSize": 50,
                    "bodySize": 0
                ] as [String: Any],
                "response": [
                    "status": 200,
                    "statusText": "OK",
                    "httpVersion": "HTTP/1.1",
                    "headers": [
                        ["name": "Content-Type", "value": "application/json"]
                    ],
                    "cookies": [] as [[String: Any]],
                    "content": includeBase64Body
                        ? [
                            "size": 12,
                            "mimeType": "application/json",
                            "text": "SGVsbG8gV29ybGQ=",
                            "encoding": "base64"
                        ] as [String: Any]
                        : ["size": 12, "mimeType": "application/json", "text": "{\"ok\":true}"] as [String: Any],
                    "redirectURL": "",
                    "headersSize": 30,
                    "bodySize": 12
                ] as [String: Any],
                "cache": [String: Any]()
            ]

            if includeTimings {
                entry["timings"] = [
                    "dns": 10.0,
                    "connect": 20.0,
                    "ssl": 30.0,
                    "send": 0.0,
                    "wait": 50.0,
                    "receive": 40.0
                ] as [String: Any]
            }

            entries.append(entry)
        }

        let root: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "TestFixtures", "version": "1.0"],
                "entries": entries
            ] as [String: Any]
        ]

        return try! JSONSerialization.data(withJSONObject: root) // swiftlint:disable:this force_try
    }

    static func makeAnnotatedTransaction(
        comment: String? = "Test annotation",
        highlightColor: HighlightColor? = .blue,
        isPinned: Bool = true,
        isSaved: Bool = true,
        isTLSFailure: Bool = false
    )
        -> HTTPTransaction
    {
        let transaction = makeTransaction()
        transaction.comment = comment
        transaction.highlightColor = highlightColor
        transaction.isPinned = isPinned
        transaction.isSaved = isSaved
        transaction.isTLSFailure = isTLSFailure
        return transaction
    }

    static func makeHARJSONWithPostData(
        body: String = "{\"key\":\"value\"}",
        mimeType: String = "application/json"
    )
        -> Data
    {
        let root: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "TestFixtures", "version": "1.0"],
                "entries": [
                    [
                        "startedDateTime": "2025-01-15T10:00:00.000Z",
                        "time": 100.0,
                        "request": [
                            "method": "POST",
                            "url": "https://api.example.com/data",
                            "httpVersion": "HTTP/1.1",
                            "headers": [
                                ["name": "Content-Type", "value": mimeType]
                            ],
                            "cookies": [] as [[String: Any]],
                            "queryString": [] as [[String: Any]],
                            "headersSize": 40,
                            "bodySize": body.count,
                            "postData": [
                                "mimeType": mimeType,
                                "text": body
                            ] as [String: Any]
                        ] as [String: Any],
                        "response": [
                            "status": 200,
                            "statusText": "OK",
                            "httpVersion": "HTTP/1.1",
                            "headers": [
                                ["name": "Content-Type", "value": "application/json"]
                            ],
                            "cookies": [] as [[String: Any]],
                            "content": [
                                "size": 12,
                                "mimeType": "application/json",
                                "text": "{\"ok\":true}"
                            ] as [String: Any],
                            "redirectURL": "",
                            "headersSize": 30,
                            "bodySize": 12
                        ] as [String: Any],
                        "cache": [String: Any](),
                        "timings": [
                            "dns": 5.0, "connect": 10.0, "ssl": 15.0,
                            "send": 1.0, "wait": 50.0, "receive": 20.0
                        ] as [String: Any]
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ]
        return try! JSONSerialization.data(withJSONObject: root) // swiftlint:disable:this force_try
    }

    static func makeErrorTransaction(statusCode: Int = 500) -> HTTPTransaction {
        makeTransaction(
            url: "https://api.example.com/error",
            statusCode: statusCode,
            state: statusCode >= 500 ? .failed : .completed
        )
    }

    static func makeBulkTransactions(count: Int) -> [HTTPTransaction] {
        let methods = ["GET", "POST", "PUT", "DELETE"]
        let paths = ["/users", "/posts", "/comments", "/todos", "/albums"]
        let statusCodes = [200, 200, 200, 201, 301, 400, 404, 500]

        return (0 ..< count).map { i in
            let method = methods[i % methods.count]
            let path = paths[i % paths.count]
            let status = statusCodes[i % statusCodes.count]
            let transaction = makeTransaction(
                method: method,
                url: "https://api.example.com\(path)/\(i)",
                statusCode: status,
                state: status >= 500 ? .failed : .completed
            )
            transaction.timingInfo = TimingInfo(
                dnsLookup: Double.random(in: 0.005 ... 0.05),
                tcpConnection: Double.random(in: 0.01 ... 0.08),
                tlsHandshake: Double.random(in: 0.02 ... 0.1),
                timeToFirstByte: Double.random(in: 0.05 ... 0.5),
                contentTransfer: Double.random(in: 0.01 ... 2.0)
            )
            return transaction
        }
    }

    // MARK: - Plugin Helpers

    /// Creates a temp plugin inside the given directory (isolated from real app-support).
    /// Use `makeIsolatedPluginDir()` to get an isolated directory, and
    /// `makeIsolatedPluginManager(pluginsDir:)` to get a manager that scans only that directory.
    static func createTempPlugin(
        id: String,
        enabled: Bool,
        in pluginsDir: URL,
        defaults: UserDefaults = .standard
    )
        throws -> URL
    {
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

        let bundlePath = pluginsDir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)

        let manifest = """
        {
            "id": "\(id)",
            "name": "Test Plugin \(id)",
            "version": "1.0.0",
            "author": { "name": "Test" },
            "description": "Test plugin",
            "types": ["script"],
            "entryPoints": { "script": "index.js" },
            "capabilities": []
        }
        """
        try manifest.write(
            to: bundlePath.appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )

        let script = "module.exports = {};"
        try script.write(
            to: bundlePath.appendingPathComponent("index.js"),
            atomically: true,
            encoding: .utf8
        )

        let key = RockxyIdentity.current.pluginEnabledKey(pluginID: id)
        if enabled {
            defaults.set(true, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }

        return bundlePath
    }

    /// **Deprecated for new call sites.** Writes into the **real app-support `Plugins/`
    /// directory** and mutates `UserDefaults.standard` for the plugin-enabled key.
    ///
    /// **Residual risk:** a crash between creation and the matching
    /// `cleanupTempPlugin(id:bundlePath:)` leaks the plugin bundle and enabled flag
    /// into the developer's real environment until manual cleanup.
    ///
    /// Prefer `makeIsolatedPluginEnv()` plus `createTempPlugin(id:enabled:in:defaults:)`
    /// for new tests so the plugin directory, defaults suite, and manager are fully
    /// isolated and teardown is bounded. This overload is retained only for tests that
    /// intentionally exercise the production singleton path.
    @available(
        *,
        deprecated,
        message: "Writes to the real app-support Plugins directory; prefer isolated plugin fixtures."
    )
    static func createTempPlugin(id: String, enabled: Bool) throws -> URL {
        try createTempPlugin(
            id: id,
            enabled: enabled,
            in: RockxyIdentity.current.appSupportPath("Plugins")
        )
    }

    static func cleanupTempPlugin(id: String, bundlePath: URL, defaults: UserDefaults = .standard) {
        try? FileManager.default.removeItem(at: bundlePath)
        defaults.removeObject(forKey: RockxyIdentity.current.pluginEnabledKey(pluginID: id))
    }

    /// Returns a fresh temp directory for isolated plugin tests.
    static func makeIsolatedPluginDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyPluginTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Returns an ephemeral `UserDefaults` suite isolated from `.standard`.
    static func makeIsolatedDefaults() -> UserDefaults {
        makeNamedIsolatedDefaults().defaults
    }

    /// Returns an ephemeral `UserDefaults` suite isolated from `.standard`, together
    /// with the suite name so callers can clear the persistent domain on teardown.
    static func makeNamedIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "RockxyPluginTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Expected isolated UserDefaults suite")
        }
        return (defaults, suiteName)
    }

    /// Creates a fully isolated plugin test environment.
    static func makeIsolatedPluginEnv() -> IsolatedPluginEnv {
        let dir = makeIsolatedPluginDir()
        let (defs, suiteName) = makeNamedIsolatedDefaults()
        let discovery = PluginDiscovery(pluginsDirectory: dir, defaults: defs)
        let manager = ScriptPluginManager(discovery: discovery, defaults: defs)
        return IsolatedPluginEnv(
            pluginsDir: dir,
            defaults: defs,
            defaultsSuiteName: suiteName,
            manager: manager
        )
    }

    /// Removes an isolated plugin test directory entirely.
    static func cleanupIsolatedPluginDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}
