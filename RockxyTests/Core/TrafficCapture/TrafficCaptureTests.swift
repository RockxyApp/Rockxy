import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

// MARK: - ContinuationGate

private final class ContinuationGate: @unchecked Sendable {
    // MARK: Internal

    func tryOpen() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isOpen else {
            return false
        }

        isOpen = true
        return true
    }

    // MARK: Private

    private let lock = NSLock()
    private var isOpen = false
}

// Tests for `InMemorySessionBuffer`: append/retrieve, ordering, count, clear,
// capacity-based eviction, and unknown-ID lookup.

// MARK: - TrafficCaptureTests

struct TrafficCaptureTests {
    @Test("recording gate snapshots Pause and Resume synchronously")
    func recordingGateTransitions() {
        let gate = CaptureRecordingGate()
        #expect(gate.allowsCapture())

        gate.update(isRecording: false)
        #expect(!gate.allowsCapture())

        gate.update(isRecording: true)
        #expect(gate.allowsCapture())
    }

    @Test("InMemorySessionBuffer append and retrieve by id")
    func appendAndRetrieve() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)
        let transaction = TestFixtures.makeTransaction()

        await buffer.append(transaction)
        let retrieved = await buffer.transaction(for: transaction.id)

        #expect(retrieved?.id == transaction.id)
    }

    @Test("InMemorySessionBuffer allTransactions returns in order")
    func allTransactionsOrder() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)
        let t1 = TestFixtures.makeTransaction(url: "https://api.example.com/first")
        let t2 = TestFixtures.makeTransaction(url: "https://api.example.com/second")
        let t3 = TestFixtures.makeTransaction(url: "https://api.example.com/third")

        await buffer.append(t1)
        await buffer.append(t2)
        await buffer.append(t3)

        let all = await buffer.allTransactions()

        #expect(all.count == 3)
        #expect(all[0].id == t1.id)
        #expect(all[1].id == t2.id)
        #expect(all[2].id == t3.id)
    }

    @Test("InMemorySessionBuffer count property")
    func countProperty() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)

        let initialCount = await buffer.count
        #expect(initialCount == 0)

        await buffer.append(TestFixtures.makeTransaction())
        await buffer.append(TestFixtures.makeTransaction())

        let afterCount = await buffer.count
        #expect(afterCount == 2)
    }

    @Test("InMemorySessionBuffer clear removes all transactions")
    func clearRemovesAll() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)
        await buffer.append(TestFixtures.makeTransaction())
        await buffer.append(TestFixtures.makeTransaction())

        await buffer.clear()

        let count = await buffer.count
        #expect(count == 0)

        let all = await buffer.allTransactions()
        #expect(all.isEmpty)
    }

    @Test("InMemorySessionBuffer evicts when exceeding capacity")
    func evictionOnCapacityExceeded() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 10)

        for _ in 0 ..< 12 {
            await buffer.append(TestFixtures.makeTransaction())
        }

        let count = await buffer.count
        #expect(count <= 10)
    }

    @Test("InMemorySessionBuffer transaction(for:) returns nil for unknown id")
    func unknownIdReturnsNil() async {
        let buffer = InMemorySessionBuffer(maxCapacity: 100)
        await buffer.append(TestFixtures.makeTransaction())

        let result = await buffer.transaction(for: UUID())

        #expect(result == nil)
    }
}

// MARK: - TrafficSessionManagerTests

struct TrafficSessionManagerTests {
    @Test("onBatchReady callback receives transactions after setup")
    func batchCallbackReceivesTransactions() async {
        let manager = TrafficSessionManager()

        await manager.setOnBatchReady { _, _ in }
        await manager.setMaxBufferSize(50_000)

        let transaction = TestFixtures.makeTransaction()
        await manager.addTransaction(transaction)

        let flushed = await manager.flushPendingUpdates()
        #expect(flushed.count == 1)
        #expect(flushed[0].id == transaction.id)
    }

