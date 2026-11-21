import Foundation
@testable import Rockxy
import Testing

// MARK: - BabylonRuntimeEventTests

/// Behavioral contracts for the runtime event model, its bounded validation,
/// composite identity, filtering projection, intake batching, and the
/// count/byte-bounded retention store.
struct BabylonRuntimeEventTests {
    // MARK: Internal

    // MARK: Model mapping, validation, and bounds

    @Test("Valid package maps into a bounded event and preserves the package ID separately")
    func validPackageMapsWithBounds() throws {
        let package = makePackage(
            id: "pkg-1",
            name: String(repeating: "n", count: 900),
            metadata: ["b": "beta", "a": "alpha"],
            errorMessage: String(repeating: "e", count: 5_000)
        )
        let event = try BabylonRuntimeEvent(validating: package, source: makeIdentity())

        #expect(event.packageID == "pkg-1")
        #expect(event.name.utf8.count == BabylonRuntimeEvent.maximumNameByteCount)
        // CapturedError applies the tighter wire-level cap before runtime-event retention.
        #expect(event.errorMessage?.utf8.count == 1_024)
        #expect(event.metadata == ["a": "alpha", "b": "beta"])
        #expect(event.isContentTruncated)
        #expect(event.truncatedFields == [.name])
        #expect(event.byteCount > 0)
    }

    @Test("Metadata is bounded to producer-compatible pair, key, and value limits")
    func metadataIsBounded() throws {
        var metadata: [String: String] = [:]
        for index in 0 ..< 200 {
            // Zero-padded keys keep the retained subset deterministic after sorting.
            metadata[String(format: "key-%03d", index)] = "value-\(index)"
        }
        metadata["huge-key-" + String(repeating: "k", count: 200)] = String(repeating: "v", count: 8_000)

        let event = try BabylonRuntimeEvent(
            validating: makePackage(id: "pkg-meta", metadata: metadata),
            source: makeIdentity()
        )

        #expect(event.metadata.count == BabylonRuntimeEvent.maximumMetadataPairs)
        for (key, value) in event.metadata {
            #expect(key.utf8.count <= BabylonRuntimeEvent.maximumMetadataKeyByteCount)
            #expect(value.utf8.count <= BabylonRuntimeEvent.maximumMetadataValueByteCount)
        }
        // Deterministic selection keeps the lexicographically-smallest keys.
        #expect(event.metadata["key-000"] == "value-0")
        #expect(event.metadata["key-100"] == nil)
        #expect(event.isContentTruncated)
        #expect(event.truncatedFields == [.metadata])
    }

