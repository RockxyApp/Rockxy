import Foundation
@testable import Rockxy
import Testing

// MARK: - EmulatorHostAliasTests

struct EmulatorHostAliasTests {
    @Test("Loopback clients asking for the emulator alias connect to 127.0.0.1")
    func mapsAliasForLoopbackClients() {
        #expect(EmulatorHostAlias.connectHost(for: "10.0.2.2", clientHost: "127.0.0.1", localAddresses: ["192.168.1.20"])
            == "127.0.0.1")
        #expect(EmulatorHostAlias.connectHost(for: "10.0.3.2", clientHost: "::1", localAddresses: []) == "127.0.0.1")
    }

    @Test("Other hosts, remote clients, and Macs on the alias subnet are left alone")
    func leavesRealAddressesAlone() {
        #expect(EmulatorHostAlias.connectHost(for: "10.0.2.3", clientHost: "127.0.0.1", localAddresses: []) == "10.0.2.3")
        #expect(EmulatorHostAlias.connectHost(for: "10.0.2.2", clientHost: "192.168.1.50", localAddresses: [])
            == "10.0.2.2")
        #expect(EmulatorHostAlias.connectHost(for: "10.0.2.2", clientHost: nil, localAddresses: []) == "10.0.2.2")
        #expect(EmulatorHostAlias.connectHost(for: "10.0.2.2", clientHost: "127.0.0.1", localAddresses: ["10.0.2.15"])
            == "10.0.2.2")
    }
}
