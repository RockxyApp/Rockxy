@testable import Rockxy
import Testing

/// "Cannot tell" must never travel as "clean". The wire pair is `(Bool, Int)` and stays that way,
/// so these pin how the three answers map onto it and back.
struct HelperProxyStatusReadingTests {
    @Test("A clean machine is the only reading that encodes as not overridden")
    func onlyCleanIsNotOverridden() {
        #expect(HelperProxyStatusReading.notOverridden.wire == (false, 0))
        #expect(HelperProxyStatusReading.overridden(port: 9_090).wire == (true, 9_090))
        #expect(HelperProxyStatusReading.undeterminable.wire.isOverridden)
        #expect(HelperProxyStatusReading.undeterminable.wire.port == HelperProxyStatusReading.undeterminablePort)
    }

    @Test("Every reading survives the wire round trip")
    func roundTrip() {
        for reading: HelperProxyStatusReading in [.notOverridden, .overridden(port: 8_888), .undeterminable] {
            let wire = reading.wire
            #expect(HelperProxyStatusReading(isOverridden: wire.isOverridden, port: wire.port) == reading)
        }
    }

    @Test("An overridden reply with a port that is not a port is undeterminable, never a match")
    func invalidPortIsNotTrusted() {
        for port in [-1, 0, 65_536] {
            #expect(HelperProxyStatusReading(isOverridden: true, port: port) == .undeterminable, "port \(port)")
        }
        #expect(HelperProxyStatusReading(isOverridden: true, port: 65_535) == .overridden(port: 65_535))
    }

    @Test("Only a proven override carries a port")
    func provenPort() {
        #expect(HelperProxyStatusReading.overridden(port: 9_090).provenPort == 9_090)
        #expect(HelperProxyStatusReading.undeterminable.provenPort == nil)
        #expect(HelperProxyStatusReading.notOverridden.provenPort == nil)
    }

    @Test("The app treats an undeterminable helper as an override it must restore, not as nothing")
    func appOwnerForUndeterminable() {
        var consulted = false
        let owner = SystemProxyManager.helperOverrideOwner(for: .undeterminable) { _ in
            consulted = true
            return false
        }
        guard case let .helper(port)? = owner else {
            Issue.record("expected a helper-held override, got \(String(describing: owner))")
            return
        }
        #expect(port == SystemProxyManager.unknownHelperOverridePort)
        // The unknown port can never equal a live proxy port, so it never reads as capture-ready.
        #expect(!(1 ... 65_535).contains(port))
        #expect(!consulted)
    }

    @Test("A clean helper is no owner, and a proven port still has to match the effective proxy")
    func appOwnerForKnownReadings() {
        #expect(SystemProxyManager.helperOverrideOwner(for: .notOverridden) { _ in true } == nil)
        #expect(SystemProxyManager.helperOverrideOwner(for: .overridden(port: 9_090)) { _ in false } == nil)
        guard case let .helper(port)? = SystemProxyManager.helperOverrideOwner(
            for: .overridden(port: 9_090),
            effectiveProxyMatches: { $0 == 9_090 }
        ) else {
            Issue.record("expected a helper-held override")
            return
        }
        #expect(port == 9_090)
    }
}
