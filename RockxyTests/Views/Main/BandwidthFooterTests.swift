import Foundation
@testable import Rockxy
import Testing

// Regression tests for `BandwidthFooter` in the views main layer.

// MARK: - BandwidthFooterTests

@MainActor
struct BandwidthFooterTests {
    // MARK: Internal

    // MARK: - recordTrafficMetrics

    @Test("recordTrafficMetrics updates totalDataSize from request and response bodies")
    func recordUpdatesTotal() {
        let coordinator = makeCoordinator()
        let tx = makeTransactionWithBodies(requestSize: 100, responseSize: 500)

        coordinator.recordTrafficMetrics(for: [tx])

        #expect(coordinator.totalUploadBytes == 100)
        #expect(coordinator.totalDownloadBytes == 500)
        #expect(coordinator.totalDataSize == 600)
    }

    @Test("recordTrafficMetrics accumulates across multiple batches")
    func recordAccumulates() {
        let coordinator = makeCoordinator()
        let tx1 = makeTransactionWithBodies(requestSize: 100, responseSize: 200)
        let tx2 = makeTransactionWithBodies(requestSize: 50, responseSize: 300)

        let now = Date()
        coordinator.recordTrafficMetrics(for: [tx1], at: now)
        coordinator.recordTrafficMetrics(for: [tx2], at: now.addingTimeInterval(0.1))

        #expect(coordinator.totalUploadBytes == 150)
        #expect(coordinator.totalDownloadBytes == 500)
        #expect(coordinator.totalDataSize == 650)
    }

    // MARK: - extractBytes

    @Test("extractBytes counts request body as upload")
    func extractBytesUpload() {
        let tx = makeTransactionWithBodies(requestSize: 256, responseSize: 0)
        let bytes = MainContentCoordinator.extractBytes(from: tx)

        #expect(bytes.upload == 256)
        #expect(bytes.download == 0)
    }

    @Test("extractBytes counts response body as download")
    func extractBytesDownload() {
        let tx = makeTransactionWithBodies(requestSize: 0, responseSize: 1_024)
        let bytes = MainContentCoordinator.extractBytes(from: tx)

        #expect(bytes.upload == 0)
        #expect(bytes.download == 1_024)
    }

    @Test("extractBytes includes WebSocket frame sizes by direction")
    func extractBytesWebSocket() {
        let tx = TestFixtures.makeWebSocketTransaction()
        let bytes = MainContentCoordinator.extractBytes(from: tx)

        // makeWebSocketTransaction creates 5 frames: indices 0,2,4 sent; 1,3 received
        // Each frame payload is "Frame N" — 7 bytes each
        let sentCount = 3
        let receivedCount = 2
        let frameSize = Int64(7) // "Frame X".count

        #expect(bytes.upload == Int64(sentCount) * frameSize)
        #expect(bytes.download == Int64(receivedCount) * frameSize)
    }

    // MARK: - resetTrafficMetrics

    @Test("resetTrafficMetrics zeroes everything")
    func resetZeroesAll() {
        let coordinator = makeCoordinator()
        let tx = makeTransactionWithBodies(requestSize: 100, responseSize: 200)
        coordinator.recordTrafficMetrics(for: [tx])

        coordinator.resetTrafficMetrics()

        #expect(coordinator.totalUploadBytes == 0)
        #expect(coordinator.totalDownloadBytes == 0)
        #expect(coordinator.totalDataSize == 0)
        #expect(coordinator.uploadSpeed == 0)
        #expect(coordinator.downloadSpeed == 0)
        #expect(coordinator.trafficSamples.isEmpty)
    }

    // MARK: - resetInstantaneousSpeeds

    @Test("resetInstantaneousSpeeds zeroes speeds but keeps totals")
    func resetSpeedsKeepsTotals() {
        let coordinator = makeCoordinator()
        let tx = makeTransactionWithBodies(requestSize: 100, responseSize: 200)
        coordinator.recordTrafficMetrics(for: [tx])

        coordinator.resetInstantaneousSpeeds()

        #expect(coordinator.uploadSpeed == 0)
        #expect(coordinator.downloadSpeed == 0)
        #expect(coordinator.trafficSamples.isEmpty)
        #expect(coordinator.totalUploadBytes == 100)
        #expect(coordinator.totalDownloadBytes == 200)
        #expect(coordinator.totalDataSize == 300)
    }

    // MARK: - Speed Not Inflated

    @Test("Speed equals batch bytes, not inflated by small duration")
    func speedNotInflated() {
        let coordinator = makeCoordinator()
        let tx = makeTransactionWithBodies(requestSize: 100, responseSize: 200)
        let now = Date()

        coordinator.recordTrafficMetrics(for: [tx], at: now)

        // Speed should be 100 B/s upload and 200 B/s download (1s window),
        // NOT 100000 / 200000 (which would happen with 0.001s division)
        #expect(coordinator.uploadSpeed == 100)
        #expect(coordinator.downloadSpeed == 200)
    }

    // MARK: - Speed Decay

    @Test("recomputeInstantaneousSpeeds with stale samples decays to zero")
    func speedsDecayToZero() {
        let coordinator = makeCoordinator()
        let tx = makeTransactionWithBodies(requestSize: 1_000, responseSize: 2_000)

        let pastTime = Date().addingTimeInterval(-5.0)
        coordinator.recordTrafficMetrics(for: [tx], at: pastTime)

        // Recompute at "now" — samples are >1s old, should be pruned
        coordinator.recomputeInstantaneousSpeeds(now: Date())

        #expect(coordinator.uploadSpeed == 0)
        #expect(coordinator.downloadSpeed == 0)
    }

    // MARK: - Empty Batch

    @Test("Empty batch does not inflate metrics")
    func emptyBatchNoEffect() {
        let coordinator = makeCoordinator()
        coordinator.recordTrafficMetrics(for: [])

        #expect(coordinator.totalUploadBytes == 0)
        #expect(coordinator.totalDownloadBytes == 0)
        #expect(coordinator.totalDataSize == 0)
        #expect(coordinator.trafficSamples.isEmpty)
    }

    // MARK: - rebuildTrafficTotals

    @Test("rebuildTrafficTotals recomputes from transaction array")
    func rebuildFromTransactions() {
        let coordinator = makeCoordinator()
        let tx1 = makeTransactionWithBodies(requestSize: 100, responseSize: 200)
        let tx2 = makeTransactionWithBodies(requestSize: 50, responseSize: 150)

        coordinator.rebuildTrafficTotals(from: [tx1, tx2])

        #expect(coordinator.totalUploadBytes == 150)
        #expect(coordinator.totalDownloadBytes == 350)
        #expect(coordinator.totalDataSize == 500)
    }

    // MARK: Private

    // MARK: - Setup

    private func makeCoordinator() -> MainContentCoordinator {
        MainContentCoordinator()
    }

    private func makeTransactionWithBodies(
        requestSize: Int,
        responseSize: Int
    )
        -> HTTPTransaction
    {
        let requestBody = Data(repeating: 0xAA, count: requestSize)
        let responseBody = Data(repeating: 0xBB, count: responseSize)

        let request = HTTPRequestData(
            method: "POST",
            url: URL(string: "https://api.example.com/data")!,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/octet-stream")],
            body: requestBody
        )
        let transaction = HTTPTransaction(request: request, state: .completed)
        transaction.response = TestFixtures.makeResponse(statusCode: 200, body: responseBody)
        return transaction
    }
}
