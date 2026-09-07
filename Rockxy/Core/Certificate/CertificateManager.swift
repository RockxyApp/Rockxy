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

    #if DEBUG
    /// How often a status answer actually reached persisted storage on this manager.
    ///
    /// One status answer must attempt the load at most once: a second attempt repeats the same
    /// failing Keychain and filesystem work for a result that is already known, and lets the
    /// second failure overwrite the diagnostic the first one recorded.
    private(set) var persistedRootLoadAttemptsForTests = 0
    #endif

    var cachedHostCount: Int {
        hostCertCache.count
    }

    #if DEBUG
    /// Creates an independent manager so a test can exercise cold, per-test actor state — a
    /// simulated relaunch — instead of the process-wide singleton. Never used in production.
    static func makeForTesting() -> CertificateManager {
        CertificateManager()
    }

    /// Puts the actor in exactly the state `installAndTrust()` holds across its privileged
    /// awaits, so the rejection of competing mutations can be verified without triggering a
    /// real authorization dialog.
    func setTrustInstallationInFlightForTests(_ inFlight: Bool) {
        isInstallingTrust = inFlight
    }

    func observeStatusNotificationsForTests(_ observer: @escaping @Sendable () -> Void) {
        statusNotificationObserverForTests = observer
    }

    /// Replaces the privileged helper removal for exactly this manager.
    ///
    /// Nothing reachable from a test may talk to the real daemon, and an override that returns
    /// without removing anything is how "the helper replied success but the certificate is
    /// still installed" is exercised — the case where the reply must not be believed. The
    /// override receives the exact removal targets the real call would have been given.
    func setHelperRemovalOverrideForTests(_ override: (@Sendable ([Data]) async throws -> Void)?) {
        helperRemovalOverrideForTests = override
    }

    func setAppRemovalOverrideForTests(_ override: (@Sendable ([Data]) throws -> Void)?) {
        appRemovalOverrideForTests = override
    }

    /// Replaces the app-side trust-settings removal for exactly this manager.
    ///
    /// This is the step that goes through Authorization Services and can raise the macOS dialog,
    /// so a test injects it to model an approved, a refused, or a cancelled removal without one.
    /// The override receives the exact removal targets the real call would have been given.
    func setAppTrustSettingsRemovalOverrideForTests(
        _ override: (@Sendable ([Data]) async throws -> Void)?
    ) {
        appTrustSettingsRemovalOverrideForTests = override
    }

    /// Installs the privileged-helper installation seam for exactly this manager.
    ///
    /// Trust installation runs in this process now, so nothing invokes this override: it is kept
    /// precisely so a test can inject one and prove that `installAndTrust()` sends no helper
    /// installation RPC, whatever the helper's state.
    func setHelperInstallOverrideForTests(_ override: (@Sendable (Data) async throws -> Void)?) {
        helperInstallOverrideForTests = override
    }

    /// Replaces the app-side installation, so a test can drive the one installation path without
    /// reaching `SecTrustSettingsSetTrustSettings` or the authorization dialog behind it.
    ///
    /// Asynchronous because the production call suspends across that dialog: an override that
    /// stays suspended is how the in-flight mutation guards are exercised without a real prompt.
    func setAppInstallOverrideForTests(_ override: (@Sendable (Data) async throws -> Void)?) {
        appInstallOverrideForTests = override
    }

    /// Replaces the strict Keychain-presence and admin-trust reads for exactly this manager.
    ///
    /// Producing the real failure would mean locking the user's login Keychain or their system
    /// trust store, which no test may do. Injecting it here covers every caller that matters:
    /// the status snapshot, the legacy getters, and the `installAndTrust` preflight all go
    /// through this one seam. Pass `nil` to restore the real reads — do that before the fixture
    /// lease is released, never from an async `defer`.
    func setStatusReadOverrideForTests(
        _ override: (@Sendable () throws -> StatusReadResultForTests)?
    ) {
        statusReadOverrideForTests = override
    }
    #endif

    /// Decides how `rootCAStatusSnapshot` should answer "is this root system-trusted?".
    ///
    /// Extracted as a pure rule because the two cache mistakes it prevents are invisible at
    /// the call site: reporting a cached positive result after the trust settings behind it
    /// disappeared, and reporting keychain metadata alone as a validated green state.
    ///
    /// - Parameter trustPresent: admin trust-settings metadata for the current CA. This is a
    ///   prefilter only, so its presence can never by itself mean "trusted".
    /// - Parameter cachedValidation: the result of the last real `SecTrust` evaluation for the
    ///   currently adopted CA, or `nil` when none has run for it.
    nonisolated static func trustEvaluationDecision(
        trustPresent: Bool,
        performValidation: Bool,
        cachedValidation: Bool?
    )
        -> TrustEvaluationDecision
    {
        guard trustPresent else {
            // Trust settings that are gone — removed in Keychain Access, or belonging to a CA
            // that has since been replaced — immediately invalidate a cached positive result.
            return .notTrusted(invalidatesCachedResult: cachedValidation == true)
        }
        if performValidation {
            return .runValidation
        }
        guard let cachedValidation else {
            // No real evaluation has run for this CA yet, and metadata must never produce the
            // first green result. Evaluate once; later cheap refreshes reuse the answer.
            return .runValidation
        }
        return .useCached(cachedValidation)
    }

    /// Whether a failed helper trust attempt may continue into the app-side authorization
    /// prompt.
    ///
    /// Classification for the legacy `HelperConnection.installRootCertificate` dispatch path, kept
    /// with that RPC and applied only there. `installAndTrust()` never asks the helper — the trust
    /// write needs an interactive authorization session this headless daemon cannot obtain — so
    /// the GUI installation has no fallback to classify in the first place.
    ///
    /// On that RPC path a cancelled request may not fall through: the caller abandoned it, and
    /// falling through would raise an admin dialog for work the helper may already have applied.
    /// Cancellation reaches the caller either as `CancellationError` or as an XPC failure raised
    /// because the task was cancelled, so both are checked. Nothing here claims the helper rolled
    /// its own request back — only that this process must not prompt for it.
    nonisolated static func shouldFallBackToAppSideTrust(
        afterHelperError error: any Error,
        isCancelled: Bool
    )
        -> Bool
    {
        !(error is CancellationError) && !isCancelled
    }

    /// Whether a failed helper installation is known to have sent nothing to the daemon.
    ///
    /// The second half of the same legacy classification, and the stricter one. Cancellation aside, a
    /// failure only licenses an app-side install when the wrapper can prove the message was never
    /// committed: a reported helper error, a dropped connection after the send, and a local
    /// timeout all leave privileged work that may have been applied, and installing again on top
    /// of that would raise a second admin dialog for material that is possibly already installed.
    nonisolated static func helperInstallSentNothing(_ error: any Error) -> Bool {
        error is HelperInstallNotDispatched
    }

    /// Whether the privileged helper may be asked to perform certificate work at all.
    ///
    /// This gates the exact removal `removeInstalledRootMaterial` dispatches, and the legacy
    /// installation RPC that survives for older callers. It answers reachability and helper
    /// state only; the connected helper's protocol version is probed by the wrapper on the same
    /// connection that carries the request.
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
        try rejectIfMutationInFlight()

        let result = try RootCAGenerator.generate()
        // Read the rollback key straight from the Keychain. Going through the recovery-capable
        // load would migrate and rename disk PEM files as a side effect of a generation that
        // may still fail, and could adopt a stale key as the rollback value.
        let previousPrivateKey: P256.Signing.PrivateKey? = if let rootCAPrivateKey {
            rootCAPrivateKey
        } else {
            try CertificateStore.loadRootCAPrivateKeyFromKeychain()
        }

        // Persist before adopting. A root CA whose private key cannot be stored would be
        // gone on the next launch, silently invalidating the fingerprint the user just
        // approved, so a persistence failure must propagate instead of leaving a
        // usable-looking volatile root behind. The key is written first: a certificate on
        // disk without its key would force another regeneration on the next launch.
        try CertificateStore.saveRootCAPrivateKey(result.privateKey)
        do {
            try CertificateStore.saveRootCACertificate(result.certificate)
        } catch {
            // Keychain and the certificate PEM are separate stores. If the PEM write
            // fails after replacing the key, restore the previous key (or remove the
            // orphan created by a first-time generation) so the persisted pair cannot
            // become mismatched on the next launch.
            do {
                if let previousPrivateKey {
                    try CertificateStore.saveRootCAPrivateKey(previousPrivateKey)
                } else {
                    try KeychainHelper.deletePrivateKey(label: CertificateStore.activeKeychainKeyLabel)
                }
            } catch let rollbackError {
                Self.logger.error(
                    "Failed to roll back root CA key after certificate persistence failed: \(rollbackError.localizedDescription)"
                )
            }
            throw error
        }

        lastTrustValidationResult = nil
        lastValidationErrorMessage = nil
        adoptRootCA(certificate: result.certificate, privateKey: result.privateKey)
        rootCAFreshlyInstalled = true
        Self.logger.info("Generated new root CA certificate")
        postCertificateStatusChanged()
    }

    /// Attempts to restore the root CA certificate from disk together with the private key
    /// that actually belongs to it, from the Keychain (primary) or a disk PEM recovery file.
    func loadExistingRootCA() throws -> Bool {
        // Adopting persisted material replaces what an in-flight installation is trusting, so
        // this is guarded exactly like reset, generation, and trust removal.
        try rejectIfMutationInFlight()

        guard let cert = try CertificateStore.loadRootCACertificate() else {
            Self.logger.debug("No existing root CA certificate found on disk")
            return false
        }

        let hasSKI = (try? cert.extensions.subjectKeyIdentifier) != nil
        if !hasSKI {
            Self.logger.info("Root CA missing SubjectKeyIdentifier — regenerating")
            return false
        }

        // Every key source is searched for the one key belonging to this certificate, and the
        // match is decided before anything is migrated. Taking the first *decodable* key
        // instead lets a valid-but-stale Keychain item or primary PEM shadow the recovery file
        // that does match, and renames that stale primary over the matching `.bak` on the way.
        // Certificate.PublicKey wraps the raw SPKI bytes, so the comparison is byte-exact.
        let certPublicKeyBytes = cert.publicKey.subjectPublicKeyInfoBytes
        let matchingKey = try CertificateStore.loadRootCAPrivateKey(matching: { candidate in
            Certificate.PublicKey(candidate.publicKey).subjectPublicKeyInfoBytes == certPublicKeyBytes
        })

        guard let key = matchingKey else {
            // No stored key belongs to this certificate, so that CA cannot be preserved. Every
            // recovery source is still intact; one regeneration follows and needs one final
            // trust approval, and the new key persists from then on.
            Self.logger.info("No stored private key matches the persisted root CA — regenerating once")
            return false
        }

        let identityChanged = adoptRootCA(certificate: cert, privateKey: key)
        CertificateStore.cleanupLegacyDiskKeys(matching: key)
        Self.logger.info("Loaded existing root CA")

        if identityChanged {
            // The status notification belongs to the moment a different identity is actually
            // adopted, whoever triggered the load — the launch task, `ensureRootCA`, or a
            // status refresh. Re-adopting the same identity changes nothing, so an observer
            // that refreshes in response cannot turn this into a notification loop.
            postCertificateStatusChanged()
        }
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

    /// Fail-closed presence check for callers that can only take a boolean. An unreadable
    /// Keychain or storage answers `false`; nothing mutating is authorized from that answer.
    func isRootCAInstalled() -> Bool {
        // Called on its own — from the certificate wizard or a diagnostic — this is the only
        // chance to adopt the persisted identity before answering, so the load stays here.
        guard loadPersistedRootCAIfNeeded() == .resolved else {
            return false
        }
        return (try? installedStateForAdoptedRoot()) ?? false
    }

    /// Trust check for UI surfaces that only need one boolean — the app menu's onboarding
    /// backfill and the certificate wizard.
    ///
    /// It answers through the same production rule as `rootCAStatusSnapshot`, so a green
    /// checkmark here always means a real `SecTrust` evaluation passed. Reporting keychain
    /// metadata directly is what let onboarding mark trust complete for a CA the system does
    /// not actually trust, and reading it before the persisted root was loaded is what made
    /// the step incomplete again after a relaunch.
    func isRootCATrusted() -> Bool {
        resolveSystemTrust(performValidation: false).isSystemTrustValidated
    }

    /// Pure metadata check for trust-settings presence, without consulting the
    /// cached `lastTrustValidationResult`. Use this as a pre-filter before
    /// running the expensive `validateSystemTrust()` — it avoids the problem
    /// where a stale cached `false` in `isRootCATrusted()` blocks recovery.
    ///
    /// Fail-closed: an unreadable admin domain answers `false` here. Callers that could act on
    /// that answer — status resolution and `installAndTrust` — use the strict read instead, so a
    /// failed read never becomes a reason to write trust settings.
    func hasTrustSettingsPresent() -> Bool {
        (try? strictTrustSettingsPresent()) ?? false
    }

    /// Real trust validation for proxy-start gating and post-install verification.
    /// Performs full SecTrust evaluation using Strategy A (system trust only).
    /// Returns true only when macOS system trust store accepts the generated leaf —
    /// this is what real TLS clients (browsers, curl) actually check.
    func isRootCATrustValidated() -> Bool {
        resolveSystemTrust(performValidation: true).isSystemTrustValidated
    }

    /// Ensures the root CA exists, installs it, and marks it trusted for TLS — always in this
    /// app process, through the native Security API.
    ///
    /// Trust is not a privilege problem, it is an *interaction* problem. Writing `.admin` trust
    /// settings goes through Authorization Services, which needs a session that can ask a human;
    /// a launchd root daemon has none. Routed through the helper, the request arrived, the
    /// certificate was added to the System keychain, and the trust write then failed with
    /// "authorization denied" — an installed, still-untrusted root, and no way to prompt for the
    /// approval macOS was waiting for. Root is not the missing piece, a GUI session is. So the
    /// installation runs here, unconditionally: a reachable, current helper takes the same path as
    /// an absent one, and no helper installation RPC is sent from this call at all.
    ///
    /// The operation only ever *adds*. No certificate is deleted, swept, or rolled back on any
    /// path: not the previous Rockxy root, not a login-keychain copy of it, not on a failed add,
    /// a refused trust write, a cancellation, or a timeout. Those cleanups exist, but they are
    /// separate, explicit operations — folding them into an install is what let a routine
    /// reinstall destroy a root the user was still relying on.
    ///
    /// A failure is reported as itself. This call never answers one by installing again, never
    /// raises a second authorization dialog for the same material, and never claims anything was
    /// undone.
    func installAndTrust() async throws {
        // A second installation would raise a second authorization dialog for the same
        // material and race the first one's cleanup, so overlapping calls are rejected with
        // feedback the caller can surface instead of being silently coalesced.
        try rejectIfMutationInFlight()

        // An abandoned request must not raise an authorization dialog at all.
        try Task.checkCancellation()

        // `ensureRootCA` runs without suspending, so no other call can interleave with it.
        try ensureRootCA()

        // Another Rockxy process can share this certificate namespace while retaining a
        // different root in memory. Never ask macOS to trust material that is no longer the
        // certificate/key pair this process would load after a relaunch. Reconcile before the
        // authorization prompt so the one prompt applies to the durable identity.
        try reconcilePersistedRootIdentityBeforeTrust()

        guard let certificate = rootCACertificate else {
            throw CertificateManagerError.noRootCA
        }

        // Preflight, before the add, the trust write, and the authorization dialog:
        // if the Keychain or the admin trust domain cannot be read, this call cannot tell whether
        // the work is already done. Asking for administrator approval on the strength of a failed
        // read is exactly the second prompt this guard exists to prevent, so it stops here with a
        // reason the UI can offer a recheck for.
        let initialTrust = resolveSystemTrust(performValidation: true)
        if let failure = initialTrust.readFailure {
            throw CertificateManagerError.trustStateUnavailable(failure.message)
        }

        // Idempotency: a CA that is already genuinely system-trusted needs no reinstall and above
        // all no admin prompt. This runs the real SecTrust evaluation, so it cannot short-circuit
        // on keychain metadata alone.
        if initialTrust.isSystemTrustValidated {
            Self.logger.info("Root CA is already system-trusted — skipping reinstall")
            postCertificateStatusChanged()
            return
        }

        lastTrustValidationResult = nil
        lastValidationErrorMessage = nil

        // From here the actor suspends into the macOS authorization dialog. Anything that would
        // replace the material being installed is rejected until this completes; the flag is
        // cleared on every exit path, including cancellation.
        isInstallingTrust = true

        // Once the mutating step is attempted, trust state may have changed even if this call then
        // fails or is cancelled — an approved dialog applies its write whether or not the caller is
        // still waiting. Observers are told to re-read the real state on every such exit so no
        // surface keeps reporting the pre-install answer.
        var mayHaveMutatedTrustState = false
        defer {
            isInstallingTrust = false
            if mayHaveMutatedTrustState {
                postCertificateStatusChanged()
            }
        }

        let derData = try certToDER(certificate)
        let fingerprint = computeFingerprint(certificate) ?? KeychainHelper.computeFingerprintSHA256(derData)

        // An abandoned request must never reach the dialog.
        try Task.checkCancellation()

        #if DEBUG
        if helperInstallOverrideForTests != nil {
            // The seam stays wired so a test can prove this path never invokes it. Sending an
            // installation to the daemon here is the routing defect this call exists to prevent.
            Self.logger.debug("Helper installation seam present but unused — trust installs app-side")
        }
        #endif

        // The only installation step: add to the login keychain and write admin trust through the
        // macOS authorization dialog. From here on every exit republishes status, so no surface
        // keeps reporting the pre-install answer after work that may have been applied.
        mayHaveMutatedTrustState = true
        do {
            try await performAppSideInstall(derData: derData)
        } catch {
            // The dialog was refused, dismissed, or the write failed. The reason is kept for the
            // UI; nothing is installed again, and nothing claims a rollback.
            lastValidationErrorMessage = error.localizedDescription
            Self.logger.error("App-side certificate install failed: \(error.localizedDescription)")
            throw error
        }
        Self.logger.info("Root CA trusted app-side (fingerprint: \(fingerprint))")

        // The authorization dialog suspends this actor while another process remains free to
        // replace the shared certificate or key. A successful trust write is not a successful
        // Rockxy setup if that identity will disappear on the next launch. Detect the race,
        // report it, and never raise an automatic second prompt or delete either identity.
        do {
            guard try activeRootMatchesPersistedStorage() else {
                throw CertificateManagerError.persistedRootIdentityChanged
            }
        } catch let error as CertificateManagerError {
            lastValidationErrorMessage = error.localizedDescription
            throw error
        } catch {
            let wrapped = CertificateManagerError.trustStateUnavailable(error.localizedDescription)
            lastValidationErrorMessage = wrapped.localizedDescription
            throw wrapped
        }

        try Task.checkCancellation()
        activeRootFingerprint = fingerprint
        rootCAFreshlyInstalled = true

        // The only thing that counts as success is a real SecTrust evaluation of a freshly issued
        // leaf against the system trust store, with no injected anchors — what a browser actually
        // does. Metadata, an OSStatus, and a privileged success reply are all reports.
        guard validateSystemTrust() else {
            Self.logger.error("Root CA installed but macOS still does not accept the chain for TLS")
            throw CertificateManagerError.trustValidationFailed
        }
        Self.logger.info("Root CA installed and trusted")
    }

    /// Removes the installed trust settings and certificate, keeping the local key/certificate
    /// pair by definition — this is the "untrust" operation, not a reset.
    ///
    /// Shares the verified removal `reset()` runs, so a failure here is reported the same way:
    /// nothing is declared removed that is still installed or still trusted.
    func removeRootCATrust() async throws {
        try rejectIfMutationInFlight()
        try Task.checkCancellation()

        let activeDER = try persistedRemovalTarget()

        isRemovingRootMaterial = true
        // Every exit below has attempted a mutation, so observers are told once to re-read the
        // real state and the guard is released on the same path.
        defer {
            isRemovingRootMaterial = false
            lastTrustValidationResult = nil
            rootCAFreshlyInstalled = false
            postCertificateStatusChanged()
        }

        lastTrustValidationResult = nil
        lastValidationErrorMessage = nil

        do {
            try await removeInstalledRootMaterial(activeDER: activeDER)
        } catch {
            lastValidationErrorMessage = error.localizedDescription
            throw error
        }

        Self.logger.info("Root CA trust removed")
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
            var systemValidationError: String?

            if createStatus == errSecSuccess, let trustObj = trustA {
                var errorA: CFError?
                isValid = SecTrustEvaluateWithError(trustObj, &errorA)
                Self.logger.info("DIAGNOSTIC: Strategy A (leaf only): \(isValid ? "PASSED" : "FAILED")")

                if !isValid {
                    if let errorA {
                        let description = CFErrorCopyDescription(errorA) as String
                        systemValidationError = description
                        Self.logger.error("DIAGNOSTIC: A error: \(description)")
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
                systemValidationError = "Could not create macOS trust evaluation (status \(createStatus))"
            }

            if isValid {
                Self.logger.info("DIAGNOSTIC: System trust validation PASSED")
                lastValidationErrorMessage = nil
            } else {
                Self.logger.error("DIAGNOSTIC: System trust validation FAILED")
                lastValidationErrorMessage = systemValidationError
                    ?? "macOS did not accept the certificate chain for TLS"
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

    func getRootCADER() throws -> Data? {
        guard let certificate = rootCACertificate else {
            return nil
        }
        return try certToDER(certificate)
    }

    func getRootCAPrivateKeyPEM() throws -> String? {
        guard let privateKey = rootCAPrivateKey else {
            return nil
        }
        return privateKey.pemRepresentation
    }

    func exportMaterial() throws -> CertificateExportMaterial {
        CertificateExportMaterial(certificate: rootCACertificate, privateKey: rootCAPrivateKey)
    }

    // MARK: - Host Certificates

    func certificateForHost(_ host: String) throws -> (certificate: Certificate, privateKey: P256.Signing.PrivateKey) {
        if let customRoot = try CustomCertificateManager.shared.activeRootIssuerSnapshot() {
            let cacheKey = "\(customRoot.fingerprintSHA256):\(host)"
            if let cached = hostCertCache[cacheKey] {
                touchCacheEntry(cacheKey)
                return (cached.certificate, cached.privateKey)
            }

            let result = try HostCertGenerator.generate(
                host: host,
                issuer: customRoot.certificate,
                issuerPrivateKey: customRoot.privateKey
            )
            insertCacheEntry(
                cacheKey,
                entry: HostCertEntry(certificate: result.certificate, privateKey: result.privateKey)
            )
            Self.logger.debug("Generated certificate for host with custom root issuer: \(host)")
            return result
        }

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
        // Any surface can ask for status before the launch task has initialized the root CA.
        // Answering from an unloaded actor reports a persisted, already-trusted CA as missing
        // and its trust as absent, which is what makes onboarding ask for admin approval again
        // after a relaunch. The shared resolution loads it first, so the answer is independent
        // of launch scheduling and identical to what `isRootCATrusted()` reports.
        let trust = resolveSystemTrust(performValidation: performValidation)

        let hasGenerated = rootCACertificate != nil
        // Presence, trust metadata, and validation share one resolution. A second read here
        // could fail after validation and leave a stale positive cache behind an unknown UI.

        let validityBefore = rootCACertificate?.notValidBefore
        let validityAfter = rootCACertificate?.notValidAfter
        let fingerprint = activeRootFingerprint ?? rootCACertificate.flatMap { computeFingerprint($0) }
        let cn = rootCACertificate.flatMap { extractCommonName(from: $0.subject) }

        return RootCAStatusSnapshot(
            hasGeneratedCertificate: hasGenerated,
            isInstalledInKeychain: trust.isInstalledInKeychain,
            hasTrustSettings: trust.trustSettingsPresent,
            isSystemTrustValidated: trust.isSystemTrustValidated,
            notValidBefore: validityBefore,
            notValidAfter: validityAfter,
            fingerprintSHA256: fingerprint,
            commonName: cn,
            lastValidationErrorMessage: lastValidationErrorMessage,
            statusReadFailure: trust.readFailure
        )
    }

    func clearFreshlyInstalledFlag() {
        rootCAFreshlyInstalled = false
    }

    // MARK: - Cleanup

    /// Removes the installed root CA and then the local material behind it.
    ///
    /// Removal comes first and has to be verified. Destroying the private key and the
    /// certificate PEM before the installed copy is gone leaves an installed, still-trusted
    /// certificate that nothing can identify, remove, or re-derive a fingerprint for — and, if
    /// the certificate delete then failed, a persisted key/certificate pair that no longer
    /// describes one CA. On a removal failure everything local is preserved exactly as it was;
    /// only the derived trust state is invalidated so no surface keeps reporting the old answer.
    func reset() async throws {
        try rejectIfMutationInFlight()
        try Task.checkCancellation()

        let activeDER = try persistedRemovalTarget()

        isRemovingRootMaterial = true
        defer {
            isRemovingRootMaterial = false
            lastTrustValidationResult = nil
            rootCAFreshlyInstalled = false
            postCertificateStatusChanged()
        }

        do {
            try await removeInstalledRootMaterial(activeDER: activeDER)
        } catch {
            // The key, the certificate on disk, and the fingerprint still describe the CA whose
            // installed copy survived, so they are all kept. Only the cached trust answer is
            // dropped, and the failure is surfaced instead of being reported as a clean reset.
            lastTrustValidationResult = nil
            lastValidationErrorMessage = error.localizedDescription
            Self.logger.error("Reset aborted before deleting local material: \(error.localizedDescription)")
            throw error
        }

        // The installed copy is gone and verified gone, so the local material can follow. The
        // certificate PEM goes first: an orphaned key means one clean regeneration on the next
        // launch, while an orphaned certificate is the mismatched pair this ordering prevents.
        do {
            try CertificateStore.deleteAll()
            // Only remove the key after installed material has been proved absent.
            try KeychainHelper.deletePrivateKey(label: CertificateStore.activeKeychainKeyLabel)
        } catch {
            lastValidationErrorMessage = error.localizedDescription
            throw error
        }

        lastTrustValidationResult = nil
        lastValidationErrorMessage = nil
        rootCACertificate = nil
        rootCAPrivateKey = nil
        // The fingerprint and the freshly-installed flag describe the CA being removed. Left
        // behind, they would make the next load look like the same generation and let a stale
        // "restart your browser" state and validation result survive the reset.
        activeRootFingerprint = nil
        rootCAFreshlyInstalled = false
        clearHostCache()

        Self.logger.info("Reset certificate manager — all certificates removed")
    }

    // MARK: Private

    /// How a status-driven attempt to load the persisted root CA ended.
    private enum PersistedRootLoadOutcome: Equatable {
        /// Material is in memory, was adopted by this call, or is simply not persisted yet.
        /// Trust can be resolved from whatever the actor now holds.
        case resolved
        /// Storage could not be read; the reason is carried so the answer can report itself as
        /// unavailable instead of as an absent root CA.
        case failed(String)
    }

    /// The resolved trust state for one status answer.
    private struct TrustResolution {
        let isInstalledInKeychain: Bool
        /// Admin trust-settings metadata for the adopted CA. A prefilter, never proof.
        let trustSettingsPresent: Bool
        /// The result of a real `SecTrust` evaluation, or the cached result of one.
        let isSystemTrustValidated: Bool
        /// Set when the answer above is a fail-closed default rather than a finding.
        let readFailure: RootCAStatusReadFailure?
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CertificateManager")

    private static let maxCacheSize = Int(1e3)

    /// Where the blocking, authorization-backed Security calls run.
    ///
    /// The queue owns a thread of its own for as long as the macOS dialog is on screen, and the
    /// actor suspends on a continuation instead of holding the main actor or a cooperative-pool
    /// thread hostage for the whole interaction. The mutation guards are held across that
    /// suspension, so nothing can replace the material while the dialog is up.
    private static let authorizationQueue = AuthorizationWorkQueue(
        label: "\(RockxyIdentity.current.appBundleIdentifier).certificate-authorization"
    )

    /// Certificate label paired with the key label the store is currently using. Every
    /// certificate read, install, trust check, and delete goes through this, so a test can
    /// never address the production root CA certificate.
    private static var keychainCertLabel: String {
        CertificateStore.activeKeychainCertificateLabel
    }

    /// True only when this process is addressing the installed app's real root CA material.
    ///
    /// A test namespace has its own labels and never installs anything system-wide, so it must
    /// not reach a privileged service that would act on the production certificate.
    private static var ownsProductionRootIdentity: Bool {
        !RockxyIdentity.isRunningTests
            && keychainCertLabel == RockxyIdentity.current.rootCACertificateLabel
    }

    private var rootCACertificate: Certificate?
    private var rootCAPrivateKey: P256.Signing.PrivateKey?
    private var activeRootFingerprint: String?

    /// True while `installAndTrust()` is suspended in the macOS authorization dialog. This actor
    /// is reentrant across that await, so any operation that would replace the material
    /// mid-install is rejected instead of racing it.
    private var isInstallingTrust = false

    /// True when the last status answer could not read storage or the admin trust domain. Kept so
    /// the diagnostic that failure recorded is dropped as soon as a real read succeeds.
    private var hadUnreadableStatus = false

    /// True while `reset()` or `removeRootCATrust()` is suspended in the authorization dialog or
    /// the privileged helper call. Removal reads the material it is about to delete across those
    /// awaits, so anything that would replace, adopt, or re-delete it is rejected until removal
    /// completes.
    private var isRemovingRootMaterial = false

    #if DEBUG
    private var statusNotificationObserverForTests: (@Sendable () -> Void)?
    private var helperRemovalOverrideForTests: (@Sendable ([Data]) async throws -> Void)?
    private var appRemovalOverrideForTests: (@Sendable ([Data]) throws -> Void)?
    private var appTrustSettingsRemovalOverrideForTests: (@Sendable ([Data]) async throws -> Void)?
    private var helperInstallOverrideForTests: (@Sendable (Data) async throws -> Void)?
    private var appInstallOverrideForTests: (@Sendable (Data) async throws -> Void)?
    private var statusReadOverrideForTests: (@Sendable () throws -> StatusReadResultForTests)?
    #endif

    private var hostCertCache: [String: HostCertEntry] = [:]
    private var cacheAccessOrder: [String] = []

    /// Runs one blocking, authorization-backed Security call off the actor's executor.
    ///
    /// The dialog it raises is answered by a human, so the call has to own a thread for as long as
    /// that takes. Cancellation is honoured at admission: a request abandoned while it was still
    /// queued behind an open dialog never runs, so it cannot surface later as a dialog of its own.
    /// Once the native call has started it is awaited to completion — a prompt that is already on
    /// screen cannot be withdrawn, and pretending otherwise would report a cancellation for
    /// privileged work that was in fact applied, and would release the mutation guards while that
    /// work could still change the trust state.
    ///
    /// Between two interactive operations, `work` asks the signal it is given rather than
    /// `Task.checkCancellation()`: the queue's thread carries no task context, so the task
    /// function there answers for a task that does not exist.
    private static func withAuthorizationThread(
        _ work: @escaping @Sendable (AuthorizationCancellationSignal) throws -> Void
    )
        async throws
    {
        try await authorizationQueue.run(work)
    }

    /// A missing/unreadable private key must not hide the certificate we are removing.
    /// Read the public certificate directly; never regenerate or swallow a disk/DER error.
    private func persistedRemovalTarget() throws -> Data? {
        guard let certificate = try rootCACertificate ?? CertificateStore.loadRootCACertificate() else {
            return nil
        }
        return try certToDER(certificate)
    }

    /// Makes the in-memory root agree with the identity that will survive a process restart.
    ///
    /// This is intentionally limited to trust installation. Routine status reads stay
    /// non-mutating, while the explicit install action may already generate a missing root. If
    /// another process replaced either persisted half since this actor adopted its root, reload
    /// the complete persisted pair or follow the existing one-time regeneration policy before
    /// asking the user for administrator approval.
    private func reconcilePersistedRootIdentityBeforeTrust() throws {
        let matches: Bool
        do {
            matches = try activeRootMatchesPersistedStorage()
        } catch {
            throw CertificateManagerError.trustStateUnavailable(error.localizedDescription)
        }
        guard !matches else {
            return
        }

        Self.logger.warning(
            "Active root CA differs from persisted certificate/key identity — reloading before trust"
        )
        rootCACertificate = nil
        rootCAPrivateKey = nil
        try ensureRootCA()

        do {
            guard try activeRootMatchesPersistedStorage() else {
                throw CertificateManagerError.persistedRootIdentityChanged
            }
        } catch let error as CertificateManagerError {
            throw error
        } catch {
            throw CertificateManagerError.trustStateUnavailable(error.localizedDescription)
        }
    }

    /// Exact certificate bytes plus the private key are the durable root identity. A key that is
    /// decodable but belongs to another certificate is a mismatch, not proof of corruption.
    private func activeRootMatchesPersistedStorage(migrateLegacyKey: Bool = true) throws -> Bool {
        guard let activeCertificate = rootCACertificate,
              let activePrivateKey = rootCAPrivateKey,
              let persistedCertificate = try CertificateStore.loadRootCACertificate() else
        {
            return false
        }

        let persistedPublicKey = persistedCertificate.publicKey.subjectPublicKeyInfoBytes
        let matchesPersistedCertificate: (P256.Signing.PrivateKey) -> Bool = { candidate in
            Certificate.PublicKey(candidate.publicKey).subjectPublicKeyInfoBytes == persistedPublicKey
        }
        let persistedPrivateKey = if migrateLegacyKey {
            try CertificateStore.loadRootCAPrivateKey(matching: matchesPersistedCertificate)
        } else {
            try CertificateStore.loadRootCAPrivateKeyWithoutMigration(matching: matchesPersistedCertificate)
        }
        guard let persistedPrivateKey else {
            return false
        }

        return try certToDER(activeCertificate) == certToDER(persistedCertificate)
            && activePrivateKey.rawRepresentation == persistedPrivateKey.rawRepresentation
    }

    /// Rejects any operation that would replace or destroy the material another privileged
    /// operation is currently suspended inside.
    ///
    /// This actor is reentrant across the helper and authorization-dialog awaits, so both the
    /// installation guard and the removal guard have to survive those suspensions.
    private func rejectIfMutationInFlight() throws {
        if isInstallingTrust {
            throw CertificateManagerError.trustInstallationInProgress
        }
        if isRemovingRootMaterial {
            throw CertificateManagerError.rootRemovalInProgress
        }
    }

    /// Removes the installed root CA certificate and its trust settings, and proves it.
    ///
    /// The order is the point. Clearing `.admin` trust settings goes through Authorization
    /// Services exactly like writing them, and this headless launchd daemon has no GUI session to
    /// obtain that authorization in, so the request is denied there even as root. It therefore
    /// runs here, in the GUI process, *before* the daemon is asked to delete anything — otherwise
    /// a successful delete would leave admin trust settings behind for a certificate that is no
    /// longer in any keychain: still trusted, and addressable only through the DER this removal
    /// snapshotted. A refused, failed, or cancelled approval stops the removal there, with the
    /// installed bytes and the local key/certificate pair untouched.
    ///
    /// After that the helper is asked to remove named certificates and reports its own failures,
    /// but a success reply is still only a hint: an outdated helper cannot accept the request at
    /// all, and either keychain can retain a copy after a partial failure. Every path uses exact
    /// DER, including legacy labels. The single source of truth is therefore the verification
    /// below: the saved active DER and every certificate the label pointed at before removal
    /// started must all be gone, in both the keychain and the trust settings. Nothing is widened
    /// to match by name.
    private func removeInstalledRootMaterial(activeDER: Data?) async throws {
        let label = Self.keychainCertLabel

        // Snapshotted before anything is removed and before the first await: after a
        // successful delete the label points at nothing, so these are the only DERs that can
        // still prove a leftover copy — and they are exactly what the trust clearing, the helper,
        // and the verification address, so all three name the same certificates.
        let discoveredTargets = try KeychainHelper.findLabeledCertificates(label: label).map(\.derData)
        var targets: [Data] = []
        for der in ([activeDER].compactMap { $0 } + discoveredTargets) where !targets.contains(der) {
            targets.append(der)
        }

        // Step 1: the interactive half, in this process, before any privileged delete. A target
        // that carries no settings needs no approval at all, so removing an untrusted root is
        // prompt-free; a presence read that fails propagates rather than passing for "nothing to
        // remove".
        try Task.checkCancellation()
        do {
            try await removeAppSideTrustSettings(targets)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard !Task.isCancelled else {
                throw CancellationError()
            }
            // Nothing privileged has run. Reporting this as an incomplete removal keeps the
            // material intact and tells the user where the state still is.
            Self.logger.error("Trust settings removal was not authorized: \(error.localizedDescription)")
            throw CertificateManagerError.rootRemovalIncomplete(error.localizedDescription)
        }
        try Task.checkCancellation()

        var helperFailure: (any Error)?
        do {
            try await attemptHelperRemoval(targets: targets)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard !Task.isCancelled else {
                throw CancellationError()
            }
            // Not fatal on its own: the app-side removal below may still clear everything, and
            // the verification decides. The reason is kept for the failure message.
            helperFailure = error
            Self.logger.error("Helper root certificate removal failed: \(error.localizedDescription)")
        }
        try Task.checkCancellation()

        // App-side removal covers the login-keychain copies the helper does not own. It refuses
        // to delete a certificate whose trust settings could not be removed.
        do {
            try removeAppSideTargets(targets)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let helperDetail = helperFailure.map { " Helper: \($0.localizedDescription)" } ?? ""
            throw CertificateManagerError.rootRemovalIncomplete(error.localizedDescription + helperDetail)
        }

        try verifyRootMaterialRemoved(targets: targets, helperFailure: helperFailure)
    }

    /// Installs and trusts in this process. This is the path that raises the macOS authorization
    /// dialog, and the only installation path there is.
    ///
    /// The blocking Security call runs on the authorization queue rather than on the actor's
    /// executor, so a dialog waiting for a human does not hold a concurrency thread. The actor
    /// suspends here with `isInstallingTrust` set, so a competing mutation is still rejected.
    private func performAppSideInstall(derData: Data) async throws {
        #if DEBUG
        if let appInstallOverrideForTests {
            try await appInstallOverrideForTests(derData)
            return
        }
        guard !RockxyIdentity.isRunningTests else {
            throw CertificateManagerError.helperInstallUnavailable("tests require an injected app-side installer")
        }
        #endif
        let label = Self.keychainCertLabel
        try await Self.withAuthorizationThread { signal in
            // Checked before the add and again before the trust write, so an abandoned request
            // stops between the two rather than raising the dialog the second one needs.
            try KeychainHelper.installRootCAWithTrust(
                derData,
                label: label,
                cancellationCheck: { try signal.checkCancellation() }
            )
        }
    }

    /// Clears exactly these certificates' admin and user trust settings, in this process.
    ///
    /// The interactive half of a removal. `SecTrustSettingsRemoveTrustSettings(.admin)` goes
    /// through Authorization Services and can raise the macOS dialog, which only a process with a
    /// GUI session can answer — the headless daemon cannot obtain that authorization and receives
    /// "authorization denied" for the same call. A
    /// certificate that carries no settings in a domain is left alone, so an untrusted root is
    /// removed with no prompt at all, and a presence read that fails propagates instead of being
    /// taken for "nothing to remove".
    private func removeAppSideTrustSettings(_ targets: [Data]) async throws {
        guard !targets.isEmpty else {
            return
        }

        #if DEBUG
        if let override = appTrustSettingsRemovalOverrideForTests {
            try await override(targets)
            return
        }
        if RockxyIdentity.isRunningTests {
            // Reading presence never prompts; removing settings that are present would. A fixture
            // that somehow carries trust settings fails closed rather than raising a real dialog,
            // and an unreadable domain fails closed with it.
            for der in targets {
                guard try !KeychainHelper.hasAnyTrustSettings(certData: der) else {
                    throw CertificateManagerError.rootRemovalIncomplete(
                        "tests require an injected trust-settings remover"
                    )
                }
            }
            return
        }
        #endif

        try await Self.withAuthorizationThread { signal in
            for der in targets {
                // Between two targets, and inside the call between the two trust domains: an
                // abandoned removal stops before the next interactive write instead of clearing
                // settings nobody is waiting for.
                try signal.checkCancellation()
                try KeychainHelper.removeRootCATrustSettings(
                    certData: der,
                    cancellationCheck: { try signal.checkCancellation() }
                )
            }
        }
    }

    /// Removes exactly these certificates from the keychains this process owns, and proves each
    /// one gone — without touching a trust-settings API.
    ///
    /// The last step of a removal, after the one authorization phase in `removeAppSideTrustSettings`
    /// and after the helper's delete. Calling the interactive trust removal again here is what
    /// could raise a second dialog: trust settings live independently of the keychain item, so a
    /// target whose settings were restored or re-added between the two steps would send this
    /// cleanup back through Authorization Services for an operation the user already answered.
    ///
    /// So this only deletes, and only what is already proved untrusted: absence of admin and user
    /// trust settings is verified strictly for every target, and a target that still carries
    /// settings — or whose domains cannot be read — is kept installed rather than deleted. The
    /// certificate is what still addresses those settings; deleting it would leave them behind
    /// with only the snapshotted DER to name them.
    private func removeAppSideTargets(_ targets: [Data]) throws {
        #if DEBUG
        if let override = appRemovalOverrideForTests {
            try override(targets)
            return
        }
        #endif
        for der in targets {
            try Task.checkCancellation()
            try KeychainHelper.removeExactCertificateItems(certData: der)
        }
    }

    /// Asks the privileged helper to remove exactly the snapshotted targets, if this manager is
    /// allowed to reach it at all.
    ///
    /// Only the real production identity may: a test namespace owns no system-installed
    /// certificate, so calling the daemon from a test would ask for privilege to remove
    /// material belonging to the installed app.
    ///
    /// This is a delete, not an untrust: the trust settings were already cleared in this process,
    /// because clearing them needs an interactive authorization session this headless daemon
    /// cannot obtain. What the helper contributes is the one thing this process cannot do —
    /// removing the item from the System keychain, which is not writable from the app.
    ///
    /// Nothing here falls back to the helper's legacy label sweep. That sweep removes every
    /// certificate carrying the label, which is not what this call means, and a helper too old
    /// to accept a specific certificate reports it so the caller can surface an update prompt
    /// while app-side removal and the final verification still run.
    private func attemptHelperRemoval(targets: [Data]) async throws {
        guard !targets.isEmpty else {
            Self.logger.info("No installed root CA certificate to remove — skipping the privileged helper")
            return
        }

        #if DEBUG
        if let override = helperRemovalOverrideForTests {
            try await override(targets)
            return
        }
        #endif

        guard Self.ownsProductionRootIdentity else {
            Self.logger.info("Skipping helper removal — this manager does not own the production root CA identity")
            return
        }

        let helperAvailable = await MainActor.run {
            Self.shouldUseHelperForTrustInstall(
                status: HelperManager.shared.status,
                isReachable: HelperManager.shared.isReachable
            )
        }
        guard helperAvailable else {
            Self.logger.info("Helper unavailable for removal — using app-side removal only")
            return
        }

        try Task.checkCancellation()
        let helperConnection = await MainActor.run { HelperConnection.shared }
        for der in targets {
            try Task.checkCancellation()
            try await helperConnection.removeRootCertificate(matching: der)
        }
    }

    /// Fails unless every removal target is absent from the keychain *and* carries no admin
    /// trust settings.
    ///
    /// Admin trust settings are stored independently of the certificate item, so a deleted
    /// certificate is not by itself proof that the system stopped trusting it.
    private func verifyRootMaterialRemoved(
        targets: [Data],
        helperFailure: (any Error)?
    )
        throws
    {
        var leftovers: [String] = []
        for der in targets {
            let fingerprint = KeychainHelper.computeFingerprintSHA256(der)
            if try KeychainHelper.isCertificateInstalledStrict(certData: der) {
                leftovers.append("certificate \(fingerprint) is still installed")
            }
            if try KeychainHelper.hasAnyTrustSettings(certData: der) {
                leftovers.append("certificate \(fingerprint) still has trust settings")
            }
        }

        if try !KeychainHelper.findLabeledCertificates(label: Self.keychainCertLabel).isEmpty {
            leftovers.append("root CA label still has installed certificates")
        }

        guard leftovers.isEmpty else {
            var detail = leftovers.joined(separator: "; ")
            if let helperFailure {
                detail += " (helper removal failed: \(helperFailure.localizedDescription))"
            }
            throw CertificateManagerError.rootRemovalIncomplete(detail)
        }
    }

    /// Adopts a certificate/key pair as the active root CA.
    ///
    /// A pair whose fingerprint differs from the one already adopted is a different CA, so
    /// everything derived from the previous one has to go: host leaves signed by it, the
    /// cached real-trust result recorded for it, and the session flag telling the UI that
    /// browsers still need a restart.
    ///
    /// - Returns: true when the adopted CA is a different identity from the previous one.
    @discardableResult
    private func adoptRootCA(certificate: Certificate, privateKey: P256.Signing.PrivateKey) -> Bool {
        let fingerprint = computeFingerprint(certificate)
        let identityChanged = fingerprint != activeRootFingerprint

        rootCACertificate = certificate
        rootCAPrivateKey = privateKey
        activeRootFingerprint = fingerprint

        if identityChanged {
            clearHostCache()
            lastTrustValidationResult = nil
            lastValidationErrorMessage = nil
            rootCAFreshlyInstalled = false
        }
        return identityChanged
    }

    /// Loads the persisted root CA when nothing is in memory yet.
    ///
    /// This never generates a replacement: rotation stays an explicit `ensureRootCA()`
    /// decision. A Keychain or filesystem failure is reported fail-closed through the existing
    /// validation diagnostic instead of being read as "no CA exists", which would silently
    /// invalidate the fingerprint the user already approved.
    private func loadPersistedRootCAIfNeeded() -> PersistedRootLoadOutcome {
        #if DEBUG
        persistedRootLoadAttemptsForTests += 1
        #endif

        if rootCACertificate != nil, rootCAPrivateKey != nil {
            // A privileged mutation owns this identity across an await. Its post-operation check
            // and notification will publish the final state; a concurrent status read must not
            // adopt or diagnose the half-finished storage transition.
            if isInstallingTrust || isRemovingRootMaterial {
                return .resolved
            }

            do {
                guard try activeRootMatchesPersistedStorage(migrateLegacyKey: false) else {
                    throw CertificateManagerError.persistedRootIdentityDrift
                }
                return .resolved
            } catch {
                Self.logger.error(
                    "Persisted root CA no longer matches the active certificate/key identity: \(error.localizedDescription)"
                )
                // A cached green answer belongs to the in-memory CA. It cannot describe the CA a
                // relaunch would use after another process changed either persisted half.
                lastTrustValidationResult = nil
                lastValidationErrorMessage = error.localizedDescription
                return .failed(error.localizedDescription)
            }
        }

        do {
            _ = try loadExistingRootCA()
            return .resolved
        } catch CertificateManagerError.trustInstallationInProgress {
            // An installation owns the material right now. It is not a storage failure, so it
            // must not overwrite the validation diagnostic; the next refresh reports the
            // installed state.
            return .resolved
        } catch CertificateManagerError.rootRemovalInProgress {
            // Likewise for a removal that is suspended in the privileged helper call: the
            // material it is about to delete is not this caller's to adopt or diagnose.
            return .resolved
        } catch {
            Self.logger.error("Failed to load persisted root CA for status: \(error.localizedDescription)")
            // A stale green result cannot outlive a storage read that no longer confirms it, and
            // `false` would claim a finding this call does not have. The reason is kept.
            lastTrustValidationResult = nil
            lastValidationErrorMessage = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    /// Reports whether the currently adopted root CA is present in a keychain, without
    /// attempting a persisted load of its own. Callers that need the load do it once, up front.
    ///
    /// Reads the exact DER of the adopted root; the label lookup is only for the case where
    /// storage was read successfully and holds no certificate at all. Both are strict, so an
    /// unreadable Keychain propagates instead of looking like an uninstalled root.
    private func installedStateForAdoptedRoot() throws -> Bool {
        #if DEBUG
        if let statusReadOverrideForTests {
            return try statusReadOverrideForTests().isInstalledInKeychain
        }
        #endif
        if let cert = rootCACertificate {
            let installed = try KeychainHelper.isCertificateInstalledStrict(certData: certToDER(cert))
            Self.logger.debug("Root CA install check (DER): \(installed)")
            return installed
        }
        let installed = try KeychainHelper.isCertificateInstalledStrict(label: Self.keychainCertLabel)
        Self.logger.debug("Root CA install check (label fallback): \(installed)")
        return installed
    }

    /// The single production rule behind every "is this root system-trusted?" answer, shared
    /// by `rootCAStatusSnapshot` and the legacy `isRootCATrusted()` getter.
    ///
    /// Persisted material is loaded first, keychain metadata is only ever a prefilter, and the
    /// positive result always comes from `validateSystemTrust()` — a real `SecTrust`
    /// evaluation of a freshly issued leaf against the system trust store, with no injected
    /// anchors.
    private func resolveSystemTrust(performValidation: Bool) -> TrustResolution {
        if case let .failed(reason) = loadPersistedRootCAIfNeeded() {
            // The load diagnostic explains why trust cannot be resolved. Continuing would
            // replace it with the generic "no root CA certificate or private key available"
            // message from `validateSystemTrust()` and hide the real cause.
            hadUnreadableStatus = true
            return TrustResolution(
                isInstalledInKeychain: false,
                trustSettingsPresent: false,
                isSystemTrustValidated: false,
                readFailure: RootCAStatusReadFailure(scope: .persistedMaterial, message: reason)
            )
        }

        let status: (installed: Bool, trustPresent: Bool)
        do {
            status = try readInstalledTrustState()
        } catch {
            // The installed state or admin domain could not be read. That is not "no trust settings": answering it
            // that way is what asks for administrator approval again after a failed read.
            Self.logger.error("Failed to read certificate status: \(error.localizedDescription)")
            lastTrustValidationResult = nil
            lastValidationErrorMessage = error.localizedDescription
            hadUnreadableStatus = true
            return TrustResolution(
                isInstalledInKeychain: false,
                trustSettingsPresent: false,
                isSystemTrustValidated: false,
                readFailure: RootCAStatusReadFailure(
                    scope: .installedTrustState,
                    message: error.localizedDescription
                )
            )
        }

        if hadUnreadableStatus {
            // The read that failed now succeeds, so the reason it left behind describes nothing.
            // A real validation failure below records its own message.
            hadUnreadableStatus = false
            lastValidationErrorMessage = nil
        }

        let systemTrusted: Bool
        switch Self.trustEvaluationDecision(
            trustPresent: status.trustPresent,
            performValidation: performValidation,
            cachedValidation: lastTrustValidationResult
        ) {
        case let .notTrusted(invalidatesCachedResult):
            if invalidatesCachedResult {
                lastTrustValidationResult = nil
                lastValidationErrorMessage = nil
            }
            systemTrusted = false
        case .runValidation:
            systemTrusted = validateSystemTrust()
        case let .useCached(cachedValidation):
            systemTrusted = cachedValidation
        }

        return TrustResolution(
            isInstalledInKeychain: status.installed,
            trustSettingsPresent: status.trustPresent,
            isSystemTrustValidated: systemTrusted,
            readFailure: nil
        )
    }

    /// Read both prerequisites before evaluating or reusing trust. The install path consumes
    /// this same result instead of making another boolean query that could erase a read error.
    private func readInstalledTrustState() throws -> (installed: Bool, trustPresent: Bool) {
        #if DEBUG
        if let statusReadOverrideForTests {
            let status = try statusReadOverrideForTests()
            return (status.isInstalledInKeychain, status.hasAdminTrustSettings)
        }
        #endif
        return try (installedStateForAdoptedRoot(), strictTrustSettingsPresent())
    }

    /// Admin trust-settings metadata for the adopted root CA, or a throw when the domain could
    /// not be read. The exact DER is preferred; the label is only used when nothing is adopted.
    private func strictTrustSettingsPresent() throws -> Bool {
        #if DEBUG
        if let statusReadOverrideForTests {
            return try statusReadOverrideForTests().hasAdminTrustSettings
        }
        #endif
        if let cert = rootCACertificate {
            return try KeychainHelper.adminTrustsRootStrict(certData: certToDER(cert))
        }
        return try KeychainHelper.adminTrustsRootStrict(label: Self.keychainCertLabel)
    }

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
        #if DEBUG
        statusNotificationObserverForTests?()
        #endif
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

nonisolated enum CertificateManagerError: LocalizedError, Equatable {
    case noRootCA
    case rootCANotTrusted
    case trustValidationFailed
    case trustInstallationInProgress
    case persistedRootIdentityChanged
    case persistedRootIdentityDrift
    case rootRemovalInProgress
    case rootRemovalIncomplete(String)
    case helperInstallUnavailable(String)
    case trustStateUnavailable(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .helperInstallUnavailable(detail):
            "The privileged helper was not used for this installation (\(detail))."
        case .noRootCA:
            "Root CA certificate has not been generated"
        case .rootCANotTrusted:
            "Root CA certificate is not trusted — install and trust the certificate before HTTPS interception"
        case .trustValidationFailed:
            "macOS has not validated the certificate for TLS. Your certificate and key were kept. Recheck the certificate status in Settings."
        case .trustInstallationInProgress:
            "A certificate trust installation is already in progress. Wait for it to finish, then try again."
        case .persistedRootIdentityChanged:
            "Rockxy's persisted root CA changed while trust was being prepared. Quit other running copies of Rockxy, then try again. No second trust prompt was requested."
        case .persistedRootIdentityDrift:
            "Rockxy's active root CA no longer matches its saved certificate and private key. " +
                "This can happen after another Rockxy copy or a Keychain restore changed certificate storage. " +
                "Use Install & Trust Certificate to reconcile it before HTTPS interception."
        case .rootRemovalInProgress:
            "A certificate removal is already in progress. Wait for it to finish, then try again."
        case let .trustStateUnavailable(detail):
            "Rockxy could not read the certificate's Keychain and trust status, so it did not request administrator approval. Check the status again once the keychain is available (\(detail))."
        case let .rootRemovalIncomplete(detail):
            "The installed root CA certificate could not be fully removed, so your local certificate and key were kept. Remove it in Keychain Access and try again (\(detail))."
        }
    }
}

// MARK: - TrustEvaluationDecision

/// How `CertificateManager.rootCAStatusSnapshot` should resolve system-trust state.
nonisolated enum TrustEvaluationDecision: Equatable {
    /// Trust metadata is absent, so the answer is "not trusted". `invalidatesCachedResult`
    /// is true when a previously cached positive result must be dropped as well.
    case notTrusted(invalidatesCachedResult: Bool)
    /// A real `SecTrust` evaluation has to run before this state can be reported.
    case runValidation
    /// A real evaluation already ran for the currently adopted CA; reuse its result.
    case useCached(Bool)
}

#if DEBUG

// MARK: - StatusReadResultForTests

/// One injected answer for the strict Keychain-presence and admin-trust reads.
///
/// A throwing override models an unreadable Keychain or trust domain; returning a value models a
/// readable answer, including a readable negative.
nonisolated struct StatusReadResultForTests: Sendable {
    let isInstalledInKeychain: Bool
    let hasAdminTrustSettings: Bool
}
#endif

// MARK: - RootCAStatusReadFailure

/// Why a status answer could not describe the real system state.
///
/// This is not "the certificate is missing" and not "macOS rejected it" — it is "Rockxy could
/// not tell". Reporting it as either of the other two is what turns a failed read into another
/// administrator prompt for a root the user already approved.
nonisolated struct RootCAStatusReadFailure: Equatable {
    /// Which part of the answer is unknown.
    enum Scope: Equatable {
        /// The persisted certificate or key could not be read, so nothing about the root CA —
        /// including whether one exists — is known.
        case persistedMaterial
        /// The root CA is known, but the Keychain or the admin trust domain could not be read.
        case installedTrustState
    }

    let scope: Scope
    /// User-facing reason. Carries an OSStatus where one is useful; never a path, DER bytes, or
    /// private key material.
    let message: String
}

// MARK: - RootCAStatusSnapshot

/// Complete diagnostic snapshot of root CA state, returned by `CertificateManager.rootCAStatusSnapshot()`.
/// All fields are computed from a single real validation pass — no caching shortcuts.
///
/// When `statusReadFailure` is set, the boolean fields are *not* findings: they are the
/// fail-closed defaults for an answer that could not be produced. Surfaces must report the
/// unavailable state rather than "missing", "untrusted", or "failed".
nonisolated struct RootCAStatusSnapshot {
    // MARK: Lifecycle

    init(
        hasGeneratedCertificate: Bool,
        isInstalledInKeychain: Bool,
        hasTrustSettings: Bool,
        isSystemTrustValidated: Bool,
        notValidBefore: Date?,
        notValidAfter: Date?,
        fingerprintSHA256: String?,
        commonName: String?,
        lastValidationErrorMessage: String?,
        statusReadFailure: RootCAStatusReadFailure? = nil
    ) {
        self.hasGeneratedCertificate = hasGeneratedCertificate
        self.isInstalledInKeychain = isInstalledInKeychain
        self.hasTrustSettings = hasTrustSettings
        self.isSystemTrustValidated = isSystemTrustValidated
        self.notValidBefore = notValidBefore
        self.notValidAfter = notValidAfter
        self.fingerprintSHA256 = fingerprintSHA256
        self.commonName = commonName
        self.lastValidationErrorMessage = lastValidationErrorMessage
        self.statusReadFailure = statusReadFailure
    }

    // MARK: Internal

    let hasGeneratedCertificate: Bool
    let isInstalledInKeychain: Bool
    let hasTrustSettings: Bool
    let isSystemTrustValidated: Bool
    let notValidBefore: Date?
    let notValidAfter: Date?
    let fingerprintSHA256: String?
    let commonName: String?
    let lastValidationErrorMessage: String?
    let statusReadFailure: RootCAStatusReadFailure?

    /// True when this snapshot describes an answer Rockxy could not read.
    var isStatusUnavailable: Bool {
        statusReadFailure != nil
    }

    /// The reason to show for an unavailable status.
    var statusReadErrorMessage: String? {
        statusReadFailure?.message
    }

    /// False only when storage itself was unreadable, so "Not Generated" would be a guess.
    var isGeneratedStateKnown: Bool {
        statusReadFailure?.scope != .persistedMaterial
    }

    /// False whenever any part of the status read failed: install presence, trust settings, and
    /// TLS validation are all downstream of the reads that did not complete.
    var isInstalledAndTrustStateKnown: Bool {
        statusReadFailure == nil
    }
}