    @Test("A live WebSocket is appended once and its close is routed as an in-place update")
    func liveWebSocketCloseIsRoutedAsUpdate() async {
        let manager = TrafficSessionManager()
        let updates = UpdateRecorder()
        await manager.setOnBatchReady { _, _ in }
        await manager.setOnLiveTransactionUpdated { transactions in
            updates.record(transactions.map(\.id))
        }
        await manager.setMaxBufferSize(50_000)

        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let transaction = HTTPTransaction(
            request: request,
            state: .active,
            webSocketConnection: WebSocketConnection(upgradeRequest: request)
        )

        await manager.addTransaction(transaction)
        let opened = await manager.flushPendingUpdates()
        #expect(opened.map(\.id) == [transaction.id])
        #expect(updates.value.isEmpty)

        await MainActor.run { transaction.state = .completed }
        await manager.addTransaction(transaction)
        let afterClose = await manager.flushPendingUpdates()
        #expect(afterClose.isEmpty)
        #expect(updates.value == [[transaction.id]])

        // A re-delivery after the update path has retired the connection appends nothing new
        // and updates again, so a duplicate close can never create a second row.
        await manager.addTransaction(transaction)
        #expect(await manager.flushPendingUpdates().map(\.id) == [transaction.id])
    }

    @Test("Clear Session drops the close delivery of a WebSocket it already dismissed")
    func clearedLiveWebSocketDoesNotResurface() async {
        let manager = TrafficSessionManager()
        let updates = UpdateRecorder()
        await manager.setOnBatchReady { _, _ in }
        await manager.setOnLiveTransactionUpdated { transactions in
            updates.record(transactions.map(\.id))
        }
        await manager.setMaxBufferSize(50_000)

        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let transaction = HTTPTransaction(
            request: request,
            state: .active,
            webSocketConnection: WebSocketConnection(upgradeRequest: request)
        )
        await manager.addTransaction(transaction)
        _ = await manager.flushPendingUpdates()
        _ = await manager.beginNewSession()

        await MainActor.run { transaction.state = .completed }
        await manager.addTransaction(transaction)

        #expect(await manager.flushPendingUpdates().isEmpty)
        #expect(updates.value.isEmpty)
    }

    @Test("A streaming response is a live row that completes in place")
    func liveStreamingResponseCompletesInPlace() async {
        // An LLM completion can stream for 30 s. It is delivered as an `.active` row when its
        // head arrives and again at `.end`; the second delivery must update, not append.
        let manager = TrafficSessionManager()
        let updates = UpdateRecorder()
        await manager.setOnBatchReady { _, _ in }
        await manager.setOnLiveTransactionUpdated { transactions in
            updates.record(transactions.map(\.id))
        }
        await manager.setMaxBufferSize(50_000)

        let stream = HTTPTransaction(
            request: TestFixtures.makeRequest(method: "POST", url: "https://api.openai.com/v1/chat/completions"),
            response: TestFixtures.makeResponse(
                statusCode: 200,
                headers: [HTTPHeader(name: "Content-Type", value: "text/event-stream")]
            ),
            state: .active
        )
        await manager.addTransaction(stream)
        #expect(await manager.flushPendingUpdates().map(\.id) == [stream.id])

        let liveInspectionKey = stream.inspectionKey
        await MainActor.run { stream.state = .completed }
        // Inspectors re-analyse the completed body instead of keeping the live, empty one.
        #expect(stream.inspectionKey != liveInspectionKey)
        await manager.addTransaction(stream)
        #expect(await manager.flushPendingUpdates().isEmpty)
        #expect(updates.value == [[stream.id]])

        // An ordinary completed response is never tracked as live.
        let plain = TestFixtures.makeTransaction()
        await manager.addTransaction(plain)
        #expect(await manager.flushPendingUpdates().map(\.id) == [plain.id])
        #expect(updates.value == [[stream.id]])
    }

