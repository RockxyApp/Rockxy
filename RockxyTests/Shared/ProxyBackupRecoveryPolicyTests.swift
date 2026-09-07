import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ProxyBackupRecoveryPolicy`, owner identity, and subset selection in the
// shared recovery layer.

// MARK: - ProxyBackupRecoveryPolicyTests

struct ProxyBackupRecoveryPolicyTests {
    @Test("Recovery keeps the backup while any backed-up service is still Rockxy-owned")
    func recoveryFollowsResidualOwnership() {
        #expect(ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: true,
            ownerSessionIsLive: true
        ) == .preserve)
        #expect(ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: true,
            ownerSessionIsLive: false
        ) == .restore)
        #expect(ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: false,
            ownerSessionIsLive: false
        ) == .clear)
    }

    @Test("A live owner cannot keep a backup that no service still needs")
    func liveOwnerDoesNotPreserveAnUnownedBackup() {
        #expect(ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: false,
            ownerSessionIsLive: true
        ) == .clear)
    }
}

// MARK: - ProxyBackupOwnerIdentityPolicyTests

struct ProxyBackupOwnerIdentityPolicyTests {
    @Test("A live, signature-matched, validated owner keeps its session")
    func authenticatedOwnerIsLive() {
        #expect(ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
            recordedOwnerPID: 4_242,
            recordedStartSignature: "1788787973.748707",
            ownerProcessIsAlive: true,
            liveStartSignature: "1788787973.748707",
            ownerPassesCallerValidation: true
        ))
    }

    @Test("An owner that fails caller validation is treated as gone")
    func untrustedOwnerIsNotLive() {
        #expect(!ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
            recordedOwnerPID: 4_242,
            recordedStartSignature: "1788787973.748707",
            ownerProcessIsAlive: true,
            liveStartSignature: "1788787973.748707",
            ownerPassesCallerValidation: false
        ))
    }

    @Test("A recycled PID does not inherit the recorded session")
    func recycledPIDIsNotLive() {
        #expect(!ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
            recordedOwnerPID: 4_242,
            recordedStartSignature: "1788787973.748707",
            ownerProcessIsAlive: true,
            liveStartSignature: "1788799999.100000",
            ownerPassesCallerValidation: true
        ))
    }

    @Test("A legacy backup without recorded identity is never live")
    func legacyIdentityIsNotLive() {
        #expect(!ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
            recordedOwnerPID: nil,
            recordedStartSignature: nil,
            ownerProcessIsAlive: true,
            liveStartSignature: "1788787973.748707",
            ownerPassesCallerValidation: true
        ))
        #expect(!ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
            recordedOwnerPID: 4_242,
            recordedStartSignature: nil,
            ownerProcessIsAlive: true,
            liveStartSignature: "1788787973.748707",
            ownerPassesCallerValidation: true
        ))
    }

    @Test("A dead owner is never live even when everything else lines up")
    func deadOwnerIsNotLive() {
        #expect(!ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
            recordedOwnerPID: 4_242,
            recordedStartSignature: "1788787973.748707",
            ownerProcessIsAlive: false,
            liveStartSignature: nil,
            ownerPassesCallerValidation: true
        ))
    }
}

// MARK: - ProxyBackupSubsetTests

struct ProxyBackupSubsetTests {
    // MARK: Internal

    @Test("Subset selection keeps only the owned services, in backup order")
    func selectionKeepsOwnedServicesInOrder() {
        let entries = [entry("Wi-Fi"), entry("Ethernet"), entry("USB LAN")]

        let selected = ProxyBackupSubset.select(
            entries,
            services: ["USB LAN", "Wi-Fi"],
            serviceName: \.service
        )

        #expect(selected.map(\.service) == ["Wi-Fi", "USB LAN"])
    }

    @Test("Subset selection of nothing owned is empty")
    func selectionOfNoOwnedServicesIsEmpty() {
        let entries = [entry("Wi-Fi"), entry("Ethernet")]

        #expect(ProxyBackupSubset.select(entries, services: [], serviceName: \.service).isEmpty)
    }

    @Test("Unresolved entries cover both failed commands and services still pointing at Rockxy")
    func unresolvedEntriesUnionFailuresAndResidualOwnership() {
        let entries = [entry("Wi-Fi"), entry("Ethernet"), entry("USB LAN")]

        let unresolved = ProxyBackupSubset.unresolvedEntries(
            entries,
            failedServices: ["Ethernet"],
            stillOwnedServices: ["USB LAN"],
            serviceName: \.service
        )

        #expect(unresolved.map(\.service) == ["Ethernet", "USB LAN"])
    }

    @Test("A fully resolved restore attempt leaves nothing to retry")
    func resolvedRestoreLeavesNoEntries() {
        let entries = [entry("Wi-Fi"), entry("Ethernet")]

        let unresolved = ProxyBackupSubset.unresolvedEntries(
            entries,
            failedServices: [],
            stillOwnedServices: [],
            serviceName: \.service
        )

        #expect(unresolved.isEmpty)
    }

    // MARK: Private

    private struct BackupEntry {
        let service: String
    }

    private func entry(_ service: String) -> BackupEntry {
        BackupEntry(service: service)
    }
}
