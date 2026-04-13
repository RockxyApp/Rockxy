import Crypto
import Foundation
import os
import Security
import SwiftASN1
import X509

// MARK: - CertificateManager

/// Central coordinator for all TLS certificate operations. Manages the root CA
/// lifecycle (generate, persist, install in keychain) and provides per-host
/// certificates for HTTPS interception on demand.
///
/// Actor isolation guarantees thread-safe access to the LRU host certificate cache
/// (capped at 1,000 entries) and root CA state. The proxy engine's NIO handlers
/// call into this actor via `makeFutureWithTask` to bridge from event loop threads.
actor CertificateManager {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CertificateManager()

    /// True if the root CA was generated or trust was installed during this app session.
    /// Browsers cache their trust store per-process and need restart to pick up new CAs.
    private(set) var rootCAFreshlyInstalled = false

    /// Cached result of the last real SecTrust evaluation. `nil` means no validation has run yet.
    /// Set by `validateSystemTrust()`. Cleared when trust state changes (install, remove, reset).
    /// When `false`, `isRootCATrusted()` returns false even if metadata says trusted.
    private(set) var lastTrustValidationResult: Bool?

    /// Human-readable error description from the most recent failed `validateSystemTrust()` call.
    /// Cleared alongside `lastTrustValidationResult`.
    private(set) var lastValidationErrorMessage: String?

    var cachedHostCount: Int {
        hostCertCache.count
    }

    nonisolated static func shouldUseHelperForTrustInstall(
        status: HelperManager.HelperStatus,
        isReachable: Bool
    )
        -> Bool
    {
        guard isReachable else {
            return false
        }

        switch status {
        case .installedCompatible,
             .installedOutdated:
            return true
        case .notInstalled,
             .requiresApproval,
             .installedIncompatible,
             .unreachable,
             .signingMismatch:
            return false
        }
    }

    // MARK: - Root CA

    func generateRootCA() throws {
        lastTrustValidationResult = nil
        lastValidationErrorMessage = nil
        let result = try RootCAGenerator.generate()
        rootCACertificate = result.certificate
        rootCAPrivateKey = result.privateKey

        try CertificateStore.saveRootCACertificate(result.certificate)
        // saveRootCAPrivateKey stores to Keychain (primary) and disk (recovery fallback)
        try CertificateStore.saveRootCAPrivateKey(result.privateKey)

        activeRootFingerprint = computeFingerprint(result.certificate)
        rootCAFreshlyInstalled = true
        Self.logger.info("Generated new root CA certificate")
        postCertificateStatusChanged()
    }

    /// Attempts to restore root CA certificate from disk and private key from Keychain
    /// (primary) or disk PEM (migration fallback). CertificateStore.loadRootCAPrivateKey()
    /// handles the Keychain-first lookup with automatic disk-to-Keychain migration.
    func loadExistingRootCA() throws -> Bool {
        guard let cert = try CertificateStore.loadRootCACertificate() else {
            Self.logger.debug("No existing root CA certificate found on disk")
            return false
        }

        let hasSKI = (try? cert.extensions.subjectKeyIdentifier) != nil
        if !hasSKI {
            Self.logger.info("Root CA missing SubjectKeyIdentifier — regenerating")
            return false
        }

        // loadRootCAPrivateKey tries Keychain first, falls back to disk PEM with auto-migration
        guard let key = try CertificateStore.loadRootCAPrivateKey() else {
            Self.logger.debug("No existing root CA private key found")
            return false
        }

        // Verify cert and key are from the same generation by comparing public keys.
        // Certificate.PublicKey wraps the raw SPKI bytes; P256.Signing.PrivateKey.publicKey
        // gives a P256.Signing.PublicKey. Compare via SPKI byte representation.
        let certPublicKeyBytes = cert.publicKey.subjectPublicKeyInfoBytes
        let keyPublicKeyBytes = Certificate.PublicKey(key.publicKey).subjectPublicKeyInfoBytes
        if certPublicKeyBytes != keyPublicKeyBytes {
            Self.logger.warning("SECURITY: Cert-key mismatch detected — cert and key are from different generations")
            rootCACertificate = nil
            rootCAPrivateKey = nil
            lastTrustValidationResult = nil
            lastValidationErrorMessage = nil

            if let diskKey = try? CertificateStore.loadRootCAPrivateKeyFromDisk() {
                let diskKeyBytes = Certificate.PublicKey(diskKey.publicKey).subjectPublicKeyInfoBytes
                if cert.publicKey.subjectPublicKeyInfoBytes == diskKeyBytes {
                    Self.logger.info("Disk PEM key matches certificate — using disk fallback")
                    rootCACertificate = cert
                    rootCAPrivateKey = diskKey
                    activeRootFingerprint = computeFingerprint(cert)
                    return true
                }
            }

            Self.logger.error("SECURITY: All key sources mismatch certificate — forcing full regeneration")
            return false
        }

        rootCACertificate = cert
        rootCAPrivateKey = key
        activeRootFingerprint = computeFingerprint(cert)
        Self.logger.info("Loaded existing root CA (key source: Keychain or migrated)")
        return true
    }

    func ensureRootCA() throws {
        if rootCACertificate != nil, rootCAPrivateKey != nil {
            return
        }

        let loaded = try loadExistingRootCA()
        if !loaded {
            try generateRootCA()
            clearHostCache()
            Self.logger.info("Root CA regenerated — trust must be re-established before HTTPS interception")
        }
    }

    func installRootCAInKeychain() throws {
        guard let certificate = rootCACertificate else {
            throw CertificateManagerError.noRootCA
        }

        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        let derData = Data(serializer.serializedBytes)

        try KeychainHelper.installCertificate(derData, label: Self.keychainCertLabel)
        Self.logger.info("Installed root CA certificate in keychain")
    }

    func isRootCAInstalled() -> Bool {
        if let cert = rootCACertificate, let derData = try? certToDER(cert) {
            let installed = KeychainHelper.isCertificateInstalled(certData: derData)
            Self.logger.debug("Root CA install check (DER): \(installed)")
            return installed
        }
        let installed = KeychainHelper.isCertificateInstalled(label: Self.keychainCertLabel)
        Self.logger.debug("Root CA install check (label fallback): \(installed)")
        return installed
    }

    /// Cheap trust check for UI polling. Returns true only if admin trust-settings
    /// metadata is present in keychain. Cached validation failure overrides to false.
    func isRootCATrusted() -> Bool {
        if let cached = lastTrustValidationResult, !cached {
            return false
        }
        if let cert = rootCACertificate, let derData = try? certToDER(cert) {
            let trusted = KeychainHelper.isRootCATrusted(certData: derData)
            Self.logger.debug("Root CA trust check (DER): \(trusted)")
            return trusted
        }
        let trusted = KeychainHelper.isRootCATrusted(label: Self.keychainCertLabel)
        Self.logger.debug("Root CA trust check (label fallback): \(trusted)")
        return trusted
    }

    /// Pure metadata check for trust-settings presence, without consulting the
    /// cached `lastTrustValidationResult`. Use this as a pre-filter before
    /// running the expensive `validateSystemTrust()` — it avoids the problem
    /// where a stale cached `false` in `isRootCATrusted()` blocks recovery.
    func hasTrustSettingsPresent() -> Bool {
        if let cert = rootCACertificate, let derData = try? certToDER(cert) {
            return KeychainHelper.isRootCATrusted(certData: derData)
        }
        return KeychainHelper.isRootCATrusted(label: Self.keychainCertLabel)
    }

    /// Real trust validation for proxy-start gating and post-install verification.
    /// Performs full SecTrust evaluation using Strategy A (system trust only).
    /// Returns true only when macOS system trust store accepts the generated leaf —
    /// this is what real TLS clients (browsers, curl) actually check.
    func isRootCATrustValidated() -> Bool {
        guard hasTrustSettingsPresent() else {
            return false
        }
        return validateSystemTrust()
    }

    /// Ensures root CA exists, installs it in the system keychain via the privileged
    /// helper tool, and marks it as trusted for TLS. Falls back to direct KeychainHelper
    /// if the helper is unavailable.
    func installAndTrust() async throws {
        lastTrustValidationResult = nil
        lastValidationErrorMessage = nil
        try ensureRootCA()

        guard let certificate = rootCACertificate else {
            throw CertificateManagerError.noRootCA
        }

        let derData = try certToDER(certificate)
        let fingerprint = computeFingerprint(certificate) ?? KeychainHelper.computeFingerprintSHA256(derData)

        var helperHandledTrust = false
        let helperTrustAvailable = await MainActor.run {
            Self.shouldUseHelperForTrustInstall(
                status: HelperManager.shared.status,
                isReachable: HelperManager.shared.isReachable
            )
        }

        // Step 1: Use helper to install cert + set trust in System.keychain only when the
        // cached helper state already says the daemon is usable. Otherwise skip straight to
        // app-side trust so the macOS security prompt appears immediately.
        if helperTrustAvailable {
            do {
                let helperConnection = await MainActor.run { HelperConnection.shared }
                let staleCount = try await helperConnection.cleanupStaleCertificates(activeFingerprint: fingerprint)
                if staleCount > 0 {
                    Self.logger.info("Cleaned up \(staleCount) stale root CA certificate(s)")
                }
                try await helperConnection.installRootCertificate(derData: derData)
                Self.logger.info("Root CA installed and trusted in system keychain via helper")
                helperHandledTrust = true

                // Clean up any stale login-keychain copies from previous installs.
                // Duplicate copies in login keychain can confuse SecTrust evaluation.
                KeychainHelper.removeAllRockxyCertsFromLoginKeychain(label: Self.keychainCertLabel)
            } catch {
                Self.logger.info("Helper unavailable, falling back to app-side trust: \(error.localizedDescription)")
                KeychainHelper.cleanupStaleRockxyCerts(activeFingerprint: fingerprint, label: Self.keychainCertLabel)
            }
        } else {
            Self.logger.info("Skipping helper trust path and using app-side trust immediately")
            KeychainHelper.cleanupStaleRockxyCerts(activeFingerprint: fingerprint, label: Self.keychainCertLabel)
        }

        // Step 2 (fallback only): If helper is unavailable, set trust from app process.
        // This adds to login keychain and uses SecTrustSettingsSetTrustSettings(.admin).
        if !helperHandledTrust {
            try KeychainHelper.installRootCAWithTrust(derData, label: Self.keychainCertLabel)
            Self.logger.info("Root CA trusted via app-side fallback (fingerprint: \(fingerprint))")
        }

        activeRootFingerprint = fingerprint
        rootCAFreshlyInstalled = true

        // Step 3: Run real validation to update cached state for UI.
        // Don't throw on failure — the trust settings may need time to propagate,
        // or the helper daemon may need to be updated. The UI shows the real state.
        let reallyTrusted = validateSystemTrust()
        if reallyTrusted {
            Self.logger.info("Root CA installed and trusted")
        } else {
            Self.logger
                .warning(
                    "Root CA installed but system trust validation not yet passing — trust may need manual verification"
                )
        }
        postCertificateStatusChanged()
    }

    /// Removes trust settings and certificate from keychain.
    func removeRootCATrust() throws {
        lastTrustValidationResult = nil
        lastValidationErrorMessage = nil
        try KeychainHelper.removeRootCATrust(label: Self.keychainCertLabel)
        Self.logger.info("Root CA trust removed")
        postCertificateStatusChanged()
    }

    func getRootCACertificate() -> Certificate? {
        rootCACertificate
    }

    func getActiveRootFingerprint() -> String? {
        activeRootFingerprint
    }

    // MARK: - Chain Validation Diagnostic

    /// Performs a full SecTrust evaluation to verify the certificate chain works
    /// the same way macOS TLS clients validate it. Generates a test leaf cert,
    /// evaluates it against the root CA, and logs the detailed result.
    func validateCertificateChain() {
        guard let rootCert = rootCACertificate, let rootKey = rootCAPrivateKey else {
            Self.logger.error("DIAGNOSTIC: Cannot validate chain — no root CA")
            return
        }

        do {
            let leafResult = try HostCertGenerator.generate(
                host: "diagnostic.test",
                issuer: rootCert,
                issuerKey: rootKey
            )

            let rootDER = try certToDER(rootCert)
            let leafDER = try certToDER(leafResult.certificate)

            guard let secRoot = SecCertificateCreateWithData(nil, rootDER as CFData),
                  let secLeaf = SecCertificateCreateWithData(nil, leafDER as CFData) else
            {
                Self.logger.error("DIAGNOSTIC: Failed to create SecCertificate objects")
                return
            }

            let policy = SecPolicyCreateSSL(true, "diagnostic.test" as CFString)
            var trust: SecTrust?
            let createStatus = SecTrustCreateWithCertificates(
                [secLeaf, secRoot] as CFArray,
                policy,
                &trust
            )

            guard createStatus == errSecSuccess, let trust else {
                Self.logger.error("DIAGNOSTIC: SecTrustCreate failed: \(createStatus)")
                return
            }

            SecTrustSetAnchorCertificates(trust, [secRoot] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, false)

            var error: CFError?
            let isValid = SecTrustEvaluateWithError(trust, &error)

            if isValid {
                Self.logger.info("DIAGNOSTIC: SecTrust chain validation PASSED ✓")
            } else {
                let errorDesc = error.map { CFErrorCopyDescription($0) as String } ?? "unknown"
                Self.logger.error("DIAGNOSTIC: SecTrust chain validation FAILED — \(errorDesc)")

                if let error {
                    let code = CFErrorGetCode(error)
                    let domain = CFErrorGetDomain(error) as String
                    Self.logger.error("DIAGNOSTIC: Error domain=\(domain) code=\(code)")
                }
            }
        } catch {
            Self.logger.error("DIAGNOSTIC: Chain validation threw: \(error.localizedDescription)")
        }
    }

    /// Validates that a generated host leaf cert is trusted by the real macOS trust store
    /// WITHOUT injecting the root as an explicit anchor. This tests what browsers actually see.
    @discardableResult
    func validateSystemTrust() -> Bool {
        guard let rootCert = rootCACertificate, let rootKey = rootCAPrivateKey else {
            Self.logger.error("DIAGNOSTIC: Cannot validate system trust — no root CA")
            lastTrustValidationResult = false
            lastValidationErrorMessage = "No root CA certificate or private key available"
            return false
        }

        do {
            let leafResult = try HostCertGenerator.generate(
                host: "diagnostic.test.rockxy.local",
                issuer: rootCert,
                issuerKey: rootKey
            )

            let rootDER = try certToDER(rootCert)
            let leafDER = try certToDER(leafResult.certificate)

            guard let secRoot = SecCertificateCreateWithData(nil, rootDER as CFData),
                  let secLeaf = SecCertificateCreateWithData(nil, leafDER as CFData) else
            {
                Self.logger.error("DIAGNOSTIC: Failed to create SecCertificate objects for system trust check")
                lastTrustValidationResult = false
                lastValidationErrorMessage = "Failed to create SecCertificate objects from DER data"
                return false
            }

            // Diagnostics: cert identity and keychain state
            let rootSummary = SecCertificateCopySubjectSummary(secRoot) as String? ?? "unknown"
            let leafSummary = SecCertificateCopySubjectSummary(secLeaf) as String? ?? "unknown"
            let validationFingerprint = KeychainHelper.computeFingerprintSHA256(rootDER)
            Self.logger.info("DIAGNOSTIC: Root subject=\(rootSummary), Leaf subject=\(leafSummary)")
            Self.logger.info("DIAGNOSTIC: Validation root fingerprint=\(validationFingerprint)")
            Self.logger.info("DIAGNOSTIC: Active root fingerprint=\(self.activeRootFingerprint ?? "none")")

            let keychainHasRoot = KeychainHelper.isCertificateInstalled(certData: rootDER)
            let keychainTrustPresent = KeychainHelper.isRootCATrusted(certData: rootDER)
            Self.logger.info("DIAGNOSTIC: Root in keychain=\(keychainHasRoot), trust present=\(keychainTrustPresent)")

            // Strategy A: leaf only — macOS discovers root from system trust store
            let policy = SecPolicyCreateSSL(true, "diagnostic.test.rockxy.local" as CFString)
            var trustA: SecTrust?
            var createStatus = SecTrustCreateWithCertificates(secLeaf, policy, &trustA)

            var isValid = false

            if createStatus == errSecSuccess, let trustObj = trustA {
                var errorA: CFError?
                isValid = SecTrustEvaluateWithError(trustObj, &errorA)
                Self.logger.info("DIAGNOSTIC: Strategy A (leaf only): \(isValid ? "PASSED" : "FAILED")")

                if !isValid {
                    if let errorA {
                        Self.logger.error("DIAGNOSTIC: A error: \(CFErrorCopyDescription(errorA) as String)")
                    }

                    // Strategy B (diagnostic only): validates cert chain integrity via explicit anchor.
                    // NOT used for production result — real TLS clients use system trust (Strategy A).
                    // If B passes but A fails, the chain is valid but trust is not registered.
                    var trustB: SecTrust?
                    createStatus = SecTrustCreateWithCertificates([secLeaf, secRoot] as CFArray, policy, &trustB)
                    if createStatus == errSecSuccess, let trustObjB = trustB {
                        SecTrustSetAnchorCertificates(trustObjB, [secRoot] as CFArray)
                        SecTrustSetAnchorCertificatesOnly(trustObjB, true)
                        var errorB: CFError?
                        let validB = SecTrustEvaluateWithError(trustObjB, &errorB)
                        Self.logger.info("DIAGNOSTIC: Strategy B (explicit anchor): \(validB ? "PASSED" : "FAILED")")
                        if let errorB {
                            Self.logger.error("DIAGNOSTIC: B error: \(CFErrorCopyDescription(errorB) as String)")
                        }
                    }
                }
            } else {
                Self.logger.error("DIAGNOSTIC: SecTrustCreate failed: \(createStatus)")
            }

            if isValid {
                Self.logger.info("DIAGNOSTIC: System trust validation PASSED")
                lastValidationErrorMessage = nil
            } else {
                Self.logger.error("DIAGNOSTIC: System trust validation FAILED — all strategies failed")
                lastValidationErrorMessage = "System trust validation failed for all evaluation strategies"
            }

            lastTrustValidationResult = isValid
            return isValid
        } catch {
            Self.logger.error("DIAGNOSTIC: System trust validation threw: \(error.localizedDescription)")
            lastTrustValidationResult = false
            lastValidationErrorMessage = error.localizedDescription
            return false
        }
    }

    func getRootCAPEM() throws -> String? {
        guard let certificate = rootCACertificate else {
            return nil
        }

        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        let pemDocument = PEMDocument(type: "CERTIFICATE", derBytes: Array(serializer.serializedBytes))
        return pemDocument.pemString
    }

    // MARK: - Host Certificates

    func certificateForHost(_ host: String) throws -> (certificate: Certificate, privateKey: P256.Signing.PrivateKey) {
        if let cached = hostCertCache[host] {
            touchCacheEntry(host)
            return (cached.certificate, cached.privateKey)
        }

        guard let rootCert = rootCACertificate, let rootKey = rootCAPrivateKey else {
            throw CertificateManagerError.noRootCA
        }

        let result = try HostCertGenerator.generate(host: host, issuer: rootCert, issuerKey: rootKey)

        let entry = HostCertEntry(certificate: result.certificate, privateKey: result.privateKey)
        insertCacheEntry(host, entry: entry)

        Self.logger.debug("Generated certificate for host: \(host)")
        return result
    }

    func clearHostCache() {
        hostCertCache.removeAll()
        cacheAccessOrder.removeAll()
        Self.logger.debug("Cleared host certificate cache")
    }

    // MARK: - Status Snapshot

    /// Returns a diagnostic snapshot of the root CA state.
    /// When `performValidation` is false, reuse cached validation and cheap keychain
    /// trust metadata so routine UI refreshes do not re-run full SecTrust work.
    func rootCAStatusSnapshot(performValidation: Bool = false) async -> RootCAStatusSnapshot {
        let hasGenerated = rootCACertificate != nil
        let installed = isRootCAInstalled()
        let trustPresent = hasTrustSettingsPresent()
        let systemTrusted: Bool = if performValidation, trustPresent {
            validateSystemTrust()
        } else if let cachedValidation = lastTrustValidationResult {
            cachedValidation
        } else if trustPresent {
            isRootCATrusted()
        } else {
            false
        }

        let validityBefore = rootCACertificate?.notValidBefore
        let validityAfter = rootCACertificate?.notValidAfter
        let fingerprint = activeRootFingerprint ?? rootCACertificate.flatMap { computeFingerprint($0) }
        let cn = rootCACertificate.flatMap { extractCommonName(from: $0.subject) }

        return RootCAStatusSnapshot(
            hasGeneratedCertificate: hasGenerated,
            isInstalledInKeychain: installed,
            hasTrustSettings: trustPresent,
            isSystemTrustValidated: systemTrusted,
            notValidBefore: validityBefore,
            notValidAfter: validityAfter,
            fingerprintSHA256: fingerprint,
            commonName: cn,
            lastValidationErrorMessage: lastValidationErrorMessage
        )
    }

    func clearFreshlyInstalledFlag() {
        rootCAFreshlyInstalled = false
    }

    // MARK: - Cleanup

    func reset() throws {
        lastTrustValidationResult = nil
        lastValidationErrorMessage = nil
        rootCACertificate = nil
        rootCAPrivateKey = nil
        clearHostCache()

        try KeychainHelper.deletePrivateKey(label: Self.keychainKeyLabel)
        try KeychainHelper.removeCertificate(label: Self.keychainCertLabel)
        try CertificateStore.deleteAll()

        Self.logger.info("Reset certificate manager — all certificates removed")
        postCertificateStatusChanged()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CertificateManager")

    private static let keychainKeyLabel = RockxyIdentity.current.rootCAKeyLabel
    private static let keychainCertLabel = RockxyIdentity.current.rootCACertificateLabel
    private static let maxCacheSize = Int(1e3)

    private var rootCACertificate: Certificate?
    private var rootCAPrivateKey: P256.Signing.PrivateKey?
    private var activeRootFingerprint: String?

    private var hostCertCache: [String: HostCertEntry] = [:]
    private var cacheAccessOrder: [String] = []

    private func computeFingerprint(_ certificate: Certificate) -> String? {
        guard let derData = try? certToDER(certificate) else {
            Self.logger.error("Failed to serialize certificate for fingerprint")
            return nil
        }
        return KeychainHelper.computeFingerprintSHA256(derData)
    }

    private func certToDER(_ certificate: Certificate) throws -> Data {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }

    /// Extracts the first CommonName (CN) value from an X.509 DistinguishedName.
    private func extractCommonName(from subject: DistinguishedName) -> String? {
        for relativeDistinguishedName in subject {
            for attribute in relativeDistinguishedName {
                if attribute.type == ASN1ObjectIdentifier.NameAttributes.commonName {
                    return String(describing: attribute.value)
                }
            }
        }
        return nil
    }

    // MARK: - Cache Management (LRU)

    /// Moves a host to the end of the access order list to mark it as recently used.
    private func touchCacheEntry(_ host: String) {
        if let index = cacheAccessOrder.firstIndex(of: host) {
            cacheAccessOrder.remove(at: index)
        }
        cacheAccessOrder.append(host)
    }

    private func insertCacheEntry(_ host: String, entry: HostCertEntry) {
        if hostCertCache.count >= Self.maxCacheSize {
            evictOldestCacheEntry()
        }

        hostCertCache[host] = entry
        cacheAccessOrder.append(host)
    }

    private func postCertificateStatusChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .certificateStatusChanged, object: nil)
        }
    }

    /// Evicts the least-recently-used host cert to keep memory bounded.
    private func evictOldestCacheEntry() {
        guard let oldest = cacheAccessOrder.first else {
            return
        }
        cacheAccessOrder.removeFirst()
        hostCertCache.removeValue(forKey: oldest)
    }
}