    @Test("A live row's close delivery arriving before its open delivery still yields one row")
    func reorderedLiveDeliveriesYieldOneRow() async {
        // The open and close deliveries travel through independent tasks. A short stream can
        // finish, and flip `state` to `.completed`, before the opening delivery is taken in.
        let manager = TrafficSessionManager()
        let updates = UpdateRecorder()
        await manager.setOnBatchReady { _, _ in }
        await manager.setOnLiveTransactionUpdated { transactions in
            updates.record(transactions.map(\.id))
        }
        await manager.setMaxBufferSize(50_000)

        let stream = HTTPTransaction(
            request: TestFixtures.makeRequest(method: "POST", url: "https://api.openai.com/v1/chat/completions"),
            response: TestFixtures.makeResponse(
                statusCode: 200,
                headers: [HTTPHeader(name: "Content-Type", value: "text/event-stream")]
            ),
            state: .active
        )
        await MainActor.run { stream.state = .completed }

        // Both deliveries now read `.completed`; only the first one adds a row.
        await manager.addTransaction(stream)
        await manager.addTransaction(stream)

        #expect(await manager.flushPendingUpdates().map(\.id) == [stream.id])
        #expect(updates.value == [[stream.id]])
    }

    @Test("Paused recording still finishes a live row but adds no new rows")
    func pausedRecordingFinishesLiveRows() async {
        let manager = TrafficSessionManager()
        let updates = UpdateRecorder()
        await manager.setOnBatchReady { _, _ in }
        await manager.setOnLiveTransactionUpdated { transactions in
            updates.record(transactions.map(\.id))
        }
        await manager.setMaxBufferSize(50_000)

        let request = TestFixtures.makeRequest(url: "ws://127.0.0.1/socket")
        let socket = HTTPTransaction(
            request: request,
            state: .active,
            webSocketConnection: WebSocketConnection(upgradeRequest: request)
        )
        await manager.addTransaction(socket)
        #expect(await manager.flushPendingUpdates().map(\.id) == [socket.id])

        // Recording is paused while the socket is open, then it closes.
        await MainActor.run { socket.state = .completed }
        await manager.addTransaction(socket, acceptsNewRows: false)
        #expect(await manager.flushPendingUpdates().isEmpty)
        #expect(updates.value == [[socket.id]])

        // New traffic during the pause is still dropped.
        await manager.addTransaction(TestFixtures.makeTransaction(), acceptsNewRows: false)
        #expect(await manager.flushPendingUpdates().isEmpty)
    }

    @Test("A stop burst coalesces live completions without losing paused rows")
    func liveCompletionBurstIsBatched() async {
        let manager = TrafficSessionManager()
        let updates = UpdateRecorder()
        await manager.setOnLiveTransactionUpdated { updates.record($0.map(\.id)) }
        let rows = (0 ..< 1_003).map { _ in TestFixtures.makeTransaction(state: .active) }
        for row in rows {
            await manager.addTransaction(row)
        }
        _ = await manager.flushPendingUpdates()
        await MainActor.run { rows.forEach { $0.state = .completed } }
        for row in rows {
            await manager.addTransaction(row, acceptsNewRows: false)
        }
        #expect(await manager.flushPendingUpdates().isEmpty)
        let batches = updates.value
        #expect(batches.count <= 21)
        #expect(batches.allSatisfy { $0.count <= 50 })
        #expect(batches.flatMap { $0 } == rows.map(\.id))
    }

    @Test("Session rollover discards queued completion refreshes", arguments: [false, true])
    func rolloverDiscardsQueuedCompletions(useRollover: Bool) async {
        let manager = TrafficSessionManager()
        let updates = UpdateRecorder()
        await manager.setOnLiveTransactionUpdated { updates.record($0.map(\.id)) }
        let row = TestFixtures.makeTransaction(state: .active)
        await manager.addTransaction(row)
        _ = await manager.flushPendingUpdates()
        await manager.addTransaction(row, acceptsNewRows: false)
        #expect(updates.value.isEmpty)
        if useRollover {
            _ = await manager.beginNewSessionPreservingPending()
        } else {
            await manager.resetBufferState()
        }
        #expect(await manager.flushPendingUpdates().isEmpty)
        #expect(updates.value.isEmpty)
    }

