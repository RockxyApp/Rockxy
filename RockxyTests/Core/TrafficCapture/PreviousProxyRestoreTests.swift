import Foundation
@testable import Rockxy
import Testing

// Regression tests for capture over another proxy app's system proxy: the helper restore puts a
// Clash-style loopback endpoint back exactly, and when something else changed the settings during
// the session the previous settings are reported for the user to decide instead of disappearing.

// MARK: - PreviousProxyRestoreTests

struct PreviousProxyRestoreTests {
    // MARK: Internal

    @Test("Settings that route nothing are never offered back")
    func directSettingsDoNotRouteTraffic() {
        #expect(!PreviousProxyRestorePolicy.routesTraffic(Self.direct))
        #expect(PreviousProxyRestorePolicy.routesTraffic(Self.clash))
        #expect(PreviousProxyRestorePolicy.routesTraffic(Self.pac))
    }

    @Test("Host and port left on a switched-off endpoint do not count as a difference")
    func switchedOffEndpointsAreIgnored() {
        let leftover = Self.snapshot(http: (false, "127.0.0.1", 9_090), https: (false, "127.0.0.1", 9_090))
        #expect(PreviousProxyRestorePolicy.effectiveRoutingMatches(Self.direct, leftover))
        #expect(!PreviousProxyRestorePolicy.effectiveRoutingMatches(Self.clash, Self.direct))
    }

    @Test("A restored proxy app endpoint needs no decision")
    func restoredSettingsAreNotReported() {
        let unrestored = PreviousProxyRestorePolicy.unrestoredServices(
            previous: ["Wi-Fi": Self.clash],
            previousBypassDomains: ["Wi-Fi": Self.clashBypass],
            current: ["Wi-Fi": Self.clash],
            rockxyPort: Self.rockxyPort
        )
        #expect(unrestored.isEmpty)
    }

    @Test("A proxy app that switched everything off mid-session leaves its endpoint to offer back")
    func proxyAppSwitchedOffIsReported() {
        let unrestored = PreviousProxyRestorePolicy.unrestoredServices(
            previous: ["Wi-Fi": Self.clash, "USB LAN": Self.clash],
            previousBypassDomains: ["Wi-Fi": Self.clashBypass],
            current: ["Wi-Fi": Self.direct, "USB LAN": Self.clash],
            rockxyPort: Self.rockxyPort
        )
        #expect(unrestored == [
            UnrestoredPreviousProxy(
                service: "Wi-Fi",
                previous: Self.clash,
                previousBypassDomains: Self.clashBypass,
                current: Self.direct
            ),
        ])
    }

    @Test("Settings left on Rockxy's stopped listener are offered back too")
    func residualRockxyOverrideIsReported() {
        let rockxyOverride = Self.snapshot(
            http: (true, "127.0.0.1", Self.rockxyPort),
            https: (true, "127.0.0.1", Self.rockxyPort),
            socks: (true, "127.0.0.1", 7_890)
        )
        let unrestored = PreviousProxyRestorePolicy.unrestoredServices(
            previous: ["Wi-Fi": Self.clash],
            previousBypassDomains: [:],
            current: ["Wi-Fi": rockxyOverride],
            rockxyPort: Self.rockxyPort
        )
        #expect(unrestored.map(\.service) == ["Wi-Fi"])
        #expect(unrestored.first?.previousBypassDomains == nil)
    }

    @Test("A previous setting that pointed at Rockxy itself is never offered back")
    func previousRockxyOverrideIsNotReported() {
        let staleRockxy = Self.snapshot(
            http: (true, "127.0.0.1", Self.rockxyPort),
            https: (true, "127.0.0.1", Self.rockxyPort)
        )
        let unrestored = PreviousProxyRestorePolicy.unrestoredServices(
            previous: ["Wi-Fi": staleRockxy],
            previousBypassDomains: [:],
            current: ["Wi-Fi": Self.direct],
            rockxyPort: Self.rockxyPort
        )
        #expect(unrestored.isEmpty)
    }

    @Test("A service that cannot be read now is left out, because no later write could be proven safe")
    func unreadableServiceIsNotReported() {
        let unrestored = PreviousProxyRestorePolicy.unrestoredServices(
            previous: ["Wi-Fi": Self.clash],
            previousBypassDomains: [:],
            current: [:],
            rockxyPort: Self.rockxyPort
        )
        #expect(unrestored.isEmpty)
    }

    @Test("Services are reported in a stable order")
    func reportIsSorted() {
        let unrestored = PreviousProxyRestorePolicy.unrestoredServices(
            previous: ["Wi-Fi": Self.clash, "Ethernet": Self.pac],
            previousBypassDomains: [:],
            current: ["Wi-Fi": Self.direct, "Ethernet": Self.direct],
            rockxyPort: nil
        )
        #expect(unrestored.map(\.service) == ["Ethernet", "Wi-Fi"])
        #expect(SystemProxyRestoreReport(unrestoredPreviousProxies: unrestored).needsDecision)
        #expect(!SystemProxyRestoreReport.empty.needsDecision)
    }

    @Test("Summary lists a shared endpoint once with every protocol it serves")
    func summaryGroupsSharedEndpoints() {
        #expect(PreviousProxyRestoreSummary.descriptions(of: Self.clash) == ["127.0.0.1:7890 (HTTP, HTTPS, SOCKS)"])
        let split = Self.snapshot(http: (true, "proxy.corp.example", 8_080), socks: (true, "127.0.0.1", 1_080))
        #expect(PreviousProxyRestoreSummary.descriptions(of: split) == [
            "proxy.corp.example:8080 (HTTP)",
            "127.0.0.1:1080 (SOCKS)",
        ])
        #expect(PreviousProxyRestoreSummary.descriptions(of: Self.pac).count == 1)
        #expect(PreviousProxyRestoreSummary.descriptions(of: Self.pac).first?
            .contains("http://127.0.0.1:33331/pac") == true)
    }

    // MARK: Private

    private static let rockxyPort = 9_090
    private static let clashBypass = ["127.0.0.1", "localhost", "*.local", "192.168.0.0/16"]

    private static let direct = Self.snapshot()
    private static let clash = Self.snapshot(
        http: (true, "127.0.0.1", 7_890),
        https: (true, "127.0.0.1", 7_890),
        socks: (true, "127.0.0.1", 7_890)
    )
    private static let pac = Self.snapshot(pac: (true, "http://127.0.0.1:33331/pac"))

    private static func snapshot(
        http: (Bool, String, Int) = (false, "", 0),
        https: (Bool, String, Int) = (false, "", 0),
        socks: (Bool, String, Int) = (false, "", 0),
        pac: (Bool, String) = (false, "")
    )
        -> ServiceProxySnapshot
    {
        ServiceProxySnapshot(
            httpEnabled: http.0,
            httpHost: http.1,
            httpPort: http.2,
            httpsEnabled: https.0,
            httpsHost: https.1,
            httpsPort: https.2,
            socksEnabled: socks.0,
            socksHost: socks.1,
            socksPort: socks.2,
            pacEnabled: pac.0,
            pacURL: pac.1,
            autoDiscoveryEnabled: false
        )
    }
}

