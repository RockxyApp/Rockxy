import Foundation
@testable import Rockxy
import Testing

// Regression tests for the system proxy override rate limit and for evaluating it inside the
// privileged mutation gate rather than beside it.

// MARK: - HelperProxyRateLimitPolicyTests

struct HelperProxyRateLimitPolicyTests {
    @Test("The first request of a session is never rate limited")
    func firstRequestIsAllowed() {
        #expect(!HelperProxyRateLimitPolicy.isRateLimited(
            lastChange: nil,
            now: Date(timeIntervalSince1970: 1_000),
            interval: 2.0
        ))
    }

    @Test("A request inside the interval is refused and one on the boundary is not")
    func intervalBoundaryIsExclusive() {
        let lastChange = Date(timeIntervalSince1970: 1_000)

        #expect(HelperProxyRateLimitPolicy.isRateLimited(
            lastChange: lastChange,
            now: lastChange.addingTimeInterval(1.999),
            interval: 2.0
        ))
        #expect(!HelperProxyRateLimitPolicy.isRateLimited(
            lastChange: lastChange,
            now: lastChange.addingTimeInterval(2.0),
            interval: 2.0
        ))
        #expect(!HelperProxyRateLimitPolicy.isRateLimited(
            lastChange: lastChange,
            now: lastChange.addingTimeInterval(30),
            interval: 2.0
        ))
    }

    @Test("A backward wall-clock adjustment does not extend the rate limit")
    func backwardClockAdjustmentIsAllowed() {
        let lastChange = Date(timeIntervalSince1970: 1_000)

        #expect(!HelperProxyRateLimitPolicy.isRateLimited(
            lastChange: lastChange,
            now: lastChange.addingTimeInterval(-30),
            interval: 2.0
        ))
    }
}

// MARK: - GatedProxyRateLimitTests

/// Mirrors the shape of the helper's override entry point: the rate-limit read, the mutation, and
/// the timestamp write all happen inside one `withExclusiveAccess` turn.
struct GatedProxyRateLimitTests {
    // MARK: Internal

    @Test("A busy gate refuses the request without reading or advancing the timestamp")
    func busyGateNeitherReadsNorWritesTheTimestamp() throws {
        let gate = HelperPrivilegedMutationGate()
        let recorder = OverrideRecorder(gate: gate)

        let ticket = try #require(gate.tryAcquire())
        #expect(recorder.override() == .busy)
        #expect(recorder.appliedCount == 0)
        #expect(recorder.observedLastChange == nil)

        gate.release(ticket)
        #expect(recorder.override() == .applied)
        #expect(recorder.appliedCount == 1)
    }

    @Test("A second request inside the interval is rate limited, not applied")
    func repeatRequestIsRateLimited() {
        let recorder = OverrideRecorder(gate: HelperPrivilegedMutationGate())

        #expect(recorder.override() == .applied)
        #expect(recorder.override() == .rateLimited)
        #expect(recorder.appliedCount == 1)

        recorder.rewindLastChange(by: 5)
        #expect(recorder.override() == .applied)
        #expect(recorder.appliedCount == 2)
    }

    @Test("Concurrent requests cannot both see an unset timestamp")
    func concurrentRequestsSerializeOnTheTimestamp() async {
        let recorder = OverrideRecorder(gate: HelperPrivilegedMutationGate())

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 16 {
                group.addTask {
                    // The gate never waits, so a refused caller retries — the point under test is
                    // that whoever gets in sees a timestamp nobody else is midway through writing.
                    while recorder.override() == .busy {
                        continue
                    }
                }
            }
        }

        // Reading and writing the timestamp in the same guarded turn is what makes exactly one
        // request the first: reading it outside the gate let several observe the unset value.
        #expect(recorder.firstRequestCount == 1)
        #expect(recorder.appliedCount == 1)
    }

    // MARK: Private

    private enum OverrideResult: Equatable {
        case applied
        case rateLimited
        case busy
    }

    private final class OverrideRecorder: @unchecked Sendable {
        // MARK: Lifecycle

        init(gate: HelperPrivilegedMutationGate) {
            self.gate = gate
        }

        // MARK: Internal

        private(set) var appliedCount = 0
        private(set) var firstRequestCount = 0
        private(set) var observedLastChange: Date?

        func override() -> OverrideResult {
            gate.withExclusiveAccess { () -> OverrideResult in
                observedLastChange = lastProxyChangeTime
                if lastProxyChangeTime == nil {
                    firstRequestCount += 1
                }
                guard !HelperProxyRateLimitPolicy.isRateLimited(
                    lastChange: lastProxyChangeTime,
                    now: Date(),
                    interval: 2.0
                ) else {
                    return .rateLimited
                }
                appliedCount += 1
                lastProxyChangeTime = Date()
                return .applied
            } ?? .busy
        }

        func rewindLastChange(by interval: TimeInterval) {
            lastProxyChangeTime = lastProxyChangeTime?.addingTimeInterval(-interval)
        }

        // MARK: Private

        private let gate: HelperPrivilegedMutationGate
        private var lastProxyChangeTime: Date?
    }
}