    @Test("A short stream publishes its opening batch before its completion refresh")
    func opensBeforeCompletionRefresh() async {
        let manager = TrafficSessionManager()
        let deliveries = UpdateRecorder()
        await manager.setOnBatchReady { batch, _ in deliveries.record(batch.map(\.id)) }
        await manager.setOnLiveTransactionUpdated { deliveries.record($0.map(\.id)) }
        let row = TestFixtures.makeTransaction(state: .active)
        await manager.addTransaction(row)
        await manager.addTransaction(row, acceptsNewRows: false)
        for _ in 0 ..< 49 {
            await manager.addTransaction(TestFixtures.makeTransaction())
        }
        #expect(deliveries.value.count == 2)
        #expect(deliveries.value.first?.count == 50)
        #expect(deliveries.value.first?.first == row.id)
        #expect(deliveries.value.last == [row.id])
    }

    @Test("The timer delivers a completion tail even without any new requests")
    func timerDeliversCompletionTail() async {
        let manager = TrafficSessionManager()
        let row = TestFixtures.makeTransaction(state: .active)
        await manager.addTransaction(row)
        _ = await manager.flushPendingUpdates()
        let gate = ContinuationGate()
        let delivered = await withCheckedContinuation { continuation in
            Task {
                await manager.setOnLiveTransactionUpdated { batch in
                    guard batch.map(\.id) == [row.id], gate.tryOpen() else {
                        return
                    }
                    continuation.resume(returning: true)
                }
                await manager.startBatchTimer()
                await manager.addTransaction(row, acceptsNewRows: false)
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                guard gate.tryOpen() else {
                    return
                }
                continuation.resume(returning: false)
            }
        }
        await manager.stopBatchTimer()
        #expect(delivered)
    }

    @Test("Only event streams and NDJSON get a live row")
    func streamingContentTypes() {
        func headers(_ value: String) -> HTTPHeaders {
            HTTPHeaders([("Content-Type", value)])
        }
        #expect(UpstreamResponseHandler.isStreamingResponse(headers("text/event-stream")))
        #expect(UpstreamResponseHandler.isStreamingResponse(headers("text/event-stream; charset=utf-8")))
        #expect(UpstreamResponseHandler.isStreamingResponse(headers("application/x-ndjson")))
        #expect(UpstreamResponseHandler.isStreamingResponse(headers("Application/NDJSON")))
        #expect(!UpstreamResponseHandler.isStreamingResponse(headers("application/json")))
        #expect(!UpstreamResponseHandler.isStreamingResponse(headers("text/plain")))
        #expect(!UpstreamResponseHandler.isStreamingResponse(HTTPHeaders()))
    }

    @Test("onBatchReady nil drops batch silently without crash")
    func nilCallbackDoesNotCrash() async {
        let manager = TrafficSessionManager()

        for _ in 0 ..< 51 {
            await manager.addTransaction(TestFixtures.makeTransaction())
        }
    }

    @Test("batch timer delivers transactions")
    func batchTimerDeliversTransactions() async {
        let manager = TrafficSessionManager()
        let gate = ContinuationGate()

        let delivered = await withCheckedContinuation { continuation in
            Task {
                await manager.setOnBatchReady { batch, _ in
                    guard !batch.isEmpty, gate.tryOpen() else {
                        return
                    }
                    continuation.resume(returning: true)
                }
                await manager.setMaxBufferSize(50_000)
                await manager.startBatchTimer()
                await manager.addTransaction(TestFixtures.makeTransaction())
            }

            Task {
                try? await Task.sleep(for: .seconds(5))
                guard gate.tryOpen() else {
                    return
                }
                continuation.resume(returning: false)
            }
        }

        await manager.stopBatchTimer()
        #expect(delivered == true)
    }
}

// MARK: - UpdateRecorder

private final class UpdateRecorder: @unchecked Sendable {
    // MARK: Internal

    var value: [[UUID]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ ids: [UUID]) {
        lock.lock()
        recorded.append(ids)
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var recorded: [[UUID]] = []
}
