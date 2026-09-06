import Dispatch
import Foundation
@testable import Rockxy
import Testing

// Regression tests for `RecentFailureTracker` in the core proxy engine layer.

struct RecentFailureTrackerTests {
    @Test("first failure starts a new window")
    func firstFailureStartsNewWindow() {
        let tracker = RecentFailureTracker(
            nowProvider: {
                DispatchTime(uptimeNanoseconds: 1_000_000_000)
            }
        )

        let info = tracker.recordFailure(host: "example.com")

        #expect(info.count == 1)
        #expect(info.lastFailed.uptimeNanoseconds == 1_000_000_000)
    }

    @Test("failure within the window increments count")
    func failureWithinWindowIncrementsCount() {
        var timestamps: [UInt64] = [1_000_000_000, 5_000_000_000]
        let tracker = RecentFailureTracker(
            windowSeconds: 30,
            nowProvider: {
                DispatchTime(uptimeNanoseconds: timestamps.removeFirst())
            }
        )

        _ = tracker.recordFailure(host: "example.com")
        let info = tracker.recordFailure(host: "example.com")

        #expect(info.count == 2)
        #expect(info.lastFailed.uptimeNanoseconds == 5_000_000_000)
    }

    @Test("failure outside the window resets count")
    func failureOutsideWindowResetsCount() {
        var timestamps: [UInt64] = [1_000_000_000, 40_000_000_000]
        let tracker = RecentFailureTracker(
            windowSeconds: 30,
            nowProvider: {
                DispatchTime(uptimeNanoseconds: timestamps.removeFirst())
            }
        )

        _ = tracker.recordFailure(host: "example.com")
        let info = tracker.recordFailure(host: "example.com")

        #expect(info.count == 1)
        #expect(info.lastFailed.uptimeNanoseconds == 40_000_000_000)
    }

    @Test("out-of-order timestamps do not underflow and still update the host")
    func outOfOrderTimestampsDoNotUnderflow() {
        var timestamps: [UInt64] = [5_000_000_000, 1_000_000_000]
        let tracker = RecentFailureTracker(
            windowSeconds: 30,
            nowProvider: {
                DispatchTime(uptimeNanoseconds: timestamps.removeFirst())
            }
        )

        _ = tracker.recordFailure(host: "img.alicdn.com")
        let info = tracker.recordFailure(host: "img.alicdn.com")

        #expect(info.count == 2)
        #expect(info.lastFailed.uptimeNanoseconds == 1_000_000_000)
    }

    @Test("successful handshake starts a fresh failure window for the host")
    func successClearsDuplicateSuppression() {
        var timestamps: [UInt64] = [1_000_000_000, 2_000_000_000]
        let tracker = RecentFailureTracker(
            windowSeconds: 30,
            nowProvider: {
                DispatchTime(uptimeNanoseconds: timestamps.removeFirst())
            }
        )

        _ = tracker.recordFailure(host: "example.com")
        tracker.recordSuccess(host: "example.com")
        let info = tracker.recordFailure(host: "example.com")

        #expect(info.count == 1)
        #expect(info.lastFailed.uptimeNanoseconds == 2_000_000_000)
    }

    @Test("one client cannot suppress another client on the same host")
    func failuresAreScopedByClient() {
        var timestamps: [UInt64] = [1_000_000_000, 2_000_000_000, 3_000_000_000]
        let tracker = RecentFailureTracker(
            windowSeconds: 30,
            nowProvider: { DispatchTime(uptimeNanoseconds: timestamps.removeFirst()) }
        )

        _ = tracker.recordFailure(host: "example.com", clientIdentifier: "app.one")
        let otherClient = tracker.recordFailure(host: "example.com", clientIdentifier: "app.two")
        let firstClientAgain = tracker.recordFailure(host: "example.com", clientIdentifier: "app.one")

        #expect(otherClient.count == 1)
        #expect(firstClientAgain.count == 2)
    }

    @Test("success clears only the matching client and host")
    func successIsScopedByClient() {
        var timestamps: [UInt64] = [1_000_000_000, 2_000_000_000, 3_000_000_000, 4_000_000_000]
        let tracker = RecentFailureTracker(
            windowSeconds: 30,
            nowProvider: { DispatchTime(uptimeNanoseconds: timestamps.removeFirst()) }
        )

        _ = tracker.recordFailure(host: "example.com", clientIdentifier: "app.one")
        _ = tracker.recordFailure(host: "example.com", clientIdentifier: "app.two")
        tracker.recordSuccess(host: "example.com", clientIdentifier: "app.one")

        #expect(tracker.recordFailure(host: "example.com", clientIdentifier: "app.one").count == 1)
        #expect(tracker.recordFailure(host: "example.com", clientIdentifier: "app.two").count == 2)
    }

    @Test("tracker evicts old keys instead of growing without bound")
    func trackerIsBounded() {
        var now: UInt64 = 1_000_000_000
        let tracker = RecentFailureTracker(
            windowSeconds: 30,
            maximumEntries: 2,
            nowProvider: { DispatchTime(uptimeNanoseconds: now) }
        )

        _ = tracker.recordFailure(host: "one.example", clientIdentifier: "app")
        now += 1_000_000_000
        _ = tracker.recordFailure(host: "two.example", clientIdentifier: "app")
        now += 1_000_000_000
        _ = tracker.recordFailure(host: "three.example", clientIdentifier: "app")

        #expect(tracker.trackedEntryCount == 2)
    }
}
