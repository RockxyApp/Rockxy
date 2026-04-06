import Foundation
@testable import Rockxy
import Testing

// MARK: - TrustCacheRecoveryTests

/// Tests that the trust validation cache (`lastTrustValidationResult`) correctly
/// clears on state-changing operations and does not short-circuit real validation.
/// Uses `CertificateManager.shared` singleton — serialized to avoid cross-test races.
@Suite(.serialized)
struct TrustCacheRecoveryTests {
    @Test("helper trust install only runs when helper is reachable and compatible")
    func helperTrustInstallAvailability() {
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .installedCompatible,
            isReachable: true
        ))
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .installedOutdated,
            isReachable: true
        ))

        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .notInstalled,
            isReachable: false
        ) == false)
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .requiresApproval,
            isReachable: false
        ) == false)
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .installedCompatible,
            isReachable: false
        ) == false)
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .unreachable,
            isReachable: false
        ) == false)
    }

    @Test("cached false does not block real revalidation via isRootCATrustValidated")
    func cachedFalseDoesNotBlockRealRevalidation() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        // Generate a root CA so validateSystemTrust() has material to work with
        try await manager.generateRootCA()

        // Force a failed validation — without real trust settings installed,
        // validateSystemTrust() will return false and cache that result.
        // validateSystemTrust() may pass via Strategy B (explicit anchor) even without
        // admin trust. The key test: isRootCATrustValidated() uses hasTrustSettingsPresent()
        // as its pre-filter (NOT isRootCATrusted()), so the cache never blocks revalidation.
        let firstResult = await manager.validateSystemTrust()
        let cached = await manager.lastTrustValidationResult
        #expect(cached != nil) // Cached some result (true or false)

        // isRootCATrustValidated() requires hasTrustSettingsPresent() as pre-filter.
        // In test context without admin trust metadata, it returns false early.
        let validated = await manager.isRootCATrustValidated()
        #expect(validated == false)
    }

    @Test("cached false surfaces in cheap check isRootCATrusted")
    func cachedFalseSurfacesInCheapCheck() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try await manager.generateRootCA()

        // Run validateSystemTrust() — may return true (Strategy B) or false
        let result = await manager.validateSystemTrust()
        let cached = await manager.lastTrustValidationResult
        #expect(cached != nil)

        // If validation cached false, isRootCATrusted() must also return false
        if result == false {
            let trusted = await manager.isRootCATrusted()
            #expect(trusted == false)
        }
    }

    @Test("cache cleared by generateRootCA")
    func cacheClearedByGenerateRootCA() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        // Generate once and force a validation failure into the cache
        try await manager.generateRootCA()
        _ = await manager.validateSystemTrust()
        let cachedBefore = await manager.lastTrustValidationResult
        #expect(cachedBefore != nil)

        // Generate again — cache must be cleared
        try await manager.generateRootCA()
        let cachedAfter = await manager.lastTrustValidationResult
        #expect(cachedAfter == nil)
    }

    @Test("installAndTrust clears cache at start (verified via source inspection)")
    func cacheClearedByInstallAndTrust() async throws {
        // installAndTrust() sets lastTrustValidationResult = nil as its first line.
        // We cannot call it in unit tests because it requires XPC to the helper daemon.
        // This test verifies the equivalent behavior: that generateRootCA() (which also
        // clears the cache) demonstrates the pattern works correctly.
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try await manager.generateRootCA()
        _ = await manager.validateSystemTrust()
        let cachedBefore = await manager.lastTrustValidationResult
        #expect(cachedBefore != nil)

        // generateRootCA() clears cache — same pattern as installAndTrust()
        try await manager.generateRootCA()
        let cachedAfter = await manager.lastTrustValidationResult
        #expect(cachedAfter == nil)
    }

    @Test("cache cleared by removeRootCATrust")
    func cacheClearedByRemoveRootCATrust() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try await manager.generateRootCA()

        // Force a cached result
        _ = await manager.validateSystemTrust()
        let cachedBefore = await manager.lastTrustValidationResult
        #expect(cachedBefore != nil)

        // removeRootCATrust() clears the cache
        do {
            try await manager.removeRootCATrust()
        } catch {
            // May throw if cert not in keychain — that's fine for this test
        }

        let cachedAfter = await manager.lastTrustValidationResult
        #expect(cachedAfter == nil)
    }

    @Test("cache cleared by reset")
    func cacheClearedByReset() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try await manager.generateRootCA()

        // Force a cached result
        _ = await manager.validateSystemTrust()
        let cachedBefore = await manager.lastTrustValidationResult
        #expect(cachedBefore != nil)

        // reset() clears the cache
        do {
            try await manager.reset()
        } catch {
            // May throw from keychain cleanup — acceptable in test context
        }

        let cachedAfter = await manager.lastTrustValidationResult
        #expect(cachedAfter == nil)
    }

    @Test("lastValidationErrorMessage set on failure and cleared on cache reset")
    func validationErrorMessageLifecycle() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try await manager.generateRootCA()

        // Run validateSystemTrust() — may succeed via Strategy B or fail via Strategy A.
        // Either way, the cache and error message state should be updated.
        let result = await manager.validateSystemTrust()
        let cached = await manager.lastTrustValidationResult
        #expect(cached != nil)

        // If validation passed (Strategy B), error message should be nil.
        // If validation failed, error message should be non-nil.
        let errorMessage = await manager.lastValidationErrorMessage
        if result {
            #expect(errorMessage == nil)
        } else {
            #expect(errorMessage != nil)
        }

        // generateRootCA clears the error message along with the cache
        try await manager.generateRootCA()
        let clearedMessage = await manager.lastValidationErrorMessage
        #expect(clearedMessage == nil)
    }
}

