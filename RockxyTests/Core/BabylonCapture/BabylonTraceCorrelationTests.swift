import Foundation
@testable import Rockxy
import Testing

@Suite("Babylon trace correlation")
struct BabylonTraceCorrelationTests {
    // MARK: Internal

    @Test("A request keeps the runtime session, trace, and step the app sent with it")
    func mapperStoresCorrelation() throws {
        let transaction = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(context: .init(sessionID: "s1", traceID: "checkout", stepID: "pay", createdAt: 1)),
            identity: identity
        )

        #expect(transaction.babylonCorrelation == BabylonCorrelation(
            sourceClientID: "client",
            sessionID: "s1",
            traceID: "checkout",
            stepID: "pay"
        ))
    }

    @Test("A request made outside any step keeps its trace without a step")
    func emptyStepMeansOutsideAnyStep() {
        let correlation = BabylonCorrelation(context: .init(sessionID: "s1", traceID: "t", stepID: "", createdAt: 1))
        #expect(correlation?.traceID == "t")
        #expect(correlation?.stepID == nil)
    }

    @Test("Unusable identifiers record no correlation instead of a misleading one", arguments: [
        BabylonTrafficPackageDTO.CorrelationContext(sessionID: "s", traceID: "", stepID: "a", createdAt: 1),
        BabylonTrafficPackageDTO.CorrelationContext(sessionID: "", traceID: "t", stepID: "a", createdAt: 1),
        BabylonTrafficPackageDTO.CorrelationContext(sessionID: "s", traceID: "has space", stepID: "a", createdAt: 1),
        BabylonTrafficPackageDTO.CorrelationContext(sessionID: "s", traceID: "t", stepID: "bad\nstep", createdAt: 1),
        BabylonTrafficPackageDTO.CorrelationContext(
            sessionID: "s",
            traceID: String(repeating: "x", count: BabylonCaptureProtocol.maximumClientIDSize + 1),
            stepID: "a",
            createdAt: 1
        ),
    ])
    func rejectsUnusableIdentifiers(context: BabylonTrafficPackageDTO.CorrelationContext) {
        #expect(BabylonCorrelation(context: context) == nil)
    }

    @Test("Concurrent traces keep their own requests")
    func concurrentTracesDoNotCrossAttribute() throws {
        let first = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(
                id: "a",
                context: .init(sessionID: "s", traceID: "checkout", stepID: "pay", createdAt: 1)
            ),
            identity: identity
        )
        let second = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(id: "b", context: .init(sessionID: "s", traceID: "sync", stepID: "pay", createdAt: 1)),
            identity: identity
        )
        let unrelated = try BabylonCaptureMapper.makeTransaction(from: makePackage(id: "c"), identity: identity)
        let all = [first, second, unrelated]

        let checkout = SmartTrafficFilter.parse("trace:checkout")
        #expect(all.filter(checkout.matches).map(\.id) == [first.id])

        // The same step name in two traces is told apart by also matching the trace.
        let step = SmartTrafficFilter.parse(
            MainContentCoordinator.babylonTraceQuery(sessionID: "s", traceID: "sync", stepID: "pay")
        )
        #expect(all.filter(step.matches).map(\.id) == [second.id])
        #expect(step.remainingSearchText.isEmpty)
    }

    @Test("Trace identifiers are compared exactly")
    func traceTokenIsExact() throws {
        let transaction = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(context: .init(sessionID: "s", traceID: "Checkout-1", stepID: "", createdAt: 1)),
            identity: identity
        )
        #expect(SmartTrafficFilter.parse("trace:Checkout-1").matches(transaction))
        #expect(!SmartTrafficFilter.parse("trace:checkout-1").matches(transaction))
        #expect(!SmartTrafficFilter.parse("trace:Checkout").matches(transaction))
    }

    @Test("Runtime session, trace, and step traffic tokens compose exactly")
    func sessionTokenScopesRepeatedTraceIDs() throws {
        let first = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(
                id: "first",
                context: .init(sessionID: "s1", traceID: "checkout", stepID: "pay", createdAt: 1)
            ),
            identity: identity
        )
        let second = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(
                id: "second",
                context: .init(sessionID: "s2", traceID: "checkout", stepID: "pay", createdAt: 1)
            ),
            identity: identity
        )
        let query = MainContentCoordinator.babylonTraceQuery(sessionID: "s2", traceID: "checkout", stepID: "pay")
        let filter = SmartTrafficFilter.parse(query)

        #expect([first, second].filter(filter.matches).map(\.id) == [second.id])
        #expect(filter.remainingSearchText.isEmpty)
    }

    @Test("Source, session, trace, and step tokens isolate identical contexts from different clients")
    func sourceTokenScopesRepeatedClientContexts() throws {
        let context = BabylonTrafficPackageDTO.CorrelationContext(
            sessionID: "shared-session",
            traceID: "checkout",
            stepID: "pay",
            createdAt: 1
        )
        let first = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(id: "first", context: context),
            identity: identity
        )
        let secondIdentity = BabylonCaptureIdentity(
            clientID: "client \"2\"",
            sessionID: identity.sessionID,
            projectName: identity.projectName,
            bundleIdentifier: identity.bundleIdentifier,
            deviceName: identity.deviceName,
            deviceModel: identity.deviceModel
        )
        let second = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(id: "second", context: context),
            identity: secondIdentity
        )
        let query = MainContentCoordinator.babylonTraceQuery(
            sourceClientID: "client \"2\"",
            sessionID: "shared-session",
            traceID: "checkout",
            stepID: "pay"
        )
        let filter = SmartTrafficFilter.parse(query)

        #expect([first, second].filter(filter.matches).map(\.id) == [second.id])
        #expect(filter.remainingSearchText.isEmpty)
    }

    @Test("Saving and reloading a session keeps the correlation")
    func sessionRoundTripKeepsCorrelation() throws {
        let transaction = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(context: .init(sessionID: "s1", traceID: "checkout", stepID: "pay", createdAt: 1)),
            identity: identity
        )

        let data = try JSONEncoder().encode(CodableTransaction(from: transaction))
        let reloaded = try JSONDecoder().decode(CodableTransaction.self, from: data).toLiveModel()

        #expect(reloaded.babylonCorrelation == transaction.babylonCorrelation)
    }

    @Test("Exporting and importing a session keeps the runtime correlation")
    func exportedSessionRoundTripKeepsCorrelation() throws {
        let transaction = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(context: .init(sessionID: "s1", traceID: "checkout", stepID: "pay", createdAt: 1)),
            identity: identity
        )
        let metadata = SessionSerializer.makeMetadata(transactionCount: 1)

        let data = try SessionSerializer.serialize(transactions: [transaction], metadata: metadata)
        let imported = try SessionSerializer.deserialize(from: data)
        let restored = try #require(imported.transactions.first).toLiveModel()

        #expect(restored.babylonCorrelation == transaction.babylonCorrelation)
    }

    @Test("A session saved before correlation was recorded still opens")
    func legacySessionDecodesWithoutCorrelation() throws {
        let transaction = try BabylonCaptureMapper.makeTransaction(from: makePackage(), identity: identity)
        var json = try #require(
            JSONSerialization
                .jsonObject(with: JSONEncoder().encode(CodableTransaction(from: transaction))) as? [String: Any]
        )
        json["babylonCorrelation"] = ["unexpected": true]
        let data = try JSONSerialization.data(withJSONObject: json)

        let reloaded = try JSONDecoder().decode(CodableTransaction.self, from: data).toLiveModel()

        #expect(reloaded.babylonCorrelation == nil)
    }

    @Test("Redacted exports keep the correlation")
    func redactionKeepsCorrelation() throws {
        let transaction = try BabylonCaptureMapper.makeTransaction(
            from: makePackage(context: .init(sessionID: "s1", traceID: "checkout", stepID: "pay", createdAt: 1)),
            identity: identity
        )

        let redacted = SensitiveDataRedactor().redactTransaction(transaction)

        #expect(redacted.babylonCorrelation == transaction.babylonCorrelation)
    }

    @Test("Runtime Events can be narrowed to one trace")
    func runtimeFilterByTrace() throws {
        let events = try [
            event(id: "1", kind: .traceStarted, trace: "checkout"),
            event(id: "2", kind: .traceStarted, trace: "sync"),
            event(id: "3", kind: .mark, trace: nil),
        ]

        let filter = BabylonRuntimeEventFilter(traceID: "checkout")

        #expect(filter.isActive)
        #expect(filter.apply(to: events).map(\.packageID) == ["1"])
    }

    @Test("Runtime filters isolate reused trace identifiers by runtime session")
    func runtimeFilterBySessionAndTrace() throws {
        let first = try event(id: "first", kind: .traceStarted, trace: "checkout", session: "s1")
        let second = try event(id: "second", kind: .traceStarted, trace: "checkout", session: "s2")
        let filter = BabylonRuntimeEventFilter(sessionID: "s2", traceID: "checkout")

        #expect(filter.apply(to: [first, second]).map(\.packageID) == ["second"])
    }

    @Test("Runtime step filter is exact within its trace and source scope")
    func runtimeFilterByStep() throws {
        let sourceA = try event(id: "a", kind: .stepStarted, trace: "checkout", step: "pay", clientID: "client-a")
        let sameStepOtherTrace = try event(
            id: "b",
            kind: .stepStarted,
            trace: "sync",
            step: "pay",
            clientID: "client-a"
        )
        let sameTraceOtherSource = try event(
            id: "c",
            kind: .stepStarted,
            trace: "checkout",
            step: "pay",
            clientID: "client-b"
        )
        let filter = BabylonRuntimeEventFilter(
            sourceClientID: "client-a",
            sessionID: "s",
            stepID: "pay",
            traceID: "checkout"
        )

        #expect(filter.apply(to: [sourceA, sameStepOtherTrace, sameTraceOtherSource]).map(\.packageID) == ["a"])
    }

    @Test("Step hierarchy is chronological and repairs missing parents and cycles")
    func nestedStepHierarchyHandlesOutOfOrderEvents() throws {
        let events = try [
            event(
                id: "child-finished",
                kind: .stepFinished,
                trace: "t",
                step: "child",
                parentStep: "parent",
                createdAt: 4
            ),
            event(id: "cycle-a", kind: .stepStarted, trace: "t", step: "cycle-a", parentStep: "cycle-b", createdAt: 5),
            event(id: "parent-started", kind: .stepStarted, trace: "t", step: "parent", createdAt: 1),
            event(
                id: "orphan",
                kind: .stepStarted,
                trace: "t",
                step: "orphan",
                parentStep: "evicted-parent",
                createdAt: 3
            ),
            event(id: "cycle-b", kind: .stepStarted, trace: "t", step: "cycle-b", parentStep: "cycle-a", createdAt: 6),
            event(
                id: "child-started",
                kind: .stepStarted,
                trace: "t",
                step: "child",
                parentStep: "parent",
                createdAt: 2
            ),
        ]

        let hierarchy = BabylonRuntimeStepHierarchy.build(from: events)

        #expect(hierarchy.map(\.stepID) == ["parent", "orphan", "cycle-a"])
        #expect(hierarchy[0].children.map(\.stepID) == ["child"])
        #expect(hierarchy[0].children[0].events.map(\.packageID) == ["child-started", "child-finished"])
        #expect(hierarchy.reduce(0) { $0 + $1.descendantCount } == 5)
    }

    @Test("Showing a step selects its start")
    func focusSelectsStepStart() throws {
        let events = try [
            event(id: "trace", kind: .traceStarted, trace: "t"),
            event(id: "start", kind: .stepStarted, trace: "t", step: "pay"),
            event(id: "end", kind: .stepFinished, trace: "t", step: "pay"),
        ]

        let focus = BabylonRuntimeNavigation.Focus(sessionID: "s", traceID: "t", stepID: "pay")

        #expect(BabylonRuntimeNavigation.eventID(for: focus, in: events) == events[1].id)
    }

    @Test("A step whose start was not received still resolves to that step")
    func focusHandlesOutOfOrderStep() throws {
        let events = try [
            event(id: "end", kind: .stepFinished, trace: "t", step: "pay", createdAt: 2),
            event(id: "start", kind: .stepStarted, trace: "t", step: "pay", createdAt: 1),
            event(id: "trace", kind: .traceStarted, trace: "t", createdAt: 0),
        ]

        let focus = BabylonRuntimeNavigation.Focus(sessionID: "s", traceID: "t", stepID: "pay")

        #expect(BabylonRuntimeNavigation.eventID(for: focus, in: events) == events[1].id)
    }

    @Test("An unknown step falls back to the trace, and an unknown trace selects nothing")
    func focusFallsBackHonestly() throws {
        let events = try [
            event(id: "mark", kind: .mark, trace: "t"),
            event(id: "trace", kind: .traceStarted, trace: "t"),
        ]

        let unknownStep = BabylonRuntimeNavigation.Focus(sessionID: "s", traceID: "t", stepID: "missing")
        let unknownTrace = BabylonRuntimeNavigation.Focus(sessionID: "s", traceID: "other", stepID: nil)

        #expect(BabylonRuntimeNavigation.eventID(for: unknownStep, in: events) == events[1].id)
        #expect(BabylonRuntimeNavigation.eventID(for: unknownTrace, in: events) == nil)
    }

    @Test("Focused trace selection stays within its runtime session")
    func focusScopesRepeatedTraceIDsBySession() throws {
        let first = try event(id: "first", kind: .traceStarted, trace: "t", session: "s", clientID: "client-1")
        let second = try event(id: "second", kind: .traceStarted, trace: "t", session: "s", clientID: "client 2")
        let focus = BabylonRuntimeNavigation.Focus(
            sourceClientID: "client 2",
            sessionID: "s",
            traceID: "t",
            stepID: nil
        )

        #expect(BabylonRuntimeNavigation.eventID(for: focus, in: [first, second]) == second.id)
    }

    @Test("A hidden old event cannot remain in the inspector after the visible trace changes")
    func selectionFollowsVisibleEvents() throws {
        let previous = try event(id: "previous", kind: .mark, trace: "old", session: "old-session")
        let current = try event(id: "current", kind: .mark, trace: "new", session: "new-session")

        #expect(BabylonRuntimeNavigation.selectedVisibleEvent(for: previous.id, in: [current]) == nil)
        #expect(BabylonRuntimeNavigation.selectedVisibleEvent(for: current.id, in: [current]) == current)
        #expect(BabylonRuntimeNavigation.reconciledSelection(previous.id, visibleIDs: [current.id]) == current.id)
        #expect(BabylonRuntimeNavigation.reconciledSelection(nil, visibleIDs: [current.id]) == nil)
        #expect(BabylonRuntimeNavigation.reconciledSelection(previous.id, visibleIDs: []) == nil)
    }

    @Test("A focus request stays pending until its event arrives or is cleared")
    @MainActor
    func focusWaitsForLateEvents() throws {
        let navigation = BabylonRuntimeNavigation()
        navigation.focus(sessionID: "s1", traceID: "t", stepID: "late")

        #expect(navigation.pendingFocus?.sessionID == "s1")
        #expect(navigation.pendingFocus?.traceID == "t")
        #expect(try BabylonRuntimeNavigation.eventID(for: #require(navigation.pendingFocus), in: []) == nil)

        let lateStep = try event(id: "late-step", kind: .stepStarted, trace: "t", step: "late", session: "s1")
        #expect(
            try BabylonRuntimeNavigation.eventID(for: #require(navigation.pendingFocus), in: [lateStep]) == lateStep.id
        )
        navigation.clearPendingFocus()
        #expect(navigation.pendingFocus == nil)

        navigation.focus(sessionID: "s2", traceID: "late", stepID: "step")
        navigation.clearPendingFocus()
        #expect(navigation.pendingFocus == nil)
    }

    // MARK: Private

    private let identity = BabylonCaptureIdentity(
        clientID: "client",
        sessionID: "session",
        projectName: "Example",
        bundleIdentifier: "com.example.app",
        deviceName: "iPhone",
        deviceModel: "iPhone 17"
    )

    private func makePackage(
        id: String = "request",
        context: BabylonTrafficPackageDTO.CorrelationContext? = nil
    )
        -> BabylonTrafficPackageDTO
    {
        BabylonTrafficPackageDTO(
            id: id,
            startAt: 100,
            request: .init(url: "https://api.example.com/items", method: "GET", headers: [], body: nil),
            response: .init(statusCode: 200, headers: []),
            error: nil,
            responseBodyData: Data("ok".utf8),
            endAt: 100.5,
            packageType: .http,
            correlationContext: context,
            urlSessionTiming: nil,
            websocketMessagePackage: nil,
            grpcCapture: nil
        )
    }

    private func event(
        id: String,
        kind: BabylonRuntimePackageDTO.Kind,
        trace: String?,
        step: String? = nil,
        parentStep: String? = nil,
        session: String = "s",
        clientID: String = "client",
        createdAt: TimeInterval = 1
    )
        throws -> BabylonRuntimeEvent
    {
        try BabylonRuntimeEvent(
            validating: BabylonRuntimePackageDTO(
                id: id,
                kind: kind,
                sessionID: session,
                traceID: trace,
                stepID: step,
                parentStepID: parentStep,
                name: id,
                createdAt: createdAt,
                startedAt: nil,
                endedAt: nil,
                duration: nil,
                metadata: [:],
                error: nil
            ),
            source: BabylonCaptureIdentity(
                clientID: clientID,
                sessionID: identity.sessionID,
                projectName: identity.projectName,
                bundleIdentifier: identity.bundleIdentifier,
                deviceName: identity.deviceName,
                deviceModel: identity.deviceModel
            )
        )
    }
}
