import Foundation
@testable import Rockxy
import SQLite3
import Testing

// Regression tests for databases whose `user_version` claims more schema than the file has.

struct SessionStoreSchemaRepairTests {
    // MARK: Internal

    @Test("Database stamped current but missing columns is repaired without losing rows")
    func stampedCurrentButMissingColumnsIsRepaired() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let transaction = try await seedPinnedTransaction(at: dir)
        let stamped = try intPragma("user_version", at: dir)
        try dropTrackedColumns(at: dir)
        #expect(try !columns("transactions", at: dir).contains("capture_evidence"))
        #expect(try !columns("websocket_frames", at: dir).contains("is_abnormal"))

        let store = try SessionStore(directory: dir)
        let loaded = try await store.loadPinnedAndSavedTransactions()

        #expect(loaded.map(\.id) == [transaction.id])
        #expect(loaded.first?.comment == "keep me")
        #expect(loaded.first?.isPinned == true)
        #expect(try columns("transactions", at: dir).contains("capture_evidence"))
        let frameColumns = try columns("websocket_frames", at: dir)
        for name in ["close_code", "close_reason", "close_origin", "is_abnormal"] {
            #expect(frameColumns.contains(name))
        }
        // The stamp is left alone: repair is driven by the real schema, not by rewriting it.
        #expect(try intPragma("user_version", at: dir) == stamped)
        #expect(try await store.transactionCount() == 1)
    }

    @Test("Genuinely current database is not modified by the repair")
    func currentDatabaseIsUntouched() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try await seedPinnedTransaction(at: dir)
        let columnsBefore = try columns("transactions", at: dir)
        let frameColumnsBefore = try columns("websocket_frames", at: dir)
        let schemaCookieBefore = try intPragma("schema_version", at: dir)
        let versionBefore = try intPragma("user_version", at: dir)

        let store = try SessionStore(directory: dir)
        #expect(try await store.loadPinnedAndSavedTransactions().count == 1)

        #expect(try columns("transactions", at: dir) == columnsBefore)
        #expect(try columns("websocket_frames", at: dir) == frameColumnsBefore)
        #expect(try intPragma("schema_version", at: dir) == schemaCookieBefore)
        #expect(try intPragma("user_version", at: dir) == versionBefore)
    }

    @Test("Repair is idempotent across repeated opens")
    func repairIsIdempotent() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try await seedPinnedTransaction(at: dir)
        try dropTrackedColumns(at: dir)

        _ = try SessionStore(directory: dir)
        let afterFirst = try columns("transactions", at: dir)
        let cookieAfterFirst = try intPragma("schema_version", at: dir)

        let second = try SessionStore(directory: dir)
        _ = try SessionStore(directory: dir)

        #expect(try columns("transactions", at: dir) == afterFirst)
        #expect(try intPragma("schema_version", at: dir) == cookieAfterFirst)
        #expect(try await second.loadPinnedAndSavedTransactions().count == 1)
    }

    /// Not modelled: a column vanishing under a live store. Migrations only ever ADD columns and
    /// nothing in Rockxy drops one, so a second instance can add a column but never remove one;
    /// the stamped-but-missing state is a database that is already short when it is OPENED, which
    /// the first test covers. A drop under a live connection also trips SQLite.swift's cached
    /// column-index map (an out-of-range trap), which is outside what the repair guarantees.
    @Test("Another instance adding a column under a live store does not disturb it")
    func columnAddedUnderLiveStoreIsHarmless() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SessionStore(directory: dir)
        let first = TestFixtures.makeTransaction(url: "https://api.example.com/before")
        first.isPinned = true
        try await store.saveTransaction(first)

        // A newer build sharing the file adds a column this build has never heard of.
        try withHandle(at: dir) { handle in
            try exec("ALTER TABLE transactions ADD COLUMN future_column TEXT", handle)
        }

        let second = TestFixtures.makeTransaction(url: "https://api.example.com/after")
        second.isPinned = true
        try await store.saveTransaction(second)

        let loaded = try await store.loadPinnedAndSavedTransactions()
        #expect(Set(loaded.map(\.id)) == [first.id, second.id])
    }

    @Test("Two stores opening the same mis-stamped database concurrently both succeed")
    func concurrentOpensOfMisstampedDatabaseSucceed() async throws {
        for _ in 0 ..< 5 {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let transaction = try await seedPinnedTransaction(at: dir)
            try dropTrackedColumns(at: dir)

            let loadedCounts = try await withThrowingTaskGroup(of: [UUID].self) { group in
                for _ in 0 ..< 2 {
                    group.addTask {
                        let store = try SessionStore(directory: dir)
                        return try await store.loadPinnedAndSavedTransactions().map(\.id)
                    }
                }
                var results: [[UUID]] = []
                for try await ids in group {
                    results.append(ids)
                }
                return results
            }
            #expect(loadedCounts.count == 2)
            #expect(loadedCounts.allSatisfy { $0 == [transaction.id] })
            let names = try columns("transactions", at: dir)
            #expect(names.filter { $0 == "capture_evidence" }.count == 1)
            #expect(Set(names).count == names.count)
            let frameNames = try columns("websocket_frames", at: dir)
            #expect(Set(frameNames).count == frameNames.count)
            for name in ["close_code", "close_reason", "close_origin", "is_abnormal"] {
                #expect(frameNames.filter { $0 == name }.count == 1)
            }
        }
    }

    // MARK: Private

    private func seedPinnedTransaction(at dir: URL) async throws -> HTTPTransaction {
        let store = try SessionStore(directory: dir)
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/pinned")
        transaction.isPinned = true
        transaction.comment = "keep me"
        try await store.saveTransaction(transaction)
        return transaction
    }

    /// Reproduces the field state: the version stamp is untouched, but columns added by the
    /// newer migrations are gone.
    private func dropTrackedColumns(at dir: URL) throws {
        try withHandle(at: dir) { handle in
            for sql in [
                "ALTER TABLE transactions DROP COLUMN capture_evidence",
                "ALTER TABLE websocket_frames DROP COLUMN close_code",
                "ALTER TABLE websocket_frames DROP COLUMN close_reason",
                "ALTER TABLE websocket_frames DROP COLUMN close_origin",
                "ALTER TABLE websocket_frames DROP COLUMN is_abnormal",
            ] {
                try exec(sql, handle)
            }
        }
    }

    private func columns(_ table: String, at dir: URL) throws -> [String] {
        try withHandle(at: dir) { handle in
            var statement: OpaquePointer?
            try #require(sqlite3_prepare_v2(handle, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            var names: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let cString = sqlite3_column_text(statement, 1) {
                    names.append(String(cString: cString))
                }
            }
            return names
        }
    }

    private func intPragma(_ name: String, at dir: URL) throws -> Int {
        try withHandle(at: dir) { handle in
            var statement: OpaquePointer?
            try #require(sqlite3_prepare_v2(handle, "PRAGMA \(name)", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            try #require(sqlite3_step(statement) == SQLITE_ROW)
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func withHandle<T>(at dir: URL, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var handle: OpaquePointer?
        let dbPath = dir.appendingPathComponent("rockxy.sqlite3").path
        try #require(sqlite3_open(dbPath, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        return try body(handle)
    }

    private func exec(_ sql: String, _ handle: OpaquePointer?) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        let message = errorMessage.map { String(cString: $0) } ?? ""
        sqlite3_free(errorMessage)
        try #require(status == SQLITE_OK, "\(sql) failed: \(message)")
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
