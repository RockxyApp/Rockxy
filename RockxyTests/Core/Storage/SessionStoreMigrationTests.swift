import Foundation
@testable import Rockxy
import SQLite3
import Testing

// Regression tests for `SessionStoreMigration` in the core storage layer.

struct SessionStoreMigrationTests {
    // MARK: Internal

    @Test("Default store uses test app support namespace")
    func defaultStoreUsesTestAppSupportNamespace() async throws {
        let dir = RockxyIdentity.current.appSupportDirectory()

        let store = try SessionStore()
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/test-isolation")
        transaction.isSaved = true

        try await store.saveTransaction(transaction)

        let isolatedStore = try SessionStore(directory: dir)
        let loaded = try await isolatedStore.loadPinnedAndSavedTransactions()

        #expect(loaded.map(\.id).contains(transaction.id))
    }

    @Test("Fresh database migrates to latest schema version")
    func freshDatabaseMigratesToLatest() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)
        let version = try await store.schemaVersion()

        #expect(version >= 3)
    }

    @Test("Second initialization skips migration")
    func secondInitSkipsMigration() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store1 = try SessionStore(directory: dir)
        let v1 = try await store1.schemaVersion()

        let store2 = try SessionStore(directory: dir)
        let v2 = try await store2.schemaVersion()

        #expect(v1 == v2)
    }

    @Test("Schema version persists across instances")
    func schemaVersionPersists() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try SessionStore(directory: dir)
        let store = try SessionStore(directory: dir)
        let version = try await store.schemaVersion()

        #expect(version >= 3)
    }

    @Test("Save and load transaction after migration")
    func saveLoadAfterMigration() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)
        let transaction = TestFixtures.makeTransaction()
        transaction.isPinned = true
        transaction.comment = "test comment"

        try await store.saveTransaction(transaction)
        let loaded = try await store.loadTransactions(limit: 10)

        #expect(loaded.count == 1)
        #expect(loaded[0].isPinned == true)
        #expect(loaded[0].comment == "test comment")
    }

    @Test("Strikethrough survives a save and load, and defaults off")
    func strikethroughPersists() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)
        let struck = TestFixtures.makeTransaction()
        struck.isStruckThrough = true
        let plain = TestFixtures.makeTransaction()

        try await store.saveTransaction(struck)
        try await store.saveTransaction(plain)
        let loaded = try await store.loadTransactions(limit: 10)

        #expect(loaded.first { $0.id == struck.id }?.isStruckThrough == true)
        #expect(loaded.first { $0.id == plain.id }?.isStruckThrough == false)
        #expect(try await store.schemaVersion() >= 5)
    }

    @Test("Save and load preserves Web3 RPC metadata")
    func saveLoadPreservesWeb3RPCMetadata() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)
        let transaction = TestFixtures.makeWeb3RPCTransaction(
            method: nil,
            batch: Web3RPCBatchSummary(
                requestCount: 2,
                web3RequestCount: 2,
                responseCount: 2,
                errorCount: 1,
                methods: ["eth_chainId", "eth_blockNumber"]
            ),
            error: Web3RPCError(code: -32_000, message: "rate limited")
        )

        try await store.saveTransaction(transaction)
        let loaded = try await store.loadTransaction(byID: transaction.id)
        let info = try #require(loaded?.web3RPCInfo)

        #expect(info.family == .evm)
        #expect(info.providerHost == "rpc.example.com")
        #expect(info.method == nil)
        #expect(info.requestID == nil)
        #expect(info.batch?.requestCount == 2)
        #expect(info.batch?.web3RequestCount == 2)
        #expect(info.batch?.responseCount == 2)
        #expect(info.batch?.errorCount == 1)
        #expect(info.batch?.methods == ["eth_chainId", "eth_blockNumber"])
        #expect(info.error?.code == -32_000)
        #expect(info.error?.message == "rate limited")
        #expect(info.chainHint?.chainID == "0x1")
        #expect(info.requestPayloadSize == transaction.web3RPCInfo?.requestPayloadSize)
        #expect(info.responsePayloadSize == transaction.web3RPCInfo?.responsePayloadSize)
    }

    @Test("Save and load preserves a zero-frame WebSocket identity")
    func saveLoadPreservesZeroFrameWebSocketIdentity() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)
        let request = TestFixtures.makeRequest(url: "wss://ws.example.com/empty")
        let transaction = HTTPTransaction(
            request: request,
            state: .completed,
            webSocketConnection: WebSocketConnection(upgradeRequest: request)
        )

        try await store.saveTransaction(transaction)
        let reloadedStore = try SessionStore(directory: dir)
        let loaded = try #require(try await reloadedStore.loadTransaction(byID: transaction.id))

        #expect(loaded.webSocketConnection != nil)
        #expect(loaded.webSocketConnection?.frames.isEmpty == true)
        #expect(!MainContentCoordinator.canReplay(loaded))
    }

    @Test("Legacy zero-frame WebSocket handshake regains its identity after the v3 migration")
    func legacyZeroFrameWebSocketHandshakeMigratesToWebSocketIdentity() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let handshake = HTTPTransaction(
            request: TestFixtures.makeRequest(
                url: "wss://ws.example.com/legacy",
                headers: [
                    HTTPHeader(name: "Upgrade", value: "websocket"),
                    HTTPHeader(name: "Connection", value: "Upgrade"),
                    HTTPHeader(name: "Sec-WebSocket-Key", value: "dGhlIHNhbXBsZSBub25jZQ=="),
                ]
            ),
            state: .completed
        )
        handshake.response = HTTPResponseData(
            statusCode: 101,
            statusMessage: "Switching Protocols",
            headers: [
                HTTPHeader(name: "upgrade", value: "WebSocket"),
                HTTPHeader(name: "connection", value: "keep-alive, Upgrade"),
            ],
            body: nil
        )

        try await seedLegacyDatabase(at: dir, transactions: [handshake])

        let migratedStore = try SessionStore(directory: dir)
        #expect(try await migratedStore.schemaVersion() >= 4)
        let loaded = try #require(try await migratedStore.loadTransaction(byID: handshake.id))

        #expect(loaded.webSocketConnection != nil)
        #expect(loaded.webSocketConnection?.frames.isEmpty == true)
        #expect(!MainContentCoordinator.canReplay(loaded))
    }

    @Test("A database already migrated to buggy v3 repairs zero-frame WebSocket identity")
    func alreadyMigratedV3ZeroFrameWebSocketHandshakeIsRepaired() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let handshake = HTTPTransaction(
            request: TestFixtures.makeRequest(
                url: "wss://ws.example.com/already-v3",
                headers: [
                    HTTPHeader(name: "Upgrade", value: "websocket"),
                    HTTPHeader(name: "Connection", value: "Upgrade"),
                ]
            ),
            state: .completed
        )
        handshake.response = HTTPResponseData(
            statusCode: 101,
            statusMessage: "Switching Protocols",
            headers: [
                HTTPHeader(name: "Upgrade", value: "websocket"),
                HTTPHeader(name: "Connection", value: "Upgrade"),
            ],
            body: nil
        )

        try await seedBuggyV3Database(at: dir, transactions: [handshake])

        let migratedStore = try SessionStore(directory: dir)
        #expect(try await migratedStore.schemaVersion() >= 4)
        let loaded = try #require(try await migratedStore.loadTransaction(byID: handshake.id))

        #expect(loaded.webSocketConnection != nil)
        #expect(loaded.webSocketConnection?.frames.isEmpty == true)
        #expect(!MainContentCoordinator.canReplay(loaded))
    }

    @Test("Legacy 101 rows without WebSocket handshake evidence stay plain HTTP after migration")
    func legacyNonWebSocketSwitchingProtocolsRowsStayReplayable() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let h2cUpgrade = HTTPTransaction(
            request: TestFixtures.makeRequest(
                url: "http://api.example.com/h2c",
                headers: [
                    HTTPHeader(name: "Upgrade", value: "h2c"),
                    HTTPHeader(name: "Connection", value: "Upgrade, HTTP2-Settings"),
                ]
            ),
            state: .completed
        )
        h2cUpgrade.response = HTTPResponseData(
            statusCode: 101,
            statusMessage: "Switching Protocols",
            headers: [
                HTTPHeader(name: "Upgrade", value: "h2c"),
                HTTPHeader(name: "Connection", value: "Upgrade"),
            ],
            body: nil
        )

        let bareSwitchingProtocols = HTTPTransaction(
            request: TestFixtures.makeRequest(url: "http://api.example.com/bare-101", headers: []),
            state: .completed
        )
        bareSwitchingProtocols.response = HTTPResponseData(
            statusCode: 101,
            statusMessage: "Switching Protocols",
            headers: [],
            body: nil
        )

        // "websocket" must be a whole token, not a substring, and Connection must carry "upgrade".
        let missingConnectionToken = HTTPTransaction(
            request: TestFixtures.makeRequest(
                url: "http://api.example.com/no-connection-token",
                headers: [HTTPHeader(name: "Upgrade", value: "websocket")]
            ),
            state: .completed
        )

        let conflictingResponseProtocol = HTTPTransaction(
            request: TestFixtures.makeRequest(
                url: "http://api.example.com/conflicting-response-protocol",
                headers: [
                    HTTPHeader(name: "Upgrade", value: "websocket"),
                    HTTPHeader(name: "Connection", value: "Upgrade"),
                ]
            ),
            state: .completed
        )
        conflictingResponseProtocol.response = HTTPResponseData(
            statusCode: 101,
            statusMessage: "Switching Protocols",
            headers: [
                HTTPHeader(name: "Upgrade", value: "h2c"),
                HTTPHeader(name: "Connection", value: "Upgrade"),
            ],
            body: nil
        )
        missingConnectionToken.response = HTTPResponseData(
            statusCode: 101,
            statusMessage: "Switching Protocols",
            headers: [
                HTTPHeader(name: "Upgrade", value: "websocket-compat"),
                HTTPHeader(name: "Connection", value: "keep-alive"),
            ],
            body: nil
        )

        let plainHTTP = TestFixtures.makeTransaction(url: "https://api.example.com/plain")

        try await seedLegacyDatabase(
            at: dir,
            transactions: [
                h2cUpgrade,
                bareSwitchingProtocols,
                missingConnectionToken,
                conflictingResponseProtocol,
                plainHTTP,
            ]
        )

        let migratedStore = try SessionStore(directory: dir)
        for transaction in [
            h2cUpgrade,
            bareSwitchingProtocols,
            missingConnectionToken,
            conflictingResponseProtocol,
            plainHTTP,
        ] {
            let loaded = try #require(try await migratedStore.loadTransaction(byID: transaction.id))
            #expect(loaded.webSocketConnection == nil)
            #expect(MainContentCoordinator.canReplay(loaded))
        }
    }

    @Test("Migrated columns have correct defaults")
    func migratedColumnDefaults() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)
        let transaction = TestFixtures.makeTransaction()

        try await store.saveTransaction(transaction)
        let loaded = try await store.loadTransactions(limit: 1)

        #expect(loaded.count == 1)
        #expect(loaded[0].isPinned == false)
        #expect(loaded[0].isSaved == false)
        #expect(loaded[0].comment == nil)
        #expect(loaded[0].highlightColor == nil)
        #expect(loaded[0].clientApp == nil)
        #expect(loaded[0].web3RPCInfo == nil)
    }

    // MARK: Private

    /// Writes `transactions` as plain HTTP rows, then rewinds the database to schema v2 by
    /// dropping `is_websocket` and resetting `user_version`, which is exactly the shape a
    /// pre-v3 capture database has before the current build migrates it.
    private func seedLegacyDatabase(at dir: URL, transactions: [HTTPTransaction]) async throws {
        do {
            let store = try SessionStore(directory: dir)
            for transaction in transactions {
                #expect(transaction.webSocketConnection == nil)
                try await store.saveTransaction(transaction)
            }
        }

        var handle: OpaquePointer?
        let dbPath = dir.appendingPathComponent("rockxy.sqlite3").path
        try #require(sqlite3_open(dbPath, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        for sql in [
            "ALTER TABLE transactions DROP COLUMN is_websocket",
            "PRAGMA user_version = 2",
        ] {
            var errorMessage: UnsafeMutablePointer<CChar>?
            let status = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
            let message = errorMessage.map { String(cString: $0) } ?? ""
            sqlite3_free(errorMessage)
            try #require(status == SQLITE_OK, "\(sql) failed: \(message)")
        }
    }

    /// Recreates the shipped shape of the buggy v3 migration: the identity column exists,
    /// handshake headers are persisted, but zero-frame WebSockets retain the default false flag.
    private func seedBuggyV3Database(at dir: URL, transactions: [HTTPTransaction]) async throws {
        do {
            let store = try SessionStore(directory: dir)
            for transaction in transactions {
                #expect(transaction.webSocketConnection == nil)
                try await store.saveTransaction(transaction)
            }
        }

        var handle: OpaquePointer?
        let dbPath = dir.appendingPathComponent("rockxy.sqlite3").path
        try #require(sqlite3_open(dbPath, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, "PRAGMA user_version = 3", nil, nil, &errorMessage)
        let message = errorMessage.map { String(cString: $0) } ?? ""
        sqlite3_free(errorMessage)
        try #require(status == SQLITE_OK, "setting v3 schema failed: \(message)")
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
