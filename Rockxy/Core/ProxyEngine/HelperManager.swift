import Foundation
import os
import Security
import ServiceManagement

// Defines `HelperManager`, which coordinates helper behavior in the proxy engine.

// MARK: - HelperManager

/// Manages the lifecycle of the Rockxy privileged helper tool via SMAppService.
///
/// The helper tool is a launch daemon that enables fast system proxy changes without
/// repeated password prompts. This manager handles installation, updates, and removal.
@MainActor @Observable
final class HelperManager {
    // MARK: Internal

    /// Current state of the helper tool installation.
    enum HelperStatus: Equatable {
        case notInstalled
        case requiresApproval
        case installedCompatible
        case installedOutdated
        case installedIncompatible
        case unreachable
        case signingMismatch
    }

    /// Identifies the specific signing issue when status is `.signingMismatch`.
    enum SigningIssue: Equatable {
        case applicationMustReopen
        case appSignatureInvalid(detail: String)
        case identityMismatch(appSigner: String, helperSigner: String)
    }

    /// Normalized result from a helper info probe, scoped to the actual error surface.
    enum ProbeOutcome: Equatable {
        case applicationMustReopen
        case appSignatureInvalid(detail: String)
        case signingIdentityMismatch(appSigner: String, helperSigner: String)
        case xpcFailure
    }

    /// Recovery action determined from a probe outcome.
    enum RecoveryAction: Equatable {
        case surfaceApplicationMustReopen
        case surfaceAppSignatureInvalid(detail: String)
        case surfaceSigningMismatch(appSigner: String, helperSigner: String)
        case surfaceUnreachable
    }

    enum InstallDisposition: Equatable {
        case register
        case requiresApproval
        case alreadyEnabled
    }

    enum HelperPlistValidationError: Error, Equatable {
        case malformedPlist
        case missingLabel
        case unexpectedLabel(String)
        case missingBundleProgram
        case unexpectedBundleProgram(String)
        case missingMachServices
        case missingMachService(String)
        case disabledMachService(String)
        case missingAssociatedBundleIdentifiers
        case unexpectedAssociatedBundleIdentifiers([String])
        case unknown(Error)

        // MARK: Internal

        static func == (lhs: HelperPlistValidationError, rhs: HelperPlistValidationError) -> Bool {
            switch (lhs, rhs) {
            case (.malformedPlist, .malformedPlist),
                 (.missingLabel, .missingLabel),
                 (.missingBundleProgram, .missingBundleProgram),
                 (.missingMachServices, .missingMachServices),
                 (.missingAssociatedBundleIdentifiers, .missingAssociatedBundleIdentifiers):
                true
            case let (.unexpectedLabel(lhsLabel), .unexpectedLabel(rhsLabel)):
                lhsLabel == rhsLabel
            case let (.unexpectedBundleProgram(lhsProgram), .unexpectedBundleProgram(rhsProgram)):
                lhsProgram == rhsProgram
            case let (.missingMachService(lhsService), .missingMachService(rhsService)):
                lhsService == rhsService
            case let (.disabledMachService(lhsService), .disabledMachService(rhsService)):
                lhsService == rhsService
            case let (
                .unexpectedAssociatedBundleIdentifiers(lhsIdentifiers),
                .unexpectedAssociatedBundleIdentifiers(rhsIdentifiers)
            ):
                lhsIdentifiers == rhsIdentifiers
            case let (.unknown(lhsError), .unknown(rhsError)):
                String(describing: lhsError) == String(describing: rhsError)
            default:
                false
            }
        }
    }

    enum HelperMetadataValidationError: Error, Equatable {
        case missingInfoDictionary
        case missingValue(String)
        case unexpectedValue(key: String, value: String)
        case unexpectedAllowedCallerIdentifiers([String])
    }

    enum HelperInstallPreflightError: LocalizedError, Equatable {
        case missingBundledHelperBinary(path: String)
        case missingBundledLaunchdPlist(path: String)
        case unreadableBundledLaunchdPlist(path: String)
        case invalidBundledLaunchdPlist(HelperPlistValidationError)
        case invalidBundledHelperMetadata(HelperMetadataValidationError)
        case invalidBundledHelperSignature

        // MARK: Internal

        var errorDescription: String? {
            HelperManager.helperPackageIncompleteMessage
        }
    }

    static let shared = HelperManager()

    nonisolated static let bundledHelperBinaryRelativePath = "Contents/Library/HelperTools/RockxyHelperTool"

    nonisolated static var applicationMustReopenMessage: String {
        String(
            localized: "Rockxy was updated or replaced while it was open. Quit and reopen Rockxy, then check the helper again.",
            bundle: RockxyLocalization.bundle
        )
    }

    private(set) var signingIssue: SigningIssue?
    private(set) var installedInfo: HelperInfo?
    private(set) var isReachable: Bool = false
    private(set) var lastErrorMessage: String?
    private(set) var isBusy: Bool = false
    private(set) var registrationStatus: String = "Unknown"
    private(set) var automaticRefreshRecoveryPending = false

    private(set) var status: HelperStatus = .notInstalled {
        didSet {
            if status != .signingMismatch {
                signingIssue = nil
            }
        }
    }

    var bundledHelperVersion: String {
        Bundle.main.infoDictionary?["RockxyBundledHelperVersion"] as? String ?? "0.0.0"
    }

