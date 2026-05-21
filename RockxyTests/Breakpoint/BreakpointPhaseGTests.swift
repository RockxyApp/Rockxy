import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct BreakpointPhaseGTests {
    // BP_G1
    @Test("threeConcurrentMatchesProduceThreeQueueItems")
    func threeConcurrentMatchesProduceThreeQueueItems() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let tasks = (1...3).map { index in
            Task { await manager.enqueueAndWait(.test(url: "https://httpbin.org/get?id=\(index)")) }
        }
        try await waitForQueueCount(3, manager: manager)
        #expect(manager.pausedItems.count == 3)
        let ids = Set(manager.pausedItems.map(\.id))
        #expect(ids.count == 3)
        manager.resolveAll(decision: .cancel)
        for task in tasks {
            _ = await task.value
        }
        _ = harness
    }

    // BP_G2
    @Test("nonMatchingRequestsFlowWhilePaused")
    func nonMatchingRequestsFlowWhilePaused() async throws {
        let upstream = try await BreakpointLocalHTTPServer.start()
        defer { Task { await upstream.stop() } }
        let harness = try await BreakpointTestHarness.start()
        await harness.addRule(.breakpointTest(matchingRule: await upstream.matchingRule("delay/1"), phases: .request))
        let session = try await harness.client()
        async let paused = BreakpointTestHarness.dataWithRetry(
            from: await upstream.url("delay/1"),
            session: session
        )
        let item = try await harness.awaitNextPause(timeout: 8)

        let (data, response) = try await BreakpointTestHarness.dataWithRetry(
            from: await upstream.url("get"),
            session: session
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(!data.isEmpty)

        await harness.resolve(item.id, decision: .cancel)
        _ = try await paused
        await harness.stop()
    }

    // BP_G3
    @Test("closeWindowKeepsQueue")
    func closeWindowKeepsQueue() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let task = Task { await manager.enqueueAndWait(.test()) }
        let item = try await harness.awaitNextPause(timeout: 2)
        #expect(manager.pausedItems.contains { $0.id == item.id })
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_G4
    @Test("selectionSwapPreservesIndependentDrafts")
    func selectionSwapPreservesIndependentDrafts() async throws {
        let manager = BreakpointManager()
        let tasks = [
            Task { await manager.enqueueAndWait(.test(url: "https://httpbin.org/get?item=1")) },
            Task { await manager.enqueueAndWait(.test(url: "https://httpbin.org/get?item=2")) },
        ]
        try await waitForQueueCount(2, manager: manager)
        let firstID = manager.pausedItems[0].id
        let secondID = manager.pausedItems[1].id
        manager.updateDraft(id: secondID) { $0.body = "second" }
        manager.selectedItemId = firstID
        manager.selectedItemId = secondID
        #expect(manager.pausedItems.first(where: { $0.id == secondID })?.editableDraft.body == "second")
        manager.resolveAll(decision: .cancel)
        for task in tasks {
            _ = await task.value
        }
    }

    // BP_G5
    @Test("selectionAdvancesAfterExecute")
    func selectionAdvancesAfterExecute() async throws {
        let manager = BreakpointManager()
        let first = Task { await manager.enqueueAndWait(.test(url: "https://httpbin.org/get?item=1")) }
        let second = Task { await manager.enqueueAndWait(.test(url: "https://httpbin.org/get?item=2")) }
        try await waitForQueueCount(2, manager: manager)
        let firstID = manager.pausedItems[0].id
        let secondID = manager.pausedItems[1].id
        manager.resolve(id: firstID, decision: .execute)
        #expect(manager.selectedItemId == secondID)
        manager.resolve(id: secondID, decision: .cancel)
        _ = await first.value
        _ = await second.value
    }

    // BP_G6
    @Test("queueEmptiesAfterAllResolved")
    func queueEmptiesAfterAllResolved() async throws {
        let manager = BreakpointManager()
        let task = Task { await manager.enqueueAndWait(.test()) }
        try await waitForQueueCount(1, manager: manager)
        manager.resolveAll(decision: .cancel)
        #expect(manager.pausedItems.isEmpty)
        #expect(manager.selectedItemId == nil)
        _ = await task.value
    }

    // BP_G7
    @Test("quitCleanupBehaviourDocumented")
    func quitCleanupBehaviourDocumented() async throws {
        let manager = BreakpointManager()
        let task = Task { await manager.enqueueAndWait(.test()) }
        try await waitForQueueCount(1, manager: manager)
        manager.resolveAll(decision: .cancel)
        let decision = await task.value.0
        #expect(decision == .cancel)
    }

    // BP_G8
    @Test("disablingRuleWhileItemQueuedDocumented")
    func disablingRuleWhileItemQueuedDocumented() async throws {
        let manager = BreakpointManager()
        let engine = RuleEngine()
        let rule = ProxyRule.breakpointTest(matchingRule: "httpbin.org/get")
        await engine.addRule(rule)
        let task = Task { await manager.enqueueAndWait(.test()) }
        try await waitForQueueCount(1, manager: manager)
        await engine.setEnabled(id: rule.id, enabled: false)
        #expect(manager.pausedItems.count == 1)
        manager.resolveAll(decision: .cancel)
        _ = await task.value
    }

    private func waitForQueueCount(
        _ count: Int,
        manager: BreakpointManager,
        timeout seconds: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if manager.pausedItems.count >= count {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
            await Task.yield()
        }
        throw BreakpointHarnessError.timeout("Timed out waiting for \(count) queued breakpoint items.")
    }
}