// MARK: - LoopbackProxyAppRecoveryJournalTests

/// The helper's journaled restore with a proxy app's loopback endpoint as the captured settings.
/// The existing journal fixtures use a corporate proxy; these pin the loopback case from #375.
struct LoopbackProxyAppRecoveryJournalTests {
    // MARK: Internal

    @Test("A clean session over a proxy app restores its endpoint, SOCKS, and bypass list exactly")
    func cleanSessionRestoresProxyAppEndpoint() throws {
        let completed = try #require(ProxyOverrideTransition.completedState(
            from: Self.clash,
            port: Self.rockxyPort,
            appliedBypassDomains: Self.rockxyBypass
        ))
        let plan = plan(live: completed)

        #expect(plan.abandonedServices.isEmpty)
        let entry = try #require(plan.entriesToRestore.first)
        #expect(entry.target == Self.clash)
        #expect(ProxyServiceRestorationState.expectedRestorationResult(target: Self.clash, from: completed) == Self
            .clash)
    }

    @Test("A proxy app that re-applied its own settings is left as it is")
    func proxyAppReappliedIsUntouched() {
        let plan = plan(live: Self.clash)
        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.completedServices == [Self.service])
    }

    @Test("A proxy app that switched everything off is not overwritten automatically")
    func proxyAppSwitchedOffIsAbandoned() {
        // Restore never writes over a change it did not make; the app reports the previous
        // settings to the user instead (`PreviousProxyRestorePolicy`).
        let switchedOff = ProxyServiceRestorationState(
            service: Self.service,
            http: ProxyEndpointState(enabled: false, host: "127.0.0.1", port: 7_890),
            https: ProxyEndpointState(enabled: false, host: "127.0.0.1", port: 7_890),
            socks: ProxyEndpointState(enabled: false, host: "127.0.0.1", port: 7_890),
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false,
            bypassDomains: []
        )
        let plan = plan(live: switchedOff)
        #expect(plan.entriesToRestore.isEmpty)
        #expect(plan.abandonedServices == [Self.service])
    }

    // MARK: Private

    private static let service = "Wi-Fi"
    private static let rockxyPort = 9_090
    private static let rockxyBypass = ["localhost", "127.0.0.1", "*.local"]
    private static let clash = ProxyServiceRestorationState(
        service: service,
        http: ProxyEndpointState(enabled: true, host: "127.0.0.1", port: 7_890),
        https: ProxyEndpointState(enabled: true, host: "127.0.0.1", port: 7_890),
        socks: ProxyEndpointState(enabled: true, host: "127.0.0.1", port: 7_890),
        pacEnabled: false,
        pacURL: "",
        autoDiscoveryEnabled: false,
        bypassDomains: ["127.0.0.1", "localhost", "*.local", "192.168.0.0/16"]
    )

    private func plan(live: ProxyServiceRestorationState) -> ProxyRecoveryPlan {
        ProxyRecoveryPlanner.plan(
            targets: [Self.clash],
            journal: [
                ProxyServiceRecoveryJournalEntry(
                    overrideApplicationFor: Self.clash,
                    stage: .applying,
                    port: Self.rockxyPort,
                    appliedBypassDomains: Self.rockxyBypass
                ),
            ],
            liveStates: [Self.service: live],
            ownedPort: Self.rockxyPort
        )
    }
}
