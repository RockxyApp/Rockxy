import Foundation
@testable import Rockxy
import Testing

// Regression tests for `SessionSerializer` in the core plugins layer.

// MARK: - SessionSerializerTests

struct SessionSerializerTests {
    // MARK: - Round-Trip

    @Test("Round-trip preserves transaction count")
    func roundTripTransactionCount() throws {
        let transactions = TestFixtures.makeBulkTransactions(count: 5)
        let metadata = SessionSerializer.makeMetadata(transactionCount: transactions.count)
        let data = try SessionSerializer.serialize(transactions: transactions, metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)
        #expect(session.transactions.count == 5)
    }

    @Test("Round-trip preserves request fields")
    func roundTripRequestFields() throws {
        let transaction = TestFixtures.makeTransaction(method: "POST", url: "https://example.com/api")
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.request.method == "POST")
        #expect(restored.request.url.absoluteString == "https://example.com/api")
        #expect(restored.request.httpVersion == "HTTP/1.1")
        #expect(!restored.request.headers.isEmpty)
    }

    @Test("Round-trip preserves response fields")
    func roundTripResponseFields() throws {
        let transaction = TestFixtures.makeTransaction(statusCode: 404)
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.response?.statusCode == 404)
        #expect(restored.response?.statusMessage == "Error")
    }

    @Test("Round-trip preserves timing info")
    func roundTripTimingInfo() throws {
        let transaction = TestFixtures.makeTransactionWithTiming(
            dns: 0.01, tcp: 0.02, tls: 0.03, ttfb: 0.1, transfer: 0.05
        )
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let timing = session.transactions[0].toLiveModel().timingInfo
        #expect(timing?.dnsLookup == 0.01)
        #expect(timing?.tcpConnection == 0.02)
        #expect(timing?.tlsHandshake == 0.03)
        #expect(timing?.timeToFirstByte == 0.1)
        #expect(timing?.contentTransfer == 0.05)
    }

    @Test("Round-trip preserves WebSocket frames")
    func roundTripWebSocket() throws {
        let transaction = TestFixtures.makeWebSocketTransaction()
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.webSocketConnection != nil)
        #expect(restored.webSocketConnection?.frames.count == 5)
    }

    @Test("Round-trip preserves WebSocket binary frames")
    func roundTripWebSocketBinary() throws {
        let request = TestFixtures.makeRequest(url: "wss://binary.example.com/ws")
        let connection = WebSocketConnection(upgradeRequest: request)
        connection.addFrame(WebSocketFrameData(
            direction: .received,
            opcode: .binary,
            payload: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ))
        let transaction = HTTPTransaction(
            request: request, state: .completed, webSocketConnection: connection
        )
        transaction.response = TestFixtures.makeResponse(statusCode: 101)

        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.webSocketConnection?.frames.count == 1)
        #expect(restored.webSocketConnection?.frames[0].opcode == .binary)
        #expect(restored.webSocketConnection?.frames[0].payload == Data([
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A
        ]))
    }

    @Test("Round-trip preserves WebSocket with zero frames")
    func roundTripWebSocketEmpty() throws {
        let request = TestFixtures.makeRequest(url: "wss://empty.example.com/ws")
        let connection = WebSocketConnection(upgradeRequest: request)
        let transaction = HTTPTransaction(
            request: request, state: .completed, webSocketConnection: connection
        )
        transaction.response = TestFixtures.makeResponse(statusCode: 101)

        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.webSocketConnection != nil)
        #expect(restored.webSocketConnection?.frames.isEmpty == true)
    }

    @Test("Round-trip preserves GraphQL info")
    func roundTripGraphQL() throws {
        let transaction = TestFixtures.makeGraphQLTransaction(
            operationName: "FetchUsers",
            operationType: .query,
            query: "{ users { id } }"
        )
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let gql = session.transactions[0].toLiveModel().graphQLInfo
        #expect(gql?.operationName == "FetchUsers")
        #expect(gql?.operationType == .query)
        #expect(gql?.query == "{ users { id } }")
    }

    @Test("Round-trip preserves log entries")
    func roundTripLogEntries() throws {
        let transactions = [TestFixtures.makeTransaction()]
        let logEntries = [
            TestFixtures.makeLogEntry(level: .error, message: "Connection refused"),
            TestFixtures.makeLogEntry(level: .debug, message: "Request sent")
        ]
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(
            transactions: transactions, logEntries: logEntries, metadata: metadata
        )
        let session = try SessionSerializer.deserialize(from: data)

        #expect(session.logEntries?.count == 2)
        let restored = session.logEntries?.map { $0.toLiveModel() }
        #expect(restored?[0].level == .error)
        #expect(restored?[0].message == "Connection refused")
        #expect(restored?[1].level == .debug)
    }

    @Test("Format version is present in metadata")
    func formatVersionPresent() throws {
        let metadata = SessionSerializer.makeMetadata(transactionCount: 0)
        let data = try SessionSerializer.serialize(transactions: [], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)
        #expect(session.metadata.formatVersion == 1)
    }

    @Test("Large body base64 encoding survives round-trip")
    func largeBodyRoundTrip() throws {
        let bodyData = Data(repeating: 0xAB, count: 1_024 * 512) // 512 KB
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(statusCode: 200, body: bodyData)
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.response?.body == bodyData)
    }

    @Test("Unsupported format version throws error")
    func unsupportedVersion() throws {
        let metadata = SessionMetadata(
            rockxyVersion: "99.0",
            formatVersion: 999,
            captureStartDate: nil,
            captureEndDate: nil,
            transactionCount: 0
        )
        let session = CodableSession(metadata: metadata, transactions: [], logEntries: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        #expect(throws: SessionSerializerError.self) {
            try SessionSerializer.deserialize(from: data)
        }
    }

    // MARK: - Annotation Preservation

    @Test("Round-trip preserves comment")
    func roundTripPreservesComment() throws {
        let transaction = TestFixtures.makeTransaction()
        transaction.comment = "User note"
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.comment == "User note")
    }

    @Test("Round-trip preserves highlight color")
    func roundTripPreservesHighlightColor() throws {
        let transaction = TestFixtures.makeTransaction()
        transaction.highlightColor = .purple
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.highlightColor == .purple)
    }

    @Test("Round-trip preserves isPinned")
    func roundTripPreservesIsPinned() throws {
        let transaction = TestFixtures.makeTransaction()
        transaction.isPinned = true
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.isPinned == true)
    }

    @Test("Round-trip preserves isSaved")
    func roundTripPreservesIsSaved() throws {
        let transaction = TestFixtures.makeTransaction()
        transaction.isSaved = true
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.isSaved == true)
    }

    @Test("Round-trip preserves isTLSFailure")
    func roundTripPreservesIsTLSFailure() throws {
        let transaction = TestFixtures.makeTransaction()
        transaction.isTLSFailure = true
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.isTLSFailure == true)
    }

    @Test("Round-trip preserves all annotations together")
    func roundTripPreservesAllAnnotationsTogether() throws {
        let transaction = TestFixtures.makeAnnotatedTransaction(
            comment: "Important request",
            highlightColor: .red,
            isPinned: true,
            isSaved: true,
            isTLSFailure: true
        )
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.comment == "Important request")
        #expect(restored.highlightColor == .red)
        #expect(restored.isPinned == true)
        #expect(restored.isSaved == true)
        #expect(restored.isTLSFailure == true)
    }

    @Test("Round-trip preserves mixed annotations across transactions")
    func roundTripPreservesMixedAnnotations() throws {
        let tx1 = TestFixtures.makeAnnotatedTransaction(
            comment: "First", highlightColor: .blue, isPinned: true, isSaved: false, isTLSFailure: false
        )
        let tx2 = TestFixtures.makeAnnotatedTransaction(
            comment: nil, highlightColor: .green, isPinned: false, isSaved: true, isTLSFailure: false
        )
        let tx3 = TestFixtures.makeAnnotatedTransaction(
            comment: "Third", highlightColor: nil, isPinned: false, isSaved: false, isTLSFailure: true
        )
        let metadata = SessionSerializer.makeMetadata(transactionCount: 3)
        let data = try SessionSerializer.serialize(
            transactions: [tx1, tx2, tx3], metadata: metadata
        )
        let session = try SessionSerializer.deserialize(from: data)

        let r1 = session.transactions[0].toLiveModel()
        #expect(r1.comment == "First")
        #expect(r1.highlightColor == .blue)
        #expect(r1.isPinned == true)
        #expect(r1.isSaved == false)

        let r2 = session.transactions[1].toLiveModel()
        #expect(r2.comment == nil)
        #expect(r2.highlightColor == .green)
        #expect(r2.isSaved == true)

        let r3 = session.transactions[2].toLiveModel()
        #expect(r3.comment == "Third")
        #expect(r3.highlightColor == nil)
        #expect(r3.isTLSFailure == true)
    }

    @Test("Round-trip preserves all annotations as nil/false defaults")
    func roundTripPreservesAllAnnotationsNil() throws {
        let transaction = TestFixtures.makeTransaction()
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.comment == nil)
        #expect(restored.highlightColor == nil)
        #expect(restored.isPinned == false)
        #expect(restored.isSaved == false)
        #expect(restored.isTLSFailure == false)
    }

    @Test("Deserializes v1 file without annotation fields using defaults")
    func deserializesV1FileWithoutAnnotationFields() throws {
        let transaction = TestFixtures.makeTransaction()
        let codableTx = CodableTransaction(from: transaction)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let txData = try encoder.encode(codableTx)
        var txDict = try #require(
            try JSONSerialization.jsonObject(with: txData) as? [String: Any]
        )

        txDict.removeValue(forKey: "comment")
        txDict.removeValue(forKey: "highlightColor")
        txDict.removeValue(forKey: "isPinned")
        txDict.removeValue(forKey: "isSaved")
        txDict.removeValue(forKey: "isTLSFailure")

        let sessionDict: [String: Any] = [
            "metadata": [
                "rockxyVersion": "1.0",
                "formatVersion": 1,
                "transactionCount": 1
            ] as [String: Any],
            "transactions": [txDict]
        ]
        let sessionData = try JSONSerialization.data(withJSONObject: sessionDict)
        let session = try SessionSerializer.deserialize(from: sessionData)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.comment == nil)
        #expect(restored.highlightColor == nil)
        #expect(restored.isPinned == false)
        #expect(restored.isSaved == false)
        #expect(restored.isTLSFailure == false)
    }

    @Test("Metadata contains correct format version")
    func metadataContainsCorrectFormatVersion() throws {
        let metadata = SessionSerializer.makeMetadata(transactionCount: 0)
        let data = try SessionSerializer.serialize(transactions: [], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)
        #expect(session.metadata.formatVersion == SessionSerializer.currentFormatVersion)
    }

    // MARK: - Matched Rule Metadata

    @Test("Round-trip preserves matched rule metadata")
    func roundTripPreservesMatchedRuleMetadata() throws {
        let transaction = TestFixtures.makeTransaction()
        let ruleID = UUID()
        transaction.matchedRuleID = ruleID
        transaction.matchedRuleName = "Block Ads"
        transaction.matchedRuleActionSummary = "block(403)"
        transaction.matchedRulePattern = ".*ads\\.example\\.com.*"

        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.matchedRuleID == ruleID)
        #expect(restored.matchedRuleName == "Block Ads")
        #expect(restored.matchedRuleActionSummary == "block(403)")
        #expect(restored.matchedRulePattern == ".*ads\\.example\\.com.*")
    }

    @Test("Round-trip preserves nil matched rule metadata")
    func roundTripPreservesNilMatchedRuleMetadata() throws {
        let transaction = TestFixtures.makeTransaction()
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)
        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let session = try SessionSerializer.deserialize(from: data)

        let restored = session.transactions[0].toLiveModel()
        #expect(restored.matchedRuleID == nil)
        #expect(restored.matchedRuleName == nil)
        #expect(restored.matchedRuleActionSummary == nil)
        #expect(restored.matchedRulePattern == nil)
    }
}
