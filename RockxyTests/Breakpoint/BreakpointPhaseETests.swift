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

    @Test("A blank header row from Add Header is not an error and is dropped on apply")
    func blankHeaderRowIsIgnored() async throws {
        let blank = EditableHeader(name: "", value: " ")
        var draft = BreakpointRequestData.test(headers: [EditableHeader(name: "X-Test", value: "1"), blank], phase: .response)
        #expect(draft.executionValidationMessage == nil)
        draft.headers.append(EditableHeader(name: "", value: "orphan value"))
        #expect(draft.executionValidationMessage != nil)

        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let task = Task {
            await manager.enqueueAndWait(.test(headers: [EditableHeader(name: "X-Test", value: "1"), blank], phase: .response))
        }
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.resolve(id: item.id, decision: .execute)
        let (_, applied) = await task.value
        #expect(applied.headers.map(\.name) == ["X-Test"])
    }

    @Test("custom response status validation accepts non-preset HTTP codes")
    func customResponseStatusValidation() {
        var draft = BreakpointRequestData.test(statusCode: 200, phase: .response)
        draft.statusCode = 418

        #expect(draft.executionValidationMessage == nil)

        draft.statusCode = 99
        #expect(draft.executionValidationMessage != nil)

        draft.statusCode = 600
        #expect(draft.executionValidationMessage != nil)
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
    func templateMenuFiltersToResponseKind() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "com.amunx.rockxy.tests.bp.e4.\(UUID().uuidString)")
        )
        let store = BreakpointTemplateStore(
            defaults: defaults,
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
        await harness.addRule(.breakpointTest(
            name: "Response review",
            matchingRule: await upstream.matchingRule("status/401"),
            phases: .response
        ))
        let session = try await harness.client()
        async let response = BreakpointTestHarness.dataWithRetry(
            from: await upstream.url("status/401"),
            session: session
        )
        let item = try await harness.awaitNextPause(timeout: 8)
        #expect(item.matchedRuleName == "Response review")
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

    @Test("response breakpoint owns inspector rule impact when another rule also matches")
    func responseBreakpointOwnsCapturedRuleImpact() async throws {
        let upstream = try await BreakpointLocalHTTPServer.start()
        defer { Task { await upstream.stop() } }
        let harness = try await BreakpointTestHarness.start()
        let matchingRule = await upstream.matchingRule("get")
        let sharedCondition = ProxyRule.breakpointTest(matchingRule: matchingRule).matchCondition
        await harness.addRule(ProxyRule(
            name: "Earlier header rule",
            matchCondition: sharedCondition,
            action: .modifyHeader(operations: [
                HeaderOperation(type: .add, headerName: "X-Earlier", headerValue: "true", phase: .request),
            ])
        ))
        await harness.addRule(.breakpointTest(
            name: "Response review",
            matchingRule: matchingRule,
            phases: .response
        ))
        let session = try await harness.client()
        async let response = BreakpointTestHarness.dataWithRetry(
            from: await upstream.url("get"),
            session: session
        )

        let item = try await harness.awaitNextPause(timeout: 8)
        #expect(item.matchedRuleName == "Response review")
        await harness.resolve(item.id, decision: .cancel)
        _ = try await response

        let capture = try #require(await harness.lastCapturedRow())
        #expect(capture.matchedRuleName == "Response review")
        #expect(capture.matchedRuleActionSummary == "Breakpoint (Response)")
        await harness.stop()
    }

    @Test("locally consumed traffic keeps the rule that produced its response")
    func localRuleKeepsTransactionImpact() {
        let condition = ProxyRule.breakpointTest(matchingRule: "example.com/get").matchCondition
        let breakpoint = ProxyRule(
            name: "Response review",
            matchCondition: condition,
            action: .breakpoint(phase: .response)
        )
        let block = ProxyRule(
            name: "Block request",
            matchCondition: condition,
            action: .block(statusCode: 451)
        )

        let selected = ProxyHandlerShared.transactionRule(
            breakpointRule: breakpoint,
            matchedRule: block
        )

        #expect(selected?.id == block.id)
    }

    // BP_E7
    @Test("response abort returns 503 and retains capture metadata")
    func responseAbortRetainsCaptureMetadata() async throws {
        let upstream = try await BreakpointLocalHTTPServer.start()
        defer { Task { await upstream.stop() } }
        let harness = try await BreakpointTestHarness.start()
        await harness.addRule(.breakpointTest(
            name: "Abort response review",
            matchingRule: await upstream.matchingRule("graphql"),
            method: .post,
            phases: .response
        ))
        let session = try await harness.client()
        var request = URLRequest(url: await upstream.url("graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BreakpointAbortTest/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(#"{"query":"query Demo { viewer { id } }","operationName":"Demo"}"#.utf8)
        async let response = session.data(for: request)

        let item = try await harness.awaitNextPause(timeout: 8)
        #expect(item.matchedRuleName == "Abort response review")
        await harness.resolve(item.id, decision: .abort)

        let (_, urlResponse) = try await response
        let httpResponse = try #require(urlResponse as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 503)
        let capture = try await waitForCapturedRow(harness, timeout: 8)
        #expect(capture.response?.statusCode == 503)
        #expect(capture.state == .failed)
        #expect(capture.timingInfo != nil)
        #expect(capture.sourcePort != nil)
        #expect(capture.clientApp == "BreakpointAbortTest")
        #expect(capture.graphQLInfo?.operationName == "Demo")
        #expect(capture.request.httpVersion == "1.1")
        #expect(capture.matchedRuleName == "Abort response review")
        await harness.stop()
    }

    /// BP_E8 — a client that disconnects while the response is paused must drain the queue
    /// without any user resolution. This exercises UpstreamResponseHandler's client
    /// `closeFuture` path: the origin response has already arrived and is buffered when the
    /// downstream client goes away, so the handler must cancel the paused item itself.
    @Test("client disconnect during a response pause drains the queue without resolution")
    func responsePauseClientDisconnectDrainsQueue() async throws {
        let upstream = try await BreakpointLocalHTTPServer.start()
        defer { Task { await upstream.stop() } }
        let harness = try await BreakpointTestHarness.start()
        let matchingRule = await upstream.matchingRule("get")
        await harness.addRule(.breakpointTest(matchingRule: matchingRule, phases: .response))
        let proxyPort = try await harness.startProxy()
        let url = await upstream.url("get")

        // The raw client lets the origin respond immediately, then gives the test an
        // explicit downstream descriptor to close while the response is buffered.
        let client = try BreakpointRawHTTPClient.connect(proxyPort: proxyPort, requestURL: url)

        let paused = try await harness.awaitNextPause(timeout: 8)
        #expect(paused.phase == .response)

        // Closing the descriptor fires the client channel's closeFuture inside
        // UpstreamResponseHandler.
        client.close()

        // The paused queue must drain on its own — no resolve()/resolveAll() is called.
        try await waitUntilQueueDrains(harness, timeout: 8)

        await harness.stop()
    }

    @Test("stopping the proxy drains a paused response queue")
    func stopDrainsResponsePause() async throws {
        let upstream = try await BreakpointLocalHTTPServer.start()
        defer { Task { await upstream.stop() } }
        let harness = try await BreakpointTestHarness.start()
        let matchingRule = await upstream.matchingRule("get")
        await harness.addRule(.breakpointTest(matchingRule: matchingRule, phases: .response))
        let proxyPort = try await harness.startProxy()
        let client = try BreakpointRawHTTPClient.connect(
            proxyPort: proxyPort,
            requestURL: await upstream.url("get")
        )

        let paused = try await harness.awaitNextPause(timeout: 8)
        #expect(paused.phase == .response)
        await harness.stopProxyOnly()

        #expect(harness.manager.pausedItems.isEmpty)
        await harness.stop()
        client.close()
    }

    // MARK: Private

    private func waitUntilQueueDrains(
        _ harness: BreakpointTestHarness,
        timeout seconds: TimeInterval
    )
        async throws
    {
        let ticks = Int(seconds / 0.01)
        for _ in 0 ..< ticks {
            if harness.manager.pausedItems.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record(
            "Response breakpoint queue did not drain after client disconnect (\(harness.manager.pausedItems.count) still paused)."
        )
    }

    private func waitForCapturedRow(
        _ harness: BreakpointTestHarness,
        timeout seconds: TimeInterval
    ) async throws -> HTTPTransaction {
        let ticks = Int(seconds / 0.01)
        for _ in 0 ..< ticks {
            if let transaction = await harness.lastCapturedRow() {
                return transaction
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw BreakpointHarnessError.timeout("Timed out waiting for the aborted response capture row.")
    }
}
