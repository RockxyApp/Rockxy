import AppKit
import os
import ServiceManagement
import SwiftUI

/// Advanced settings covering proxy helper tool management, time formatting,
/// app language, update notifications, and miscellaneous behavioral toggles.
///
/// ## Settings Wiring Status
///
/// | Key                    | Wired? | Consumer                          |
/// |------------------------|--------|-----------------------------------|
/// | appLanguage            | DEFERRED | No runtime consumer — future feature |
/// | showUpdateNotification | DEFERRED | No runtime consumer — future feature |
/// | use24HourTime          | DEFERRED | No runtime consumer — future feature |
/// | showFullTime           | DEFERRED | No runtime consumer — future feature |
/// | showAlertOnQuit        | WIRED  | AppDelegate.applicationShouldTerminate |
/// | showResourceUsage      | DEFERRED | No runtime consumer — future feature |
/// | hideAppleRequests      | DEFERRED | No runtime consumer — future feature |
/// | stayOnTop              | DEFERRED | No runtime consumer — future feature |
/// | showInvisibleChars     | DEFERRED | No runtime consumer — future feature |
/// | autoCleanUp            | DEFERRED | No runtime consumer — future feature |
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

                HStack {
                    Color.clear.frame(width: 176)
                    Button(String(localized: "Full Changelogs")) {
                        if let url = URL(string: "https://github.com/LocNguyenHuu/Rockxy/blob/main/CHANGELOG.md") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }

                Divider()

                settingsRow(label: String(localized: "App Language:")) {
                    Picker("", selection: $appLanguage) {
                        Text("English").tag("en")
                        Text("System Default").tag("system")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                .disabled(true)
                .opacity(0.6)

                Divider()

                settingsRow(label: String(localized: "App Update:")) {
                    Toggle(
                        String(localized: "Show notification when a new version is available"),
                        isOn: $showUpdateNotification
                    )
                    .toggleStyle(.checkbox)
                }
                .disabled(true)
                .opacity(0.6)

                Divider()

                settingsRow(label: String(localized: "Time Format:")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(String(localized: "Use 24-Hour Time"), isOn: $use24HourTime)
                            .toggleStyle(.checkbox)
                        Toggle(String(localized: "Show Full Time"), isOn: $showFullTime)
                            .toggleStyle(.checkbox)
                    }
                }
                .disabled(true)
                .opacity(0.6)

                Divider()

                Text(String(localized: "MISCELLANEOUS"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 176)

                checkboxRow(
                    title: String(localized: "Show alert when quitting Rockxy"),
                    isOn: $showAlertOnQuit
                )
                checkboxRow(
                    title: String(localized: "Show resource usage in status bar"),
                    isOn: $showResourceUsage
                )
                .disabled(true)
                .opacity(0.6)

                checkboxRow(
                    title: String(localized: "Hide Apple system requests"),
                    isOn: $hideAppleRequests
                )
                .disabled(true)
                .opacity(0.6)

                checkboxRow(
                    title: String(localized: "Stay on top of other windows"),
                    isOn: $stayOnTop
                )
                .disabled(true)
                .opacity(0.6)

                checkboxRow(
                    title: String(localized: "Show invisible characters in body view"),
                    isOn: $showInvisibleChars
                )
                .disabled(true)
                .opacity(0.6)

                checkboxRow(
                    title: String(localized: "Auto clean up resources on quit"),
                    isOn: $autoCleanUp
                )
                .disabled(true)
                .opacity(0.6)

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

    @AppStorage(RockxyIdentity.current.defaultsKey("appLanguage")) private var appLanguage =
        "en" // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("showUpdateNotification")) private var showUpdateNotification =
        true // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("use24HourTime")) private var use24HourTime =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("showFullTime")) private var showFullTime =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("showAlertOnQuit")) private var showAlertOnQuit =
        true // WIRED: AppDelegate.applicationShouldTerminate
    @AppStorage(RockxyIdentity.current.defaultsKey("showResourceUsage")) private var showResourceUsage =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("hideAppleRequests")) private var hideAppleRequests =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("stayOnTop")) private var stayOnTop =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("showInvisibleChars")) private var showInvisibleChars =
        false // DEFERRED: No runtime consumer — future feature
    @AppStorage(RockxyIdentity.current.defaultsKey("autoCleanUp")) private var autoCleanUp =
        true // DEFERRED: No runtime consumer — future feature

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
