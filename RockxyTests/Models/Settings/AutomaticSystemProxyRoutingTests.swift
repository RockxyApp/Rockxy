import Foundation
@testable import Rockxy
import Testing

// MARK: - AutomaticSystemProxyRoutingTests

@MainActor
@Suite("Automatic system proxy routing")
struct AutomaticSystemProxyRoutingTests {
    @Test("Missing preference preserves automatic routing, and an explicit opt-out survives reload")
    func persistenceAndDefault() throws {
        let name = IsolatedDefaultsSuite.uniqueName(prefix: "routing-policy-")
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(AutomaticSystemProxyRouting.isEnabled(in: defaults))
        defaults.set(false, forKey: AutomaticSystemProxyRouting.defaultsKey)
        let reloaded = try #require(UserDefaults(suiteName: name))
        #expect(!AutomaticSystemProxyRouting.isEnabled(in: reloaded))
        reloaded.set(true, forKey: AutomaticSystemProxyRouting.defaultsKey)
        #expect(AutomaticSystemProxyRouting.isEnabled(in: defaults))
    }

    @Test("Legacy boolean migrates losslessly: absent and true are Automatic, false is Manual")
    func legacyMigration() throws {
        let name = IsolatedDefaultsSuite.uniqueName(prefix: "routing-migration-")
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(AutomaticSystemProxyRouting.mode(in: defaults) == .automatic)
        defaults.set(true, forKey: AutomaticSystemProxyRouting.defaultsKey)
        #expect(AutomaticSystemProxyRouting.mode(in: defaults) == .automatic)
        defaults.set(false, forKey: AutomaticSystemProxyRouting.defaultsKey)
        #expect(AutomaticSystemProxyRouting.mode(in: defaults) == .manual)
        #expect(defaults.string(forKey: AutomaticSystemProxyRouting.modeDefaultsKey) == nil)
    }

    @Test(
        "An explicit mode wins over the legacy boolean and survives reload",
        arguments: SystemProxyRoutingMode.allCases
    )
    func explicitModePersists(mode: SystemProxyRoutingMode) throws {
        let name = IsolatedDefaultsSuite.uniqueName(prefix: "routing-mode-")
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AutomaticSystemProxyRouting.defaultsKey)
        AutomaticSystemProxyRouting.setMode(mode, in: defaults)
        let reloaded = try #require(UserDefaults(suiteName: name))
        #expect(AutomaticSystemProxyRouting.mode(in: reloaded) == mode)
        #expect(AutomaticSystemProxyRouting.isEnabled(in: reloaded) == (mode == .automatic))
    }

    @Test("Never blocks acquiring but never blocks releasing")
    func neverBlocksAcquireNotRelease() throws {
        for mode in SystemProxyRoutingMode.allCases {
            #expect(AutomaticSystemProxyRouting.permits(.release, mode: mode))
        }
        #expect(AutomaticSystemProxyRouting.permits(.acquireAutomatically, mode: .automatic))
        #expect(!AutomaticSystemProxyRouting.permits(.acquireAutomatically, mode: .manual))
        #expect(!AutomaticSystemProxyRouting.permits(.acquireAutomatically, mode: .never))
        #expect(AutomaticSystemProxyRouting.permits(.acquireExplicitly, mode: .automatic))
        #expect(AutomaticSystemProxyRouting.permits(.acquireExplicitly, mode: .manual))
        #expect(!AutomaticSystemProxyRouting.permits(.acquireExplicitly, mode: .never))

        let name = IsolatedDefaultsSuite.uniqueName(prefix: "routing-never-")
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        AutomaticSystemProxyRouting.setMode(.manual, in: defaults)
        try AutomaticSystemProxyRouting.requireExplicitAcquisition(mode: AutomaticSystemProxyRouting.mode(in: defaults))
        AutomaticSystemProxyRouting.setMode(.never, in: defaults)
        #expect(throws: SystemProxyRoutingBlocked.self) {
            try AutomaticSystemProxyRouting.requireExplicitAcquisition(
                mode: AutomaticSystemProxyRouting.mode(in: defaults)
            )
        }
    }

    @Test("Manual routing never invokes the privileged system mutation", arguments: [false, true])
    func manualStartDoesNotMutate(currentPreference: Bool) async throws {
        var mutations = 0
        let enabled = try await AutomaticSystemProxyRouting.enableForCapture(
            enabledAtStart: false, currentPreference: { currentPreference }
        ) { mutations += 1 }
        #expect(!enabled)
        #expect(mutations == 0)
    }

    @Test("Opting out while startup is in progress prevents automatic takeover")
    func latestOptOutWins() async throws {
        var mutations = 0
        let enabled = try await AutomaticSystemProxyRouting.enableForCapture(
            enabledAtStart: true, currentPreference: { false }
        ) { mutations += 1 }
        #expect(!enabled)
        #expect(mutations == 0)
    }

    @Test("Automatic routing invokes the system mutation once")
    func automaticStart() async throws {
        var mutations = 0
        let enabled = try await AutomaticSystemProxyRouting.enableForCapture(
            enabledAtStart: true, currentPreference: { true }
        ) { mutations += 1 }
        #expect(enabled)
        #expect(mutations == 1)
    }

    @Test("Automatic routing errors propagate so the running listener can report degraded routing")
    func automaticFailure() async {
        enum Failure: Error { case denied }
        do {
            _ = try await AutomaticSystemProxyRouting.enableForCapture(
                enabledAtStart: true, currentPreference: { true }
            ) { throw Failure.denied }
            Issue.record("Routing failure must not be reported as success")
        } catch Failure.denied {} catch { Issue.record("Unexpected error: \(error)") }
    }
}