    var bundledHelperBuild: Int {
        Int(Bundle.main.infoDictionary?["RockxyBundledHelperBuild"] as? String ?? "0") ?? 0
    }

    var expectedProtocolVersion: Int {
        Int(Bundle.main.infoDictionary?["RockxyHelperProtocolVersion"] as? String ?? "0") ?? 0
    }

    static func installDisposition(for status: SMAppService.Status) -> InstallDisposition {
        switch status {
        case .requiresApproval:
            .requiresApproval
        case .enabled:
            .alreadyEnabled
        case .notRegistered,
             .notFound:
            .register
        @unknown default:
            .register
        }
    }

    nonisolated static func validateBundledHelperLaunchdPlistData(
        _ data: Data,
        expectedLabel: String,
        expectedBundleProgram: String,
        expectedMachServiceName: String,
        expectedAssociatedBundleIdentifiers: [String]
    )
        throws
    {
        let plistObject: Any
        do {
            plistObject = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw HelperPlistValidationError.malformedPlist
        }

        guard let plist = plistObject as? [String: Any] else {
            throw HelperPlistValidationError.malformedPlist
        }
        guard let label = plist["Label"] as? String, !label.isEmpty else {
            throw HelperPlistValidationError.missingLabel
        }
        guard label == expectedLabel else {
            throw HelperPlistValidationError.unexpectedLabel(label)
        }
        guard let bundleProgram = plist["BundleProgram"] as? String, !bundleProgram.isEmpty else {
            throw HelperPlistValidationError.missingBundleProgram
        }
        guard bundleProgram == expectedBundleProgram else {
            throw HelperPlistValidationError.unexpectedBundleProgram(bundleProgram)
        }
        guard let machServices = plist["MachServices"] as? [String: Any] else {
            throw HelperPlistValidationError.missingMachServices
        }
        guard let machServiceValue = machServices[expectedMachServiceName] else {
            throw HelperPlistValidationError.missingMachService(expectedMachServiceName)
        }
        guard let machServiceEnabled = machServiceValue as? Bool else {
            throw HelperPlistValidationError.missingMachService(expectedMachServiceName)
        }
        guard machServiceEnabled else {
            throw HelperPlistValidationError.disabledMachService(expectedMachServiceName)
        }

        guard let associatedBundleIdentifiers = plist["AssociatedBundleIdentifiers"] as? [String] else {
            throw HelperPlistValidationError.missingAssociatedBundleIdentifiers
        }

        let normalizedAssociatedBundleIdentifiers = normalizedIdentifiers(associatedBundleIdentifiers)
        let normalizedExpectedAssociatedBundleIdentifiers = normalizedIdentifiers(expectedAssociatedBundleIdentifiers)
        guard normalizedAssociatedBundleIdentifiers == normalizedExpectedAssociatedBundleIdentifiers else {
            throw HelperPlistValidationError.unexpectedAssociatedBundleIdentifiers(
                normalizedAssociatedBundleIdentifiers
            )
        }
    }

    nonisolated static func validateBundledHelperInfoDictionary(
        _ info: [String: Any],
        expectedIdentity: RockxyIdentity
    )
        throws
    {
        let bundleIdentifier = stringValue(forKey: "CFBundleIdentifier", in: info)
        guard !bundleIdentifier.isEmpty else {
            throw HelperMetadataValidationError.missingValue("CFBundleIdentifier")
        }
        guard bundleIdentifier == expectedIdentity.helperBundleIdentifier else {
            throw HelperMetadataValidationError.unexpectedValue(
                key: "CFBundleIdentifier",
                value: bundleIdentifier
            )
        }

        let helperBundleIdentifier = stringValue(forKey: "RockxyHelperBundleIdentifier", in: info)
        guard !helperBundleIdentifier.isEmpty else {
            throw HelperMetadataValidationError.missingValue("RockxyHelperBundleIdentifier")
        }
        guard helperBundleIdentifier == expectedIdentity.helperBundleIdentifier else {
            throw HelperMetadataValidationError.unexpectedValue(
                key: "RockxyHelperBundleIdentifier",
                value: helperBundleIdentifier
            )
        }

        let helperMachServiceName = stringValue(forKey: "RockxyHelperMachServiceName", in: info)
        guard !helperMachServiceName.isEmpty else {
            throw HelperMetadataValidationError.missingValue("RockxyHelperMachServiceName")
        }
        guard helperMachServiceName == expectedIdentity.helperMachServiceName else {
            throw HelperMetadataValidationError.unexpectedValue(
                key: "RockxyHelperMachServiceName",
                value: helperMachServiceName
            )
        }

        let familyNamespace = stringValue(forKey: "RockxyFamilyNamespace", in: info)
        guard !familyNamespace.isEmpty else {
            throw HelperMetadataValidationError.missingValue("RockxyFamilyNamespace")
        }
        guard familyNamespace == expectedIdentity.familyNamespace else {
            throw HelperMetadataValidationError.unexpectedValue(
                key: "RockxyFamilyNamespace",
                value: familyNamespace
            )
        }

        let allowedCallerIdentifiers = normalizedIdentifiers(
            stringValue(forKey: "RockxyAllowedCallerIdentifiers", in: info)
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
        )
        guard !allowedCallerIdentifiers.isEmpty else {
            throw HelperMetadataValidationError.missingValue("RockxyAllowedCallerIdentifiers")
        }
        guard allowedCallerIdentifiers == normalizedIdentifiers(expectedIdentity.allowedCallerIdentifiers) else {
            throw HelperMetadataValidationError.unexpectedAllowedCallerIdentifiers(
                allowedCallerIdentifiers
            )
        }
    }

