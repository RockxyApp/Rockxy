import Foundation
@testable import Rockxy
import Testing

// MARK: - HelperOrphanedRecordTests

/// The state a registration reaches when the bundle that created it is gone: launchd keeps the
/// job, cannot resolve the bundle-relative program, and spawn-fails with `EX_CONFIG` forever.
struct HelperOrphanedRecordTests {
    // MARK: Internal

    @Test("A job spawn-failing on configuration is recognised between retries, not only during one")
    func spawnFailingOnConfigurationIsRecognised() {
        // Captured from `launchctl print system/com.amunx.rockxy.helper` on 2026-11-21 while the
        // record pointed at a bundle that no longer existed. The old predicate only matched the
        // throttle pause (`state = spawn scheduled`), so a reading taken mid-retry — which is
        // most of them, at one attempt every ten seconds — missed the state it looks for.
        let midRetry = Self.snapshot("""
        system/com.amunx.rockxy.helper = {
            active count = 0
            state = not running
            runs = 534
            last exit code = 78: EX_CONFIG
            BTM uuid = 928AE75A-F33E-434B-B070-90EF82323FDB
            job state = spawn failed
        }
        """)
        #expect(midRetry.runs == 534)
        #expect(midRetry.lastExitCode == 78)
        #expect(!midRetry.isSpawnScheduledAndIdle)
        #expect(midRetry.isSpawnFailingOnConfiguration)
        #expect(midRetry.cannotStart)
    }

    @Test("The throttle pause is still recognised")
    func throttlePauseStillRecognised() {
        let duringPause = Self.snapshot("""
        system/com.amunx.rockxy.helper = {
            active count = 0
            state = spawn scheduled
            runs = 478
            last exit code = 78: EX_CONFIG
            BTM uuid = 928AE75A-F33E-434B-B070-90EF82323FDB
        }
        """)
        #expect(duringPause.isSpawnScheduledAndIdle)
        #expect(duringPause.cannotStart)
    }

    @Test("A healthy helper is never read as unable to start")
    func healthyHelperIsNotFlagged() {
        // The shape after recovery on the same machine: it has run once and never exited.
        let healthy = Self.snapshot("""
        system/com.amunx.rockxy.helper = {
            active count = 2
            state = running
            runs = 1
            last exit code = (never exited)
            BTM uuid = 1A2B3C4D-5E6F-7788-99AA-BBCCDDEEFF00
        }
        """)
        #expect(healthy.runs == 1)
        #expect(healthy.lastExitCode == nil)
        #expect(!healthy.isSpawnFailingOnConfiguration)
        #expect(!healthy.cannotStart)
    }

    @Test("An on-demand helper that has never been called is not read as broken")
    func idleOnDemandHelperIsNotFlagged() {
        // A registered helper nothing has talked to yet: no runs, no exit. Flagging this would
        // tell a user with a working install to reset their Mac's background items.
        let idle = Self.snapshot("""
        system/com.amunx.rockxy.helper = {
            active count = 0
            state = not running
            runs = 0
            last exit code = (never exited)
        }
        """)
        #expect(!idle.isSpawnFailingOnConfiguration)
        #expect(!idle.cannotStart)
    }

    @Test("A job that failed for some other reason is not read as an orphaned record")
    func otherExitCodesAreNotFlagged() {
        // Only EX_CONFIG means "launchd could not resolve the program". A helper that crashed
        // needs a different answer than "reset your Mac's background items".
        let crashed = Self.snapshot("""
        system/com.amunx.rockxy.helper = {
            active count = 0
            state = not running
            runs = 12
            last exit code = 1
        }
        """)
        #expect(crashed.lastExitCode == 1)
        #expect(!crashed.isSpawnFailingOnConfiguration)
        #expect(!crashed.cannotStart)
    }

    @Test("The unresolvable finding survives a reading taken mid-retry")
    func unresolvableRecordDetectedMidRetry() {
        let job = Self.snapshot("""
        system/com.amunx.rockxy.helper = {
            active count = 0
            state = not running
            runs = 65
            last exit code = 78: EX_CONFIG
            BTM uuid = 928AE75A-F33E-434B-B070-90EF82323FDB
        }
        """)
        // Same record before and after a re-registration is the evidence that re-registering
        // reused it rather than replacing it, which is what happened on 2026-11-21.
        #expect(HelperManager.isUnresolvableRecord(
            job: job,
            beforeBTMUUID: "928AE75A-F33E-434B-B070-90EF82323FDB"
        ))
        // A record that demonstrably changed should resolve, so it is not this finding.
        #expect(!HelperManager.isUnresolvableRecord(
            job: job,
            beforeBTMUUID: "00000000-0000-0000-0000-000000000000"
        ))
    }

    @Test("The remedy names the reset and admits what does not work")
    func remedyIsHonestAboutReinstalling() {
        let message = HelperManager.registrationRecordUnresolvableMessage
        // The user's own first instinct is to delete and reinstall the app. That does not clear
        // the record, so the message has to say so or it sends them down a dead end.
        #expect(message.lowercased().contains("reinstalling"))
        #expect(HelperManager.registrationRecordResetCommand == "sudo sfltool resetbtm")
        // The cost is not visible in the command, so it is stated next to it.
        #expect(HelperManager.registrationRecordResetCaveat.contains("every app"))
    }

    // MARK: Private

    private static func snapshot(_ output: String) -> LaunchdJobSnapshot {
        HelperLaunchdProbe.makeSnapshot(
            exitStatus: 0,
            wasSignalled: false,
            output: output,
            machService: "com.amunx.rockxy.helper"
        )
    }
}
