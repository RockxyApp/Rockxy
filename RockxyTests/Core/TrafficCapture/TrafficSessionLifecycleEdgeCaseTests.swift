import Foundation
@testable import Rockxy
import Testing

// MARK: - TrafficSessionLifecycleEdgeCaseTests

struct TrafficSessionLifecycleEdgeCaseTests {
    @Test("Repeated terminal delivery never adds a live row twice")
    func repeatedCloseIsIdempotent() async {
        let manager = TrafficSessionManager()
        let row = TestFixtures.makeTransaction(state: .active)
        let events = CompletionEdgeRecorder()
        await manager.setOnBatchReady { batch, _ in events.record(batch.map(\.state)) }
        await manager.setOnLiveTransactionUpdated { events.record($0.map(\.state)) }
        await manager.addTransaction(row)
        #expect(await manager.flushPendingUpdates().map(\.id) == [row.id])
        await MainActor.run { row.state = .failed }
        for _ in 0 ..< 100 {
            await manager.addTransaction(row)
        }
        #expect(await manager.flushPendingUpdates().isEmpty)
        #expect(events.value == [[.failed]])
    }

    @Test("Repeated opening updates cannot retire a stream before its real close")
    func duplicateOpenStillReceivesClose() async {
        let manager = TrafficSessionManager()
        let row = TestFixtures.makeTransaction(state: .active)
        let events = CompletionEdgeRecorder()
        await manager.setOnLiveTransactionUpdated { events.record($0.map(\.state)) }
        await manager.addTransaction(row)
        _ = await manager.flushPendingUpdates()
        for _ in 0 ..< 100 {
            await manager.addTransaction(row)
        }
        #expect(await manager.flushPendingUpdates().isEmpty)
        #expect(events.value == [[.active]])
        await MainActor.run { row.state = .failed }
        await manager.addTransaction(row, acceptsNewRows: false)
        #expect(await manager.flushPendingUpdates().isEmpty)
        #expect(events.value == [[.active], [.failed]])
    }

    @Test("Clear with more than 4096 open streams retains bounded dismissal identities")
    func largeClearDoesNotResurrectStreams() async {
        let manager = TrafficSessionManager()
        await manager.setMaxBufferSize(5_000)
        let deliveries = CompletionEdgeRecorder()
        await manager.setOnBatchReady { batch, _ in deliveries.record(batch.map(\.state)) }
        await manager.setOnLiveTransactionUpdated { deliveries.record($0.map(\.state)) }
        let rows = (0 ..< 4_100).map { _ in TestFixtures.makeTransaction(state: .active) }
        for row in rows {
            await manager.addTransaction(row)
        }
        _ = await manager.flushPendingUpdates()
        let openingBatchCount = deliveries.value.count
        _ = await manager.beginNewSession()
        await MainActor.run { rows.forEach { $0.state = .completed } }
        for _ in 0 ..< 2 {
            for row in rows {
                await manager.addTransaction(row)
            }
        }
        #expect(await manager.flushPendingUpdates().isEmpty)
        #expect(deliveries.value.count == openingBatchCount)
    }

    @Test("Project clear retains other streams and newly stamped target streams", arguments: [false, true])
    func scopedClearPreservesLiveOwnership(closeBeforeClear: Bool) async {
        let manager = TrafficSessionManager()
        let project = UUID()
        let session = UUID()
        let old = TrafficCaptureContext(projectID: project, sessionID: session, generation: 0)
        let next = TrafficCaptureContext(projectID: project, sessionID: session, generation: 1)
        let other = TrafficCaptureContext(projectID: UUID(), sessionID: UUID(), generation: 0)
        let contexts = [old, next, other]
        let rows = contexts.map { context in
            let row = TestFixtures.makeTransaction(state: .active)
            row.assignCaptureContextIfMissing(context)
            return row
        }
        let updates = CompletionIdentityRecorder()
        await manager.setOnLiveTransactionUpdated { updates.record($0.map(\.id)) }
        for row in rows {
            await manager.addTransaction(row)
        }
        _ = await manager.flushPendingUpdates()
        await MainActor.run { rows.forEach { $0.state = .failed } }
        if closeBeforeClear {
            for row in rows {
                await manager.addTransaction(row)
            }
        }
        _ = await manager.beginNewSessionPreservingPending(clearingProjectInto: next)
        if !closeBeforeClear {
            for row in rows {
                await manager.addTransaction(row, acceptsNewRows: false)
            }
        }
        #expect(await manager.flushPendingUpdates().isEmpty)
        #expect(Set(updates.value) == Set(rows.dropFirst().map(\.id)))
    }

    @Test("Identity windows remain bounded through long sessions and capacity changes")
    func identityWindowRemainsBounded() {
        var window = RecentLiveTransactionIDs(capacity: 100)
        let first = UUID()
        window.insert(first)
        var latest = first
        var peakCount = 0
        for _ in 0 ..< 20_000 {
            latest = UUID()
            window.insert(latest)
            peakCount = max(peakCount, window.count)
        }
        #expect(peakCount == 100)
        #expect(!window.contains(first))
        #expect(window.contains(latest))
        window.setCapacity(1)
        #expect(window.count == 1)
        #expect(window.contains(latest))
        window.insert(latest)
        #expect(window.count == 1)
        window.setCapacity(0)
        window.insert(UUID())
        #expect(window.count == 1)
    }
}

// MARK: - CompletionEdgeRecorder

private final class CompletionEdgeRecorder: @unchecked Sendable {
    // MARK: Internal

    var value: [[TransactionState]] {
        lock.withLock { values }
    }

    func record(_ states: [TransactionState]) {
        lock.withLock { values.append(states) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var values: [[TransactionState]] = []
}

// MARK: - CompletionIdentityRecorder

private final class CompletionIdentityRecorder: @unchecked Sendable {
    // MARK: Internal

    var value: [UUID] {
        lock.withLock { identities }
    }

    func record(_ ids: [UUID]) {
        lock.withLock { identities.append(contentsOf: ids) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var identities: [UUID] = []
}
