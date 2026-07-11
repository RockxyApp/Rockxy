import Foundation
@testable import Rockxy
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

        #expect(version >= 2)
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

        #expect(version >= 2)
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

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
