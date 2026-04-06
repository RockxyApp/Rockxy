import Foundation
@testable import Rockxy
import Testing

// Regression tests for `Storage` in the core storage layer.

// MARK: - InMemorySessionBufferTests

struct InMemorySessionBufferTests {
    @Test("append and retrieve by ID")
    func appendAndRetrieve() async {
        let buffer = InMemorySessionBuffer()
        let transaction = TestFixtures.makeTransaction()

        await buffer.append(transaction)
        let retrieved = await buffer.transaction(for: transaction.id)

        #expect(retrieved != nil)
        #expect(retrieved?.id == transaction.id)
    }

    @Test("count increments on append")
    func countIncrementsOnAppend() async {
        let buffer = InMemorySessionBuffer()

        await buffer.append(TestFixtures.makeTransaction(url: "https://example.com/1"))
        await buffer.append(TestFixtures.makeTransaction(url: "https://example.com/2"))
        await buffer.append(TestFixtures.makeTransaction(url: "https://example.com/3"))

        let count = await buffer.count
        #expect(count == 3)
    }

    @Test("clear resets buffer")
    func clearResetsBuffer() async {
        let buffer = InMemorySessionBuffer()

        await buffer.append(TestFixtures.makeTransaction())
        await buffer.append(TestFixtures.makeTransaction())
        await buffer.clear()

        let count = await buffer.count
        let all = await buffer.allTransactions()
        #expect(count == 0)
        #expect(all.isEmpty)
    }

    @Test("eviction at capacity limit")
    func evictionAtCapacity() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)

        for i in 0 ..< 110 {
            await buffer.append(
                TestFixtures.makeTransaction(url: "https://example.com/\(i)")
            )
        }

        let count = await buffer.count
        #expect(count <= 100)
    }

    @Test("allTransactions preserves insertion order")
    func allTransactionsPreservesOrder() async {
        let buffer = InMemorySessionBuffer()
        var ids: [UUID] = []

        for i in 0 ..< 5 {
            let transaction = TestFixtures.makeTransaction(url: "https://example.com/\(i)")
            ids.append(transaction.id)
            await buffer.append(transaction)
        }

        let all = await buffer.allTransactions()
        let retrievedIds = all.map(\.id)
        #expect(retrievedIds == ids)
    }

    @Test("duplicate ID overwrites existing entry")
    func duplicateIdOverwrites() async {
        let buffer = InMemorySessionBuffer()
        let transaction = TestFixtures.makeTransaction(statusCode: 200)

        await buffer.append(transaction)
        transaction.response = TestFixtures.makeResponse(statusCode: 404)
        await buffer.append(transaction)

        let count = await buffer.count
        let retrieved = await buffer.transaction(for: transaction.id)
        #expect(count == 1)
        #expect(retrieved?.response?.statusCode == 404)
    }
}

// MARK: - AppSettingsStorageTests

struct AppSettingsStorageTests {
    // MARK: Internal

    @Test("save and load roundtrip preserves values")
    func saveAndLoadRoundtrip() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        var settings = AppSettings()
        settings.proxyPort = Self.testPort
        settings.autoStartProxy = true
        settings.recordOnLaunch = false
        settings.onlyListenOnLocalhost = false
        settings.listenIPv6 = true
        settings.autoSelectPort = true

        AppSettingsStorage.save(settings)
        let loaded = AppSettingsStorage.load()

        #expect(loaded.proxyPort == Self.testPort)
        #expect(loaded.autoStartProxy == true)
        #expect(loaded.recordOnLaunch == false)
        #expect(loaded.onlyListenOnLocalhost == false)
        #expect(loaded.listenIPv6 == true)
        #expect(loaded.autoSelectPort == true)
    }

    @Test("default values match AppSettings initializer")
    func defaultValues() {
        let defaultSettings = AppSettings()
        #expect(defaultSettings.proxyPort == Self.defaultPort)
        #expect(defaultSettings.recordOnLaunch == true)
        #expect(defaultSettings.onlyListenOnLocalhost == true)
        #expect(defaultSettings.autoStartProxy == false)
        #expect(defaultSettings.listenIPv6 == false)
        #expect(defaultSettings.autoSelectPort == true)
    }

    // MARK: Private

    // swiftlint:disable:next number_separator
    private static let testPort = 8888
    // swiftlint:disable:next number_separator
    private static let defaultPort = 9090
}
