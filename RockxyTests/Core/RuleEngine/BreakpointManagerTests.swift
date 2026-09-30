import Foundation
@testable import Rockxy
import Testing

// MARK: - BreakpointManagerTests

// Regression tests for `BreakpointManager` in the core rule engine layer.

@Suite(.serialized)
@MainActor
struct BreakpointManagerTests {
    // MARK: Internal

    @Test("enqueue adds item to pausedItems")
    func enqueueAddsItem() async {
        let manager = BreakpointManager()
        let data = BreakpointRequestData(
            method: "GET", url: "https://example.com/test", headers: [], body: "", statusCode: 200, phase: .request
        )

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let id = manager.pausedItems.first?.id {
                manager.resolve(id: id, decision: .cancel)
            }
        }

        _ = await manager.enqueueAndWait(data)
        // After resolve, item is removed
        #expect(manager.pausedItems.isEmpty)
    }

    @Test("resolve one does not drop others")
    func resolveOneKeepsOthers() async {
        let manager = BreakpointManager()
        let data1 = BreakpointRequestData(
            method: "GET", url: "https://a.com", headers: [], body: "", statusCode: 200, phase: .request
        )
        let data2 = BreakpointRequestData(
            method: "POST", url: "https://b.com", headers: [], body: "", statusCode: 200, phase: .request
        )

        // Enqueue two items
        Task {
            _ = await manager.enqueueAndWait(data1)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        Task {
            _ = await manager.enqueueAndWait(data2)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(manager.pausedItems.count == 2)

        // Resolve first, second remains
        let firstId = manager.pausedItems[0].id
        manager.resolve(id: firstId, decision: .execute)
        #expect(manager.pausedItems.count == 1)
    }

    @Test("resolveAll clears everything")
    func resolveAllClears() async {
        let manager = BreakpointManager()
        let data = BreakpointRequestData(
            method: "GET", url: "https://example.com", headers: [], body: "", statusCode: 200, phase: .request
        )

        Task { _ = await manager.enqueueAndWait(data) }
        Task { _ = await manager.enqueueAndWait(data) }
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(manager.pausedItems.count == 2)
        manager.resolveAll(decision: .cancel)
        #expect(manager.pausedItems.isEmpty)
    }

    @Test("selectedItemId auto-selects first item")
    func autoSelectsFirst() async {
        let manager = BreakpointManager()
        #expect(manager.selectedItemId == nil)

        let data = BreakpointRequestData(
            method: "GET", url: "https://example.com", headers: [], body: "", statusCode: 200, phase: .request
        )
        Task { _ = await manager.enqueueAndWait(data) }
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(manager.selectedItemId == manager.pausedItems.first?.id)
    }

    @Test("enqueue projects queue metadata")
    func enqueueProjectsQueueMetadata() async throws {
        let manager = BreakpointManager()
        let data = BreakpointRequestData(
            method: "POST",
            url: "http://127.0.0.1:43210/rockxy-demo/profile?operationName=ExpiredToken",
            headers: [
                EditableHeader(name: "X-Rockxy-Runtime", value: "Flutter"),
                EditableHeader(name: "Content-Type", value: "application/json"),
            ],
            body: #"{"operationName":"BodyName"}"#,
            statusCode: 200,
            phase: .request,
            matchedRuleName: "Profile request"
        )

        Task { _ = await manager.enqueueAndWait(data) }
        try await Task.sleep(nanoseconds: 50_000_000)

        let item = try #require(manager.pausedItems.first)
        #expect(item.sequenceNumber == 1)
        #expect(item.url == "127.0.0.1:43210/rockxy-demo/profile?operationName=ExpiredToken")
        #expect(item.client == "Flutter")
        #expect(item.queryName == "ExpiredToken")
        #expect(item.matchedRuleName == "Profile request")

        manager.resolve(id: item.id, decision: .cancel)
    }

    // MARK: - Selection stability

    @Test("a newer hit does not steal selection from the edited item")
    func newerHitKeepsExistingSelection() async throws {
        let manager = BreakpointManager()
        await enqueueItem(on: manager, url: "https://first.com")
        let firstId = try #require(manager.pausedItems.first?.id)
        // First hit self-selects because the queue was empty.
        #expect(manager.selectedItemId == firstId)

        // The user is editing `first`; a second, newer hit arrives.
        await enqueueItem(on: manager, url: "https://second.com")
        #expect(manager.pausedItems.count == 2)
        // Selection must stay on the item under edit — the newcomer never steals it.
        #expect(manager.selectedItemId == firstId)

        manager.resolveAll(decision: .cancel)
    }

    @Test("selection re-arms only when the current selection is no longer valid")
    func reselectsWhenSelectionInvalidated() async throws {
        let manager = BreakpointManager()
        await enqueueItem(on: manager, url: "https://a.com")
        let firstId = try #require(manager.pausedItems.first?.id)
        #expect(manager.selectedItemId == firstId)

        // Resolving the sole selected item empties the queue and clears selection.
        manager.resolve(id: firstId, decision: .cancel)
        #expect(manager.selectedItemId == nil)

        // A fresh hit into an empty queue self-selects again.
        await enqueueItem(on: manager, url: "https://b.com")
        #expect(manager.selectedItemId == manager.pausedItems.first?.id)

        manager.resolveAll(decision: .cancel)
    }

    // MARK: - Notification lifecycle

    @Test("posts breakpointHit only on the empty to non-empty transition")
    func notifiesOncePerNonEmptyLifetime() async {
        let manager = BreakpointManager()
        let counter = NotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .breakpointHit,
            object: manager,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // A burst of three hits must auto-raise the window exactly once: the first raise
        // opens it, so later hits find it visible.
        await enqueueItem(on: manager, url: "https://a.com")
        manager.isQueueWindowVisible = true
        await enqueueItem(on: manager, url: "https://b.com")
        await enqueueItem(on: manager, url: "https://c.com")
        #expect(manager.pausedItems.count == 3)
        #expect(counter.count == 1)

        // Drain the queue back to empty.
        manager.resolveAll(decision: .cancel)
        #expect(manager.pausedItems.isEmpty)

        // A new hit after the queue emptied re-arms the notification.
        await enqueueItem(on: manager, url: "https://d.com")
        #expect(counter.count == 2)

        manager.resolveAll(decision: .cancel)
    }

    @Test("a hit raises the queue again when its window was closed with items waiting")
    func raisesAgainAfterWindowClosed() async {
        let manager = BreakpointManager()
        let counter = NotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .breakpointHit,
            object: manager,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await enqueueItem(on: manager, url: "https://a.com")
        manager.isQueueWindowVisible = true
        await enqueueItem(on: manager, url: "https://b.com")
        #expect(counter.count == 1)

        manager.isQueueWindowVisible = false
        await enqueueItem(on: manager, url: "https://c.com")
        #expect(counter.count == 2)

        manager.resolveAll(decision: .cancel)
    }

    // MARK: - Adjacent-fallback selection on resolve

    @Test("resolving the selected first item selects the row now at that index")
    func resolveFirstFallsToNewFirst() async {
        let manager = BreakpointManager()
        await enqueueItem(on: manager, url: "https://a.com")
        await enqueueItem(on: manager, url: "https://b.com")
        await enqueueItem(on: manager, url: "https://c.com")
        let ids = manager.pausedItems.map(\.id)

        manager.selectedItemId = ids[0]
        manager.resolve(id: ids[0], decision: .cancel)
        // The item that shifted into index 0 (former `b`) becomes selected.
        #expect(manager.selectedItemId == ids[1])

        manager.resolveAll(decision: .cancel)
    }

    @Test("resolving the selected middle item selects the row now at that index")
    func resolveMiddleFallsToNext() async {
        let manager = BreakpointManager()
        await enqueueItem(on: manager, url: "https://a.com")
        await enqueueItem(on: manager, url: "https://b.com")
        await enqueueItem(on: manager, url: "https://c.com")
        let ids = manager.pausedItems.map(\.id)

        manager.selectedItemId = ids[1]
        manager.resolve(id: ids[1], decision: .cancel)
        // `c` shifts into index 1 and becomes selected.
        #expect(manager.selectedItemId == ids[2])

        manager.resolveAll(decision: .cancel)
    }

    @Test("resolving the selected last item falls back to the previous final row")
    func resolveLastFallsToPreviousFinal() async {
        let manager = BreakpointManager()
        await enqueueItem(on: manager, url: "https://a.com")
        await enqueueItem(on: manager, url: "https://b.com")
        await enqueueItem(on: manager, url: "https://c.com")
        let ids = manager.pausedItems.map(\.id)

        manager.selectedItemId = ids[2]
        manager.resolve(id: ids[2], decision: .cancel)
        // Nothing occupies the old last index, so selection clamps to `b`.
        #expect(manager.selectedItemId == ids[1])

        manager.resolveAll(decision: .cancel)
    }

    @Test("resolving a non-selected item preserves the current selection")
    func resolveNonSelectedPreservesSelection() async {
        let manager = BreakpointManager()
        await enqueueItem(on: manager, url: "https://a.com")
        await enqueueItem(on: manager, url: "https://b.com")
        await enqueueItem(on: manager, url: "https://c.com")
        let ids = manager.pausedItems.map(\.id)

        manager.selectedItemId = ids[1]
        // Resolve an unrelated item; the edited item stays selected.
        manager.resolve(id: ids[0], decision: .cancel)
        #expect(manager.selectedItemId == ids[1])
        #expect(manager.pausedItems.count == 2)

        manager.resolveAll(decision: .cancel)
    }

    // MARK: - Cross-singleton isolation

    @Test("a local manager never mutates BreakpointManager.shared selection")
    func localManagerDoesNotTouchSharedSelection() async throws {
        let sharedSelectionBefore = BreakpointManager.shared.selectedItemId

        let manager = BreakpointManager()
        await enqueueItem(on: manager, url: "https://a.com")
        await enqueueItem(on: manager, url: "https://b.com")
        // Exercise every selection-mutating path on the local instance.
        manager.selectNextItem()
        manager.selectPreviousItem()
        let firstId = try #require(manager.pausedItems.first?.id)
        manager.resolve(id: firstId, decision: .cancel)

        #expect(manager.selectedItemId != nil)
        // None of the local operations may leak into the shared singleton.
        #expect(BreakpointManager.shared.selectedItemId == sharedSelectionBefore)

        manager.resolveAll(decision: .cancel)
    }

    @Test("execute preserves a protected binary payload while applying metadata edits")
    func protectedPayloadExecutePreservesBody() async throws {
        let manager = BreakpointManager()
        var data = BreakpointRequestData(
            method: "POST",
            url: "https://example.com/upload",
            headers: [],
            body: "",
            statusCode: 200,
            phase: .request
        )
        data.isBodyEditable = false

        let task = Task { await manager.enqueueAndWait(data) }
        for _ in 0 ..< 100 where manager.pausedItems.isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let item = try #require(manager.pausedItems.first)
        manager.resolve(id: item.id, decision: .execute)

        let result = await task.value
        #expect(result.0 == .execute)
        #expect(result.1.isBodyEditable == false)
    }

    // MARK: - Cancellation-aware waiting

    @Test("cancelling a waiting task removes only that item and returns .cancel with the original draft")
    func cancelRemovesOnlyThatItemWithOriginalDraft() async throws {
        let manager = BreakpointManager()
        let dataA = BreakpointRequestData(
            method: "GET", url: "https://a.com", headers: [], body: "original-a", statusCode: 200, phase: .request
        )
        let dataB = BreakpointRequestData(
            method: "POST", url: "https://b.com", headers: [], body: "original-b", statusCode: 200, phase: .request
        )

        let taskA = Task { await manager.enqueueAndWait(dataA) }
        try await waitForCount(1, on: manager)
        let itemAID = try #require(manager.pausedItems.first).id
        let taskB = Task { await manager.enqueueAndWait(dataB) }
        try await waitForCount(2, on: manager)
        let itemBID = try #require(manager.pausedItems.last).id

        // Cancelling task A must drain exactly A and leave B paused.
        taskA.cancel()
        try await waitForCount(1, on: manager)

        let resultA = await taskA.value
        #expect(resultA.0 == .cancel)
        #expect(resultA.1.body == "original-a")

        let remaining = try #require(manager.pausedItems.first)
        #expect(remaining.id == itemBID)
        #expect(remaining.id != itemAID)

        // B was never resolved by A's cancellation: it still honors its own decision.
        manager.resolve(id: remaining.id, decision: .execute)
        let resultB = await taskB.value
        #expect(resultB.0 == .execute)
    }

    @Test("a task cancelled before it enqueues never adds a row and returns .cancel")
    func cancelBeforeEnqueueAddsNoRow() async {
        let manager = BreakpointManager()
        let data = BreakpointRequestData(
            method: "GET", url: "https://a.com", headers: [], body: "orig", statusCode: 200, phase: .request
        )

        let task = Task {
            // Yield so the cancellation below lands before the continuation registers.
            await Task.yield()
            return await manager.enqueueAndWait(data)
        }
        task.cancel()

        let result = await task.value
        #expect(result.0 == .cancel)
        #expect(result.1.body == "orig")
        #expect(manager.pausedItems.isEmpty)
    }

    @Test("cancelling one paused task never resolves a concurrently paused task")
    func cancelOneDoesNotResolveAnother() async throws {
        let manager = BreakpointManager()
        let first = Task {
            await manager.enqueueAndWait(
                BreakpointRequestData(
                    method: "GET", url: "https://first.com", headers: [], body: "", statusCode: 200, phase: .request
                )
            )
        }
        try await waitForCount(1, on: manager)
        let firstID = try #require(manager.pausedItems.first).id
        let second = Task {
            await manager.enqueueAndWait(
                BreakpointRequestData(
                    method: "GET", url: "https://second.com", headers: [], body: "", statusCode: 200, phase: .request
                )
            )
        }
        try await waitForCount(2, on: manager)
        let secondID = try #require(manager.pausedItems.last).id

        first.cancel()
        try await waitForCount(1, on: manager)
        _ = await first.value

        // The survivor is the second item, still suspended and independently resolvable.
        let survivor = try #require(manager.pausedItems.first)
        #expect(survivor.id == secondID)
        #expect(survivor.id != firstID)
        manager.resolve(id: survivor.id, decision: .abort)
        let secondResult = await second.value
        #expect(secondResult.0 == .abort)
    }

    // MARK: Private

    /// Poll until the queue reaches `count` items or a bounded number of ticks elapse.
    private func waitForCount(_ count: Int, on manager: BreakpointManager) async throws {
        for _ in 0 ..< 200 where manager.pausedItems.count != count {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(manager.pausedItems.count == count)
    }

    /// Enqueue one paused item and wait until it is appended, so the queue order
    /// is deterministic across sequential `enqueueItem` calls. The spawned task's
    /// continuation is resolved by the caller's later `resolve`/`resolveAll`.
    private func enqueueItem(on manager: BreakpointManager, url: String) async {
        let before = manager.pausedItems.count
        Task {
            _ = await manager.enqueueAndWait(
                BreakpointRequestData(
                    method: "GET", url: url, headers: [], body: "", statusCode: 200, phase: .request
                )
            )
        }
        for _ in 0 ..< 100 where manager.pausedItems.count == before {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

// MARK: - NotificationCounter

/// Thread-safe-enough counter for observing `.breakpointHit` posts in tests.
/// `.breakpointHit` is posted on the `@MainActor`, and the synchronous observer
/// (`queue: nil`) therefore runs on the same main thread the test reads from.
private final class NotificationCounter: @unchecked Sendable {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
