import Foundation
@testable import Rockxy
import Testing

// MARK: - BoolBox

private final class BoolBox: @unchecked Sendable {
    // MARK: Internal

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func setTrue() {
        lock.lock()
        _value = true
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var _value = false
}

// MARK: - HistoryRetentionTests

@Suite(.serialized)
struct HistoryRetentionTests {
    @Test("Live buffer caps at policy limit during capture")
    @MainActor
    func bufferCapDuringCapture() {
        let policy = SmallHistoryPolicy()
        let coordinator = MainContentCoordinator(policy: policy)
        coordinator.isRecording = true

        for i in 0 ..< 15 {
            let tx = TestFixtures.makeTransaction(url: "https://example.com/\(i)")
            coordinator.transactions.append(tx)
        }

        // Simulate the post-batch cap check
        if coordinator.transactions.count > policy.maxLiveHistoryEntries {
            let overflow = coordinator.transactions.count - policy.maxLiveHistoryEntries
            coordinator.evictOldestTransactions(count: overflow)
        }

        #expect(coordinator.transactions.count == policy.maxLiveHistoryEntries)
    }

    @Test("Default policy has 1000 live history entries")
    func defaultPolicyValue() {
        let policy = DefaultAppPolicy()
        #expect(policy.maxLiveHistoryEntries == 1_000)
    }

    @Test("Eviction path does not initialize SessionStore")
    @MainActor
    func evictionPathDoesNotInitializeSessionStore() {
        let policy = SmallHistoryPolicy()
        let coordinator = MainContentCoordinator(policy: policy)

        for i in 0 ..< 15 {
            let tx = TestFixtures.makeTransaction(url: "https://example.com/evict-\(i)")
            coordinator.transactions.append(tx)
        }

        let overflow = coordinator.transactions.count - policy.maxLiveHistoryEntries
        coordinator.evictOldestTransactions(count: overflow)

        #expect(coordinator.transactions.count == policy.maxLiveHistoryEntries)
        #expect(coordinator.cachedSessionStore == nil)
    }