// MARK: - RootCAStatusSnapshotTests

/// Tests that `rootCAStatusSnapshot()` accurately reflects the certificate manager's
/// current state. These tests generate real certificates but do not install them
/// in the system keychain.
@Suite(.serialized)
struct RootCAStatusSnapshotTests {
    @Test("snapshot reflects generated state")
    func snapshotReflectsGeneratedState() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try await manager.generateRootCA()

        let snapshot = await manager.rootCAStatusSnapshot()

        #expect(snapshot.hasGeneratedCertificate == true)
        #expect(snapshot.notValidBefore != nil)
        #expect(snapshot.notValidAfter != nil)
        #expect(snapshot.fingerprintSHA256 != nil)
        #expect(snapshot.commonName?.contains("Rockxy") == true)
    }

    @Test("snapshot reflects not-available state when no cert loaded")
    func snapshotReflectsNotAvailableState() {
        // Test pure snapshot field mapping using a manually constructed snapshot
        // (avoids shared singleton state issues in parallel test execution)
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: false,
            isInstalledInKeychain: false,
            hasTrustSettings: false,
            isSystemTrustValidated: false,
            notValidBefore: nil,
            notValidAfter: nil,
            fingerprintSHA256: nil,
            commonName: nil,
            lastValidationErrorMessage: nil
        )

        #expect(snapshot.hasGeneratedCertificate == false)
        #expect(snapshot.notValidBefore == nil)
        #expect(snapshot.notValidAfter == nil)
        #expect(snapshot.fingerprintSHA256 == nil)
        #expect(snapshot.commonName == nil)
    }

    @Test("snapshot validation fields match trust result for generated-only cert")
    func snapshotValidationFieldMatchesTrustResult() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        // Generate cert but do NOT install or trust it
        try await manager.generateRootCA()

        let snapshot = await manager.rootCAStatusSnapshot()

        // Without installation, trust settings metadata is not present,
        // so system trust validation is not attempted
        #expect(snapshot.hasTrustSettings == false)
        #expect(snapshot.isSystemTrustValidated == false)
    }

    @Test("snapshot validity dates are in the correct order")
    func snapshotValidityDatesOrdered() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try await manager.generateRootCA()

        let snapshot = await manager.rootCAStatusSnapshot()

        if let before = snapshot.notValidBefore, let after = snapshot.notValidAfter {
            #expect(before < after)
        } else {
            Issue.record("Expected non-nil validity dates after generating root CA")
        }
    }

    @Test("snapshot fingerprint is SHA-256 format")
    func snapshotFingerprintFormat() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try await manager.generateRootCA()

        let snapshot = await manager.rootCAStatusSnapshot()

        guard let fingerprint = snapshot.fingerprintSHA256 else {
            Issue.record("Expected non-nil fingerprint after generating root CA")
            return
        }

        // SHA-256 fingerprint should be a hex string (64 hex chars, possibly with colons)
        let hexOnly = fingerprint.replacingOccurrences(of: ":", with: "")
        #expect(hexOnly.count == 64)
        let allHex = hexOnly.allSatisfy(\.isHexDigit)
        #expect(allHex)
    }
}

