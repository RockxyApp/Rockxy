import Foundation
@testable import Rockxy
import Testing

@Suite("Connection limiter")
struct ConnectionLimiterTests {
    @Test("default capacity accepts realistic parallel client bursts and remains bounded")
    func defaultCapacitySupportsParallelClients() {
        let limiter = ConnectionLimiter()

        for _ in 0 ..< 64 {
            #expect(limiter.acquire(host: "plugins.jetbrains.com", port: 443))
        }
        #expect(!limiter.acquire(host: "plugins.jetbrains.com", port: 443))

        limiter.release(host: "plugins.jetbrains.com", port: 443)
        #expect(limiter.acquire(host: "plugins.jetbrains.com", port: 443))
    }

    @Test("destination identity is case-insensitive and ignores a DNS trailing dot")
    func destinationIsCanonicalized() {
        let limiter = ConnectionLimiter(maxPerDestination: 1)

        #expect(limiter.acquire(host: "Example.COM.", port: 443))
        #expect(!limiter.acquire(host: "example.com", port: 443))
        #expect(limiter.acquire(host: "example.com", port: 8_443))
    }

    @Test("release below zero does not poison a future acquisition")
    func unmatchedReleaseIsHarmless() {
        let limiter = ConnectionLimiter(maxPerDestination: 1)

        limiter.release(host: "example.com", port: 443)
        #expect(limiter.acquire(host: "example.com", port: 443))
    }

    @Test("saturating one destination leaves another destination available")
    func destinationsHaveIndependentCapacity() {
        let limiter = ConnectionLimiter(maxPerDestination: 1)

        #expect(limiter.acquire(host: "api.example.com", port: 443))
        #expect(!limiter.acquire(host: "api.example.com", port: 443))
        #expect(limiter.acquire(host: "assets.example.com", port: 443))
    }

    @Test("concurrent acquisitions never exceed the configured capacity")
    func concurrentAcquisitionsRemainBounded() async {
        let limiter = ConnectionLimiter(maxPerDestination: 8)
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0 ..< 64 {
                group.addTask {
                    limiter.acquire(host: "burst.example.com", port: 443)
                }
            }

            var outcomes: [Bool] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }

        #expect(results.filter(\.self).count == 8)
        #expect(results.filter { !$0 }.count == 56)
    }
}
