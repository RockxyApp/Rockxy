import AppKit
import os
import ServiceManagement
import SwiftUI

// Renders the advanced proxy settings interface for the settings experience.

// MARK: - AdvancedProxySettingsView

/// Standalone window for advanced proxy configuration. Controls the system proxy override,
/// port number, auto-port selection, localhost-only binding, and IPv4/IPv6 dual-stack options.
struct AdvancedProxySettingsView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            systemProxySection
            Divider()
            helperToolSection
            Divider()
            portNumberSection
            Divider()
            advancedSection

            Spacer()

            footerSection
        }
        .font(toolMetrics.font())
        .padding(24)
        .frame(width: toolMetrics.fieldWidth(480), alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            settings = AppSettingsManager.shared.settings
            portText = "\(settings.proxyPort)"
        }
        .task {
            await helperManager.checkStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await helperManager.checkStatus()
            }
        }
        .alert(
            String(localized: "Uninstall Helper Tool?"),
            isPresented: $showingUninstallConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Uninstall"), role: .destructive) {
                Task {
                    do {
                        try await helperManager.uninstall()
                    } catch {
                        Self.logger.error("Failed to uninstall helper: \(error.localizedDescription)")
                    }
                }
            }
        } message: {
            Text("The helper tool will be removed. Rockxy will use networksetup and may ask for your password.")
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "AdvancedProxySettings"
    )

    @State private var settings = AppSettingsManager.shared.settings
    @State private var portText: String = ""
    @State private var helperManager = HelperManager.shared
    @State private var showingUninstallConfirmation = false
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    // MARK: - Helper Status Mappings

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

    private var helperStatusTitle: String {
        switch helperManager.status {
        case .notInstalled:
            String(localized: "Not Installed")
        case .requiresApproval:
            String(localized: "Requires Approval")
        case .installedCompatible:
            String(localized: "Installed")
        case .installedOutdated:
            String(localized: "Update Available")
        case .installedIncompatible:
            String(localized: "Incompatible Version")
        case .unreachable:
            String(localized: "Installed But Unreachable")
        case .signingMismatch:
            if case .appSignatureInvalid = helperManager.signingIssue {
                String(localized: "Invalid App Signature")
            } else {
                String(localized: "Signing Mismatch")
            }
        }
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
            String(localized: "A newer helper version is bundled with this app.")
        case .installedIncompatible:
            String(localized: "Installed helper is incompatible with this app version.")
        case .unreachable:
            String(localized: "Rockxy could not communicate with the helper over XPC.")
        case .signingMismatch:
            helperManager.lastErrorMessage
                ?? String(localized: "The app and helper have mismatched signing certificates.")
        }
    }

    // MARK: - Diagnostics Helpers

    private var installedVersionColor: Color {
        guard helperManager.installedInfo?.binaryVersion != nil else {
            return .secondary
        }
        return helperManager.status == .installedCompatible ? .primary : .orange
    }

    private var registrationColor: Color {
        switch helperManager.registrationStatus {
        case "Enabled":
            .green
        case "Awaiting Approval":
            .orange
        case "Not Registered",
             "Not Found":
            .secondary
        default:
            .secondary
        }
    }

    private var xpcReachabilityLabel: String {
        switch helperManager.status {
        case .notInstalled:
            "\u{2014}"
        default:
            if helperManager.isReachable {
                String(localized: "Reachable")
            } else {
                String(localized: "Unreachable")
            }
        }
    }

    private var xpcReachabilityColor: Color {
        switch helperManager.status {
        case .notInstalled:
            .secondary
        default:
            helperManager.isReachable ? .green : .red
        }
    }

    private var systemProxyActive: Bool {
        AppSettingsManager.shared.settings.autoStartProxy
    }

    // MARK: - System Proxy

    private var systemProxySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "System Proxy:"))
                .font(toolMetrics.font(weight: .semibold))

            HStack(spacing: 8) {
                Image(systemName: systemProxyActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(systemProxyActive ? .green : .secondary)
                    .font(.system(size: max(16, toolMetrics.bodyFontSize + 3)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        systemProxyActive
                            ? String(localized: "Overridden by Rockxy")
                            : String(localized: "Not Active")
                    )
                    .font(toolMetrics.font(weight: .medium))

                    if systemProxyActive {
                        Text("IP=\(settings.effectiveListenAddress) Port=\(settings.proxyPort)")
                            .font(toolMetrics.secondaryFont(monospaced: true))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Button(systemProxyActive
                    ? String(localized: "Toggle OFF")
                    : String(localized: "Toggle ON"))
                {
                    toggleSystemProxy()
                }
                Text("\u{2325}\u{2318}O")
                    .font(toolMetrics.secondaryFont(monospaced: true))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Port Number

    private var portNumberSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(String(localized: "Port Number:"))
                    .font(toolMetrics.font(weight: .semibold))

                TextField("", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .frame(width: toolMetrics.fieldWidth(100))
                    .frame(minHeight: toolMetrics.formControlHeight)
                    .onChange(of: portText) {
                        if let newPort = Int(portText), newPort > 0, newPort <= 65_535 {
                            settings.proxyPort = newPort
                            saveSettings()
                        }
                    }
            }

            Toggle(isOn: $settings.autoSelectPort) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Auto Select Available Port At Launch"))
                        .font(toolMetrics.font())
                    Text(String(localized: "Automatically select new available port if it's occupied at launch."))
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .onChange(of: settings.autoSelectPort) { saveSettings() }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Advanced:"))
                .font(toolMetrics.font(weight: .semibold))

            Toggle(isOn: $settings.onlyListenOnLocalhost) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Only Listen on localhost"))
                        .font(toolMetrics.font())
                    Text(String(localized: "Listen on 127.0.0.1 (localhost) instead of 0.0.0.0"))
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .onChange(of: settings.onlyListenOnLocalhost) { saveSettings() }

            Toggle(isOn: $settings.listenIPv6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Listen on IPv4 & IPv6"))
                        .font(toolMetrics.font())
                    Text(String(localized: "Listen on 0.0.0.0 (IPv4) & ::0 (IPv6)"))
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(settings.onlyListenOnLocalhost)
            .onChange(of: settings.listenIPv6) { saveSettings() }
        }
    }

    // MARK: - Helper Tool

    private var helperToolSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Privileged Helper Tool:"))
                .font(toolMetrics.font(weight: .semibold))

            // Zone A: Summary row
            helperSummaryRow

            // Zone B: Diagnostics grid
            helperDiagnosticsGrid

            // Error detail (conditional)
            if let errorMessage = helperManager.lastErrorMessage {
                helperErrorDetail(errorMessage)
            }

            // Zone C: Actions + progress
            helperActions
        }
    }

    // MARK: Zone A — Summary Row

    private var helperSummaryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: helperStatusIcon)
                .foregroundStyle(helperStatusColor)
                .font(.system(size: max(20, toolMetrics.bodyFontSize + 7)))
            VStack(alignment: .leading, spacing: 2) {
                Text(helperStatusTitle)
                    .font(toolMetrics.font(weight: .semibold))
                Text(helperStatusSubtitle)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Zone B — Diagnostics Grid

    private var helperDiagnosticsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text(String(localized: "Bundled Version:"))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text(helperManager.bundledHelperVersion)
                    .font(toolMetrics.metadataFont(monospaced: true))
            }
            GridRow {
                Text(String(localized: "Installed Version:"))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                Text(helperManager.installedInfo?.binaryVersion ?? "\u{2014}")
                    .font(toolMetrics.metadataFont(monospaced: true))
                    .foregroundStyle(installedVersionColor)
            }
            GridRow {
                Text(String(localized: "Registration:"))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                Text(helperManager.registrationStatus)
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(registrationColor)
            }
            GridRow {
                Text(String(localized: "XPC Reachability:"))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                Text(xpcReachabilityLabel)
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(xpcReachabilityColor)
            }
        }
        .padding(.leading, 4)
    }

    // MARK: Zone C — Actions

    private var helperActions: some View {
        HStack(spacing: 8) {
            if helperManager.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            switch helperManager.status {
            case .notInstalled:
                Button(String(localized: "Install Helper Tool")) {
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
                    showingUninstallConfirmation = true
                }
                .disabled(helperManager.isBusy)

            case .installedOutdated,
                 .installedIncompatible:
                Button(String(localized: "Update Helper")) {
                    updateHelper()
                }
                .disabled(helperManager.isBusy)

                Button(String(localized: "Uninstall")) {
                    showingUninstallConfirmation = true
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
                    showingUninstallConfirmation = true
                }
                .disabled(helperManager.isBusy)

            case .signingMismatch:
                if case .identityMismatch = helperManager.signingIssue {
                    Button(String(localized: "Reinstall Helper")) {
                        reinstallHelper()
                    }
                    .disabled(helperManager.isBusy)

                    Button(String(localized: "Uninstall")) {
                        showingUninstallConfirmation = true
                    }
                    .disabled(helperManager.isBusy)
                } else {
                    Button(String(localized: "Check Again")) {
                        Task { await helperManager.checkStatus() }
                    }
                    .disabled(helperManager.isBusy)
                }
            }

            Button(role: .destructive) {
                HelperRecoveryPresenter.presentForceReset()
            } label: {
                Text(String(localized: "Force Reset…"))
            }
            .disabled(helperManager.isBusy)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button(String(localized: "Restore Default")) {
                    restoreDefaults()
                }
                Spacer()
            }
        }
    }

    // MARK: Error Detail

    private func helperErrorDetail(_ errorMessage: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Last Error"))
                    .font(toolMetrics.metadataFont(weight: .semibold))
                Text(errorMessage)
                    .font(toolMetrics.metadataFont(monospaced: true))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helper Actions

    private func installHelper() {
        Task {
            do {
                try await helperManager.install()
            } catch {
                Self.logger.error("Failed to install helper: \(error.localizedDescription)")
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

    private func toggleSystemProxy() {
        settings.autoStartProxy.toggle()
        saveSettings()
    }

    private func saveSettings() {
        AppSettingsManager.shared.settings = settings
        AppSettingsManager.shared.save()
    }

    private func restoreDefaults() {
        settings.proxyPort = 9_090
        settings.onlyListenOnLocalhost = true
        settings.listenIPv6 = false
        settings.autoSelectPort = true
        portText = "9090"
        saveSettings()
    }
}