    nonisolated static func validateBundledHelperInstallResources(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        helperInfoDictionaryProvider: (URL) -> [String: Any]? = HelperManager.bundledHelperInfoDictionary
    )
        throws
    {
        let identity = RockxyIdentity(bundle: bundle)
        let appBundleURL = bundle.bundleURL
        let helperBinaryURL = appBundleURL.appendingPathComponent(bundledHelperBinaryRelativePath)
        let helperPlistURL = appBundleURL.appendingPathComponent(
            bundledHelperPlistRelativePath(plistName: identity.helperPlistName)
        )

        let helperBinaryResourceValues = try? helperBinaryURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
        ])
        guard helperBinaryResourceValues?.isRegularFile == true,
              helperBinaryResourceValues?.isDirectory != true,
              fileManager.isReadableFile(atPath: helperBinaryURL.path),
              fileManager.isExecutableFile(atPath: helperBinaryURL.path) else
        {
            throw HelperInstallPreflightError.missingBundledHelperBinary(path: helperBinaryURL.path)
        }
        guard fileManager.fileExists(atPath: helperPlistURL.path) else {
            throw HelperInstallPreflightError.missingBundledLaunchdPlist(path: helperPlistURL.path)
        }

        let plistData: Data
        do {
            plistData = try Data(contentsOf: helperPlistURL)
        } catch {
            throw HelperInstallPreflightError.unreadableBundledLaunchdPlist(path: helperPlistURL.path)
        }

        do {
            try validateBundledHelperLaunchdPlistData(
                plistData,
                expectedLabel: identity.helperMachServiceName,
                expectedBundleProgram: bundledHelperBinaryRelativePath,
                expectedMachServiceName: identity.helperMachServiceName,
                expectedAssociatedBundleIdentifiers: identity.allowedCallerIdentifiers
            )
        } catch let validationError as HelperPlistValidationError {
            throw HelperInstallPreflightError.invalidBundledLaunchdPlist(validationError)
        } catch {
            throw HelperInstallPreflightError.invalidBundledLaunchdPlist(.unknown(error))
        }

        guard let helperInfoDictionary = helperInfoDictionaryProvider(helperBinaryURL) else {
            throw HelperInstallPreflightError.invalidBundledHelperMetadata(.missingInfoDictionary)
        }

        do {
            try validateBundledHelperInfoDictionary(
                helperInfoDictionary,
                expectedIdentity: identity
            )
        } catch let validationError as HelperMetadataValidationError {
            throw HelperInstallPreflightError.invalidBundledHelperMetadata(validationError)
        }
    }

    nonisolated static func requiresApproval(error: Error, serviceStatus: SMAppService.Status) -> Bool {
        let nsError = error as NSError
        return serviceStatus == .requiresApproval
            || nsError.code == 1
            || nsError.code == kSMErrorLaunchDeniedByUser
    }

    nonisolated static func approvalMessage(error: Error, serviceStatus: SMAppService.Status) -> String {
        let nsError = error as NSError

        if serviceStatus == .requiresApproval || nsError.code == kSMErrorLaunchDeniedByUser {
            return helperApprovalMessage
        }

        if nsError.code == 1, serviceStatus == .notRegistered || serviceStatus == .notFound {
            return String(
                localized: """
                macOS blocked helper registration before Rockxy could finish installing it. \
                Open System Settings > Login Items and approve Rockxy if it appears there. \
                If Rockxy is not listed, clear stale Rockxy helper registrations and try installing again.
                """, bundle: RockxyLocalization.bundle
            )
        }

        return helperApprovalMessage
    }

    /// Detect whether any helper state property changed, including `signingIssue`.
    nonisolated static func helperStateDidChange(
        previousStatus: HelperStatus, currentStatus: HelperStatus,
        previousReachable: Bool, currentReachable: Bool,
        previousInfo: HelperInfo?, currentInfo: HelperInfo?,
        previousSigningIssue: SigningIssue?, currentSigningIssue: SigningIssue?
    )
        -> Bool
    {
        currentStatus != previousStatus
            || currentReachable != previousReachable
            || currentInfo != previousInfo
            || currentSigningIssue != previousSigningIssue
    }

    nonisolated static func bundledHelperInfoDictionary(at helperBinaryURL: URL) -> [String: Any]? {
        if let infoDictionary = signedExecutableInfoDictionary(at: helperBinaryURL) {
            return infoDictionary
        }

        if let infoDictionary = sidecarInfoDictionary(at: helperBinaryURL) {
            return infoDictionary
        }

        if let bundle = Bundle(url: helperBinaryURL),
           let infoDictionary = bundle.infoDictionary
        {
            return infoDictionary
        }

        if let bundle = Bundle(path: helperBinaryURL.path),
           let infoDictionary = bundle.infoDictionary
        {
            return infoDictionary
        }

        return nil
    }

    /// Mutation seams for `HelperManager` extensions in other files. The properties themselves
    /// stay read-only to everything else, so no view or service can drive helper state directly.
    func setBusy(_ value: Bool) {
        isBusy = value
    }

    func setLastErrorMessage(_ value: String?) {
        lastErrorMessage = value
    }

    func setAutomaticRefreshRecoveryPending(_ value: Bool) {
        automaticRefreshRecoveryPending = value
    }

    /// Register the helper daemon via SMAppService.
    ///
    /// On macOS 13+, this uses `SMAppService.daemon(plistName:).register()` which
    /// requires user approval in System Settings > Login Items.
    func install() async throws {
        HelperConnection.shared.invalidateSigningCache()
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        let previousSigningIssue = signingIssue
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo,
                previousSigningIssue: previousSigningIssue
            )
        }
        try await ensureHelperMutationCanProceed()
        try await performInstall()
        if status != .requiresApproval {
            await performCheckStatus()
        }
    }

    /// Uninstall the helper by preparing it via XPC, then unregistering from launchd.
    func uninstall() async throws {
        HelperConnection.shared.invalidateSigningCache()
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        let previousSigningIssue = signingIssue
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo,
                previousSigningIssue: previousSigningIssue
            )
        }
        try await ensureHelperMutationCanProceed()
        try await performUninstall()
    }

    /// Check whether the helper is installed, responding, and at the correct version.
    func checkStatus() async {
        HelperConnection.shared.invalidateSigningCache()
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        let previousSigningIssue = signingIssue
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo,
                previousSigningIssue: previousSigningIssue
            )
        }
        await performCheckStatus()
    }

    /// Retry establishing connection with the helper.
    func retryConnection() async {
        HelperConnection.shared.invalidateSigningCache()
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        let previousSigningIssue = signingIssue
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo,
                previousSigningIssue: previousSigningIssue
            )
        }
        HelperConnection.shared.resetConnection()
        await performCheckStatus()
    }

    /// Reinstall the helper by uninstalling, then installing fresh.
    func reinstall() async throws {
        HelperConnection.shared.invalidateSigningCache()
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        let previousSigningIssue = signingIssue
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo,
                previousSigningIssue: previousSigningIssue
            )
        }
        do {
            try await ensureHelperMutationCanProceed()
            try await performUninstall()
            try await performInstall()
            if status != .requiresApproval {
                await performCheckStatus()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    /// Force-reset the helper registration to recover from BTM desync.
    ///
    /// When macOS Background Task Management gets into a stuck state where
    /// `SMAppService` reports `.requiresApproval` but toggling the System Settings
    /// switch has no effect, this method clears the registration and re-registers
    /// with a longer delay to allow BTM to settle.
    func forceResetRegistration() async throws {
        HelperConnection.shared.invalidateSigningCache()
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        let previousSigningIssue = signingIssue
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo,
                previousSigningIssue: previousSigningIssue
            )
        }

        Self.logger.info("Force-resetting helper registration to recover from BTM desync")
        try await ensureHelperMutationCanProceed()
        let service = SMAppService.daemon(plistName: Self.plistName)

        do {
            try await service.unregister()
        } catch {
            Self.logger.warning("Unregister during force-reset: \(error.localizedDescription)")
        }

        status = .notInstalled
        installedInfo = nil
        isReachable = false
        registrationStatus = "Not Registered"
        HelperConnection.shared.resetConnection()

        try? await Task.sleep(nanoseconds: 3_000_000_000)

        do {
            try await performInstall()
            if status != .requiresApproval {
                await performCheckStatus()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    /// Hard-remove the helper from launchd and privileged helper locations.
    ///
    /// This is intentionally separate from `forceResetRegistration()`. The registration
    /// reset path is the normal SMAppService recovery path. Hard remove is a last-resort
    /// recovery for BTM/launchd drift where XPC uninstall or SMAppService unregister
    /// cannot get the app back to an observable state.
    @discardableResult
    func forceRemoveHelper(resetBackgroundItems: Bool) async throws -> ForceRemoveResult {
        HelperConnection.shared.invalidateSigningCache()
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        let previousSigningIssue = signingIssue
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo,
                previousSigningIssue: previousSigningIssue
            )
        }

        Self.logger.info("Hard force-removing helper. resetBackgroundItems=\(resetBackgroundItems)")

        try await ensureHelperMutationCanProceed()

        do {
            try await HelperConnection.shared.uninstallHelper()
        } catch {
            Self.logger.warning("Force remove could not notify helper before removal: \(error.localizedDescription)")
        }

        do {
            try await SMAppService.daemon(plistName: Self.plistName).unregister()
        } catch {
            Self.logger.warning("Force remove SMAppService unregister failed: \(error.localizedDescription)")
        }

        let shellScript = Self.forceRemoveShellScript(
            identity: RockxyIdentity.current,
            resetBackgroundItems: resetBackgroundItems
        )
        let commandOutput = try await Self.runPrivilegedShellScript(shellScript)

        status = .notInstalled
        installedInfo = nil
        isReachable = false
        registrationStatus = "Not Registered"
        HelperConnection.shared.resetConnection()

        await performCheckStatus()

        return ForceRemoveResult(
            resetBackgroundItems: resetBackgroundItems,
            commandOutput: commandOutput
        )
    }

    // MARK: - Test Support

    #if DEBUG
    /// Inject a full helper state snapshot and route through the real
    /// change-detection / notification emission pipeline.
    func injectHelperStateForTests(
        status: HelperStatus,
        signingIssue: SigningIssue?,
        isReachable: Bool = false,
        installedInfo: HelperInfo? = nil,
        lastErrorMessage: String? = nil
    ) {
        let previousStatus = self.status
        let previousReachable = self.isReachable
        let previousInfo = self.installedInfo
        let previousSigningIssue = self.signingIssue

        self.installedInfo = installedInfo
        self.isReachable = isReachable
        self.lastErrorMessage = lastErrorMessage
        self.signingIssue = signingIssue
        self.status = status

        postStatusChangeIfNeeded(
            previousStatus: previousStatus,
            previousReachable: previousReachable,
            previousInfo: previousInfo,
            previousSigningIssue: previousSigningIssue
        )
    }
    #endif

    /// Emits the helper-state change notification when anything observable moved.
    /// Internal so `HelperManager` extensions in other files can own the same busy wrapper.
    func postStatusChangeIfNeeded(
        previousStatus: HelperStatus,
        previousReachable: Bool,
        previousInfo: HelperInfo?,
        previousSigningIssue: SigningIssue?
    ) {
        let changed = Self.helperStateDidChange(
            previousStatus: previousStatus, currentStatus: status,
            previousReachable: previousReachable, currentReachable: isReachable,
            previousInfo: previousInfo, currentInfo: installedInfo,
            previousSigningIssue: previousSigningIssue, currentSigningIssue: signingIssue
        )
        if changed {
            NotificationCenter.default.post(name: .helperStatusChanged, object: nil)
        }
    }

    /// Core install logic without busy/error wrapper.
    func performInstall() async throws {
        Self.logger.info("Installing helper tool")
        do {
            try Self.validateBundledHelperInstallResources()
        } catch let error as HelperInstallPreflightError {
            Self.logger
                .error(
                    "Bundled helper install preflight failed: \(Self.helperPreflightFailureReason(error), privacy: .private)"
                )
            status = .notInstalled
            installedInfo = nil
            isReachable = false
            registrationStatus = "Package Incomplete"
            lastErrorMessage = error.localizedDescription
            throw error
        }
        let service = SMAppService.daemon(plistName: Self.plistName)

        switch Self.installDisposition(for: service.status) {
        case .requiresApproval:
            try await handleApprovalRequired(
                service: service,
                reason: "SMAppService requires Login Items approval for an Xcode-run app bundle",
                message: Self.helperApprovalMessage
            )
            return
        case .alreadyEnabled:
            Self.logger.info("Helper tool is already registered")
            registrationStatus = "Enabled"
            await verifyEnabledHelperOrRepair(service: service)
            return
        case .register:
            break
        }

        do {
            try service.register()
        } catch {
            if Self.requiresApproval(error: error, serviceStatus: service.status) {
                try await handleApprovalRequired(
                    service: service,
                    reason: "SMAppService registration was denied for an Xcode-run app bundle",
                    message: Self.approvalMessage(error: error, serviceStatus: service.status)
                )
                return
            }

            lastErrorMessage = error.localizedDescription
            throw error
        }

        let currentStatus = service.status
        if currentStatus == .requiresApproval {
            try await handleApprovalRequired(
                service: service,
                reason: "SMAppService registration transitioned to requires approval for an Xcode-run app bundle",
                message: Self.helperApprovalMessage
            )
        } else if currentStatus == .enabled {
            Self.logger.info("Helper tool installed and enabled")
            registrationStatus = "Enabled"
            lastErrorMessage = nil
            await verifyEnabledHelperOrRepair(service: service)
        } else {
            Self.logger.warning(
                "Unexpected SMAppService status after register: \(String(describing: currentStatus))"
            )
            status = .notInstalled
        }
    }

    /// Core uninstall logic without busy/error wrapper.
    func performUninstall() async throws {
        Self.logger.info("Uninstalling helper tool")

        do {
            try await HelperConnection.shared.uninstallHelper()
        } catch {
            Self.logger.warning("Failed to notify helper of uninstall: \(error.localizedDescription)")
        }

        do {
            let service = SMAppService.daemon(plistName: Self.plistName)
            try await service.unregister()

            status = .notInstalled
            installedInfo = nil
            isReachable = false
            registrationStatus = "Not Registered"
            Self.logger.info("Helper tool uninstalled")
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    /// Core status check logic without busy/error wrapper.
    func performCheckStatus() async {
        let service = SMAppService.daemon(plistName: Self.plistName)
        let smStatus = service.status

        switch smStatus {
        case .enabled:
            registrationStatus = "Enabled"
        case .requiresApproval:
            registrationStatus = "Awaiting Approval"
        case .notRegistered:
            registrationStatus = "Not Registered"
        case .notFound:
            registrationStatus = "Not Found"
        @unknown default:
            registrationStatus = "Unknown"
        }

        switch smStatus {
        case .enabled:
            await checkEnabledHelper(service: service)
        case .requiresApproval:
            if await checkLegacyLaunchdHelperIfAvailable() {
                break
            }
            status = .requiresApproval
        case .notRegistered,
             .notFound:
            if await checkLegacyLaunchdHelperIfAvailable() {
                break
            }
            status = .notInstalled
            installedInfo = nil
            isReachable = false
        @unknown default:
            Self.logger.warning("Unknown SMAppService status: \(String(describing: smStatus))")
            status = .notInstalled
            installedInfo = nil
            isReachable = false
        }

        Self.logger.info("Helper status: \(String(describing: self.status))")
    }

    /// Prevent destructive helper repair when the running process no longer matches
    /// the app bundle on disk. The helper's caller validation is expected to reject
    /// that process, so only reopening Rockxy can recover it safely.
    func ensureHelperMutationCanProceed() async throws {
        HelperConnection.shared.invalidateSigningCache()
        let result = await HelperConnection.shared.signingCache.evaluate()
        switch result {
        case let .runningCodeChanged(detail):
            Self.logger.warning("Helper mutation blocked because running code changed: \(detail)")
            setSigningMismatchState(.applicationMustReopen)
            throw HelperOperationError.applicationMustReopen
        case let .appSignatureInvalid(detail):
            Self.logger.error("Helper mutation blocked because app signature is invalid: \(detail)")
            setSigningMismatchState(.appSignatureInvalid(detail: detail))
            throw HelperOperationError.appSignatureInvalid
        case .healthy,
             .signingIdentityMismatch,
             .helperBinaryNotFound,
             .certificateChainUnavailable,
             .diagnosticError:
            break
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperManager"
    )
    private static let plistName = RockxyIdentity.current.helperPlistName
    private static let helperProbeAttempts = 3
    private static let helperProbeRetryDelay = Duration.milliseconds(750)

    nonisolated private static var helperApprovalMessage: String {
        String(
            localized: "Approve the helper tool in System Settings > Login Items to finish installation.",
            bundle: RockxyLocalization.bundle
        )
    }

    nonisolated private static var helperPackageIncompleteMessage: String {
        String(
            localized: """
            This Rockxy app package is incomplete, so the helper tool cannot be installed. \
            Reinstall the latest Rockxy release. If you installed Rockxy from Homebrew, \
            reinstall it after the fixed release is published.
            """, bundle: RockxyLocalization.bundle
        )
    }

    nonisolated private static func bundledHelperPlistRelativePath(plistName: String) -> String {
        "Contents/Library/LaunchDaemons/\(plistName)"
    }

    nonisolated private static func sidecarInfoDictionary(at helperBinaryURL: URL) -> [String: Any]? {
        let sidecarCandidates = [
            helperBinaryURL.appendingPathExtension("plist"),
            helperBinaryURL.deletingLastPathComponent().appendingPathComponent("Info.plist"),
        ]

        for plistURL in sidecarCandidates {
            if let infoDictionary = plistDictionary(at: plistURL) {
                return infoDictionary
            }
        }

        return nil
    }

    nonisolated private static func plistDictionary(at plistURL: URL) -> [String: Any]? {
        guard let plistData = try? Data(contentsOf: plistURL) else {
            return nil
        }

        guard let propertyList = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) else {
            return nil
        }

        return propertyList as? [String: Any]
    }

    nonisolated private static func signedExecutableInfoDictionary(at executableURL: URL) -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else
        {
            return nil
        }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        ) == errSecSuccess,
            let signingInfo = signingInfo as? [String: Any],
            let infoDictionary = signingInfo[kSecCodeInfoPList as String] as? [String: Any] else
        {
            return nil
        }

        return infoDictionary
    }

    nonisolated private static func helperPreflightFailureReason(_ error: HelperInstallPreflightError) -> String {
        switch error {
        case let .missingBundledHelperBinary(path):
            "Missing helper binary at \(path)"
        case let .missingBundledLaunchdPlist(path):
            "Missing helper launchd plist at \(path)"
        case let .unreadableBundledLaunchdPlist(path):
            "Unreadable helper launchd plist at \(path)"
        case let .invalidBundledLaunchdPlist(validationError):
            switch validationError {
            case .malformedPlist:
                "Helper launchd plist is malformed"
            case .missingLabel:
                "Helper launchd plist is missing Label"
            case let .unexpectedLabel(label):
                "Helper launchd plist has unexpected Label '\(label)'"
            case .missingBundleProgram:
                "Helper launchd plist is missing BundleProgram"
            case let .unexpectedBundleProgram(bundleProgram):
                "Helper launchd plist has unexpected BundleProgram '\(bundleProgram)'"
            case .missingMachServices:
                "Helper launchd plist is missing MachServices"
            case let .missingMachService(machServiceName):
                "Helper launchd plist is missing MachServices.\(machServiceName) = true"
            case let .disabledMachService(machServiceName):
                "Helper launchd plist has disabled MachServices.\(machServiceName)"
            case .missingAssociatedBundleIdentifiers:
                "Helper launchd plist is missing AssociatedBundleIdentifiers"
            case let .unexpectedAssociatedBundleIdentifiers(associatedBundleIdentifiers):
                "Helper launchd plist has unexpected AssociatedBundleIdentifiers \(associatedBundleIdentifiers.joined(separator: ", "))"
            case let .unknown(error):
                "Helper launchd plist validation failed: \(String(describing: error))"
            }
        case let .invalidBundledHelperMetadata(validationError):
            switch validationError {
            case .missingInfoDictionary:
                "Bundled helper executable is missing embedded or sidecar Info.plist metadata"
            case let .missingValue(key):
                "Bundled helper metadata is missing \(key)"
            case let .unexpectedValue(key, value):
                "Bundled helper metadata has unexpected \(key) '\(value)'"
            case let .unexpectedAllowedCallerIdentifiers(allowedCallerIdentifiers):
                "Bundled helper metadata has unexpected RockxyAllowedCallerIdentifiers \(allowedCallerIdentifiers.joined(separator: ", "))"
            }
        case .invalidBundledHelperSignature:
            "Bundled helper code signature is invalid or does not match the running app"
        }
    }

    nonisolated private static func normalizedIdentifiers(_ identifiers: [String]) -> [String] {
        Array(
            Set(
                identifiers
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    nonisolated private static func stringValue(forKey key: String, in info: [String: Any]) -> String {
        (info[key] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Resolve every approval transition through the same policy. DerivedData builds
    /// use the development-only legacy LaunchDaemon path; installed app bundles keep
    /// the normal macOS Login Items approval flow.
    private func handleApprovalRequired(
        service: SMAppService,
        reason: String,
        message: String
    )
        async throws
    {
        if Self.shouldUseLegacyInstallFallbackForCurrentBundle() {
            try await installLegacyHelperForXcode(service: service, reason: reason)
            return
        }

        Self.logger.info("Helper registration requires user approval in System Settings")
        status = .requiresApproval
        registrationStatus = "Awaiting Approval"
        lastErrorMessage = message
        SMAppService.openSystemSettingsLoginItems()
    }

    /// `SMAppService` can report `.enabled` while launchd is holding a broken submitted job
    /// after a hard reset or when running directly from Xcode's DerivedData. Install is an
    /// explicit repair action, so it may mutate registration if the enabled service cannot
    /// answer XPC.
    private func verifyEnabledHelperOrRepair(service: SMAppService) async {
        do {
            let info = try await probeHelperInfo()
            installedInfo = info
            isReachable = true
            lastErrorMessage = nil
            status = evaluateCompatibility(info)
        } catch {
            Self.logger.warning("Enabled helper did not answer during install: \(error.localizedDescription)")
            installedInfo = nil
            isReachable = false

            guard Self.shouldUseLegacyInstallFallbackForCurrentBundle() else {
                setUnreachableState(reason: error.localizedDescription)
                return
            }

            do {
                try await installLegacyHelperForXcode(service: service, reason: error.localizedDescription)
            } catch {
                lastErrorMessage = error.localizedDescription
                status = .unreachable
            }
        }
    }

    /// Xcode-run app bundles live in DerivedData. On some macOS versions, `SMAppService.daemon`
    /// can register the embedded LaunchDaemon but launchd fails the system job before the Mach
    /// service becomes usable. For that development-only case, install the same helper identity
    /// into the traditional privileged helper location.
    private func installLegacyHelperForXcode(service: SMAppService, reason: String) async throws {
        Self.logger.warning("Repairing Xcode helper registration via legacy launchd install: \(reason)")

        do {
            try await service.unregister()
        } catch {
            Self.logger
                .warning("Legacy helper repair could not unregister SMAppService job: \(error.localizedDescription)")
        }

        HelperConnection.shared.resetConnection()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let bundledHelperURL = Bundle.main.bundleURL
            .appendingPathComponent(Self.bundledHelperBinaryRelativePath, isDirectory: false)
        let shellScript = Self.legacyInstallShellScript(
            identity: RockxyIdentity.current,
            bundledHelperPath: bundledHelperURL.path
        )
        _ = try await Self.runPrivilegedShellScript(shellScript)

        registrationStatus = "Enabled"
        HelperConnection.shared.invalidateSigningCache()
        HelperConnection.shared.resetConnection()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        do {
            let info = try await probeHelperInfo()
            installedInfo = info
            isReachable = true
            lastErrorMessage = nil
            status = evaluateCompatibility(info)
        } catch {
            setUnreachableState(reason: error.localizedDescription)
            throw error
        }
    }

    /// Xcode fallback installs the same helper identity through a traditional LaunchDaemon.
    /// `SMAppService` does not own that job, so status checks need an artifact-and-XPC path.
    private func checkLegacyLaunchdHelperIfAvailable() async -> Bool {
        guard Self.shouldUseLegacyInstallFallbackForCurrentBundle() else {
            return false
        }

        let identity = RockxyIdentity.current
        let helperPath = Self.legacyInstalledHelperPath(identity: identity)
        let plistPath = Self.legacyLaunchDaemonPlistPath(identity: identity)
        let hasLegacyArtifacts = FileManager.default.fileExists(atPath: helperPath)
            || FileManager.default.fileExists(atPath: plistPath)
        guard hasLegacyArtifacts else {
            return false
        }

        registrationStatus = "Enabled"

        do {
            let info = try await probeHelperInfo()
            installedInfo = info
            isReachable = true
            lastErrorMessage = nil
            status = evaluateCompatibility(info)
        } catch let error as HelperConnectionError {
            let probe = Self.classifyProbeError(error)
            let action = Self.decideRecovery(probe: probe)

            switch action {
            case .surfaceApplicationMustReopen:
                setSigningMismatchState(.applicationMustReopen)

            case let .surfaceAppSignatureInvalid(detail):
                setSigningMismatchState(.appSignatureInvalid(detail: detail))

            case let .surfaceSigningMismatch(app, helper):
                setSigningMismatchState(.identityMismatch(appSigner: app, helperSigner: helper))

            case .surfaceUnreachable:
                setUnreachableState(reason: error.localizedDescription)
            }
        } catch {
            setUnreachableState(reason: error.localizedDescription)
        }

        return true
    }

    /// Handle the case where SMAppService reports the helper as enabled.
    /// Checks XPC reachability, then evaluates protocol-aware compatibility.
    /// Signing-related failures are surfaced immediately without re-registration attempts.
    private func checkEnabledHelper(service _: SMAppService) async {
        do {
            let info = try await probeHelperInfo()
            installedInfo = info
            isReachable = true
            lastErrorMessage = nil
            status = evaluateCompatibility(info)
        } catch let error as HelperConnectionError {
            let probe = Self.classifyProbeError(error)
            let action = Self.decideRecovery(probe: probe)

            switch action {
            case .surfaceApplicationMustReopen:
                setSigningMismatchState(.applicationMustReopen)

            case let .surfaceAppSignatureInvalid(detail):
                setSigningMismatchState(.appSignatureInvalid(detail: detail))

            case let .surfaceSigningMismatch(app, helper):
                setSigningMismatchState(.identityMismatch(appSigner: app, helperSigner: helper))

            case .surfaceUnreachable:
                setUnreachableState(reason: error.localizedDescription)
            }
        } catch {
            setUnreachableState(reason: error.localizedDescription)
        }
    }

    /// Surface XPC failure without mutating macOS Background Items registration.
    private func setUnreachableState(reason: String) {
        Self.logger.warning("Helper registered but not reachable: \(reason)")
        installedInfo = nil
        isReachable = false
        lastErrorMessage = String(
            localized: """
            Helper is registered in macOS but Rockxy could not reach it. \
            Check again, reinstall the helper from the current build, or use Force Reset if macOS Login Items is stuck.
            """, bundle: RockxyLocalization.bundle
        )
        status = .unreachable
    }

    /// Centralized state setter for signing mismatch conditions.
    private func setSigningMismatchState(_ issue: SigningIssue) {
        installedInfo = nil
        isReachable = false
        signingIssue = issue
        switch issue {
        case .applicationMustReopen:
            lastErrorMessage = Self.applicationMustReopenMessage
        case let .appSignatureInvalid(detail):
            Self.logger.error("App signature validation failed: \(detail)")
            lastErrorMessage = String(
                localized: "Rockxy could not verify this app copy. Install a fresh copy of Rockxy, then check the helper again.",
                bundle: RockxyLocalization.bundle
            )
        case let .identityMismatch(app, helper):
            lastErrorMessage = String(
                localized: """
                This app is signed by \u{201C}\(app)\u{201D} but the installed helper expects \
                \u{201C}\(helper)\u{201D}. Reinstall the helper from the current build, \
                or run the matching release version.
                """, bundle: RockxyLocalization.bundle
            )
        }
        status = .signingMismatch
    }

    /// Evaluate helper compatibility through the shared protocol-first policy.
    ///
    /// A helper one protocol behind is reported as outdated rather than incompatible: it still
    /// answers every operation it already implements, so the proxy and certificate-install
    /// paths keep working while the user is prompted to update. Only the protocol version is
    /// ever consulted for capability — see `HelperCompatibilityPolicy`.
    private func evaluateCompatibility(_ info: HelperInfo) -> HelperStatus {
        let decision = HelperCompatibilityPolicy.classify(
            installedProtocolVersion: info.protocolVersion,
            installedBuildNumber: info.buildNumber,
            expectedProtocolVersion: expectedProtocolVersion,
            bundledBuildNumber: bundledHelperBuild
        )

        Self.logger.info(
            "Helper \(String(describing: decision)): installed protocol=\(info.protocolVersion) build=\(info.buildNumber), expected protocol=\(self.expectedProtocolVersion) build=\(self.bundledHelperBuild)"
        )
        return HelperStatus(decision)
    }

    private func probeHelperInfo() async throws -> HelperInfo {
        try await AsyncRetry.retry(
            attempts: Self.helperProbeAttempts,
            delay: Self.helperProbeRetryDelay,
            onRetry: { attempt, error in
                await MainActor.run {
                    Self.logger.info(
                        "Helper probe attempt \(attempt) failed: \(error.localizedDescription), retrying"
                    )
                    HelperConnection.shared.resetConnection()
                }
            }
        ) {
            try await HelperConnection.shared.getHelperInfo()
        }
    }
}

// MARK: - HelperManager.HelperStatus + HelperCompatibilityDecision

extension HelperManager.HelperStatus {
    /// Maps the shared, protocol-first compatibility decision onto the status this manager
    /// publishes. `.outdated` stays reachable on purpose: the operations that helper already
    /// implements remain usable while the update prompt is shown.
    init(_ decision: HelperCompatibilityDecision) {
        switch decision {
        case .compatible:
            self = .installedCompatible
        case .outdated:
            self = .installedOutdated
        case .incompatible:
            self = .installedIncompatible
        }
    }
}