    @Test("UTF-8 byte limits cannot be bypassed with multi-byte or combining characters")
    func utf8LimitsAreEnforced() throws {
        let event = try BabylonRuntimeEvent(
            validating: makePackage(
                id: "pkg-unicode",
                name: String(repeating: "🧪", count: 600),
                metadata: ["a": String(repeating: "é", count: 4_000)]
            ),
            source: makeIdentity()
        )

        #expect(event.name.utf8.count <= BabylonRuntimeEvent.maximumNameByteCount)
        #expect(event.metadata["a"]?.utf8.count == BabylonRuntimeEvent.maximumMetadataValueByteCount)
        #expect(event.isContentTruncated)

        let overLongID = String(repeating: "é", count: BabylonRuntimeEvent.maximumIdentifierByteCount / 2 + 1)
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(validating: makePackage(id: overLongID), source: makeIdentity())
        }
    }

    @Test("Empty or over-long package identifiers are rejected before retention")
    func invalidPackageIdentifierRejected() {
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(validating: makePackage(id: ""), source: makeIdentity())
        }
        let overLong = String(repeating: "x", count: BabylonRuntimeEvent.maximumIdentifierByteCount + 1)
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(validating: makePackage(id: overLong), source: makeIdentity())
        }
    }

    @Test("Invalid runtime correlation identifiers are rejected instead of truncated")
    func invalidRuntimeIdentifiersRejected() {
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(
                validating: makePackage(id: "pkg", sessionID: ""),
                source: makeIdentity()
            )
        }
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(
                validating: makePackage(id: "pkg", traceID: "trace\ninjected"),
                source: makeIdentity()
            )
        }
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(
                validating: makePackage(id: "pkg", kind: .stepStarted, stepID: nil),
                source: makeIdentity()
            )
        }
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(
                validating: makePackage(
                    id: "pkg",
                    traceID: String(repeating: "x", count: BabylonRuntimeEvent.maximumIdentifierByteCount + 1)
                ),
                source: makeIdentity()
            )
        }
    }

    @Test("Non-finite timing or duration is rejected before retention")
    func nonFiniteTimingRejected() {
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(
                validating: makePackage(id: "pkg-nan", createdAt: .nan),
                source: makeIdentity()
            )
        }
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(
                validating: makePackage(id: "pkg-negative", duration: -0.1),
                source: makeIdentity()
            )
        }
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(
                validating: makePackage(id: "pkg-reversed", startedAt: 200, endedAt: 100),
                source: makeIdentity()
            )
        }
        #expect(throws: BabylonRuntimeValidationError.self) {
            _ = try BabylonRuntimeEvent(
                validating: makePackage(id: "pkg-inf", duration: .infinity),
                source: makeIdentity()
            )
        }
    }

    // MARK: Composite identity and dedup

    @Test("Identical package IDs from different clients or sessions stay distinct")
    func compositeIdentityDistinguishesSources() throws {
        let clientA = makeIdentity(clientID: "client-A", sessionID: "session-1")
        let clientB = makeIdentity(clientID: "client-B", sessionID: "session-1")
        let sameClientOtherSession = makeIdentity(clientID: "client-A", sessionID: "session-2")

        let eventA = try BabylonRuntimeEvent(validating: makePackage(id: "shared"), source: clientA)
        let eventB = try BabylonRuntimeEvent(validating: makePackage(id: "shared"), source: clientB)
        let eventC = try BabylonRuntimeEvent(validating: makePackage(id: "shared"), source: sameClientOtherSession)

        #expect(eventA.packageID == eventB.packageID)
        #expect(eventA.id != eventB.id)
        #expect(eventA.id != eventC.id)
    }

    @MainActor
    @Test("Store ignores exact composite duplicates but keeps same package ID from other sources")
    func storeDeduplicatesCompositeIdentity() throws {
        let store = BabylonRuntimeEventStore(maximumEventCount: 100)
        let clientA = makeIdentity(clientID: "client-A")
        let clientB = makeIdentity(clientID: "client-B")

        let first = try BabylonRuntimeEvent(validating: makePackage(id: "shared"), source: clientA)
        let duplicate = try BabylonRuntimeEvent(validating: makePackage(id: "shared"), source: clientA)
        let otherSource = try BabylonRuntimeEvent(validating: makePackage(id: "shared"), source: clientB)

        store.appendBatch([first, duplicate, otherSource])

        #expect(store.events.count == 2)
        #expect(store.events.map(\.source.clientID) == ["client-A", "client-B"])
    }

    @MainActor
    @Test("A duplicate stays suppressed after its original event is evicted")
    func storeDeduplicatesRecentlyEvictedIdentity() throws {
        let store = BabylonRuntimeEventStore(maximumEventCount: 1)
        let first = try BabylonRuntimeEvent(validating: makePackage(id: "first"), source: makeIdentity())
        let second = try BabylonRuntimeEvent(validating: makePackage(id: "second"), source: makeIdentity())

        store.append(first)
        store.append(second)
        store.append(first)

        #expect(store.events.map(\.packageID) == ["second"])
        #expect(store.evictedEventCount == 1)
    }

    // MARK: Retention and eviction accounting

    @MainActor
    @Test("Count-bounded retention evicts oldest arrivals and tracks eviction truthfully")
    func countBoundedRetentionEvictsOldest() throws {
        let store = BabylonRuntimeEventStore(maximumEventCount: 3)
        for index in 0 ..< 6 {
            try store.append(BabylonRuntimeEvent(validating: makePackage(id: "pkg-\(index)"), source: makeIdentity()))
        }

        #expect(store.events.count == 3)
        #expect(store.events.map(\.packageID) == ["pkg-3", "pkg-4", "pkg-5"])
        #expect(store.evictedEventCount == 3)
    }

    @MainActor
    @Test("Byte-bounded retention drops oldest events and keeps retained bytes within budget")
    func byteBoundedRetention() throws {
        let sample = try BabylonRuntimeEvent(validating: makePackage(id: "sample"), source: makeIdentity())
        // Budget for roughly two events forces eviction on the third.
        let budget = sample.byteCount * 2 + 1
        let store = BabylonRuntimeEventStore(
            maximumEventCount: 1_000,
            maximumRetainedByteCount: budget
        )
        for index in 0 ..< 5 {
            try store.append(BabylonRuntimeEvent(validating: makePackage(id: "pkg-\(index)"), source: makeIdentity()))
        }

        #expect(store.retainedByteCount <= budget)
        #expect(store.retainedByteCount == store.events.reduce(0) { $0 + $1.byteCount })
        #expect(store.events.last?.packageID == "pkg-4")
        #expect(store.evictedEventCount >= 2)
    }

    @MainActor
    @Test("A single event larger than the byte budget is evicted instead of exceeding the cap")
    func singleOversizedEventIsEvicted() throws {
        let event = try BabylonRuntimeEvent(
            validating: makePackage(id: "oversized", name: String(repeating: "x", count: 400)),
            source: makeIdentity()
        )
        let budget = max(1, event.byteCount - 1)
        let store = BabylonRuntimeEventStore(maximumEventCount: 10, maximumRetainedByteCount: budget)

        store.append(event)

        #expect(store.events.isEmpty)
        #expect(store.retainedByteCount == 0)
        #expect(store.evictedEventCount == 1)
    }

    @MainActor
    @Test("Ordered batch append preserves FIFO order")
    func orderedBatchAppend() throws {
        let store = BabylonRuntimeEventStore(maximumEventCount: 100)
        let events = try (0 ..< 4).map {
            try BabylonRuntimeEvent(validating: makePackage(id: "pkg-\($0)"), source: makeIdentity())
        }
        store.appendBatch(events)
        #expect(store.events.map(\.packageID) == ["pkg-0", "pkg-1", "pkg-2", "pkg-3"])
    }

    @MainActor
    @Test("Clear resets events, retained bytes, eviction accounting, and dedup state")
    func clearResetsAllState() throws {
        let store = BabylonRuntimeEventStore(maximumEventCount: 2)
        for index in 0 ..< 5 {
            try store.append(BabylonRuntimeEvent(validating: makePackage(id: "pkg-\(index)"), source: makeIdentity()))
        }
        #expect(store.evictedEventCount > 0)

        store.clear()
        #expect(store.events.isEmpty)
        #expect(store.retainedByteCount == 0)
        #expect(store.evictedEventCount == 0)

        // A previously-seen composite ID can be retained again after a clear.
        try store.append(BabylonRuntimeEvent(validating: makePackage(id: "pkg-0"), source: makeIdentity()))
        #expect(store.events.count == 1)
    }

    // MARK: Filtering projection

    @Test("Filter combines kind, source, and search while preserving order")
    func filterProjection() throws {
        let identityA = makeIdentity(clientID: "client-A", projectName: "Alpha")
        let identityB = makeIdentity(clientID: "client-B", projectName: "Bravo")
        let events = try [
            BabylonRuntimeEvent(validating: makePackage(id: "1", kind: .stepStarted, name: "login"), source: identityA),
            BabylonRuntimeEvent(validating: makePackage(id: "2", kind: .error, name: "timeout"), source: identityA),
            BabylonRuntimeEvent(validating: makePackage(id: "3", kind: .stepStarted, name: "login"), source: identityB),
        ]

        var byKind = BabylonRuntimeEventFilter()
        byKind.kind = .stepStarted
        #expect(byKind.apply(to: events).map(\.packageID) == ["1", "3"])

        var bySource = BabylonRuntimeEventFilter()
        bySource.sourceClientID = "client-B"
        #expect(bySource.apply(to: events).map(\.packageID) == ["3"])

        var bySearch = BabylonRuntimeEventFilter()
        bySearch.searchText = "TIMEOUT"
        #expect(bySearch.apply(to: events).map(\.packageID) == ["2"])

        var bySearchID = BabylonRuntimeEventFilter()
        bySearchID.searchText = "Bravo"
        #expect(bySearchID.apply(to: events).map(\.packageID) == ["3"])

        let diagnostics = try BabylonRuntimeEvent(
            validating: makePackage(
                id: "4",
                name: "request",
                metadata: ["route": "checkout"],
                errorMessage: "deadline exceeded"
            ),
            source: identityB
        )
        var byError = BabylonRuntimeEventFilter(searchText: "deadline")
        #expect(byError.apply(to: [diagnostics]).map(\.packageID) == ["4"])
        byError.searchText = "checkout"
        #expect(byError.apply(to: [diagnostics]).map(\.packageID) == ["4"])

        #expect(!BabylonRuntimeEventFilter().isActive)
        #expect(byKind.isActive)
    }

    @Test("Outcome derives from kind and error presence")
    func outcomeDerivation() throws {
        let finished = try BabylonRuntimeEvent(
            validating: makePackage(id: "f", kind: .stepFinished),
            source: makeIdentity()
        )
        let started = try BabylonRuntimeEvent(
            validating: makePackage(id: "s", kind: .stepStarted),
            source: makeIdentity()
        )
        let mark = try BabylonRuntimeEvent(validating: makePackage(id: "m", kind: .mark), source: makeIdentity())
        let errored = try BabylonRuntimeEvent(
            validating: makePackage(id: "e", kind: .stepFinished, errorMessage: "boom"),
            source: makeIdentity()
        )

        #expect(finished.outcome == .finished)
        #expect(started.outcome == .started)
        #expect(mark.outcome == .informational)
        #expect(errored.outcome == .failed)
    }

    @Test("Received time is retained separately from producer event time")
    func receivedTimeIsSeparate() throws {
        let receivedAt = Date(timeIntervalSince1970: 500)
        let event = try BabylonRuntimeEvent(
            validating: makePackage(id: "clock", createdAt: 100),
            source: makeIdentity(),
            receivedAt: receivedAt
        )

        #expect(event.createdAt == Date(timeIntervalSince1970: 100))
        #expect(event.receivedAt == receivedAt)
    }

    // MARK: Intake buffer

    @Test("Intake buffer batches FIFO, signals full batches, and discards pending")
    func intakeBufferSemantics() throws {
        var buffer = BabylonRuntimeIntakeBuffer(batchSize: 2)
        let eventA = try BabylonRuntimeEvent(validating: makePackage(id: "a"), source: makeIdentity())
        let eventB = try BabylonRuntimeEvent(validating: makePackage(id: "b"), source: makeIdentity())

        buffer.enqueue(eventA)
        #expect(buffer.hasPending)
        #expect(!buffer.isReadyForImmediateFlush)

        buffer.enqueue(eventB)
        #expect(buffer.isReadyForImmediateFlush)

        let drained = buffer.drain()
        #expect(drained.map(\.packageID) == ["a", "b"])
        #expect(!buffer.hasPending)

        buffer.enqueue(eventA)
        buffer.discardPending()
        #expect(!buffer.hasPending)
        #expect(buffer.drain().isEmpty)
    }

    @Test("Publication gate invalidates batches captured before Clear or Stop")
    func publicationGateInvalidatesOlderGenerations() {
        let gate = BabylonRuntimePublicationGate()
        let beforeBarrier = gate.snapshot()

        #expect(gate.isCurrent(beforeBarrier))
        let afterBarrier = gate.advance()
        #expect(!gate.isCurrent(beforeBarrier))
        #expect(gate.isCurrent(afterBarrier))
    }

    @Test("Runtime payload size accepts its boundary and rejects larger content")
    func runtimePayloadSizeBoundary() throws {
        try BabylonCaptureReceiver.validateRuntimePayloadSize(
            BabylonCaptureReceiver.maximumRuntimePayloadSize
        )
        #expect(throws: BabylonCaptureProtocolError.self) {
            try BabylonCaptureReceiver.validateRuntimePayloadSize(
                BabylonCaptureReceiver.maximumRuntimePayloadSize + 1
            )
        }
        #expect(throws: BabylonCaptureProtocolError.self) {
            try BabylonCaptureReceiver.validateRuntimePayloadSize(-1)
        }
    }

    // MARK: Private

    // MARK: Fixtures

    private func makeIdentity(
        clientID: String = "client",
        sessionID: String = "session",
        projectName: String = "Example"
    )
        -> BabylonCaptureIdentity
    {
        BabylonCaptureIdentity(
            clientID: clientID,
            sessionID: sessionID,
            projectName: projectName,
            bundleIdentifier: "com.example.app",
            deviceName: "iPhone",
            deviceModel: "iPhone 17"
        )
    }

    private func makePackage(
        id: String,
        kind: BabylonRuntimePackageDTO.Kind = .event,
        sessionID: String = "runtime-session",
        traceID: String? = "trace-1",
        stepID: String? = "step-1",
        name: String = "event",
        createdAt: TimeInterval = 100,
        startedAt: TimeInterval? = 100,
        endedAt: TimeInterval? = 100.25,
        duration: TimeInterval? = 0.25,
        metadata: [String: String] = [:],
        errorMessage: String? = nil
    )
        -> BabylonRuntimePackageDTO
    {
        BabylonRuntimePackageDTO(
            id: id,
            kind: kind,
            sessionID: sessionID,
            traceID: traceID,
            stepID: stepID,
            parentStepID: nil,
            name: name,
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: duration,
            metadata: metadata,
            error: errorMessage.map { BabylonTrafficPackageDTO.CapturedError(code: 1, message: $0) }
        )
    }
}