// MARK: - HostCertEntry

nonisolated private struct HostCertEntry {
    let certificate: Certificate
    let privateKey: P256.Signing.PrivateKey
}

// MARK: - CertificateGenerationError

nonisolated enum CertificateGenerationError: LocalizedError {
    case invalidDateComputation

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidDateComputation:
            "Failed to compute certificate validity dates"
        }
    }
}

// MARK: - CertificateManagerError

nonisolated enum CertificateManagerError: LocalizedError {
    case noRootCA
    case rootCANotTrusted
    case trustValidationFailed

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noRootCA:
            "Root CA certificate has not been generated"
        case .rootCANotTrusted:
            "Root CA certificate is not trusted — install and trust the certificate before HTTPS interception"
        case .trustValidationFailed:
            "Trust settings were applied but macOS certificate validation still fails. Try removing and reinstalling the certificate."
        }
    }
}

// MARK: - RootCAStatusSnapshot

/// Complete diagnostic snapshot of root CA state, returned by `CertificateManager.rootCAStatusSnapshot()`.
/// All fields are computed from a single real validation pass — no caching shortcuts.
nonisolated struct RootCAStatusSnapshot {
    let hasGeneratedCertificate: Bool
    let isInstalledInKeychain: Bool
    let hasTrustSettings: Bool
    let isSystemTrustValidated: Bool
    let notValidBefore: Date?
    let notValidAfter: Date?
    let fingerprintSHA256: String?
    let commonName: String?
    let lastValidationErrorMessage: String?
}
