import Foundation
import os
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
        case appSignatureInvalid(detail: String)
        case identityMismatch(appSigner: String, helperSigner: String)
    }

    /// Normalized result from a helper info probe, scoped to the actual error surface.
    enum ProbeOutcome: Equatable {
        case appSignatureInvalid(detail: String)
        case signingIdentityMismatch(appSigner: String, helperSigner: String)
        case xpcFailure
    }

    /// Recovery action determined from a probe outcome.
    enum RecoveryAction: Equatable {
        case surfaceAppSignatureInvalid(detail: String)
        case surfaceSigningMismatch(appSigner: String, helperSigner: String)
        case attemptReRegistration
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
        case unknown(Error)

        static func == (lhs: HelperPlistValidationError, rhs: HelperPlistValidationError) -> Bool {
            switch (lhs, rhs) {
            case (.malformedPlist, .malformedPlist),
                 (.missingLabel, .missingLabel),
                 (.missingBundleProgram, .missingBundleProgram),
                 (.missingMachServices, .missingMachServices):
                return true
            case let (.unexpectedLabel(lhsLabel), .unexpectedLabel(rhsLabel)):
                return lhsLabel == rhsLabel
            case let (.unexpectedBundleProgram(lhsProgram), .unexpectedBundleProgram(rhsProgram)):
                return lhsProgram == rhsProgram
            case let (.missingMachService(lhsService), .missingMachService(rhsService)):
                return lhsService == rhsService
            case let (.disabledMachService(lhsService), .disabledMachService(rhsService)):
                return lhsService == rhsService
            case let (.unknown(lhsError), .unknown(rhsError)):
                return String(describing: lhsError) == String(describing: rhsError)
            default:
                return false
            }
        }
    }

    enum HelperInstallPreflightError: LocalizedError, Equatable {
        case missingBundledHelperBinary(path: String)
        case missingBundledLaunchdPlist(path: String)
        case unreadableBundledLaunchdPlist(path: String)
        case invalidBundledLaunchdPlist(HelperPlistValidationError)

        var errorDescription: String? {
            HelperManager.helperPackageIncompleteMessage
        }
    }

    static let shared = HelperManager()

    private(set) var signingIssue: SigningIssue?
    private(set) var installedInfo: HelperInfo?
    private(set) var isReachable: Bool = false
    private(set) var lastErrorMessage: String?
    private(set) var isBusy: Bool = false
    private(set) var registrationStatus: String = "Unknown"

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
        expectedMachServiceName: String
    ) throws {
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
    }

    nonisolated static func validateBundledHelperInstallResources(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws {
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
              fileManager.isExecutableFile(atPath: helperBinaryURL.path)
        else {
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
                expectedMachServiceName: identity.helperMachServiceName
            )
        } catch let validationError as HelperPlistValidationError {
            throw HelperInstallPreflightError.invalidBundledLaunchdPlist(validationError)
        } catch {
            throw HelperInstallPreflightError.invalidBundledLaunchdPlist(.unknown(error))
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
                """
            )
        }

        return helperApprovalMessage
    }

    /// Classify a probe-path `HelperConnectionError` into a normalized outcome.
    /// Only maps the error cases that actually occur on the probe path
    /// (`getProxy()` → `getHelperInfo()`).
    nonisolated static func classifyProbeError(_ error: HelperConnectionError) -> ProbeOutcome {
        switch error {
        case let .appSignatureInvalid(detail):
            .appSignatureInvalid(detail: detail)
        case let .signingIdentityMismatch(app, helper):
            .signingIdentityMismatch(appSigner: app, helperSigner: helper)
        default:
            .xpcFailure
        }
    }

    /// Determine recovery action from a normalized probe outcome.
    nonisolated static func decideRecovery(probe: ProbeOutcome) -> RecoveryAction {
        switch probe {
        case let .appSignatureInvalid(detail):
            .surfaceAppSignatureInvalid(detail: detail)
        case let .signingIdentityMismatch(app, helper):
            .surfaceSigningMismatch(appSigner: app, helperSigner: helper)
        case .xpcFailure:
            .attemptReRegistration
        }
    }

    /// Action label for the helper step in Welcome and Settings views.
    /// Returns `nil` when no action button should be shown.
    nonisolated static func helperActionLabel(
        status: HelperStatus,
        signingIssue: SigningIssue?
    )
        -> String?
    {
        switch status {
        case .installedCompatible:
            nil
        case .installedOutdated,
             .installedIncompatible:
            String(localized: "Update")
        case .notInstalled:
            String(localized: "Install")
        case .requiresApproval:
            String(localized: "Open Settings")
        case .unreachable:
            String(localized: "Retry")
        case .signingMismatch:
            switch signingIssue {
            case .appSignatureInvalid:
                nil
            case .identityMismatch:
                String(localized: "Reinstall")
            case nil:
                nil
            }
        }
    }

    /// Warning reason text for the signing mismatch case in readiness warnings.
    nonisolated static func signingMismatchWarningReason(issue: SigningIssue?) -> String {
        switch issue {
        case .appSignatureInvalid:
            String(
                localized: "this app build has an invalid code signature \u{2014} clean the build folder and rebuild"
            )
        case .identityMismatch:
            String(
                localized: "the installed helper was signed by a different Rockxy build \u{2014} reinstall it from the current build"
            )
        case nil:
            String(localized: "the helper tool has a signing issue")
        }
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
        try performInstall()
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

    /// Update the helper by uninstalling the old version and installing the new one.
    /// After unregistering, BTM trust is cleared so re-registration may require
    /// user approval in System Settings > Login Items.
    func update() async throws {
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

        Self.logger.info("Updating helper tool")
        do {
            try await performUninstall()
            try? await Task.sleep(nanoseconds: 500_000_000)
            try performInstall()
            if status != .requiresApproval {
                await performCheckStatus()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
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
            try await performUninstall()
            try performInstall()
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
            try performInstall()
            if status != .requiresApproval {
                await performCheckStatus()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
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

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperManager"
    )
    private static let plistName = RockxyIdentity.current.helperPlistName
    nonisolated private static let bundledHelperBinaryRelativePath = "Contents/Library/HelperTools/RockxyHelperTool"
    nonisolated private static let helperApprovalMessage = String(
        localized: "Approve the helper tool in System Settings > Login Items to finish installation."
    )
    nonisolated private static let helperPackageIncompleteMessage = String(
        localized: """
        This Rockxy app package is incomplete, so the helper tool cannot be installed. \
        Reinstall the latest Rockxy release. If you installed Rockxy from Homebrew, \
        reinstall it after the fixed release is published.
        """
    )
    private static let helperProbeAttempts = 3
    private static let helperProbeRetryDelay = Duration.milliseconds(750)

    nonisolated private static func bundledHelperPlistRelativePath(plistName: String) -> String {
        "Contents/Library/LaunchDaemons/\(plistName)"
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
            case let .unknown(error):
                "Helper launchd plist validation failed: \(String(describing: error))"
            }
        }
    }

    private func postStatusChangeIfNeeded(
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
    private func performInstall() throws {
        Self.logger.info("Installing helper tool")
        do {
            try Self.validateBundledHelperInstallResources()
        } catch let error as HelperInstallPreflightError {
            Self.logger.error("Bundled helper install preflight failed: \(Self.helperPreflightFailureReason(error), privacy: .private)")
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
            Self.logger.info("Helper already registered and awaiting user approval")
            status = .requiresApproval
            registrationStatus = "Awaiting Approval"
            lastErrorMessage = Self.helperApprovalMessage
            SMAppService.openSystemSettingsLoginItems()
            return
        case .alreadyEnabled:
            Self.logger.info("Helper tool is already registered")
            registrationStatus = "Enabled"
            lastErrorMessage = nil
            return
        case .register:
            break
        }

        do {
            try service.register()
        } catch {
            if Self.requiresApproval(error: error, serviceStatus: service.status) {
                Self.logger.info("Helper registration requires user approval in System Settings")
                status = .requiresApproval
                registrationStatus = "Awaiting Approval"
                lastErrorMessage = Self.approvalMessage(error: error, serviceStatus: service.status)
                SMAppService.openSystemSettingsLoginItems()
                return
            }

            lastErrorMessage = error.localizedDescription
            throw error
        }

        let currentStatus = service.status
        if currentStatus == .requiresApproval {
            Self.logger.info("Helper requires user approval in System Settings")
            status = .requiresApproval
            registrationStatus = "Awaiting Approval"
            lastErrorMessage = Self.helperApprovalMessage
            SMAppService.openSystemSettingsLoginItems()
        } else if currentStatus == .enabled {
            Self.logger.info("Helper tool installed and enabled")
            registrationStatus = "Enabled"
            lastErrorMessage = nil
            status = .installedCompatible
        } else {
            Self.logger.warning(
                "Unexpected SMAppService status after register: \(String(describing: currentStatus))"
            )
            status = .notInstalled
        }
    }

    /// Core uninstall logic without busy/error wrapper.
    private func performUninstall() async throws {
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
    private func performCheckStatus() async {
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
            status = .requiresApproval
        case .notRegistered,
             .notFound:
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

    /// Handle the case where SMAppService reports the helper as enabled.
    /// Checks XPC reachability, then evaluates protocol-aware compatibility.
    /// Signing-related failures are surfaced immediately without re-registration attempts.
    private func checkEnabledHelper(service: SMAppService) async {
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
            case let .surfaceAppSignatureInvalid(detail):
                setSigningMismatchState(.appSignatureInvalid(detail: detail))
                return

            case let .surfaceSigningMismatch(app, helper):
                setSigningMismatchState(.identityMismatch(appSigner: app, helperSigner: helper))
                return

            case .attemptReRegistration:
                Self.logger.info(
                    "Helper registered but not responding (\(error.localizedDescription)) — attempting re-registration"
                )
                do {
                    guard try await reRegister(service: service) else {
                        return
                    }
                    do {
                        let info = try await probeHelperInfo()
                        installedInfo = info
                        isReachable = true
                        lastErrorMessage = nil
                        status = evaluateCompatibility(info)
                    } catch let retryError as HelperConnectionError {
                        let retryProbe = Self.classifyProbeError(retryError)
                        let retryAction = Self.decideRecovery(probe: retryProbe)
                        switch retryAction {
                        case let .surfaceAppSignatureInvalid(detail):
                            setSigningMismatchState(.appSignatureInvalid(detail: detail))
                        case let .surfaceSigningMismatch(app, helper):
                            setSigningMismatchState(.identityMismatch(appSigner: app, helperSigner: helper))
                        case .attemptReRegistration:
                            Self.logger.warning(
                                "Helper still not responding after re-registration: \(retryError.localizedDescription)"
                            )
                            installedInfo = nil
                            isReachable = false
                            lastErrorMessage = String(
                                localized: "Helper is installed but incompatible or unreachable. Try reinstalling the helper tool."
                            )
                            status = .installedIncompatible
                        }
                    } catch {
                        Self.logger.warning(
                            "Helper still not responding after re-registration: \(error.localizedDescription)"
                        )
                        installedInfo = nil
                        isReachable = false
                        lastErrorMessage = String(
                            localized: "Helper is installed but incompatible or unreachable. Try reinstalling the helper tool."
                        )
                        status = .installedIncompatible
                    }
                } catch {
                    Self.logger.warning("Re-registration failed: \(error.localizedDescription)")
                    installedInfo = nil
                    isReachable = false
                    lastErrorMessage = error.localizedDescription
                    status = .unreachable
                }
            }
        } catch {
            Self.logger.info(
                "Helper registered but not responding (\(error.localizedDescription)) — attempting re-registration"
            )
            do {
                guard try await reRegister(service: service) else {
                    return
                }
                let info = try await probeHelperInfo()
                installedInfo = info
                isReachable = true
                lastErrorMessage = nil
                status = evaluateCompatibility(info)
            } catch {
                Self.logger.warning("Re-registration failed: \(error.localizedDescription)")
                installedInfo = nil
                isReachable = false
                lastErrorMessage = error.localizedDescription
                status = .unreachable
            }
        }
    }

    /// Centralized state setter for signing mismatch conditions.
    private func setSigningMismatchState(_ issue: SigningIssue) {
        installedInfo = nil
        isReachable = false
        signingIssue = issue
        switch issue {
        case let .appSignatureInvalid(detail):
            lastErrorMessage = String(
                localized: """
                This app build has an invalid code signature (\(detail)). \
                Clean the build folder (Product \u{2192} Clean Build Folder) and rebuild, \
                or use the release version of Rockxy.
                """
            )
        case let .identityMismatch(app, helper):
            lastErrorMessage = String(
                localized: """
                This app is signed by \u{201C}\(app)\u{201D} but the installed helper expects \
                \u{201C}\(helper)\u{201D}. Reinstall the helper from the current build, \
                or run the matching release version.
                """
            )
        }
        status = .signingMismatch
    }

    /// Attempt to re-register the helper via SMAppService, handling the case where
    /// the new registration requires Login Items approval. Returns `true` if the
    /// service is now enabled and probing should proceed, or `false` if approval is
    /// required and the caller should stop the retry path.
    private func reRegister(service: SMAppService) async throws -> Bool {
        try await service.unregister()
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        do {
            try service.register()
        } catch {
            if Self.requiresApproval(error: error, serviceStatus: service.status) {
                Self.logger.info("Re-registration requires user approval in System Settings")
                status = .requiresApproval
                registrationStatus = "Awaiting Approval"
                lastErrorMessage = Self.approvalMessage(error: error, serviceStatus: service.status)
                SMAppService.openSystemSettingsLoginItems()
                return false
            }
            throw error
        }

        let currentStatus = service.status
        if currentStatus == .requiresApproval {
            Self.logger.info("Re-registered helper requires user approval in System Settings")
            status = .requiresApproval
            registrationStatus = "Awaiting Approval"
            lastErrorMessage = Self.helperApprovalMessage
            SMAppService.openSystemSettingsLoginItems()
            return false
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        HelperConnection.shared.resetConnection()
        return true
    }

    /// Evaluate helper compatibility based on protocol version and build number.
    private func evaluateCompatibility(_ info: HelperInfo) -> HelperStatus {
        guard info.protocolVersion == expectedProtocolVersion else {
            Self.logger.info(
                "Helper protocol mismatch: installed=\(info.protocolVersion) expected=\(self.expectedProtocolVersion)"
            )
            return .installedIncompatible
        }
        if info.buildNumber >= bundledHelperBuild {
            return .installedCompatible
        }
        Self.logger.info(
            "Helper outdated: installed build=\(info.buildNumber) bundled=\(self.bundledHelperBuild)"
        )
        return .installedOutdated
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
