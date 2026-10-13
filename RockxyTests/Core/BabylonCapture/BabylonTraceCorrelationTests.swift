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
            traceID: String(repeating: "x", count: 300),
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
        let step = SmartTrafficFilter.parse(MainContentCoordinator.babylonTraceQuery(traceID: "sync", stepID: "pay"))
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

    @Test("Showing a step selects its start")
    func focusSelectsStepStart() throws {
        let events = try [
            event(id: "trace", kind: .traceStarted, trace: "t"),
            event(id: "start", kind: .stepStarted, trace: "t", step: "pay"),
            event(id: "end", kind: .stepFinished, trace: "t", step: "pay"),
        ]

        let focus = BabylonRuntimeNavigation.Focus(traceID: "t", stepID: "pay")

        #expect(BabylonRuntimeNavigation.eventID(for: focus, in: events) == events[1].id)
    }

    @Test("A step whose start was not received still resolves to that step")
    func focusHandlesOutOfOrderStep() throws {
        let events = try [
            event(id: "end", kind: .stepFinished, trace: "t", step: "pay"),
            event(id: "trace", kind: .traceStarted, trace: "t"),
        ]

        let focus = BabylonRuntimeNavigation.Focus(traceID: "t", stepID: "pay")

        #expect(BabylonRuntimeNavigation.eventID(for: focus, in: events) == events[0].id)
    }

    @Test("An unknown step falls back to the trace, and an unknown trace selects nothing")
    func focusFallsBackHonestly() throws {
        let events = try [
            event(id: "mark", kind: .mark, trace: "t"),
            event(id: "trace", kind: .traceStarted, trace: "t"),
        ]

        let unknownStep = BabylonRuntimeNavigation.Focus(traceID: "t", stepID: "missing")
        let unknownTrace = BabylonRuntimeNavigation.Focus(traceID: "other", stepID: nil)

        #expect(BabylonRuntimeNavigation.eventID(for: unknownStep, in: events) == events[1].id)
        #expect(BabylonRuntimeNavigation.eventID(for: unknownTrace, in: events) == nil)
    }

    @Test("A focus request is applied once")
    @MainActor
    func focusIsConsumedOnce() {
        let navigation = BabylonRuntimeNavigation()
        navigation.focus(traceID: "t", stepID: nil)

        #expect(navigation.consume()?.traceID == "t")
        #expect(navigation.consume() == nil)
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
            websocketMessagePackage: nil
        )
    }

    private func event(
        id: String,
        kind: BabylonRuntimePackageDTO.Kind,
        trace: String?,
        step: String? = nil
    )
        throws -> BabylonRuntimeEvent
    {
        try BabylonRuntimeEvent(
            validating: BabylonRuntimePackageDTO(
                id: id,
                kind: kind,
                sessionID: "s",
                traceID: trace,
                stepID: step,
                parentStepID: nil,
                name: id,
                createdAt: 1,
                startedAt: nil,
                endedAt: nil,
                duration: nil,
                metadata: [:],
                error: nil
            ),
            source: identity
        )
    }
}
