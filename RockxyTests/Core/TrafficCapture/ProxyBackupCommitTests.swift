import Foundation
@testable import Rockxy
import Testing

// Regression tests for the order a proxy backup's two on-disk copies are published in, and for
// what a current build is allowed to read back from them after an upgrade.

// MARK: - ProxyBackupCommitTests

struct ProxyBackupCommitTests {
    @Test("The compatibility copies are dealt with before the authoritative record is committed")
    func compatibilityCopiesArePreparedFirst() throws {
        var steps: [String] = []

        try ProxyBackupCommit.run(
            prepareCompatibilityCopies: { steps.append("compatibility") },
            publishAuthoritative: { steps.append("authoritative") }
        )

        #expect(steps == ["compatibility", "authoritative"])
    }

    @Test("A compatibility copy that cannot be prepared stops the commit before it happens")
    func aFailedCompatibilityCopyBlocksTheCommit() {
        var committed = false

        #expect(throws: BackupWriteError.self) {
            try ProxyBackupCommit.run(
                prepareCompatibilityCopies: { throw BackupWriteError.denied },
                publishAuthoritative: { committed = true }
            )
        }

        // A reported failure has to mean nothing was committed: every caller treats a successful
        // write as its permission to issue a `networksetup` command.
        #expect(!committed)
    }

    @Test("A compatibility copy that cannot be written is removed instead")
    func anUnwritableCompatibilityCopyIsInvalidated() throws {
        var exists = true

        let outcome = try ProxyBackupCompatibilityCopy.prepare(
            publish: { throw BackupWriteError.denied },
            remove: { exists = false },
            copyExists: { exists }
        )

        #expect(outcome == .invalidated)
    }

    @Test("A compatibility copy that can be neither written nor removed is a pre-commit failure")
    func aStubbornCompatibilityCopyThrows() {
        #expect(throws: BackupWriteError.self) {
            try ProxyBackupCompatibilityCopy.prepare(
                publish: { throw BackupWriteError.denied },
                remove: {},
                copyExists: { true }
            )
        }
    }
}

// MARK: - ProxyBackupUpgradeTests

/// The upgrade these cover is the one where the marker itself is new: a build that predates it
/// wrote unmarked bytes to both locations, and a current build reads an unmarked compatibility
/// copy as truth — correctly, because for that build it was the only backup there was. What must
/// never happen is that answer surviving into a session where a current-format commit has already
/// moved on without it.
struct ProxyBackupUpgradeTests {
    // MARK: Internal

    @Test("An unmarked compatibility copy is truth only while no current commit has succeeded")
    func b0BackupIsReadableUntilB1Commits() throws {
        let disk = BackupDisk()
        disk.writeUnmarkedLegacyBackupToBothLocations(named: "b0")

        // B0's own backup: nothing current has been committed, so the compatibility copy is the
        // only record there is and reading it is the honest answer.
        #expect(disk.load() == "b0")

        try disk.commit(named: "b1")

        // After the commit both copies are current, and the authoritative one is what recovery
        // reads.
        #expect(disk.load() == "b1")
        #expect(disk.role(at: .compatibility) == .mirror)
    }

    @Test("Losing the authoritative record falls back to the prepared current mirror")
    func aLostAuthoritativeRecordUsesB1Mirror() throws {
        let disk = BackupDisk()
        disk.writeUnmarkedLegacyBackupToBothLocations(named: "b0")
        try disk.commit(named: "b1")

        disk.remove(.authoritative)

        // The compatibility copy was prepared as B1 before the authoritative commit advanced,
        // so it is the exact current restore point rather than the older unmarked B0 bytes.
        #expect(disk.load() == "b1")
    }

    @Test("A commit that could not convert the compatibility copy never advances")
    func aBlockedCompatibilityCopyLeavesTheOldCommitInPlace() throws {
        let disk = BackupDisk()
        try disk.commit(named: "b1")
        disk.compatibilityCopyIsWritable = false
        disk.compatibilityCopyIsRemovable = false

        #expect(throws: BackupWriteError.self) {
            try disk.commit(named: "b2")
        }

        // The record on disk is still the one the previous commit published, which is what a
        // caller that was told "this write failed" has to be able to rely on.
        #expect(disk.load() == "b1")
    }

    @Test("Copy roles are accepted only at compatible recovery locations")
    func copyRolesMatchTheirRecoveryLocations() {
        #expect(!ProxyBackupCopyPolicy.isRecoveryTruth(role: .mirror, isAuthoritativeLocation: true))
        #expect(ProxyBackupCopyPolicy.isRecoveryTruth(role: .authoritative, isAuthoritativeLocation: true))
        #expect(ProxyBackupCopyPolicy.isRecoveryTruth(role: nil, isAuthoritativeLocation: true))
        #expect(ProxyBackupCopyPolicy.isRecoveryTruth(role: .mirror, isAuthoritativeLocation: false))
        #expect(!ProxyBackupCopyPolicy.isRecoveryTruth(role: .authoritative, isAuthoritativeLocation: false))
        #expect(ProxyBackupCopyPolicy.isRecoveryTruth(role: nil, isAuthoritativeLocation: false))
    }

    // MARK: Private

    /// The two on-disk locations a proxy backup lives at, published and read through the same
    /// policies the helper uses. Modelling the bytes rather than the filesystem keeps the ordering
    /// under test deterministic and root-free.
    private final class BackupDisk {
        // MARK: Internal

        enum Location {
            case authoritative
            case compatibility
        }

        var compatibilityCopyIsWritable = true
        var compatibilityCopyIsRemovable = true

        func writeUnmarkedLegacyBackupToBothLocations(named name: String) {
            authoritative = (name, nil)
            compatibility = (name, nil)
        }

        func commit(named name: String) throws {
            try ProxyBackupCommit.run(
                prepareCompatibilityCopies: {
                    try ProxyBackupCompatibilityCopy.prepare(
                        publish: {
                            guard compatibilityCopyIsWritable else {
                                throw BackupWriteError.denied
                            }
                            compatibility = (name, .mirror)
                        },
                        remove: {
                            guard compatibilityCopyIsRemovable else {
                                return
                            }
                            compatibility = nil
                        },
                        copyExists: { compatibility != nil }
                    )
                },
                publishAuthoritative: { authoritative = (name, .authoritative) }
            )
        }

        func remove(_ location: Location) {
            switch location {
            case .authoritative:
                authoritative = nil
            case .compatibility:
                compatibility = nil
            }
        }

        func role(at location: Location) -> ProxyBackupCopyRole? {
            switch location {
            case .authoritative:
                authoritative?.role
            case .compatibility:
                compatibility?.role
            }
        }

        /// The loader, in the order the helper reads the locations.
        func load() -> String? {
            for (isAuthoritativeLocation, copy) in [(true, authoritative), (false, compatibility)] {
                guard let copy else {
                    continue
                }
                if ProxyBackupCopyPolicy.isRecoveryTruth(
                    role: copy.role,
                    isAuthoritativeLocation: isAuthoritativeLocation
                ) {
                    return copy.name
                }
            }
            return nil
        }

        // MARK: Private

        private var authoritative: (name: String, role: ProxyBackupCopyRole?)?
        private var compatibility: (name: String, role: ProxyBackupCopyRole?)?
    }
}

// MARK: - BackupWriteError

private enum BackupWriteError: Error {
    case denied
}
