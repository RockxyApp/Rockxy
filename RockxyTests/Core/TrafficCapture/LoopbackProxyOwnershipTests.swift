import Foundation
@testable import Rockxy
import Testing

// Regression tests for telling another proxy app's loopback endpoint (a Clash-style client on
// 127.0.0.1:7890) apart from a Rockxy session before direct mode adopts the current settings as
// its restore point.

// MARK: - LoopbackProxyOwnershipTests

struct LoopbackProxyOwnershipTests {
    // MARK: Internal

    @Test("Only enabled loopback endpoints contribute ports, each port once")
    func enabledLoopbackPortsIgnoreDisabledAndRemoteEndpoints() {
        let clash = snapshot(
            http: (true, "127.0.0.1", 7_890),
            https: (true, "127.0.0.1", 7_890),
            socks: (true, "127.0.0.1", 7_890)
        )
        let leftover = snapshot(http: (false, "127.0.0.1", 9_090), https: (false, "127.0.0.1", 9_090))
        let corporate = snapshot(http: (true, "proxy.corp.example", 8_080), https: (true, "proxy.corp.example", 8_080))
        let socksOnly = snapshot(socks: (true, "127.0.0.1", 1_080))

        #expect(LoopbackProxyOwnershipPolicy.enabledLoopbackPorts(in: [clash, leftover, corporate, socksOnly]) == [
            1_080,
            7_890
        ])
        #expect(LoopbackProxyOwnershipPolicy.enabledLoopbackPorts(in: [leftover, corporate]).isEmpty)
    }

    @Test("Another proxy app's endpoint becomes the restore point")
    func anotherApplicationIsCaptured() {
        #expect(
            LoopbackProxyOwnershipPolicy.directBaselineDecision(
                listeners: [(port: 7_890, listener: .otherApplication)],
                helperBackupExists: false
            ) == .capture
        )
    }

    @Test("A setting nothing is listening behind is the user's own, stale or not")
    func staleEndpointIsCaptured() {
        #expect(
            LoopbackProxyOwnershipPolicy.directBaselineDecision(
                listeners: [(port: 7_890, listener: .none)],
                helperBackupExists: false
            ) == .capture
        )
    }

    @Test("No loopback proxy at all needs no decision")
    func noLoopbackProxyIsCaptured() {
        #expect(LoopbackProxyOwnershipPolicy
            .directBaselineDecision(listeners: [], helperBackupExists: true) == .capture)
    }

    @Test("Another Rockxy listener on any configured port refuses the override")
    func rockxyListenerRefuses() {
        #expect(
            LoopbackProxyOwnershipPolicy.directBaselineDecision(
                listeners: [(port: 7_890, listener: .otherApplication), (port: 19_090, listener: .rockxy)],
                helperBackupExists: false
            ) == .refuseRockxySession
        )
    }

    @Test("A helper backup on disk keeps refusing any loopback proxy, as before")
    func helperBackupRefuses() {
        #expect(
            LoopbackProxyOwnershipPolicy.directBaselineDecision(
                listeners: [(port: 7_890, listener: .otherApplication)],
                helperBackupExists: true
            ) == .refuseRockxySession
        )
    }

    @Test("An unidentified listener fails closed and names its port")
    func unknownListenerRefuses() {
        #expect(
            LoopbackProxyOwnershipPolicy.directBaselineDecision(
                listeners: [(port: 7_890, listener: .otherApplication), (port: 7_891, listener: .unknown)],
                helperBackupExists: false
            ) == .refuseUnidentifiedListener(port: 7_891)
        )
    }

    @Test("Listener classification: no answer, nobody, this process, Rockxy, another app")
    func classifyListeners() {
        let rockxyPID: Int32 = 501
        func classify(_ pids: [Int32]?) -> LoopbackProxyListener {
            LoopbackProxyOwnershipPolicy.classify(pids: pids, currentPID: 42, isRockxyProcess: { $0 == rockxyPID })
        }

        #expect(classify(nil) == .unknown)
        #expect(classify([]) == .none)
        #expect(classify([42]) == .rockxy)
        #expect(classify([7, rockxyPID]) == .rockxy)
        #expect(classify([7, 8]) == .otherApplication)
    }

    @Test("Every Rockxy build is recognized by its identity keys, not its bundle identifier")
    func rockxyApplicationsAreRecognizedByIdentityKeys() {
        #expect(LoopbackProxyOwnershipPolicy.isRockxyApplication(infoDictionary: [
            "CFBundleIdentifier": "com.rockxy.qa.accept",
            "RockxyFamilyNamespace": "com.rockxy.qa.accept",
        ]))
        #expect(LoopbackProxyOwnershipPolicy.isRockxyApplication(infoDictionary: [
            "RockxyHelperMachServiceName": "com.amunx.rockxy.helper",
        ]))
        #expect(!LoopbackProxyOwnershipPolicy.isRockxyApplication(infoDictionary: [
            "CFBundleIdentifier": "io.github.clash-verge-rev.clash-verge-rev",
        ]))
    }

    @Test("lsof listener records parse in order without duplicates")
    func parseListeningProcessIDs() {
        let output = "p812\nf9\np812\np77\nfoo\np0\npabc\n"
        #expect(ProcessResolver.parseListeningProcessIDs(output) == [812, 77])
        #expect(ProcessResolver.parseListeningProcessIDs("").isEmpty)
    }

    // MARK: Private

    private func snapshot(
        http: (Bool, String, Int) = (false, "", 0),
        https: (Bool, String, Int) = (false, "", 0),
        socks: (Bool, String, Int) = (false, "", 0)
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
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false
        )
    }
}