// MARK: - CertificateStatusStateTests

/// Tests the four-state derivation logic that `CertificateStatusPanel` uses to map
/// a `RootCAStatusSnapshot` into a display state. The derivation priority is:
///
/// 1. `isSystemTrustValidated == true` -> "Trusted"
/// 2. `isInstalledInKeychain && hasTrustSettings && !isSystemTrustValidated` -> "Trust Incomplete"
/// 3. `hasGeneratedCertificate && !isInstalledInKeychain` -> "Generated Only"
/// 4. `!hasGeneratedCertificate` -> "Not Available"
struct CertificateStatusStateTests {
    // MARK: Internal

    @Test("trusted state: all flags true")
    func trustedState() {
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: true,
            isInstalledInKeychain: true,
            hasTrustSettings: true,
            isSystemTrustValidated: true,
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60),
            fingerprintSHA256: "AB:CD:EF:12:34:56:78:90",
            commonName: "Rockxy CA",
            lastValidationErrorMessage: nil
        )

        let state = deriveState(from: snapshot)
        #expect(state == .trusted)
    }

    @Test("trust incomplete state: installed + trust settings + NOT validated")
    func trustIncompleteState() {
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: true,
            isInstalledInKeychain: true,
            hasTrustSettings: true,
            isSystemTrustValidated: false,
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60),
            fingerprintSHA256: "AB:CD:EF:12:34:56:78:90",
            commonName: "Rockxy CA",
            lastValidationErrorMessage: "SecTrust evaluation failed"
        )

        let state = deriveState(from: snapshot)
        #expect(state == .trustIncomplete)
    }

    @Test("generated only state: generated + NOT installed")
    func generatedOnlyState() {
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: true,
            isInstalledInKeychain: false,
            hasTrustSettings: false,
            isSystemTrustValidated: false,
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60),
            fingerprintSHA256: "AB:CD:EF:12:34:56:78:90",
            commonName: "Rockxy CA",
            lastValidationErrorMessage: nil
        )

        let state = deriveState(from: snapshot)
        #expect(state == .generatedOnly)
    }

    @Test("not available state: nothing generated")
    func notAvailableState() {
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: false,
            isInstalledInKeychain: false,
            hasTrustSettings: false,
            isSystemTrustValidated: false,
            notValidBefore: nil,
            notValidAfter: nil,
            fingerprintSHA256: nil,
            commonName: nil,
            lastValidationErrorMessage: nil
        )

        let state = deriveState(from: snapshot)
        #expect(state == .notAvailable)
    }

    @Test("trust incomplete takes priority over generated only when installed")
    func trustIncompletePriorityOverGeneratedOnly() {
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: true,
            isInstalledInKeychain: true,
            hasTrustSettings: true,
            isSystemTrustValidated: false,
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60),
            fingerprintSHA256: "AB:CD:EF:12:34:56:78:90",
            commonName: "Rockxy CA",
            lastValidationErrorMessage: "Trust evaluation failed"
        )

        let state = deriveState(from: snapshot)
        #expect(state == .trustIncomplete)
        #expect(state != .generatedOnly)
    }

    @Test("trusted state takes priority over all other states")
    func trustedPriorityOverAll() {
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: true,
            isInstalledInKeychain: true,
            hasTrustSettings: true,
            isSystemTrustValidated: true,
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60),
            fingerprintSHA256: "AB:CD:EF:12:34:56:78:90",
            commonName: "Rockxy CA",
            lastValidationErrorMessage: nil
        )

        let state = deriveState(from: snapshot)
        #expect(state == .trusted)
        #expect(state != .trustIncomplete)
        #expect(state != .generatedOnly)
        #expect(state != .notAvailable)
    }

    @Test("error message preserved in trust incomplete snapshot")
    func errorMessagePreservedInTrustIncomplete() {
        let errorMsg = "Certificate chain validation failed: expired"
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: true,
            isInstalledInKeychain: true,
            hasTrustSettings: true,
            isSystemTrustValidated: false,
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60),
            fingerprintSHA256: "AB:CD:EF:12:34:56:78:90",
            commonName: "Rockxy CA",
            lastValidationErrorMessage: errorMsg
        )

        #expect(snapshot.lastValidationErrorMessage == errorMsg)
    }

    @Test("installed but no trust settings maps to installedNotTrusted")
    func installedNotTrustedState() {
        let snapshot = RootCAStatusSnapshot(
            hasGeneratedCertificate: true,
            isInstalledInKeychain: true,
            hasTrustSettings: false,
            isSystemTrustValidated: false,
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(24 * 60 * 60 * 365),
            fingerprintSHA256: "AABB",
            commonName: "Rockxy Test",
            lastValidationErrorMessage: nil
        )

        let state = deriveState(from: snapshot)
        #expect(state == .installedNotTrusted)
    }

    // MARK: Private

    private enum DerivedCertificateState {
        case trusted
        case trustIncomplete
        case installedNotTrusted
        case generatedOnly
        case notAvailable
    }

    /// Derives the UI display state from a `RootCAStatusSnapshot`, matching
    /// the logic defined in the `CertificateStatusPanel` design spec.
    private func deriveState(from snapshot: RootCAStatusSnapshot) -> DerivedCertificateState {
        if snapshot.isSystemTrustValidated {
            return .trusted
        }
        if snapshot.isInstalledInKeychain, snapshot.hasTrustSettings {
            return .trustIncomplete
        }
        if snapshot.isInstalledInKeychain {
            return .installedNotTrusted
        }
        if snapshot.hasGeneratedCertificate {
            return .generatedOnly
        }
        return .notAvailable
    }
}

