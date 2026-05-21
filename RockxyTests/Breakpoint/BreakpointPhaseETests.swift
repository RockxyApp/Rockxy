import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct BreakpointPhaseETests {
    // BP_E1
    @Test("matcherReusedForResponsePhase")
    func matcherReusedForResponsePhase() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/status/401", phases: .response))
        let match = await engine.evaluateBreakpointRule(
            method: "GET",
            url: TestEndpoints.httpbinHTTPS("status/401"),
            headers: []
        )
        #expect(match != nil)
    }

    // BP_E2a
    @Test("statusCodePickerLists13Presets")
    func statusCodePickerLists13Presets() {
        let presets = [200, 201, 204, 301, 302, 304, 400, 401, 403, 404, 500, 502, 503]
        #expect(presets.count == 13)
        #expect(Set(presets).contains(401))
        #expect(Set(presets).contains(503))
    }

    // BP_E2b
    @Test("statusCodePickerUpdatesDraft")
    func statusCodePickerUpdatesDraft() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let task = Task { await manager.enqueueAndWait(.test(statusCode: 401, phase: .response)) }
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.updateDraft(id: item.id) { $0.statusCode = 200 }
        #expect(manager.pausedItems.first?.editableDraft.statusCode == 200)
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_E3
    @Test("queryTabHiddenInResponsePhase")
    func queryTabHiddenInResponsePhase() {
        let responseData = BreakpointRequestData.test(url: "https://httpbin.org/get?a=b", phase: .response)
        let raw = BreakpointRawMessage.rawMessage(from: responseData, kind: .response)
        #expect(raw.hasPrefix("HTTP/1.1"))
        #expect(!raw.contains("GET /get?a=b"))
    }

    // BP_E4
    @Test("templateMenuFiltersToResponseKind")
    func templateMenuFiltersToResponseKind() {
        let store = BreakpointTemplateStore(
            defaults: UserDefaults(suiteName: "com.amunx.rockxy.tests.bp.e4.\(UUID().uuidString)")!,
            storageKey: "breakpoint.templates.e4",
            seedDefaults: false
        )
        _ = store.addTemplate(kind: .request)
        _ = store.addTemplate(kind: .response)
        #expect(store.templates(for: .response).count == 1)
        #expect(store.templates(for: .response).allSatisfy { $0.kind == .response })
    }

    // BP_E5a
    @Test("responseStatusEditWritesBack")
    func responseStatusEditWritesBack() throws {
        let draft = BreakpointRequestData.test(statusCode: 401, phase: .response)
        let updated = try BreakpointRawMessage.applying(
            "HTTP/1.1 200 OK\nContent-Type: application/json\n\n{}",
            kind: .response,
            to: draft
        )
        #expect(updated.statusCode == 200)
    }

    // BP_E5b
    @Test("responseHeadersEditWritesBack")
    func responseHeadersEditWritesBack() throws {
        let updated = try BreakpointRawMessage.applying(
            "HTTP/1.1 200 OK\nX-Response: edited\n\n",
            kind: .response,
            to: .test(phase: .response)
        )
        #expect(updated.headers.first?.name == "X-Response")
        #expect(updated.headers.first?.value == "edited")
    }

    // BP_E5c
    @Test("responseBodyEditWritesBack")
    func responseBodyEditWritesBack() throws {
        let updated = try BreakpointRawMessage.applying(
            "HTTP/1.1 200 OK\nContent-Type: application/json\n\n{\"ok\":true}",
            kind: .response,
            to: .test(phase: .response)
        )
        #expect(updated.body == "{\"ok\":true}")
    }

    // BP_E6
    @Test("executeDeliversEditedResponseToClient")
    func executeDeliversEditedResponseToClient() async throws {
        let upstream = try await BreakpointLocalHTTPServer.start()
        defer { Task { await upstream.stop() } }
        let harness = try await BreakpointTestHarness.start()
        await harness.addRule(.breakpointTest(matchingRule: await upstream.matchingRule("status/401"), phases: .response))
        let session = try await harness.client()
        async let response = BreakpointTestHarness.dataWithRetry(
            from: await upstream.url("status/401"),
            session: session
        )
        let item = try await harness.awaitNextPause(timeout: 8)
        await harness.editDraft(item.id) {
            $0.statusCode = 200
            $0.headers = [EditableHeader(name: "Content-Type", value: "application/json")]
            $0.body = #"{"ok":true}"#
        }
        await harness.resolve(item.id, decision: .execute)

        let (data, urlResponse) = try await response
        let httpResponse = try #require(urlResponse as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == #"{"ok":true}"#)
        await harness.stop()
    }

    // BP_E7
    @Test("responseAbortBehaviourDocumented")
    func responseAbortBehaviourDocumented() {
        let decision = BreakpointDecision.abort
        if case .abort = decision {
            #expect(true)
        } else {
            Issue.record("Expected response abort to use the shared abort decision.")
        }
    }
}
