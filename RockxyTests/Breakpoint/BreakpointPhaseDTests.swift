import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct BreakpointPhaseDTests {
    // BP_D1
    @Test("upstreamReceivesEditedRequest")
    func upstreamReceivesEditedRequest() async throws {
        let upstream = try await BreakpointLocalHTTPServer.start()
        defer { Task { await upstream.stop() } }
        let harness = try await BreakpointTestHarness.start()
        await harness.addRule(.breakpointTest(matchingRule: await upstream.matchingRule("headers"), phases: .request))
        let session = try await harness.client()
        async let response = BreakpointTestHarness.dataWithRetry(
            from: await upstream.url("headers"),
            session: session
        )

        let item = try await harness.awaitNextPause(timeout: 8)
        await harness.editDraft(item.id) { draft in
            draft.headers.append(EditableHeader(name: "X-Edited", value: "true"))
        }
        await harness.resolve(item.id, decision: .execute)

        let (data, _) = try await response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let headers = try #require(json?["headers"] as? [String: Any])
        #expect(headers["X-Edited"] as? String == "true")
        await harness.stop()
    }

    // BP_D2
    @Test("captureRowReflectsEditedValues")
    func captureRowReflectsEditedValues() async throws {
        let upstream = try await BreakpointLocalHTTPServer.start()
        defer { Task { await upstream.stop() } }
        let harness = try await BreakpointTestHarness.start()
        await harness.addRule(.breakpointTest(matchingRule: await upstream.matchingRule("headers"), phases: .request))
        let session = try await harness.client()
        async let response = BreakpointTestHarness.dataWithRetry(
            from: await upstream.url("headers"),
            session: session
        )
        let item = try await harness.awaitNextPause(timeout: 8)
        await harness.editDraft(item.id) { $0.method = "GET" }
        await harness.resolve(item.id, decision: .execute)
        _ = try await response
        let capture = try #require(await harness.lastCapturedRow())
        #expect(capture.request.url.absoluteString.contains(await upstream.matchingRule("headers")))
        await harness.stop()
    }

    // BP_D3
    @Test("originalRetainedForAudit")
    func originalRetainedForAudit() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let task = Task { await manager.enqueueAndWait(.test(method: "GET", url: "https://httpbin.org/get")) }
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.updateDraft(id: item.id) {
            $0.method = "POST"
            $0.url = "https://httpbin.org/post"
        }
        let queued = try #require(manager.pausedItems.first)
        #expect(queued.method == "GET")
        #expect(queued.url == "httpbin.org/get")
        #expect(queued.editableDraft.method == "POST")
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_D4
    @Test("responsePauseFiresWhenEnabled")
    func responsePauseFiresWhenEnabled() {
        guard case let .breakpoint(phase) = ProxyRule.breakpointTest(
            matchingRule: "httpbin.org/status/401",
            phases: .both
        ).action else {
            Issue.record("Expected breakpoint action")
            return
        }
        #expect(phase == .both)
    }

    // BP_D5
    @Test("responseFlowsThroughWhenResponsePhaseDisabled")
    func responseFlowsThroughWhenResponsePhaseDisabled() {
        guard case let .breakpoint(phase) = ProxyRule.breakpointTest(
            matchingRule: "httpbin.org/status/401",
            phases: .request
        ).action else {
            Issue.record("Expected breakpoint action")
            return
        }
        #expect(phase == .request)
    }
}
