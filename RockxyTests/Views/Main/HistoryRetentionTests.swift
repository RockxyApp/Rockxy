import Foundation
@testable import Rockxy
import Testing

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

    @Test("TrafficSessionManager posts eviction notification when buffer overflows")
    @MainActor
    func sessionManagerEvictionNotification() async {
        let manager = TrafficSessionManager()
        await manager.setMaxBufferSize(20)
        await manager.setOnBatchReady { _ in }

        var evictionCount: Int?
        let observer = NotificationCenter.default.addObserver(
            forName: .bufferEvictionRequested, object: nil, queue: .main
        ) { notification in
            evictionCount = notification.userInfo?["count"] as? Int
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Add 50 transactions to trigger flushAndDeliver via batch-size threshold.
        // totalBuffered becomes 50, which exceeds maxBufferSize (20),
        // so evictOldest() fires and posts the notification.
        for i in 0 ..< 50 {
            await manager.addTransaction(
                TestFixtures.makeTransaction(url: "https://evict-actor.com/\(i)")
            )
        }

        // evictOldest() posts via Task { await MainActor.run { ... } }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(evictionCount == 2) // maxBufferSize / 10 = 20 / 10
    }

    @Test("Eviction count is at least 1 even for buffer sizes below 10")
    @MainActor
    func smallBufferEvictionNotZero() async {
        let manager = TrafficSessionManager()
        await manager.setMaxBufferSize(5)
        await manager.setOnBatchReady { _ in }

        var evictionCount: Int?
        let observer = NotificationCenter.default.addObserver(
            forName: .bufferEvictionRequested, object: nil, queue: .main
        ) { notification in
            evictionCount = notification.userInfo?["count"] as? Int
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        for i in 0 ..< 50 {
            await manager.addTransaction(
                TestFixtures.makeTransaction(url: "https://small-buffer.com/\(i)")
            )
        }

        try? await Task.sleep(for: .milliseconds(100))

        // max(5 / 10, 1) = max(0, 1) = 1
        #expect(evictionCount == 1)
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
        coordinator.clearSession()

        // Give the actor reset Task time to complete
        try? await Task.sleep(for: .milliseconds(100))

        // Verify the actor's pending buffer is empty
        let pending = await coordinator.sessionManager.flushPendingUpdates()
        #expect(pending.isEmpty)
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