    @Test("reportAcceptedCount triggers eviction sized to the exact overflow")
    @MainActor
    func reportAcceptedCountTriggersEviction() async {
        let manager = TrafficSessionManager()
        await manager.setMaxBufferSize(20)

        var evictionCount: Int?
        let observer = NotificationCenter.default.addObserver(
            forName: .bufferEvictionRequested, object: nil, queue: .main
        ) { notification in
            evictionCount = notification.userInfo?["count"] as? Int
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Report 25 accepted transactions — exceeds maxBufferSize (20) by 5
        let gen = await manager.currentGeneration
        await manager.reportAcceptedCount(25, generation: gen)

        try? await Task.sleep(for: .milliseconds(100))

        #expect(evictionCount == 5)
    }

    @Test("Small buffer overflow evicts exact overflow count")
    @MainActor
    func smallBufferEvictsExactOverflow() async {
        let manager = TrafficSessionManager()
        await manager.setMaxBufferSize(5)

        var evictionCount: Int?
        let observer = NotificationCenter.default.addObserver(
            forName: .bufferEvictionRequested, object: nil, queue: .main
        ) { notification in
            evictionCount = notification.userInfo?["count"] as? Int
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Report 10 accepted — exceeds maxBufferSize (5) by 5
        let gen = await manager.currentGeneration
        await manager.reportAcceptedCount(10, generation: gen)

        try? await Task.sleep(for: .milliseconds(100))

        #expect(evictionCount == 5)
    }

    @Test("Live history stays capped without double-trim drift")
    @MainActor
    func liveHistoryCapAlignsWithActorAccounting() async {
        let coordinator = MainContentCoordinator(policy: SmallHistoryPolicy())
        coordinator.isRecording = true
        let retainedCount = SmallHistoryPolicy().maxLiveHistoryEntries

        await coordinator.sessionManager.setOnBatchReady { [weak coordinator] batch, generation in
            guard let coordinator else {
                return
            }
            Task { @MainActor in
                coordinator.processBatch(batch, generation: generation)
            }
        }
        await coordinator.sessionManager.setMaxBufferSize(retainedCount)

        let evictionObserver = NotificationCenter.default.addObserver(
            forName: .bufferEvictionRequested, object: nil, queue: .main
        ) { [weak coordinator] notification in
            guard let coordinator else {
                return
            }
            let count = notification.userInfo?["count"] as? Int ?? 0
            Task { @MainActor in
                coordinator.evictOldestTransactions(count: count)
            }
        }
        defer { NotificationCenter.default.removeObserver(evictionObserver) }

        for index in 0 ..< 50 {
            await coordinator.sessionManager.addTransaction(
                TestFixtures.makeTransaction(url: "https://drift-check.com/\(index)")
            )
        }

        for _ in 0 ..< 500 {
            if coordinator.transactions.count == retainedCount {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.transactions.count == retainedCount)
    }

    @Test("Overlapping clearSession attempts are safely coalesced")
    @MainActor
    func overlappingClearSessionCoalesced() async {
        let coordinator = MainContentCoordinator(policy: SmallHistoryPolicy())
        coordinator.isRecording = true

        for index in 0 ..< 3 {
            coordinator.transactions.append(
                TestFixtures.makeTransaction(url: "https://reentry.com/\(index)")
            )
        }
        let preClearGen = coordinator.sessionGeneration

        async let first: Void = coordinator.clearSession()
        async let second: Void = coordinator.clearSession()
        _ = await (first, second)

        // Exactly one clear succeeded; the other returned early without bumping generation again.
        #expect(coordinator.sessionGeneration == preClearGen &+ 1)
        #expect(coordinator.transactions.isEmpty)

        let actorGen = await coordinator.sessionManager.currentGeneration
        #expect(actorGen == coordinator.sessionGeneration)
    }

    @Test("Paused recording does not consume live-history budget")
    @MainActor
    func pausedRecordingDoesNotConsumeBuffer() async {
        let manager = TrafficSessionManager()
        await manager.setMaxBufferSize(20)

        let batchDelivered = BoolBox()
        await manager.setOnBatchReady { _, _ in batchDelivered.setTrue() }

        // Add 50 transactions — flushAndDeliver fires, delivering the batch
        for i in 0 ..< 50 {
            await manager.addTransaction(
                TestFixtures.makeTransaction(url: "https://paused.com/\(i)")
            )
        }

        // Batch was delivered to callback but no reportAcceptedCount was called
        // (simulating isRecording == false in processBatch which would drop the batch)
        #expect(batchDelivered.value)

        // No eviction should have fired because totalBuffered was never incremented
        var evictionFired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .bufferEvictionRequested, object: nil, queue: .main
        ) { _ in evictionFired = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        try? await Task.sleep(for: .milliseconds(100))
        #expect(!evictionFired)
    }

    @Test("clearSession resets actor-side buffer state")
    @MainActor
    func clearSessionResetsActorState() async {
        let coordinator = MainContentCoordinator(policy: SmallHistoryPolicy())
        coordinator.isRecording = true

        // Seed some transactions and simulate partial buffering on the actor
        for i in 0 ..< 5 {
            await coordinator.sessionManager.addTransaction(
                TestFixtures.makeTransaction(url: "https://buffered.com/\(i)")
            )
        }

        // Clear session — must also flush actor-side pending state
        await coordinator.clearSession()

        // Verify the actor's pending buffer is empty
        let pending = await coordinator.sessionManager.flushPendingUpdates()
        #expect(pending.isEmpty)
    }

    @Test("Stale accepted-count from pre-clear batch is rejected")
    @MainActor
    func staleAcceptedCountRejectedAfterClear() async {
        let manager = TrafficSessionManager()
        await manager.setMaxBufferSize(100)

        // Capture the pre-clear generation
        let preClearGen = await manager.currentGeneration

        // Simulate clearSession resetting the actor
        await manager.resetBufferState()

        // Now the generation has incremented. A stale report with the old generation
        // should be silently rejected and not affect the post-clear accounting.
        await manager.reportAcceptedCount(50, generation: preClearGen)

        // A valid report with the current generation should be accepted
        let currentGen = await manager.currentGeneration
        await manager.reportAcceptedCount(10, generation: currentGen)

        var evictionFired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .bufferEvictionRequested, object: nil, queue: .main
        ) { _ in evictionFired = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        try? await Task.sleep(for: .milliseconds(100))

        // totalBuffered should be 10 (only the current-generation report), not 60
        // maxBufferSize is 100, so no eviction should have fired
        #expect(!evictionFired)
    }

    @Test("Fresh post-clear traffic is not dropped as stale")
    @MainActor
    func freshPostClearTrafficAccepted() async {
        let manager = TrafficSessionManager()
        await manager.setMaxBufferSize(100)

        // Capture the pre-clear generation
        let preClearGen = await manager.currentGeneration

        // Simulate clearSession resetting the actor
        await manager.resetBufferState()
        let postClearGen = await manager.currentGeneration
        #expect(postClearGen != preClearGen)

        // Fresh traffic after clear carries the new generation → must be accepted
        await manager.reportAcceptedCount(5, generation: postClearGen)

        // Stale pre-clear report is rejected
        await manager.reportAcceptedCount(50, generation: preClearGen)

        // Only the 5 fresh transactions should be counted (not 55)
        var evictionFired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .bufferEvictionRequested, object: nil, queue: .main
        ) { _ in evictionFired = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        try? await Task.sleep(for: .milliseconds(100))
        #expect(!evictionFired) // 5 < 100, no eviction
    }

    @Test("Successful CONNECT passthrough survives batching into live session")
    @MainActor
    func successfulConnectPassthroughSurvivesBatching() async {
        let coordinator = MainContentCoordinator(policy: SmallHistoryPolicy())
        coordinator.isRecording = true

        await coordinator.sessionManager.setOnBatchReady { [weak coordinator] batch, generation in
            guard let coordinator else {
                return
            }
            Task { @MainActor in
                coordinator.processBatch(batch, generation: generation)
            }
        }
        await coordinator.sessionManager.startBatchTimer()
        defer {
            Task {
                await coordinator.sessionManager.stopBatchTimer()
            }
        }

        let connect = TLSInterceptHandler.makeTunnelTransaction(
            host: "example.com",
            port: 443,
            statusCode: 200,
            statusMessage: "Connection Established",
            state: .completed,
            sourcePort: 54_321
        )

        await coordinator.sessionManager.addTransaction(connect)

        for _ in 0 ..< 50 {
            if coordinator.transactions.count == 1 {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.transactions.count == 1)
        #expect(coordinator.transactions.first?.request.method == "CONNECT")
        #expect(coordinator.transactions.first?.isTLSFailure == false)
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions.first?.request.method == "CONNECT")
    }

    @Test("Coordinator clearSession aligns generations after awaited reset")
    @MainActor
    func coordinatorClearSessionGeneration() async {
        let coordinator = MainContentCoordinator(policy: SmallHistoryPolicy())
        coordinator.isRecording = true

        // Seed some transactions
        for i in 0 ..< 5 {
            coordinator.transactions.append(
                TestFixtures.makeTransaction(url: "https://pre-clear.com/\(i)")
            )
        }
        #expect(coordinator.transactions.count == 5)

        let preClearGen = coordinator.sessionGeneration

        // Clear session
        await coordinator.clearSession()

        // sessionGeneration incremented synchronously
        #expect(coordinator.sessionGeneration == preClearGen &+ 1)
        #expect(coordinator.transactions.isEmpty)

        // Actor generation should now match coordinator
        let actorGen = await coordinator.sessionManager.currentGeneration
        #expect(actorGen == coordinator.sessionGeneration)
    }

    @Test("Coordinator clearSession drops pre-clear pending batch and keeps only capped fresh post-clear batch")
    @MainActor
    func coordinatorClearSessionFlushPath() async {
        let coordinator = MainContentCoordinator(policy: SmallHistoryPolicy())
        coordinator.isRecording = true
        let retainedCount = SmallHistoryPolicy().maxLiveHistoryEntries

        await coordinator.sessionManager.setOnBatchReady { [weak coordinator] batch, generation in
            guard let coordinator else {
                return
            }
            Task { @MainActor in
                coordinator.processBatch(batch, generation: generation)
            }
        }
        // Align the actor-side cap with the coordinator policy so the eviction
        // notification (the single source of truth now that processBatch no
        // longer trims locally) fires when the overflow crosses the cap.
        await coordinator.sessionManager.setMaxBufferSize(retainedCount)

        let evictionObserver = NotificationCenter.default.addObserver(
            forName: .bufferEvictionRequested, object: nil, queue: .main
        ) { [weak coordinator] notification in
            guard let coordinator else {
                return
            }
            let count = notification.userInfo?["count"] as? Int ?? 0
            Task { @MainActor in
                coordinator.evictOldestTransactions(count: count)
            }
        }
        defer { NotificationCenter.default.removeObserver(evictionObserver) }

        for index in 0 ..< 49 {
            await coordinator.sessionManager.addTransaction(
                TestFixtures.makeTransaction(url: "https://pre-clear.com/\(index)")
            )
        }

        await coordinator.clearSession()

        for index in 0 ..< 50 {
            await coordinator.sessionManager.addTransaction(
                TestFixtures.makeTransaction(url: "https://post-clear.com/\(index)")
            )
        }

        for _ in 0 ..< 500 {
            if coordinator.transactions.count == retainedCount {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.transactions.count == retainedCount)
        #expect(coordinator.transactions.allSatisfy { $0.request.url.absoluteString.contains("post-clear.com") })
    }

    @Test("Coordinator clearSession queues rollover batches and drops stale batches delivered during clear")
    @MainActor
    func coordinatorClearSessionRolloverWindow() async {
        let coordinator = MainContentCoordinator(policy: SmallHistoryPolicy())
        coordinator.isRecording = true

        let stale = TestFixtures.makeTransaction(url: "https://stale-during-clear.com")
        let fresh = TestFixtures.makeTransaction(url: "https://fresh-during-clear.com")

        await coordinator.sessionManager.setOnBeginNewSession { generation in
            await MainActor.run {
                coordinator.processBatch([stale], generation: generation &- 1)
                coordinator.processBatch([fresh], generation: generation)
            }
        }

        await coordinator.clearSession()

        #expect(coordinator.transactions.count == 1)
        #expect(coordinator.transactions.first?.request.url.absoluteString.contains("fresh-during-clear.com") ?? false)
    }

    @Test("Pinned/saved transactions are independent of live buffer")
    @MainActor
    func pinnedSavedIndependent() {
        let coordinator = MainContentCoordinator(policy: SmallHistoryPolicy())

        // Persisted favorites are loaded separately and not in the live array
        let pinned = TestFixtures.makeTransaction(url: "https://pinned.com")
        pinned.isPinned = true
        coordinator.persistedFavorites = [pinned]

        // Live buffer at capacity
        for i in 0 ..< 10 {
            let tx = TestFixtures.makeTransaction(url: "https://example.com/\(i)")
            coordinator.transactions.append(tx)
        }

        // Persisted favorites remain untouched
        #expect(coordinator.persistedFavorites.count == 1)
        #expect(coordinator.transactions.count == 10)
    }
}

// MARK: - SmallHistoryPolicy

private struct SmallHistoryPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 10
}
