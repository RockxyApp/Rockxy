import Foundation
@testable import Rockxy
import Testing

// Regression tests for the protocol-first helper capability policy. The defect these pin is a
// build-number threshold standing in for a capability: a shipped Rockxy copy embeds a helper
// whose build number is at or above this checkout's while it still speaks protocol 1, so
// `build >= N` would advertise a selector that helper does not implement.

// MARK: - HelperCompatibilityPolicyTests

struct HelperCompatibilityPolicyTests {
    @Test("a protocol-1 helper is outdated whatever its build number claims")
    func protocolOneIsOutdatedRegardlessOfBuild() {
        for build in [0, 7, 8, 9, 1_000_000] {
            #expect(HelperCompatibilityPolicy.classify(
                installedProtocolVersion: 1,
                installedBuildNumber: build,
                expectedProtocolVersion: 4,
                bundledBuildNumber: 8
            ) == .outdated)
        }
    }

    @Test("a protocol-1 helper keeps its existing operations but never the DER selector")
    func protocolOneRetainsOldOperationsWithoutTheNewSelector() {
        // The manager may probe an outdated helper, but a protocol-1 result never authorizes
        // certificate installation or exact removal. Proxy operations remain usable.
        #expect(CertificateManager.shouldUseHelperForTrustInstall(status: .installedOutdated, isReachable: true))
        #expect(HelperCompatibilityPolicy.supportsExactCertificateRemoval(protocolVersion: 1) == false)
        #expect(HelperCompatibilityPolicy.supportsSafeCertificateInstall(protocolVersion: 1) == false)
    }

    @Test("the expected protocol falls through to the normal build comparison")
    func expectedProtocolUsesBuildComparison() {
        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: 4,
            installedBuildNumber: 8,
            expectedProtocolVersion: 4,
            bundledBuildNumber: 8
        ) == .compatible)

        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: 4,
            installedBuildNumber: 9,
            expectedProtocolVersion: 4,
            bundledBuildNumber: 8
        ) == .compatible)

        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: 4,
            installedBuildNumber: 7,
            expectedProtocolVersion: 4,
            bundledBuildNumber: 8
        ) == .outdated)
    }

    @Test("protocol 3 is outdated when protocol 4 owns safe proxy routing")
    func protocolThreeRequiresRoutingUpgrade() {
        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: 3,
            installedBuildNumber: 1_000_000,
            expectedProtocolVersion: 4,
            bundledBuildNumber: 8
        ) == .outdated)
    }

    @Test("protocol 2 remains operationally compatible when protocol 3 adds maintenance only")
    func maintenanceOnlyProtocolUpgradeDoesNotRequireReinstall() {
        for build in [0, 7, 8, 1_000_000] {
            #expect(HelperCompatibilityPolicy.classify(
                installedProtocolVersion: 2,
                installedBuildNumber: build,
                expectedProtocolVersion: 3,
                bundledBuildNumber: 8
            ) == .compatible)
        }
    }

    @Test("a missing, nonpositive, unknown, or future protocol fails closed")
    func unusableProtocolsFailClosed() {
        for expected in [6, 99] {
            for installed in [1, expected] {
                #expect(HelperCompatibilityPolicy.classify(
                    installedProtocolVersion: installed,
                    installedBuildNumber: 1_000_000,
                    expectedProtocolVersion: expected,
                    bundledBuildNumber: 8
                ) == .incompatible)
            }
        }
        for installed in [0, -1] {
            #expect(HelperCompatibilityPolicy.classify(
                installedProtocolVersion: installed,
                installedBuildNumber: 1_000_000,
                expectedProtocolVersion: 5,
                bundledBuildNumber: 8
            ) == .incompatible)
        }

        // Newer than this build understands — a downgrade is refused rather than performed.
        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: 5,
            installedBuildNumber: 8,
            expectedProtocolVersion: 4,
            bundledBuildNumber: 8
        ) == .incompatible)
        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: 6,
            installedBuildNumber: 8,
            expectedProtocolVersion: 5,
            bundledBuildNumber: 8
        ) == .incompatible)

        // An app bundle advertising a protocol this checkout does not know is fail-closed.
        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: 2,
            installedBuildNumber: 8,
            expectedProtocolVersion: 6,
            bundledBuildNumber: 8
        ) == .incompatible)

        // An app bundle with no readable protocol version can authorize nothing.
        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: 2,
            installedBuildNumber: 8,
            expectedProtocolVersion: 0,
            bundledBuildNumber: 8
        ) == .incompatible)
    }

    @Test("known non-destructive protocols advertise DER-specific removal")
    func knownNonDestructiveProtocolsSupportExactRemoval() {
        #expect(HelperCompatibilityPolicy.exactCertificateRemovalProtocolVersion == 2)
        #expect(HelperCompatibilityPolicy.supportsExactCertificateRemoval(protocolVersion: 2))
        #expect(HelperCompatibilityPolicy.supportsExactCertificateRemoval(protocolVersion: 3))
        #expect(HelperCompatibilityPolicy.supportsExactCertificateRemoval(protocolVersion: 4))

        #expect(HelperCompatibilityPolicy.supportsExactCertificateRemoval(protocolVersion: 5))

        for protocolVersion in [-1, 0, 1, 6, 99] {
            #expect(HelperCompatibilityPolicy
                .supportsExactCertificateRemoval(protocolVersion: protocolVersion) == false)
        }
    }

    @Test("protocol 3 and newer known helpers support approval-preserving refresh")
    func knownModernProtocolsSupportExecutableRefresh() {
        #expect(HelperCompatibilityPolicy.supportsExecutableRefresh(protocolVersion: 3))
        #expect(HelperCompatibilityPolicy.supportsExecutableRefresh(protocolVersion: 4))
        #expect(HelperCompatibilityPolicy.supportsExecutableRefresh(protocolVersion: 5))
        for protocolVersion in [-1, 0, 1, 2, 6, 99] {
            #expect(!HelperCompatibilityPolicy.supportsExecutableRefresh(protocolVersion: protocolVersion))
        }
    }

    @Test("protocol 4 and the additive protocol 5 own PAC-safe proxy routing and reclaim")
    func onlyModernProtocolsSupportSafeProxyRouting() {
        // Protocol 5 adds the identity probe without touching the proxy ownership contract, so
        // upgrading must not silently take away a capability a protocol-4 helper already had.
        #expect(HelperCompatibilityPolicy.supportsSafeProxyRouting(protocolVersion: 4))
        #expect(HelperCompatibilityPolicy.supportsSafeProxyRouting(protocolVersion: 5))
        for protocolVersion in [-1, 0, 1, 2, 3, 6, 99] {
            #expect(!HelperCompatibilityPolicy.supportsSafeProxyRouting(protocolVersion: protocolVersion))
        }
    }

    @Test("only protocol 5 may be asked to describe its own executable")
    func onlyProtocolFiveSupportsExecutableIdentity() {
        #expect(HelperCompatibilityPolicy.executableIdentityProtocolVersion == 5)
        #expect(HelperCompatibilityPolicy.supportsExecutableIdentity(protocolVersion: 5))
        for protocolVersion in [-1, 0, 1, 2, 3, 4, 6, 99] {
            #expect(!HelperCompatibilityPolicy.supportsExecutableIdentity(protocolVersion: protocolVersion))
        }
    }

    @Test("only protocol 1 and 2 may be migrated destructively")
    func onlyPreRefreshProtocolsRequireDestructiveMigration() {
        #expect(HelperCompatibilityPolicy.requiresLegacyDestructiveMigration(protocolVersion: 1))
        #expect(HelperCompatibilityPolicy.requiresLegacyDestructiveMigration(protocolVersion: 2))
        // A protocol this build cannot reason about is not "legacy" — unregistering it would ask
        // the user to approve a downgrade.
        for protocolVersion in [-1, 0, 3, 4, 5, 6, 99] {
            #expect(!HelperCompatibilityPolicy.requiresLegacyDestructiveMigration(protocolVersion: protocolVersion))
        }
    }

    @Test("a protocol-4 helper is outdated once protocol 5 is expected, but stays fully usable")
    func protocolFourIsOutdatedAgainstProtocolFive() {
        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: 4,
            installedBuildNumber: 1_000_000,
            expectedProtocolVersion: 5,
            bundledBuildNumber: 10
        ) == .outdated)
        #expect(HelperCompatibilityPolicy.supportsSafeProxyRouting(protocolVersion: 4))
        #expect(HelperCompatibilityPolicy.supportsSafeCertificateInstall(protocolVersion: 4))
        #expect(HelperCompatibilityPolicy.supportsExecutableRefresh(protocolVersion: 4))
    }

    @Test("a helper answering the current protocol classifies against this app's own expectations")
    @MainActor
    func currentBundleExpectationsAreSelfConsistent() throws {
        let expected = HelperManager.shared.expectedProtocolVersion
        let bundledBuild = HelperManager.shared.bundledHelperBuild

        // A packaging change must not advertise an unknown protocol or silently skip this check.
        try #require(expected > 0)
        #expect(HelperCompatibilityPolicy.supportsSafeCertificateInstall(protocolVersion: expected))
        #expect(HelperCompatibilityPolicy.supportsExactCertificateRemoval(protocolVersion: expected))
        #expect(HelperCompatibilityPolicy.supportsSafeProxyRouting(protocolVersion: expected))
        #expect(HelperCompatibilityPolicy.classify(
            installedProtocolVersion: expected,
            installedBuildNumber: bundledBuild,
            expectedProtocolVersion: expected,
            bundledBuildNumber: bundledBuild
        ) == .compatible)
    }
}
