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

// MARK: - ProxyOwnerWatchdogPolicyTests

struct ProxyOwnerWatchdogPolicyTests {
    @Test("The watchdog keeps watching only while the recorded process is still the live one")
    func matchingIdentityKeepsTheSessionAlive() {
        #expect(ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: 4_242,
            recordedStartSignature: "1788787973.748707",
            processIsAlive: true,
            liveStartSignature: "1788787973.748707"
        ))
    }

    @Test("A reused process identifier is treated as the owner being gone")
    func recycledIdentifierTriggersRestore() {
        #expect(!ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: 4_242,
            recordedStartSignature: "1788787973.748707",
            processIsAlive: true,
            liveStartSignature: "1788799999.100000"
        ))
        #expect(!ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: 4_242,
            recordedStartSignature: "1788787973.748707",
            processIsAlive: true,
            liveStartSignature: nil
        ))
    }

    @Test("An exited owner is gone whatever the signatures say")
    func exitedOwnerIsNotLive() {
        #expect(!ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: 4_242,
            recordedStartSignature: "1788787973.748707",
            processIsAlive: false,
            liveStartSignature: "1788787973.748707"
        ))
    }

    @Test("A record with no signature never counts as a live session")
    func missingSignatureIsNeverLive() {
        // An override is refused outright unless the requesting process can be identified, so a
        // record with no signature cannot describe a session worth protecting. Reporting it as
        // live would be the bare-identifier check this policy exists to remove.
        #expect(!ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: 4_242,
            recordedStartSignature: nil,
            processIsAlive: true,
            liveStartSignature: "1788787973.748707"
        ))
        #expect(!ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: 4_242,
            recordedStartSignature: "",
            processIsAlive: true,
            liveStartSignature: "1788787973.748707"
        ))
        #expect(!ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: 4_242,
            recordedStartSignature: nil,
            processIsAlive: false,
            liveStartSignature: nil
        ))
    }

    @Test("A preserved owner's recorded signature is what the re-armed watchdog compares against")
    func preservedOwnerCarriesItsSignatureIntoTheWatchdog() {
        let recordedSignature = "1788787973.748707"

        // Startup recovery preserves the session only when the recorded identity matches the live
        // one, so the same signature has to survive into the watchdog — otherwise the re-armed
        // watchdog would be back to trusting a bare identifier.
        #expect(ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
            recordedOwnerPID: 4_242,
            recordedStartSignature: recordedSignature,
            ownerProcessIsAlive: true,
            liveStartSignature: recordedSignature,
            ownerPassesCallerValidation: true
        ))
        #expect(ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: 4_242,
            recordedStartSignature: recordedSignature,
            processIsAlive: true,
            liveStartSignature: recordedSignature
        ))
        #expect(!ProxyOwnerWatchdogPolicy.watchedOwnerIsLive(
            recordedPID: 4_242,
            recordedStartSignature: recordedSignature,
            processIsAlive: true,
            liveStartSignature: "1788799999.100000"
        ))
    }
}

// MARK: - ProxyOverrideApplicationPolicyTests

/// Applying an override touches several network services with no transaction behind it. These
/// cover what a partially applied attempt is allowed to report, and what counts as a service it
/// never wrote to.
struct ProxyOverrideApplicationPolicyTests {
    // MARK: Internal

    @Test("A service that still reads exactly as captured was never written to")
    func unchangedServiceReadsAsUntouched() {
        #expect(ProxyOverrideApplicationPolicy.serviceIsUntouched(
            live: captured,
            captured: captured
        ))
    }

    @Test("A service that no longer matches its capture counts as mutated")
    func changedServiceReadsAsTouched() {
        let halfApplied = ProxyServiceRestorationState(
            service: "Wi-Fi",
            http: ProxyEndpointState(enabled: true, host: "127.0.0.1", port: 9_090),
            https: captured.https,
            socks: captured.socks,
            pacEnabled: captured.pacEnabled,
            pacURL: captured.pacURL,
            autoDiscoveryEnabled: captured.autoDiscoveryEnabled,
            bypassDomains: captured.bypassDomains
        )

        #expect(!ProxyOverrideApplicationPolicy.serviceIsUntouched(
            live: halfApplied,
            captured: captured
        ))
    }

    @Test("A service that could not be read is never assumed untouched")
    func unreadableServiceReadsAsTouched() {
        // An unreadable state cannot be shown to be unchanged, and assuming it is would leave a
        // mutated service with no rollback and no restore point.
        #expect(!ProxyOverrideApplicationPolicy.serviceIsUntouched(
            live: nil,
            captured: captured
        ))
    }

    @Test("An attempt that configured every service it touched is applied")
    func fullyConfiguredAttemptIsApplied() {
        #expect(ProxyOverrideApplicationPolicy.outcome(
            configuredServices: ["Wi-Fi", "Ethernet"],
            partiallyAppliedServices: [],
            unresolvedServices: []
        ) == .applied)
    }

    @Test("One half-applied service makes the whole attempt a rollback, not a success")
    func partialApplicationIsNeverReportedAsSuccess() {
        #expect(ProxyOverrideApplicationPolicy.outcome(
            configuredServices: ["Wi-Fi"],
            partiallyAppliedServices: ["Ethernet"],
            unresolvedServices: []
        ) == .rolledBack)
    }

    @Test("A service the rollback could not put back keeps the failure and the backup")
    func unresolvedRollbackIsReportedIncomplete() {
        #expect(ProxyOverrideApplicationPolicy.outcome(
            configuredServices: ["Wi-Fi"],
            partiallyAppliedServices: ["Ethernet"],
            unresolvedServices: ["Ethernet"]
        ) == .rollbackIncomplete)
    }

    @Test("A service left overridden outweighs an otherwise clean attempt")
    func residualOwnershipAfterRollbackIsIncomplete() {
        #expect(ProxyOverrideApplicationPolicy.outcome(
            configuredServices: ["Wi-Fi", "Ethernet"],
            partiallyAppliedServices: [],
            unresolvedServices: ["Wi-Fi"]
        ) == .rollbackIncomplete)
    }

    @Test("An attempt that configured nothing has nothing to report as applied")
    func nothingConfiguredIsNotApplied() {
        #expect(ProxyOverrideApplicationPolicy.outcome(
            configuredServices: [],
            partiallyAppliedServices: [],
            unresolvedServices: []
        ) == .rolledBack)
    }

    // MARK: Private

    private let captured = ProxyServiceRestorationState(
        service: "Wi-Fi",
        http: ProxyEndpointState(enabled: true, host: "proxy.corp.example", port: 8_080),
        https: ProxyEndpointState(enabled: true, host: "secure.corp.example", port: 8_443),
        socks: ProxyEndpointState(enabled: false, host: "", port: 0),
        pacEnabled: false,
        pacURL: "",
        autoDiscoveryEnabled: false,
        bypassDomains: ["localhost"]
    )
}
