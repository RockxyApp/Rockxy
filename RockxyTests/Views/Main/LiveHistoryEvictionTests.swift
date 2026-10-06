import Foundation
@testable import Rockxy
import Testing

// MARK: - LiveHistoryEvictionTests

/// The live history cap keeps capture bounded, but it must neither drop a connection that is
/// still open nor trim traffic the user opened from a file or received from a nearby device.
@MainActor
struct LiveHistoryEvictionTests {
    // MARK: Internal

    @Test("An open stream outlives finished requests captured after it")
    func openStreamSurvivesEviction() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 5
        let stream = TestFixtures.makeTransaction(url: "https://api.example.com/events", state: .active)
        coordinator.processActiveProjectTestBatch([stream])

        coordinator.processActiveProjectTestBatch(makeRequests(count: 10, host: "api.example.com"))

        #expect(coordinator.transactions.contains { $0.id == stream.id })
        #expect(coordinator.transactions.count <= 5)
    }

    @Test("Eviction still drops the oldest finished rows first")
    func oldestFinishedRowsGoFirst() {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 5
        let first = makeRequests(count: 5, host: "first.example.com")
        coordinator.processActiveProjectTestBatch(first)

        let second = makeRequests(count: 3, host: "second.example.com")
        coordinator.processActiveProjectTestBatch(second)

        #expect(!coordinator.transactions.contains { $0.id == first[0].id })
        #expect(second.allSatisfy { row in coordinator.transactions.contains { $0.id == row.id } })
    }

    @Test("A HAR import keeps every entry and live capture never trims it")
    func harImportIsNotTrimmed() async throws {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 5
        let url = try writeHAR(entryCount: 8)
        defer { try? FileManager.default.removeItem(at: url) }

        await coordinator.executeHARImport(from: url, fileName: url.lastPathComponent)
        #expect(coordinator.transactions.count == 8)
        #expect(coordinator.transactions.allSatisfy { $0.isImported })

        coordinator.processActiveProjectTestBatch(makeRequests(count: 7, host: "live.example.com"))

        #expect(coordinator.transactions.count { $0.isImported } == 8)
        #expect(coordinator.transactions.count { !$0.isImported } <= 5)
    }

    @Test("A session import keeps every transaction")
    func sessionImportIsNotTrimmed() async throws {
        let coordinator = MainContentCoordinator()
        coordinator.liveHistoryLimit = 5
        let saved = makeRequests(count: 9, host: "saved.example.com")
        let data = try SessionSerializer.serialize(
            transactions: saved,
            metadata: SessionMetadata(
                rockxyVersion: "test",
                formatVersion: SessionSerializer.currentFormatVersion,
                captureStartDate: nil,
                captureEndDate: nil,
                transactionCount: saved.count
            )
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-eviction-\(UUID().uuidString).rockxysession")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await coordinator.executeSessionImport(from: url, fileName: url.lastPathComponent)

        #expect(coordinator.transactions.count == 9)
    }

    @Test("Memory-pressure eviction prefers finished rows over open ones")
    func memoryPressureKeepsOpenRows() {
        let coordinator = MainContentCoordinator()
        let stream = TestFixtures.makeTransaction(url: "https://api.example.com/socket", state: .active)
        let finished = makeRequests(count: 3, host: "api.example.com")
        coordinator.processActiveProjectTestBatch([stream] + finished)

        coordinator.evictOldestTransactions(count: 2)

        #expect(coordinator.transactions.contains { $0.id == stream.id })
        #expect(coordinator.transactions.count == 2)
    }

    // MARK: Private

    private func makeRequests(count: Int, host: String) -> [HTTPTransaction] {
        (0 ..< count).map { TestFixtures.makeTransaction(url: "https://\(host)/item/\($0)") }
    }

    private func writeHAR(entryCount: Int) throws -> URL {
        let entries = (0 ..< entryCount).map { index -> [String: Any] in
            [
                "startedDateTime": "2026-10-06T10:00:0\(index % 10).000Z",
                "time": 12,
                "request": [
                    "method": "GET",
                    "url": "https://har.example.com/item/\(index)",
                    "httpVersion": "HTTP/1.1",
                    "headers": [],
                    "queryString": [],
                    "cookies": [],
                    "headersSize": -1,
                    "bodySize": 0,
                ],
                "response": [
                    "status": 200,
                    "statusText": "OK",
                    "httpVersion": "HTTP/1.1",
                    "headers": [],
                    "cookies": [],
                    "content": ["size": 0, "mimeType": "text/plain"],
                    "redirectURL": "",
                    "headersSize": -1,
                    "bodySize": 0,
                ],
                "cache": [:],
                "timings": ["send": 1, "wait": 10, "receive": 1],
            ]
        }
        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "RockxyTests", "version": "1"],
                "entries": entries,
            ],
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-eviction-\(UUID().uuidString).har")
        try JSONSerialization.data(withJSONObject: har).write(to: url)
        return url
    }
}
