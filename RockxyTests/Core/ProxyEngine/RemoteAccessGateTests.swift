import Foundation
@testable import Rockxy
import Testing

// MARK: - RemoteAccessAddressRangeTests

struct RemoteAccessAddressRangeTests {
    @Test("Addresses and CIDR ranges parse; everything else is rejected")
    func parsing() {
        #expect(RemoteAccessAddressRange("192.168.1.20") != nil)
        #expect(RemoteAccessAddressRange(" 10.0.0.0/8 ") != nil)
        #expect(RemoteAccessAddressRange("fe80::/10") != nil)
        #expect(RemoteAccessAddressRange("2001:db8::1") != nil)
        #expect(RemoteAccessAddressRange("192.168.1.0/33") == nil)
        #expect(RemoteAccessAddressRange("192.168.1") == nil)
        #expect(RemoteAccessAddressRange("phone.local") == nil)
        #expect(RemoteAccessAddressRange("") == nil)
        #expect(RemoteAccessAddressRange("10.0.0.0/") == nil)
    }

    @Test("A range contains exactly the addresses under its prefix")
    func containment() throws {
        let range = try #require(RemoteAccessAddressRange("192.168.1.0/24"))
        let inside = try #require(RemoteAccessAddressRange.addressBytes("192.168.1.77"))
        let outside = try #require(RemoteAccessAddressRange.addressBytes("192.168.2.1"))
        #expect(range.contains(inside))
        #expect(!range.contains(outside))

        let odd = try #require(RemoteAccessAddressRange("10.0.0.0/9"))
        #expect(try odd.contains(#require(RemoteAccessAddressRange.addressBytes("10.127.255.255"))))
        #expect(try !odd.contains(#require(RemoteAccessAddressRange.addressBytes("10.128.0.0"))))

        let any = try #require(RemoteAccessAddressRange("0.0.0.0/0"))
        #expect(any.contains(outside))
    }

    @Test("An IPv4-mapped IPv6 client matches an IPv4 entry")
    func mappedIPv4() throws {
        let range = try #require(RemoteAccessAddressRange("203.0.113.5"))
        let mapped = try #require(RemoteAccessAddressRange.addressBytes("::ffff:203.0.113.5"))
        #expect(range.contains(mapped))
    }
}

// MARK: - RemoteAccessGateTests

struct RemoteAccessGateTests {
    @Test("Allow all accepts every device")
    func allowAll() {
        let gate = RemoteAccessGate()
        #expect(gate.decision(clientAddress: "203.0.113.5", localAddress: "192.168.1.2") == .allow)
    }

    @Test("Block all refuses other devices but never this Mac")
    func disallowAll() {
        let gate = RemoteAccessGate()
        gate.update(mode: .disallowAll, allowedEntries: ["203.0.113.5"])
        #expect(gate.decision(clientAddress: "203.0.113.5", localAddress: "192.168.1.2") == .deny)
        #expect(gate.decision(clientAddress: "127.0.0.1", localAddress: "127.0.0.1") == .allow)
        #expect(gate.decision(clientAddress: "::1", localAddress: "::1") == .allow)
        #expect(gate.decision(clientAddress: "::ffff:127.0.0.1", localAddress: nil) == .allow)
        // A client using the address it connected to is this Mac.
        #expect(gate.decision(clientAddress: "198.51.100.7", localAddress: "198.51.100.7") == .allow)
        #expect(gate.decision(clientAddress: nil, localAddress: nil) == .deny)
    }

    @Test("Listed devices pass; others are refused and reported once until the policy changes")
    func listedDevices() {
        let gate = RemoteAccessGate()
        let reported = ReportedAddresses()
        gate.onListedDeviceRefused = { reported.append($0) }
        gate.update(mode: .listedDevices, allowedEntries: ["203.0.113.0/28", "not an address"])

        #expect(gate.decision(clientAddress: "203.0.113.9", localAddress: "192.168.1.2") == .allow)
        #expect(gate.decision(clientAddress: "203.0.113.20", localAddress: "192.168.1.2") == .deny)
        #expect(gate.decision(clientAddress: "203.0.113.20", localAddress: "192.168.1.2") == .deny)
        #expect(reported.values == ["203.0.113.20"])

        gate.update(mode: .listedDevices, allowedEntries: ["203.0.113.0/28"])
        #expect(gate.decision(clientAddress: "203.0.113.20", localAddress: "192.168.1.2") == .deny)
        #expect(reported.values == ["203.0.113.20", "203.0.113.20"])
    }

    @Test("Block all does not report refused devices")
    func disallowAllDoesNotReport() {
        let gate = RemoteAccessGate()
        let reported = ReportedAddresses()
        gate.onListedDeviceRefused = { reported.append($0) }
        gate.update(mode: .disallowAll, allowedEntries: [])
        _ = gate.decision(clientAddress: "203.0.113.20", localAddress: "192.168.1.2")
        #expect(reported.values.isEmpty)
    }
}

// MARK: - RemoteAccessSettingsTests

@MainActor
struct RemoteAccessSettingsTests {
    @Test("Settings persist, validate entries, and drive the gate immediately")
    func settingsDriveGate() {
        let defaults = IsolatedDefaultsSuite.make(prefix: "Rockxy.RemoteAccessSettingsTests")
        let gate = RemoteAccessGate()
        let settings = RemoteAccessSettings(defaults: defaults, gate: gate)
        #expect(settings.mode == .allowAll)

        settings.setMode(.listedDevices)
        #expect(gate.decision(clientAddress: "203.0.113.5", localAddress: "192.168.1.2") == .deny)
        #expect(!settings.addEntry("phone"))
        #expect(settings.addEntry(" 203.0.113.5 "))
        #expect(!settings.addEntry("203.0.113.5"))
        #expect(gate.decision(clientAddress: "203.0.113.5", localAddress: "192.168.1.2") == .allow)

        let reloaded = RemoteAccessSettings(defaults: defaults, gate: RemoteAccessGate())
        #expect(reloaded.mode == .listedDevices)
        #expect(reloaded.allowedEntries == ["203.0.113.5"])

        settings.removeEntry("203.0.113.5")
        #expect(gate.decision(clientAddress: "203.0.113.5", localAddress: "192.168.1.2") == .deny)
    }

    @Test("Allowing a blocked device removes it from the recently blocked list")
    func allowClearsRefused() {
        let defaults = IsolatedDefaultsSuite.make(prefix: "Rockxy.RemoteAccessSettingsTests")
        let settings = RemoteAccessSettings(defaults: defaults, gate: RemoteAccessGate())
        settings.recordRefused("203.0.113.5")
        settings.recordRefused("203.0.113.6")
        settings.recordRefused("203.0.113.5")
        #expect(settings.refusedAddresses == ["203.0.113.5", "203.0.113.6"])
        settings.addEntry("203.0.113.4/31")
        #expect(settings.refusedAddresses == ["203.0.113.6"])
    }
}

// MARK: - ReportedAddresses

private final class ReportedAddresses: @unchecked Sendable {
    // MARK: Internal

    var values: [String] {
        lock.withLock { stored }
    }

    func append(_ value: String) {
        lock.withLock { stored.append(value) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var stored: [String] = []
}