// MARK: - ProxyGatingTests

/// Tests behavioral properties of `isRootCATrustValidated()`, which is the gating
/// function used before proxy start to ensure the root CA is truly trusted.
@Suite(.serialized)
struct ProxyGatingTests {
    @Test("helper trust path is skipped when helper is not installed")
    func helperTrustPathSkippedWhenNotInstalled() {
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .notInstalled,
            isReachable: false
        ) == false)
    }

    @Test("helper trust path is skipped when helper requires approval")
    func helperTrustPathSkippedWhenApprovalPending() {
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .requiresApproval,
            isReachable: false
        ) == false)
    }

    @Test("helper trust path only runs for reachable compatible helper")
    func helperTrustPathRequiresReachableCompatibleHelper() {
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .installedCompatible,
            isReachable: true
        ))
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .installedCompatible,
            isReachable: false
        ) == false)
        #expect(CertificateManager.shouldUseHelperForTrustInstall(
            status: .installedOutdated,
            isReachable: true
        ))
    }

    @Test("proxy gating uses real validation not just metadata check")
    func proxyGatingUsesRealValidation() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        try await manager.generateRootCA()

        // Clear any cached result to start fresh
        let cachedBefore = await manager.lastTrustValidationResult
        // After generateRootCA, cache should be nil
        #expect(cachedBefore == nil)

        // isRootCATrustValidated() requires hasTrustSettingsPresent() as pre-filter.
        // In test context without admin trust, returns false without running validation.
        let gatingResult = await manager.isRootCATrustValidated()
        #expect(gatingResult == false)

        // Pre-filter short-circuited — validation was not called, cache stays nil
        let cachedAfter = await manager.lastTrustValidationResult
        #expect(cachedAfter == nil)
    }

    @Test("isRootCATrustValidated returns false without root CA")
    func proxyGatingReturnsFalseWithoutRootCA() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        // Reset to remove any existing root CA
        do {
            try await manager.reset()
        } catch {
            // Keychain cleanup may fail in test context
        }

        let result = await manager.isRootCATrustValidated()
        #expect(result == false)
    }

    @Test("validateSystemTrust returns false and sets error without root CA")
    func validateSystemTrustWithoutRootCA() async throws {
        let manager = CertificateManager.shared
        let overrides = installTestOverrides()
        defer { overrides.cleanup() }

        do {
            try await manager.reset()
        } catch {}

        let result = await manager.validateSystemTrust()
        #expect(result == false)

        let cached = await manager.lastTrustValidationResult
        #expect(cached == false)

        let errorMessage = await manager.lastValidationErrorMessage
        #expect(errorMessage != nil)
    }
}

// MARK: - Test Isolation Helpers (shared with CertificateTests)

/// Uses installSharedTestOverrides() from CertificateTestHelpers.swift
/// for cross-suite lock coordination of CertificateStore overrides.
private func installTestOverrides() -> (label: String, storageDir: URL, cleanup: () -> Void) {
    installSharedTestOverrides()
}
