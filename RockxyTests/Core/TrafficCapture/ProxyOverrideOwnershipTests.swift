import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ProxyOverrideOwnership` and its contrast with the readiness predicate
// in the core traffic capture layer.

struct ProxyOverrideOwnershipTests {
    // MARK: Internal

    @Test("Readiness requires every snapshot to match while recovery ownership is per service")
    func readinessAllMatchVersusRecoveryAnyMatch() {
        let port = 9_090
        let ownedSnapshot = makeSnapshot(host: "127.0.0.1", port: port)
        let userChangedSnapshot = makeSnapshot(host: "proxy.corp.com", port: 8_080)

        // Readiness answers "is capture actually routed through Rockxy" and must stay all-match.
        #expect(SystemProxyManager.proxySnapshotsMatchRockxy(
            port: port,
            snapshots: [ownedSnapshot, ownedSnapshot]
        ))
        #expect(!SystemProxyManager.proxySnapshotsMatchRockxy(
            port: port,
            snapshots: [ownedSnapshot, userChangedSnapshot]
        ))

        // Recovery answers "which services still need their restore point" and must be any-match.
        let states = [
            makeState(service: "Wi-Fi", host: "127.0.0.1", port: port),
            makeState(service: "Ethernet", host: "proxy.corp.com", port: 8_080),
        ]
        #expect(ProxyOverrideOwnership.residualOwnedServices(in: states, port: port) == ["Wi-Fi"])
        #expect(ProxyOverrideOwnership.hasResidualOwnedService(in: states, port: port))
    }

    @Test("Ownership requires both loopback protocols on the persisted port")
    func ownershipRequiresStrictLoopbackOverride() {
        let port = 9_090

        #expect(ProxyOverrideOwnership.isOwnedByRockxy(
            makeState(service: "Wi-Fi", host: "127.0.0.1", port: port),
            port: port
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            makeState(service: "Wi-Fi", host: "127.0.0.1", port: 9_091),
            port: port
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            makeState(service: "Wi-Fi", host: "10.0.0.2", port: port),
            port: port
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            makeState(service: "Wi-Fi", host: "127.0.0.1", port: port, httpsEnabled: false),
            port: port
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            makeState(service: "Wi-Fi", host: "127.0.0.1", port: port, httpEnabled: false),
            port: port
        ))
    }

    @Test("An unusable persisted port never claims ownership")
    func ownershipRejectsUnusablePort() {
        let states = [makeState(service: "Wi-Fi", host: "127.0.0.1", port: 0)]

        #expect(!ProxyOverrideOwnership.hasResidualOwnedService(in: states, port: 0))
        #expect(ProxyOverrideOwnership.residualOwnedServices(in: states, port: 0).isEmpty)
    }

    @Test("Alternative proxy modes and global bypass invalidate recovery ownership")
    func ownershipRejectsConflictingRoutingModes() {
        let port = 9_090
        let base = makeState(service: "Wi-Fi", host: "127.0.0.1", port: port)

        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            replacing(base, socksEnabled: true),
            port: port
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            replacing(base, pacEnabled: true),
            port: port
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            replacing(base, autoDiscoveryEnabled: true),
            port: port
        ))
        #expect(!ProxyOverrideOwnership.isOwnedByRockxy(
            replacing(base, hasGlobalBypass: true),
            port: port
        ))
    }

    @Test("A backup without a persisted port infers it from the services still overridden")
    func inferredPortComesFromResidualOverride() {
        let states = [
            makeState(service: "Ethernet", host: "proxy.corp.com", port: 8_080),
            makeState(service: "Wi-Fi", host: "127.0.0.1", port: 9_090),
        ]

        #expect(ProxyOverrideOwnership.inferredOwnedPort(in: states) == 9_090)
    }

    @Test("No inferred port when nothing carries a complete loopback override")
    func inferredPortIsNilWithoutLoopbackOverride() {
        #expect(ProxyOverrideOwnership.inferredOwnedPort(in: [
            makeState(service: "Wi-Fi", host: "127.0.0.1", port: 9_090, httpsEnabled: false),
            makeState(service: "Ethernet", host: "10.0.0.2", port: 3_128),
            makeState(service: "USB LAN", host: "127.0.0.1", port: 0),
        ]) == nil)
    }

    @Test("Residual ownership keeps the supplied service order")
    func residualOwnershipPreservesOrder() {
        let port = 9_090
        let states = [
            makeState(service: "Ethernet", host: "127.0.0.1", port: port),
            makeState(service: "Wi-Fi", host: "192.168.0.1", port: 3_128),
            makeState(service: "USB LAN", host: "127.0.0.1", port: port),
        ]

        #expect(ProxyOverrideOwnership.residualOwnedServices(in: states, port: port) == ["Ethernet", "USB LAN"])
    }

    // MARK: Private

    private func makeSnapshot(host: String, port: Int) -> ServiceProxySnapshot {
        ServiceProxySnapshot(
            httpEnabled: true,
            httpHost: host,
            httpPort: port,
            httpsEnabled: true,
            httpsHost: host,
            httpsPort: port,
            socksEnabled: false,
            socksHost: "",
            socksPort: 0,
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false
        )
    }

    private func makeState(
        service: String,
        host: String,
        port: Int,
        httpEnabled: Bool = true,
        httpsEnabled: Bool = true,
        httpsPort: Int? = nil
    )
        -> ProxyServiceOverrideState
    {
        ProxyServiceOverrideState(
            service: service,
            httpEnabled: httpEnabled,
            httpHost: host,
            httpPort: port,
            httpsEnabled: httpsEnabled,
            httpsHost: host,
            httpsPort: httpsPort ?? port
        )
    }

    private func replacing(
        _ state: ProxyServiceOverrideState,
        socksEnabled: Bool = false,
        pacEnabled: Bool = false,
        autoDiscoveryEnabled: Bool = false,
        hasGlobalBypass: Bool = false
    ) -> ProxyServiceOverrideState {
        ProxyServiceOverrideState(
            service: state.service,
            httpEnabled: state.httpEnabled,
            httpHost: state.httpHost,
            httpPort: state.httpPort,
            httpsEnabled: state.httpsEnabled,
            httpsHost: state.httpsHost,
            httpsPort: state.httpsPort,
            socksEnabled: socksEnabled,
            pacEnabled: pacEnabled,
            autoDiscoveryEnabled: autoDiscoveryEnabled,
            hasGlobalBypass: hasGlobalBypass
        )
    }
}
