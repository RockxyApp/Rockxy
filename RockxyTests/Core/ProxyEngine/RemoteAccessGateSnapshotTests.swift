import Foundation
@testable import Rockxy
import Testing

// MARK: - RemoteAccessGateSnapshotTests

/// Covers the per-connection cost of Access Control: the interface snapshot behind
/// `isThisMac` and the bound on refusal reports. Neither may change a decision.
struct RemoteAccessGateSnapshotTests {
    @Test("A burst of refused connections costs one interface lookup, and the snapshot expires")
    func snapshotIsCachedAndRefreshes() throws {
        let interfaces = InterfaceProbe(addresses: [])
        let clock = TestClock()
        let gate = RemoteAccessGate(
            interfaceAddresses: { interfaces.addresses() },
            now: { clock.now() }
        )
        gate.update(mode: .disallowAll, allowedEntries: [])

        for _ in 0 ..< 50 {
            #expect(gate.decision(clientAddress: "198.51.100.7", localAddress: "192.168.1.2") == .deny)
        }
        #expect(interfaces.count() == 1)

        // A new address on this Mac is invisible until the snapshot expires: denying our own
        // Mac for under a second fails closed, which is the safe direction.
        let newAddress = try #require(RemoteAccessAddressRange.addressBytes("198.51.100.7"))
        interfaces.set([newAddress])
        #expect(gate.decision(clientAddress: "198.51.100.7", localAddress: "192.168.1.2") == .deny)
        #expect(interfaces.count() == 1)

        clock.advance(seconds: 1.5)
        #expect(gate.decision(clientAddress: "198.51.100.7", localAddress: "192.168.1.2") == .allow)
        #expect(interfaces.count() == 2)
    }

    @Test("An address this Mac has released stops being treated as ours after the snapshot expires")
    func releasedAddressStopsMatching() throws {
        let released = try #require(RemoteAccessAddressRange.addressBytes("198.51.100.7"))
        let interfaces = InterfaceProbe(addresses: [released])
        let clock = TestClock()
        let gate = RemoteAccessGate(
            interfaceAddresses: { interfaces.addresses() },
            now: { clock.now() }
        )
        gate.update(mode: .disallowAll, allowedEntries: [])

        #expect(gate.decision(clientAddress: "198.51.100.7", localAddress: "192.168.1.2") == .allow)
        interfaces.set([])
        clock.advance(seconds: 1.5)
        #expect(gate.decision(clientAddress: "198.51.100.7", localAddress: "192.168.1.2") == .deny)
    }

    @Test("A listed device is allowed without consulting the interface snapshot")
    func listedDeviceSkipsSnapshot() {
        let interfaces = InterfaceProbe(addresses: [])
        let gate = RemoteAccessGate(interfaceAddresses: { interfaces.addresses() })
        gate.update(mode: .listedDevices, allowedEntries: ["203.0.113.0/24"])

        #expect(gate.decision(clientAddress: "203.0.113.9", localAddress: "192.168.1.2") == .allow)
        #expect(interfaces.count() == 0)
    }

    @Test("Refusal reports are bounded, and the cap never changes a decision")
    func refusalReportsAreBounded() {
        let gate = RemoteAccessGate(interfaceAddresses: { [] })
        let reported = RefusedLog()
        gate.onListedDeviceRefused = { reported.append($0) }
        gate.update(mode: .listedDevices, allowedEntries: ["203.0.113.0/24"])

        // A client cycling source addresses: 200 distinct refusals, a bounded report stream,
        // and every one of them still denied.
        for index in 0 ..< 200 {
            #expect(gate.decision(
                clientAddress: "198.51.100.\(index)",
                localAddress: "192.168.1.2"
            ) == .deny)
        }
        #expect(reported.values.count == 64)
        #expect(reported.values.first == "198.51.100.0")

        // The policy change that makes the reports actionable also clears the bound.
        gate.update(mode: .listedDevices, allowedEntries: ["203.0.113.0/24"])
        #expect(gate.decision(clientAddress: "198.51.100.200", localAddress: "192.168.1.2") == .deny)
        #expect(reported.values.count == 65)
    }
}

// MARK: - InterfaceProbe

private final class InterfaceProbe: @unchecked Sendable {
    // MARK: Lifecycle

    init(addresses: Set<[UInt8]>) {
        stored = addresses
    }

    // MARK: Internal

    func addresses() -> Set<[UInt8]> {
        lock.withLock {
            calls += 1
            return stored
        }
    }

    func set(_ addresses: Set<[UInt8]>) {
        lock.withLock { stored = addresses }
    }

    func count() -> Int {
        lock.withLock { calls }
    }

    // MARK: Private

    private let lock = NSLock()
    private var stored: Set<[UInt8]>
    private var calls = 0
}

// MARK: - TestClock

private final class TestClock: @unchecked Sendable {
    // MARK: Internal

    func now() -> DispatchTime {
        lock.withLock { DispatchTime(uptimeNanoseconds: base + offset) }
    }

    func advance(seconds: Double) {
        lock.withLock { offset += UInt64(seconds * 1_000_000_000) }
    }

    // MARK: Private

    private let lock = NSLock()
    private let base: UInt64 = 1_000_000_000_000
    private var offset: UInt64 = 0
}

// MARK: - RefusedLog

private final class RefusedLog: @unchecked Sendable {
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
