import Foundation
@testable import Rockxy
import SQLite3
import Testing

struct SessionStoreCaptureEvidenceTests {
    // MARK: Internal

    @Test("Library startup retains Babylon capture evidence", arguments: ["saved", "pinned", "note"])
    func libraryEvidence(kind: String) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transaction = try makeCapturedTransaction()
        transaction.isSaved = kind == "saved"
        transaction.isPinned = kind == "pinned"
        transaction.comment = kind == "note" ? "Keep this capture" : nil
        let store = try SessionStore(directory: directory)
        try await store.saveTransaction(transaction)
        let reopened = try SessionStore(directory: directory)
        let favorites = try await reopened.loadPinnedAndSavedTransactions()
        let restored = try #require(favorites.first { $0.id == transaction.id })
        #expect(restored.babylonCaptureMetadata == transaction.babylonCaptureMetadata)
        #expect(restored.babylonCorrelation == transaction.babylonCorrelation)
        #expect(restored.babylonGRPCCallType == "bidirectionalStreaming")
        #expect(restored.measuredDuration == 1.25)
        #expect(restored.request.body == Data("partial".utf8))
        #expect(restored.request.bodyTruncated)
        #expect(restored.request.bodyOmission == transaction.request.bodyOmission)
        #expect(restored.response?.body == nil)
        #expect(restored.response?.bodyTruncated == true)
        #expect(restored.response?.bodyOmission == transaction.response?.bodyOmission)
    }

    @Test("SQLite saves actual partial response bytes without changing omission truth")
    func partialResponseBytes() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transaction = try makeCapturedTransaction()
        transaction.response?.body = Data("prefix".utf8)
        transaction.response?.bodyOmission = .init(reason: "sizeLimit", observedBytes: 6, originalBytes: 128)
        let store = try SessionStore(directory: directory)
        try await store.saveTransaction(transaction)
        let restored = try #require(try await store.loadTransaction(byID: transaction.id))
        #expect(restored.response?.body == Data("prefix".utf8))
        #expect(restored.response?.bodyTruncated == true)
        #expect(restored.response?.bodyOmission == transaction.response?.bodyOmission)
    }

    @Test("Legacy v6 favorites migrate without requiring capture metadata")
    func legacyMigration() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transaction = TestFixtures.makeTransaction()
        transaction.isSaved = true
        let store = try SessionStore(directory: directory)
        try await store.saveTransaction(transaction)
        try execute("ALTER TABLE transactions DROP COLUMN capture_evidence; PRAGMA user_version = 6", in: directory)
        let reopened = try SessionStore(directory: directory)
        #expect(try await reopened.schemaVersion() >= 7)
        let restored = try #require(try await reopened.loadTransaction(byID: transaction.id))
        #expect(restored.isSaved)
        #expect(restored.request.body == transaction.request.body)
        #expect(restored.babylonCaptureMetadata == nil)
        #expect(!restored.request.bodyTruncated)
    }

    @Test(
        "Corrupt or newer saved capture evidence cannot turn a partial body into complete content",
        arguments: [0, 1, 2, 3]
    )
    func corruptEvidenceIsIsolated(variant: Int) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transaction = try makeCapturedTransaction()
        let healthy = TestFixtures.makeTransaction()
        let store = try SessionStore(directory: directory)
        try await store.saveTransaction(transaction)
        try await store.saveTransaction(healthy)
        let blob = switch variant {
        case 1:
            "CAST('{\"formatVersion\":2,\"requestBodyTruncated\":true,\"responseBodyTruncated\":true}' AS BLOB)"
        case 2:
            "CAST('{\"formatVersion\":1,\"requestBodyTruncated\":true,\"responseBodyTruncated\":true,\"padding\":\"' "
                + "|| replace(hex(zeroblob(131073)), '00', 'x') || '\"}' AS BLOB)"
        case 3:
            "CAST('{\"formatVersion\":1,\"requestBodyTruncated\":true,\"responseBodyTruncated\":true,\"correlation\":{\"sessionID\":\"' "
                + "|| replace(hex(zeroblob(513)), '00', 'x') || '\",\"traceID\":\"trace\"}}' AS BLOB)"
        default: "X'7B'"
        }
        try execute(
            "UPDATE transactions SET capture_evidence = \(blob) WHERE id = '\(transaction.id.uuidString)'",
            in: directory
        )
        #expect(try await store.loadTransaction(byID: transaction.id) == nil)
        let loaded = try await store.loadTransactions()
        #expect(loaded.map(\.id) == [healthy.id])
        // The unusable row stays on disk for recovery; reading never deletes it.
        #expect(try rowCount(in: directory) == 2)
    }

    @Test("Oversized capture evidence fails before body files or rows are written")
    func oversizedEvidence() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transaction = try makeCapturedTransaction()
        transaction.babylonGRPCCallType = String(repeating: "x", count: 128 * 1_024 + 1)
        transaction.request.body = Data(repeating: 65, count: 2 * 1_024 * 1_024)
        let store = try SessionStore(directory: directory)
        await #expect(throws: (any Error).self) { try await store.saveTransaction(transaction) }
        #expect(try await store.loadTransactions().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("bodies").path)
            .isEmpty)
    }

    // MARK: Private

    private func makeCapturedTransaction() throws -> HTTPTransaction {
        let transaction = TestFixtures.makeTransaction()
        transaction.request.body = Data("partial".utf8)
        transaction.request.bodyTruncated = true
        transaction.request.bodyOmission = .init(reason: "sizeLimit", observedBytes: 7, originalBytes: 64)
        transaction.response = HTTPResponseData(statusCode: 200, statusMessage: "OK", headers: [], body: nil)
        transaction.response?.bodyTruncated = true
        transaction.response?.bodyOmission = .init(reason: "policy", observedBytes: 0, originalBytes: 128)
        transaction.babylonCorrelation = .init(
            sourceClientID: "client",
            sessionID: "runtime",
            traceID: "trace",
            stepID: "step"
        )
        transaction.babylonGRPCCallType = "bidirectionalStreaming"
        transaction.measuredDuration = 1.25
        let metadata = #"""
        {
          "clientID": "client",
          "packageName": "Fixture",
          "transportSessionID": "transport",
          "runtimeSessionID": "runtime",
          "traceID": "trace",
          "stepID": "step",
          "sdkVersion": "1.2.3",
          "platform": "iOS",
          "payloadSchemaVersions": {
            "traffic": 1
          },
          "supportedMessageTypes": [
            "traffic"
          ],
          "maximumBodyBytes": 8,
          "errorDomain": "NSURLErrorDomain",
          "errorMessage": "failed without a numeric code",
          "failurePhase": "response",
          "compatibilityDiagnostics": [
            "Update Rockxy"
          ],
          "urlSessionTiming": {
            "schemaVersion": 1,
            "taskDuration": 1.25,
            "redirectCount": 0,
            "reportedTransactionCount": 1,
            "omittedTransactionCount": 0,
            "transactions": [
              {
                "index": 0,
                "fetchDuration": 1.25,
                "dnsDuration": 0.01,
                "connectDuration": 0.02,
                "requestDuration": 0.03,
                "serverWaitDuration": 0.8,
                "responseTransferDuration": 0.39,
                "networkProtocolName": "h2",
                "reusedConnection": true,
                "proxyConnection": false,
                "resourceFetchType": "networkLoad"
              }
            ]
          },
          "bundleIdentifier": "com.example.fixture",
          "deviceName": "Fixture iPhone",
          "deviceModel": "iPhone",
          "supportedTrafficTypes": [
            "http",
            "grpc"
          ],
          "maximumWebSocketFrameBytes": 8,
          "maximumCaptureMemoryBytes": 512
        }
        """#
        transaction.babylonCaptureMetadata = try JSONDecoder().decode(
            BabylonCaptureMetadata.self,
            from: Data(metadata.utf8)
        )
        return transaction
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyCaptureEvidence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func execute(_ sql: String, in directory: URL) throws {
        var database: OpaquePointer?
        try #require(sqlite3_open(directory.appendingPathComponent("rockxy.sqlite3").path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }

    private func rowCount(in directory: URL) throws -> Int {
        var database: OpaquePointer?
        try #require(sqlite3_open(directory.appendingPathComponent("rockxy.sqlite3").path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(database, "SELECT count(*) FROM transactions", -1, &statement, nil) ==
            SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        try #require(sqlite3_step(statement) == SQLITE_ROW)
        return Int(sqlite3_column_int(statement, 0))
    }
}
