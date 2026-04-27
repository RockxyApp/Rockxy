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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsRow(label: String(localized: "Proxy Helper Tool:")) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Zone A: Summary
                        HStack(spacing: 8) {
                            Image(systemName: helperStatusIcon)
                                .foregroundStyle(helperStatusColor)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(helperStatusText)
                                    .font(.system(size: 13, weight: .medium))
                                Text(helperStatusSubtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Zone B: Diagnostics
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                            GridRow {
                                Text(String(localized: "Bundled:"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                                Text(helperManager.bundledHelperVersion)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            GridRow {
                                Text(String(localized: "Installed:"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(helperManager.installedInfo?.binaryVersion ?? "\u{2014}")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(installedVersionColor)
                            }
                            GridRow {
                                Text(String(localized: "Registration:"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(helperManager.registrationStatus)
                                    .font(.system(size: 11))
                                    .foregroundStyle(registrationColor)
                            }
                            GridRow {
                                Text(String(localized: "XPC:"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(
                                    helperManager.status == .notInstalled
                                        ? "\u{2014}"
                                        : (helperManager.isReachable
                                            ? String(localized: "Reachable")
                                            : String(localized: "Unreachable"))
                                )
                                .font(.system(size: 11))
                                .foregroundStyle(xpcColor)
                            }
                        }

                        // Error detail
                        if let errorMessage = helperManager.lastErrorMessage {
                            Text(errorMessage)
                                .font(.system(size: 10, design: .monospaced))
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
                                Button(String(localized: "Install Helper")) {
                                    installHelper()
                                }
                                .disabled(helperManager.isBusy)
                            case .requiresApproval:
                                Button(String(localized: "Open System Settings")) {
                                    SMAppService.openSystemSettingsLoginItems()
                                }
                                .disabled(helperManager.isBusy)
                                Button(String(localized: "Check Again")) {
                                    Task { await helperManager.checkStatus() }
                                }
                                .disabled(helperManager.isBusy)
                                Button(String(localized: "Reset Registration")) {
                                    Task {
                                        do {
                                            try await helperManager.forceResetRegistration()
                                        } catch {
                                            Self.logger.error(
                                                "Failed to force-reset helper: \(error.localizedDescription)"
                                            )
                                        }
                                    }
                                }
                                .disabled(helperManager.isBusy)
                            case .installedCompatible:
                                Button(String(localized: "Check Again")) {
                                    Task { await helperManager.checkStatus() }
                                }
                                .disabled(helperManager.isBusy)
                                Button(String(localized: "Uninstall")) {
                                    showUninstallConfirmation = true
                                }
                                .disabled(helperManager.isBusy)
                            case .installedOutdated,
                                 .installedIncompatible:
                                Button(String(localized: "Update Helper")) {
                                    updateHelper()
                                }
                                .disabled(helperManager.isBusy)
                                Button(String(localized: "Uninstall")) {
                                    showUninstallConfirmation = true
                                }
                                .disabled(helperManager.isBusy)
                            case .unreachable:
                                Button(String(localized: "Retry Connection")) {
                                    Task { await helperManager.retryConnection() }
                                }
                                .disabled(helperManager.isBusy)
                                Button(String(localized: "Reinstall")) {
                                    reinstallHelper()
                                }
                                .disabled(helperManager.isBusy)
                                Button(String(localized: "Uninstall")) {
                                    showUninstallConfirmation = true
                                }
                                .disabled(helperManager.isBusy)
                            case .signingMismatch:
                                if case .identityMismatch = helperManager.signingIssue {
                                    Button(String(localized: "Reinstall Helper")) {
                                        reinstallHelper()
                                    }
                                    .disabled(helperManager.isBusy)
                                    Button(String(localized: "Uninstall")) {
                                        showUninstallConfirmation = true
                                    }
                                    .disabled(helperManager.isBusy)
                                } else {
                                    Button(String(localized: "Check Again")) {
                                        Task { await helperManager.checkStatus() }
                                    }
                                    .disabled(helperManager.isBusy)
                                }
                            }
                        }
                    }
                }
                .task {
                    await helperManager.checkStatus()
                }
                .alert(
                    String(localized: "Uninstall Helper Tool?"),
                    isPresented: $showUninstallConfirmation
                ) {
                    Button(String(localized: "Cancel"), role: .cancel) {}
                    Button(String(localized: "Uninstall"), role: .destructive) {
                        uninstallHelper()
                    }
                } message: {
                    Text(
                        String(
                            localized: "The proxy helper tool will be removed. You may be prompted for your password when changing proxy settings."
                        )
                    )
                }

                Divider()

                Text(String(localized: "UPDATES"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 176)

                updatesSection

                Divider()

                Text(String(localized: "MISCELLANEOUS"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 176)

                checkboxRow(
                    title: String(localized: "Show alert when quitting Rockxy"),
                    isOn: $showAlertOnQuit
                )

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "AdvancedSettingsTab")

    @State private var helperManager = HelperManager.shared
    @State private var showUninstallConfirmation = false
    @ObservedObject private var updater = AppUpdater.shared

    @AppStorage(RockxyIdentity.current.defaultsKey("showAlertOnQuit")) private var showAlertOnQuit =
        true // WIRED: AppDelegate.applicationShouldTerminate

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
            if case .appSignatureInvalid = helperManager.signingIssue {
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
            if case .appSignatureInvalid = helperManager.signingIssue {
                .red
            } else {
                .orange
            }
        }
    }

    private var helperStatusText: String {
        switch helperManager.status {
        case .notInstalled:
            String(localized: "Not Installed")
        case .requiresApproval:
            String(localized: "Requires Approval")
        case .installedCompatible:
            String(localized: "Installed")
        case .installedOutdated,
             .installedIncompatible:
            String(localized: "Update Available")
        case .unreachable:
            String(localized: "Unreachable")
        case .signingMismatch:
            if case .appSignatureInvalid = helperManager.signingIssue {
                String(localized: "Invalid App Signature")
            } else {
                String(localized: "Signing Mismatch")
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
            String(localized: "Rockxy will use networksetup and may ask for your password.")
        case .requiresApproval:
            String(localized: "Approve Rockxy Helper in System Settings \u{2192} General \u{2192} Login Items.")
        case .installedCompatible:
            String(localized: "Helper is responding and matches the bundled version.")
        case .installedOutdated:
            String(localized: "Installed helper version is outdated and should be updated.")
        case .installedIncompatible:
            String(localized: "Installed helper version is incompatible with this app.")
        case .unreachable:
            String(localized: "Rockxy could not communicate with the helper over XPC.")
        case .signingMismatch:
            helperManager.lastErrorMessage
                ?? String(localized: "The app and helper have mismatched signing certificates.")
        }
    }

    private func settingsRow(
        label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 160, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.top, 2)
            content()
        }
    }

    private func checkboxRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Color.clear.frame(width: 176)
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
        }
    }

    private var updatesSection: some View {
        settingsRow(label: String(localized: "Software Update:")) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: updater.isConfigured ? "checkmark.shield.fill" : "icloud.slash")
                            .font(.system(size: 16))
                            .foregroundStyle(updater.isConfigured ? Color.accentColor : Color.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Update Controls"))
                                .font(.system(size: 13, weight: .medium))
                            Text(updater.updateAvailabilitySummary)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        GridRow {
                            Text(String(localized: "Current:"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(updater.currentVersionSummary)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        GridRow {
                            Text(String(localized: "Last Checked:"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(updater.lastCheckedDescription)
                                .font(.system(size: 11))
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button(String(localized: "Check for Updates…")) {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.isConfigured || !updater.canCheckForUpdates)

                    Button(String(localized: "Change Logs…")) {
                        updater.openFullChangelog()
                    }

                    if updater.sessionInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Toggle(
                    String(localized: "Automatically check for updates"),
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(!updater.isConfigured)

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        String(localized: "Automatically download updates in the background"),
                        isOn: Binding(
                            get: { updater.automaticallyDownloadsUpdates },
                            set: { updater.setAutomaticallyDownloadsUpdates($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .disabled(!updater.isConfigured || !updater.automaticallyChecksForUpdates || !updater.allowsAutomaticUpdates)

                    Text(
                        String(
                            localized: "When enabled, Rockxy downloads signed updates ahead of time so install prompts are faster."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 10) {
                    Text(String(localized: "Check Frequency"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    Picker(
                        String(localized: "Check Frequency"),
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
                    .frame(width: 180)
                    .disabled(!updater.isConfigured || !updater.automaticallyChecksForUpdates)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        String(localized: "Send anonymous compatibility profile"),
                        isOn: Binding(
                            get: { updater.sendsSystemProfile },
                            set: { updater.setSendsSystemProfile($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .disabled(!updater.isConfigured)

                    Text(
                        String(
                            localized: """
                            This shares basic macOS and hardware compatibility details with Sparkle so Rockxy can match the right update. It does not include captured traffic.
                            """
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
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
