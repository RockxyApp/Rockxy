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
        "Corrupt or newer saved capture evidence drops the evidence, never the saved request",
        arguments: [0, 1, 2, 3]
    )
    func corruptEvidenceIsIsolated(variant: Int) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transaction = try makeCapturedTransaction()
        transaction.isPinned = true
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
        let restored = try #require(try await store.loadTransaction(byID: transaction.id))
        #expect(restored.isPinned)
        #expect(restored.request.url == transaction.request.url)
        #expect(restored.request.body == Data("partial".utf8))
        #expect(restored.babylonCaptureMetadata == nil)
        #expect(restored.babylonCorrelation == nil)
        // Completeness is unknown, so neither body may read as complete.
        #expect(restored.request.bodyTruncated)
        #expect(restored.request.bodyOmission?.reason == SessionStore.unreadableEvidenceOmissionReason)
        #expect(restored.request.bodyOmission?.originalBytes == nil)
        #expect(restored.response?.bodyTruncated == true)
        #expect(restored.response?.bodyOmission?.reason == SessionStore.unreadableEvidenceOmissionReason)
        #expect(try await store.loadPinnedAndSavedTransactions().map(\.id) == [transaction.id])
        #expect(Set(try await store.loadTransactions().map(\.id)) == [transaction.id, healthy.id])
        // Reading never deletes or rewrites the row.
        #expect(try rowCount(in: directory) == 2)
    }

    @Test("A healthy request without any evidence is not flagged, and unreadable evidence is exported as truncated")
    func unreadableEvidenceIsNotReportedComplete() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plain = TestFixtures.makeTransaction()
        let damaged = TestFixtures.makeTransaction()
        damaged.request.body = Data("complete?".utf8)
        let store = try SessionStore(directory: directory)
        try await store.saveTransaction(plain)
        try await store.saveTransaction(damaged)
        try execute(
            "UPDATE transactions SET capture_evidence = X'7B' WHERE id = '\(damaged.id.uuidString)'",
            in: directory
        )
        let restoredPlain = try #require(try await store.loadTransaction(byID: plain.id))
        #expect(!restoredPlain.request.bodyTruncated)
        #expect(restoredPlain.request.bodyOmission == nil)
        let restored = try #require(try await store.loadTransaction(byID: damaged.id))
        #expect(restored.request.body == Data("complete?".utf8))
        #expect(restored.request.bodyTruncated)
        #expect(restored.request.bodyOmission?.observedBytes == 9)
    }

    @Test("Stored 257-512 byte identifiers saved by earlier builds still load with their request intact")
    func legacyLongIdentifiersStillLoad() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Ingress is 256; storage is frozen at 512 so lowering ingress cannot erase saved rows.
        #expect(BabylonCaptureProtocol.maximumClientIDSize == 256)
        #expect(BabylonCaptureProtocol.maximumStoredIdentifierSize == 512)
        let long = String(repeating: "L", count: 400)
        let atStoredLimit = String(repeating: "M", count: BabylonCaptureProtocol.maximumStoredIdentifierSize)

        let transaction = try makeCapturedTransaction()
        transaction.isSaved = true
        transaction.babylonCorrelation = .init(
            sourceClientID: long,
            sessionID: atStoredLimit,
            traceID: long,
            stepID: long
        )
        let metadataJSON = Data(#"{"clientID":"\#(long)","traceID":"\#(long)","runtimeSessionID":"\#(long)"}"#.utf8)
        transaction.babylonCaptureMetadata = try JSONDecoder().decode(BabylonCaptureMetadata.self, from: metadataJSON)
        let store = try SessionStore(directory: directory)
        try await store.saveTransaction(transaction)

        let reopened = try SessionStore(directory: directory)
        let restored = try #require(try await reopened.loadPinnedAndSavedTransactions().first)
        #expect(restored.id == transaction.id)
        #expect(restored.babylonCorrelation == transaction.babylonCorrelation)
        #expect(restored.babylonCaptureMetadata?.clientID == long)
        #expect(restored.request.bodyTruncated)

        // Ingress still refuses a new identifier over 256 bytes.
        let context = BabylonTrafficPackageDTO.CorrelationContext(
            sessionID: "s", traceID: "t", stepID: "a", createdAt: 1
        )
        #expect(BabylonCorrelation(context: context, sourceClientID: long) == nil)
    }

    @Test("A pin on a request imported with over-long evidence persists instead of failing")
    func pinOnImportedOverLongEvidencePersists() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeCapturedTransaction()
        var json = try #require(
            JSONSerialization
                .jsonObject(with: JSONEncoder().encode(CodableTransaction(from: source))) as? [String: Any]
        )
        json["babylonGRPCCallType"] = String(repeating: "g", count: 129)
        json["babylonCorrelation"] = [
            "sessionID": "runtime",
            "traceID": String(repeating: "t", count: BabylonCaptureProtocol.maximumStoredIdentifierSize + 1),
        ]
        let imported = try JSONDecoder()
            .decode(CodableTransaction.self, from: JSONSerialization.data(withJSONObject: json))
            .toLiveModel()
        imported.isPinned = true

        let store = try SessionStore(directory: directory)
        try await store.saveTransaction(imported)
        let favorites = try await SessionStore(directory: directory).loadPinnedAndSavedTransactions()
        #expect(favorites.contains { $0.id == source.id })
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
