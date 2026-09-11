import AppKit
import os
import ServiceManagement
import SwiftUI

/// Advanced settings covering proxy helper tool management and miscellaneous behavioral toggles.
///
/// ## Settings Wiring Status
///
/// | Key                    | Wired? | Consumer                          |
/// |------------------------|--------|-----------------------------------|
/// | showAlertOnQuit        | WIRED  | AppDelegate.applicationShouldTerminate |
struct AdvancedSettingsTab: View {
    // MARK: Internal

    var body: some View {
        SettingsPane {
            SettingsSection(String(localized: "System Proxy", bundle: RockxyLocalization.bundle)) {
                settingsRow(label: String(localized: "Proxy Helper Tool:", bundle: RockxyLocalization.bundle)) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Zone A: Summary
                        HStack(spacing: 8) {
                            Image(systemName: helperStatusIcon)
                                .foregroundStyle(helperStatusColor)
                                .font(.system(size: max(16, settingsMetrics.bodyFontSize + 3)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(helperStatusText)
                                    .font(settingsMetrics.font(weight: .medium))
                                Text(helperStatusSubtitle)
                                    .font(settingsMetrics.secondaryFont())
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        // Zone B: Diagnostics
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                            GridRow {
                                Text(String(localized: "Bundled:", bundle: RockxyLocalization.bundle))
                                    .font(settingsMetrics.secondaryFont())
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                                Text(helperManager.bundledHelperVersion)
                                    .font(settingsMetrics.secondaryFont(monospaced: true))
                            }
                            GridRow {
                                Text(String(localized: "Installed:", bundle: RockxyLocalization.bundle))
                                    .font(settingsMetrics.secondaryFont())
                                    .foregroundStyle(.secondary)
                                Text(helperManager.installedInfo?.binaryVersion ?? "\u{2014}")
                                    .font(settingsMetrics.secondaryFont(monospaced: true))
                                    .foregroundStyle(installedVersionColor)
                            }
                            GridRow {
                                Text(String(localized: "Registration:", bundle: RockxyLocalization.bundle))
                                    .font(settingsMetrics.secondaryFont())
                                    .foregroundStyle(.secondary)
                                Text(helperManager.registrationStatus)
                                    .font(settingsMetrics.secondaryFont())
                                    .foregroundStyle(registrationColor)
                            }
                            GridRow {
                                Text(String(localized: "XPC:", bundle: RockxyLocalization.bundle))
                                    .font(settingsMetrics.secondaryFont())
                                    .foregroundStyle(.secondary)
                                Text(
                                    helperManager.status == .notInstalled
                                        ? "\u{2014}"
                                        : (helperManager.isReachable
                                            ? String(localized: "Reachable", bundle: RockxyLocalization.bundle)
                                            : String(localized: "Unreachable", bundle: RockxyLocalization.bundle))
                                )
                                .font(settingsMetrics.secondaryFont())
                                .foregroundStyle(xpcColor)
                            }
                        }

                        // Error detail
                        if let errorMessage = helperManager.lastErrorMessage {
                            Text(errorMessage)
                                .font(settingsMetrics.metadataFont(monospaced: true))
                                .foregroundStyle(.red)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        // Zone C: Actions
                        HStack(spacing: 8) {
                            if helperManager.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            switch helperManager.status {
                            case .notInstalled:
                                Button(String(localized: "Install Helper", bundle: RockxyLocalization.bundle)) {
                                    installHelper()
                                }
                                .disabled(helperManager.isBusy)
                            case .requiresApproval:
                                Button(String(localized: "Open System Settings", bundle: RockxyLocalization.bundle)) {
                                    SMAppService.openSystemSettingsLoginItems()
                                }
                                .disabled(helperManager.isBusy)
                                Button(String(localized: "Check Again", bundle: RockxyLocalization.bundle)) {
                                    Task { await helperManager.checkStatus() }
                                }
                                .disabled(helperManager.isBusy)
                            case .installedCompatible:
                                Button(String(localized: "Check Again", bundle: RockxyLocalization.bundle)) {
                                    Task { await helperManager.checkStatus() }
                                }
                                .disabled(helperManager.isBusy)
                                Button(String(localized: "Uninstall", bundle: RockxyLocalization.bundle)) {
                                    showUninstallConfirmation = true
                                }
                                .disabled(helperManager.isBusy)
                            case .installedOutdated:
                                Button(String(localized: "Update Helper", bundle: RockxyLocalization.bundle)) {
                                    updateHelper()
                                }
                                .disabled(helperManager.isBusy)
                                Button(String(localized: "Uninstall", bundle: RockxyLocalization.bundle)) {
                                    showUninstallConfirmation = true
                                }
                                .disabled(helperManager.isBusy)
                            case .installedIncompatible:
                                Button(String(localized: "Check Again", bundle: RockxyLocalization.bundle)) {
                                    Task { await helperManager.checkStatus() }
                                }
                                .disabled(helperManager.isBusy)
                            case .unreachable:
                                if helperManager.automaticRefreshRecoveryPending {
                                    Button(String(
                                        localized: "Retry Automatic Update",
                                        bundle: RockxyLocalization.bundle
                                    )) {
                                        Task { await helperManager.reconcileEmbeddedHelperOnLaunch() }
                                    }
                                    .disabled(helperManager.isBusy)
                                } else {
                                    Button(String(localized: "Retry Connection", bundle: RockxyLocalization.bundle)) {
                                        Task { await helperManager.retryConnection() }
                                    }
                                    .disabled(helperManager.isBusy)
                                    Button(String(localized: "Reinstall", bundle: RockxyLocalization.bundle)) {
                                        reinstallHelper()
                                    }
                                    .disabled(helperManager.isBusy)
                                }
                                Button(String(localized: "Uninstall", bundle: RockxyLocalization.bundle)) {
                                    showUninstallConfirmation = true
                                }
                                .disabled(helperManager.isBusy)
                            case .signingMismatch:
                                if case .applicationMustReopen = helperManager.signingIssue {
                                    Button(String(localized: "Quit Rockxy", bundle: RockxyLocalization.bundle)) {
                                        HelperRecoveryPresenter.requestRequiredReopen()
                                    }
                                } else if case .identityMismatch = helperManager.signingIssue {
                                    Button(String(localized: "Reinstall Helper", bundle: RockxyLocalization.bundle)) {
                                        reinstallHelper()
                                    }
                                    .disabled(helperManager.isBusy)
                                    Button(String(localized: "Uninstall", bundle: RockxyLocalization.bundle)) {
                                        showUninstallConfirmation = true
                                    }
                                    .disabled(helperManager.isBusy)
                                } else {
                                    Button(String(localized: "Check Again", bundle: RockxyLocalization.bundle)) {
                                        Task { await helperManager.checkStatus() }
                                    }
                                    .disabled(helperManager.isBusy)
                                }
                            }

                            if helperManager.signingIssue != .applicationMustReopen,
                               !helperManager.automaticRefreshRecoveryPending
                            {
                                Button(role: .destructive) {
                                    HelperRecoveryPresenter.presentForceReset()
                                } label: {
                                    Text(String(localized: "Force Reset…", bundle: RockxyLocalization.bundle))
                                }
                                .disabled(helperManager.isBusy)
                            }
                        }
                    }
                }
            }

            SettingsSection(String(localized: "Software Update", bundle: RockxyLocalization.bundle)) {
                updatesSection
            }

            SettingsSection(String(localized: "Behavior", bundle: RockxyLocalization.bundle)) {
                checkboxRow(
                    title: String(localized: "Show alert when quitting Rockxy", bundle: RockxyLocalization.bundle),
                    isOn: $showAlertOnQuit
                )
            }
        }
        .task {
            await helperManager.checkStatus()
        }
        .alert(
            String(localized: "Uninstall Helper Tool?", bundle: RockxyLocalization.bundle),
            isPresented: $showUninstallConfirmation
        ) {
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {}
            Button(String(localized: "Uninstall", bundle: RockxyLocalization.bundle), role: .destructive) {
                uninstallHelper()
            }
        } message: {
            Text(
                String(
                    localized: "The proxy helper tool will be removed. You may be prompted for your password when changing proxy settings.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
        .font(settingsMetrics.font())
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "AdvancedSettingsTab")

    @State private var helperManager = HelperManager.shared
    @State private var showUninstallConfirmation = false
    @ObservedObject private var updater = AppUpdater.shared
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    @AppStorage(RockxyIdentity.current.defaultsKey("showAlertOnQuit")) private var showAlertOnQuit =
        true // WIRED: AppDelegate.applicationShouldTerminate

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    // MARK: - Helper Tool Status

    private var helperStatusIcon: String {
        switch helperManager.status {
        case .notInstalled:
            "circle"
        case .requiresApproval:
            "exclamationmark.triangle.fill"
        case .installedCompatible:
            "checkmark.circle.fill"
        case .installedOutdated,
             .installedIncompatible:
            "arrow.triangle.2.circlepath.circle.fill"
        case .unreachable:
            "xmark.circle.fill"
        case .signingMismatch:
            if case .applicationMustReopen = helperManager.signingIssue {
                "arrow.clockwise.circle.fill"
            } else if case .appSignatureInvalid = helperManager.signingIssue {
                "xmark.seal.fill"
            } else {
                "exclamationmark.triangle.fill"
            }
        }
    }

    private var helperStatusColor: Color {
        switch helperManager.status {
        case .notInstalled:
            .secondary
        case .requiresApproval:
            .orange
        case .installedCompatible:
            .green
        case .installedOutdated,
             .installedIncompatible:
            .yellow
        case .unreachable:
            .red
        case .signingMismatch:
            if case .applicationMustReopen = helperManager.signingIssue {
                .orange
            } else if case .appSignatureInvalid = helperManager.signingIssue {
                .red
            } else {
                .orange
            }
        }
    }

    private var helperStatusText: String {
        switch helperManager.status {
        case .notInstalled:
            String(localized: "Not Installed", bundle: RockxyLocalization.bundle)
        case .requiresApproval:
            String(localized: "Requires Approval", bundle: RockxyLocalization.bundle)
        case .installedCompatible:
            String(localized: "Installed", bundle: RockxyLocalization.bundle)
        case .installedOutdated:
            String(localized: "Update Available", bundle: RockxyLocalization.bundle)
        case .installedIncompatible:
            String(localized: "Incompatible Version", bundle: RockxyLocalization.bundle)
        case .unreachable:
            String(localized: "Unreachable", bundle: RockxyLocalization.bundle)
        case .signingMismatch:
            if case .applicationMustReopen = helperManager.signingIssue {
                String(localized: "Reopen Required", bundle: RockxyLocalization.bundle)
            } else if case .appSignatureInvalid = helperManager.signingIssue {
                String(localized: "Invalid App Signature", bundle: RockxyLocalization.bundle)
            } else {
                String(localized: "Signing Mismatch", bundle: RockxyLocalization.bundle)
            }
        }
    }

    private var registrationColor: Color {
        switch helperManager.registrationStatus {
        case "Enabled": .green
        case "Awaiting Approval": .orange
        default: .secondary
        }
    }

    private var xpcColor: Color {
        if helperManager.status == .notInstalled {
            return .secondary
        }
        return helperManager.isReachable ? .green : .red
    }

    private var installedVersionColor: Color {
        guard helperManager.installedInfo?.binaryVersion != nil else {
            return .secondary
        }
        return helperManager.status == .installedCompatible ? .primary : .orange
    }

    private var helperStatusSubtitle: String {
        switch helperManager.status {
        case .notInstalled:
            String(
                localized: "Rockxy will use networksetup and may ask for your password.",
                bundle: RockxyLocalization.bundle
            )
        case .requiresApproval:
            String(
                localized: "Approve Rockxy Helper in System Settings \u{2192} General \u{2192} Login Items.",
                bundle: RockxyLocalization.bundle
            )
        case .installedCompatible:
            String(
                localized: "Helper is responding and supports this app's required operations.",
                bundle: RockxyLocalization.bundle
            )
        case .installedOutdated:
            String(
                localized: "Installed helper version is outdated and should be updated.",
                bundle: RockxyLocalization.bundle
            )
        case .installedIncompatible:
            String(
                localized: "Installed helper version is incompatible with this app.",
                bundle: RockxyLocalization.bundle
            )
        case .unreachable:
            String(
                localized: "Rockxy could not communicate with the helper over XPC.",
                bundle: RockxyLocalization.bundle
            )
        case .signingMismatch:
            helperManager.lastErrorMessage
                ?? String(
                    localized: "The app and helper have mismatched signing certificates.",
                    bundle: RockxyLocalization.bundle
                )
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: updater.supportsManualChecks ? "checkmark.shield.fill" : "icloud.slash")
                        .font(.system(size: max(16, settingsMetrics.bodyFontSize + 3)))
                        .foregroundStyle(updater.supportsManualChecks ? Color.accentColor : Color.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Update Controls", bundle: RockxyLocalization.bundle))
                            .font(settingsMetrics.font(weight: .medium))
                        Text(updater.updateAvailabilitySummary)
                            .font(settingsMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text(String(localized: "Current:", bundle: RockxyLocalization.bundle))
                            .font(settingsMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                        Text(updater.currentVersionSummary)
                            .font(settingsMetrics.secondaryFont(monospaced: true))
                    }
                    GridRow {
                        Text(String(localized: "Last Checked:", bundle: RockxyLocalization.bundle))
                            .font(settingsMetrics.secondaryFont())
                            .foregroundStyle(.secondary)
                        Text(updater.lastCheckedDescription)
                            .font(settingsMetrics.secondaryFont())
                    }
                }
            }

            HStack(spacing: 10) {
                Button(String(localized: "Check for Updates…", bundle: RockxyLocalization.bundle)) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canInitiateUpdateCheck)

                Button(String(localized: "Change Logs…", bundle: RockxyLocalization.bundle)) {
                    updater.openFullChangelog()
                }

                if updater.sessionInProgress {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Toggle(
                String(localized: "Automatically check for updates", bundle: RockxyLocalization.bundle),
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .toggleStyle(.checkbox)
            .disabled(!updater.supportsAutomaticChecks)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    String(
                        localized: "Automatically download updates in the background",
                        bundle: RockxyLocalization.bundle
                    ),
                    isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticallyDownloadsUpdates($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(
                    !updater.supportsAutomaticChecks
                        || !updater.automaticallyChecksForUpdates
                        || !updater.allowsAutomaticUpdates
                )

                Text(
                    String(
                        localized: "When enabled, Rockxy downloads signed updates ahead of time so install prompts are faster.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            SettingsFieldRow(String(localized: "Check Frequency", bundle: RockxyLocalization.bundle)) {
                Picker(
                    String(localized: "Check Frequency", bundle: RockxyLocalization.bundle),
                    selection: Binding(
                        get: { UpdateCheckIntervalOption.closest(to: updater.updateCheckInterval) },
                        set: { updater.setUpdateCheckInterval($0.rawValue) }
                    )
                ) {
                    ForEach(UpdateCheckIntervalOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: settingsMetrics.menuWidth(180))
                .disabled(!updater.supportsAutomaticChecks || !updater.automaticallyChecksForUpdates)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    String(localized: "Send anonymous compatibility profile", bundle: RockxyLocalization.bundle),
                    isOn: Binding(
                        get: { updater.sendsSystemProfile },
                        set: { updater.setSendsSystemProfile($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(!updater.supportsAutomaticChecks)

                Text(
                    String(
                        localized: """
                        This shares basic macOS and hardware compatibility details with Sparkle so Rockxy can match the right update. It does not include captured traffic.
                        """, bundle: RockxyLocalization.bundle
                    )
                )
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsRow(
        label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        SettingsFieldRow(label) {
            content()
        }
    }

    private func checkboxRow(title: String, isOn: Binding<Bool>) -> some View {
        SettingsIndentedContent {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
        }
    }

    // MARK: - Helper Tool Actions

    private func installHelper() {
        Task {
            do {
                try await helperManager.install()
            } catch {
                Self.logger.error("Failed to install helper: \(error.localizedDescription)")
            }
        }
    }

    private func uninstallHelper() {
        Task {
            do {
                try await helperManager.uninstall()
            } catch {
                Self.logger.error("Failed to uninstall helper: \(error.localizedDescription)")
            }
        }
    }

    private func updateHelper() {
        Task {
            do {
                try await helperManager.update()
            } catch {
                Self.logger.error("Failed to update helper: \(error.localizedDescription)")
            }
        }
    }

    private func reinstallHelper() {
        Task {
            do {
                try await helperManager.reinstall()
            } catch {
                Self.logger.error("Failed to reinstall helper: \(error.localizedDescription)")
            }
        }
    }
}
