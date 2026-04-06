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
    }

    enum InstallDisposition: Equatable {
        case register
        case requiresApproval
        case alreadyEnabled
    }

    static let shared = HelperManager()

    private(set) var status: HelperStatus = .notInstalled
    private(set) var installedInfo: HelperInfo?
    private(set) var isReachable: Bool = false
    private(set) var lastErrorMessage: String?
    private(set) var isBusy: Bool = false
    private(set) var registrationStatus: String = "Unknown"

    var bundledHelperVersion: String {
        Bundle.main.infoDictionary?["RockxyBundledHelperVersion"] as? String ?? "0.0.0"
    }

    var bundledHelperBuild: Int {
        Int(Bundle.main.infoDictionary?["RockxyBundledHelperBuild"] as? String ?? "0") ?? 0
    }

    var expectedProtocolVersion: Int {
        Int(Bundle.main.infoDictionary?["RockxyHelperProtocolVersion"] as? String ?? "0") ?? 0
    }

    /// Register the helper daemon via SMAppService.
    ///
    /// On macOS 13+, this uses `SMAppService.daemon(plistName:).register()` which
    /// requires user approval in System Settings > Login Items.
    func install() async throws {
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo
            )
        }
        try performInstall()
        if status != .requiresApproval {
            await performCheckStatus()
        }
    }

    /// Uninstall the helper by preparing it via XPC, then unregistering from launchd.
    func uninstall() async throws {
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo
            )
        }
        try await performUninstall()
    }

    /// Check whether the helper is installed, responding, and at the correct version.
    func checkStatus() async {
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo
            )
        }
        await performCheckStatus()
    }

    /// Update the helper by uninstalling the old version and installing the new one.
    /// After unregistering, BTM trust is cleared so re-registration may require
    /// user approval in System Settings > Login Items.
    func update() async throws {
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo
            )
        }

        Self.logger.info("Updating helper tool")
        do {
            try await performUninstall()
            try? await Task.sleep(nanoseconds: 500_000_000)
            do {
                try performInstall()
            } catch {
                Self.logger.warning("Re-registration needs approval: \(error.localizedDescription)")
                status = .requiresApproval
                SMAppService.openSystemSettingsLoginItems()
                return
            }
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
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo
            )
        }
        HelperConnection.shared.resetConnection()
        await performCheckStatus()
    }

    /// Reinstall the helper by uninstalling, then installing fresh.
    func reinstall() async throws {
        let previousStatus = status
        let previousReachable = isReachable
        let previousInfo = installedInfo
        lastErrorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            postStatusChangeIfNeeded(
                previousStatus: previousStatus,
                previousReachable: previousReachable,
                previousInfo: previousInfo
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

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperManager"
    )
    private static let plistName = RockxyIdentity.current.helperPlistName
    nonisolated private static let helperApprovalMessage = String(
        localized: "Approve the helper tool in System Settings > Login Items to finish installation."
    )
    private static let helperProbeAttempts = 3
    private static let helperProbeRetryDelay = Duration.milliseconds(750)

    private func postStatusChangeIfNeeded(
        previousStatus: HelperStatus,
        previousReachable: Bool,
        previousInfo: HelperInfo?
    ) {
        let changed = status != previousStatus
            || isReachable != previousReachable
            || installedInfo != previousInfo
        if changed {
            NotificationCenter.default.post(name: .helperStatusChanged, object: nil)
        }
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

    /// Core install logic without busy/error wrapper.
    private func performInstall() throws {
        Self.logger.info("Installing helper tool")
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
    /// Best-effort heuristic: XPC call failure → `.installedIncompatible`,
    /// connection failure → `.unreachable`.
    private func checkEnabledHelper(service: SMAppService) async {
        do {
            let info = try await probeHelperInfo()
            installedInfo = info
            isReachable = true
            lastErrorMessage = nil
            status = evaluateCompatibility(info)
        } catch {
            Self.logger.info(
                "Helper registered but not responding (\(error.localizedDescription)) — attempting re-registration"
            )
            do {
                try await service.unregister()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                try service.register()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                HelperConnection.shared.resetConnection()

                do {
                    let info = try await probeHelperInfo()
                    installedInfo = info
                    isReachable = true
                    lastErrorMessage = nil
                    status = evaluateCompatibility(info)
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
}
