import AppKit
import Foundation
@testable import Rockxy
import Testing

struct AppKitAutosaveTestKeysTests {
    // MARK: Internal

    @Test("A sweep clears the keys of exited runs and spares those of a live run")
    func sweepClearsDeadGenerationsAndSparesLiveOnes() throws {
        let defaults = IsolatedDefaultsSuite.make(prefix: "AppKitAutosaveTestKeysTests")

        // What bounded growth actually rests on, and the most that can be observed from inside
        // one process: a sweep removes the keys of runs that have exited and spares the keys of a
        // run still going. Across real runs that is what keeps the domain bounded, because each
        // run's own keys carry its pid and become sweepable the moment it exits.
        //
        // This cannot be written as "three loops leave the same count". Minting embeds the
        // CURRENT pid, so a key this process creates stays live-owned for as long as the test
        // runs and the sweep spares it -- correctly, because parallel test processes share this
        // domain and must never have a key deleted under them. Two earlier shapes of this test
        // failed for exactly that reason, and both times the implementation was right.
        let dead = try Self.exitedProcessID()
        #expect(!Keys.isProcessAlive(dead), "the stand-in pid must be dead for this test to mean anything")

        let deadGeneration = 50
        for _ in 0 ..< deadGeneration {
            let name = Keys.splitViewNamePrefix(.workspaceSplitView) + Keys.ownerToken(pid: dead)
            defaults.set(["0, 0, 1, 1, NO, NO"], forKey: Keys.splitViewKeyPrefix + name)
        }
        // A pid-less key is the legacy shape written before names carried a pid. It has no owner
        // that could still be running, so it is always sweepable.
        let legacy = Keys.splitViewNamePrefix(.workspaceSplitView) + UUID().uuidString
        defaults.set(["0, 0, 1, 1, NO, NO"], forKey: Keys.splitViewKeyPrefix + legacy)

        let liveGeneration = 3
        var liveKeys: [String] = []
        for _ in 0 ..< liveGeneration {
            let name = Keys.splitViewNamePrefix(.workspaceSplitView) + Keys.ownerToken()
            let key = Keys.splitViewKeyPrefix + name
            defaults.set(["0, 0, 1, 1, NO, NO"], forKey: key)
            liveKeys.append(key)
        }

        let sweeper = Keys.Sweeper(defaults: defaults)
        #expect(sweeper.prefixedKeyCount() == deadGeneration + 1 + liveGeneration)

        _ = Keys.uniqueSplitViewAutosaveName(for: .workspaceSplitView, sweeper: sweeper)

        // The dead generation and the legacy key are gone, every live-owned key survives, and
        // minting added no key of its own because only AppKit writes those.
        let survivors = liveKeys.filter { defaults.object(forKey: $0) != nil }
        #expect(survivors.count == liveGeneration, "a live run's keys must never be swept")
        #expect(sweeper.prefixedKeyCount() == liveGeneration)
    }

    // MARK: Private

    private typealias Keys = AppKitAutosaveTestKeys

    /// The pid of a process that has run and exited, so `isProcessAlive` reports it dead.
    private static func exitedProcessID() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }
}
