import AppKit
import os
import ServiceManagement
import SwiftUI

// Renders the Advanced Proxy Settings window: live system-routing diagnostics,
// the next-start listener configuration, and the privileged helper tool status.

// MARK: - AdvancedProxySettingsView

/// Standalone diagnostics + configuration window for the proxy listener.
///
/// System routing derives entirely from the live coordinator (`isProxyRunning`,
/// `isSystemProxyConfigured`, `activeProxyPort`) and drives the existing coordinator
/// override path — it never reads the persisted launch-time recording preference.
/// The live endpoint and restart-needed status read the coordinator's
/// `runtimeListenerSnapshot`, captured from the exact settings the running proxy
/// started with. Listener settings are edited through an explicit validated
/// `AdvancedProxySettingsDraft` and only persist on Apply.
struct AdvancedProxySettingsView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: toolMetrics.headerSpacing) {
                    systemRoutingSection
                    listenerSection
                    helperToolSection
                }
                .padding(.horizontal, toolMetrics.contentHorizontalPadding)
                .padding(.vertical, toolMetrics.formVerticalPadding)
            }
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(width: toolMetrics.fieldWidth(560), height: 640)
        .onAppear {
            reloadFromStorage()
        }
        .onChange(of: coordinator.isProxyRunning, initial: true) {
            coordinator.refreshProxyOverrideStatus()
        }
        .task {
            await helperManager.checkStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.refreshProxyOverrideStatus()
            Task {
                await helperManager.checkStatus()
            }
        }
        .alert(
            String(localized: "Uninstall Helper Tool?", bundle: RockxyLocalization.bundle),
            isPresented: $showingUninstallConfirmation
        ) {
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {}
            Button(String(localized: "Uninstall", bundle: RockxyLocalization.bundle), role: .destructive) {
                Task {
                    defer { coordinator.refreshProxyOverrideStatus() }
                    do {
                        try await helperManager.uninstall()
                    } catch {
                        Self.logger.error("Failed to uninstall helper: \(error.localizedDescription)")
                    }
                }
            }
        } message: {
            Text(
                String(
                    localized: "The helper tool will be removed. Rockxy will use networksetup and may ask for your password.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "AdvancedProxySettings"
    )

    @State private var draft = AdvancedProxySettingsDraft(settings: AppSettingsManager.shared.settings)
    @State private var savedDraft = AdvancedProxySettingsDraft(settings: AppSettingsManager.shared.settings)
    @State private var helperManager = HelperManager.shared
    @State private var showingUninstallConfirmation = false
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.dismiss) private var dismiss

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var isDirty: Bool {
        draft != savedDraft
    }

    /// The live endpoint (`address:port`) of the running proxy, read from the
    /// coordinator snapshot so it reflects the real listen address and any
    /// fallback port rather than a hard-coded loopback string.
    private var liveEndpointText: String? {
        guard coordinator.isProxyRunning,
              let snapshot = coordinator.runtimeListenerSnapshot else
        {
            return nil
        }
        return "\(snapshot.listenAddress):\(snapshot.resolvedPort)"
    }

    /// True when the saved (preferred) listener configuration differs from the
    /// parameters the running proxy actually started with — applied changes only
    /// take effect on restart. A fallback resolved port alone never counts, so a
    /// port collision at launch does not falsely report unsaved-restart state.
    private var listenerChangeNeedsRestart: Bool {
        guard coordinator.isProxyRunning, let snapshot = coordinator.runtimeListenerSnapshot else {
            return false
        }
        return !snapshot.matchesRequestedListener(
            preferredPort: savedDraft.parsedPort,
            autoSelectPort: savedDraft.autoSelectPort,
            listenAddress: savedDraft.effectiveListenAddress
        )
    }

    private var routingIcon: String {
        guard coordinator.isProxyRunning else {
            return "circle.slash"
        }
        return coordinator.isSystemProxyConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var routingColor: Color {
        guard coordinator.isProxyRunning else {
            return .secondary
        }
        return coordinator.isSystemProxyConfigured ? .green : .orange
    }

    private var routingTitle: String {
        guard coordinator.isProxyRunning else {
            return String(localized: "Proxy Server Stopped", bundle: RockxyLocalization.bundle)
        }
        return coordinator.isSystemProxyConfigured
            ? String(localized: "macOS System Proxy Enabled", bundle: RockxyLocalization.bundle)
            : String(localized: "macOS System Proxy Disabled", bundle: RockxyLocalization.bundle)
    }

    private var routingSubtitle: String {
        guard coordinator.isProxyRunning else {
            return String(
                localized: "System routing is unavailable while the proxy server is stopped.",
                bundle: RockxyLocalization.bundle
            )
        }
        return coordinator.isSystemProxyConfigured
            ? String(
                localized: "Proxy-aware traffic is routed to Rockxy. Some apps ignore the macOS system proxy and stay direct.",
                bundle: RockxyLocalization.bundle
            )
            : String(
                localized: "The proxy server is running, but proxy-aware traffic is not automatically routed through Rockxy.",
                bundle: RockxyLocalization.bundle
            )
    }

    private var routingFailureMessage: String? {
        if let warning = coordinator.systemProxyWarning {
            return warning.message
        }
        return coordinator.proxyError
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

    private var helperStatusTitle: String {
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
            String(localized: "Installed But Unreachable", bundle: RockxyLocalization.bundle)
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
            String(localized: "A newer helper version is bundled with this app.", bundle: RockxyLocalization.bundle)
        case .installedIncompatible:
            String(
                localized: "Installed helper is incompatible with this app version.",
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
                String(localized: "Reachable", bundle: RockxyLocalization.bundle)
            } else {
                String(localized: "Unreachable", bundle: RockxyLocalization.bundle)
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Advanced Proxy Settings", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))

                Text(String(
                    localized: "Diagnose system routing and configure how the proxy listens.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    // MARK: - System Routing

    private var systemRoutingSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "System Routing", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.tableHeaderFont())

            HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
                Image(systemName: routingIcon)
                    .foregroundStyle(routingColor)
                    .font(.system(size: toolMetrics.compactIconFontSize))

                VStack(alignment: .leading, spacing: 3) {
                    Text(routingTitle)
                        .font(toolMetrics.font(weight: .medium))

                    Text(routingSubtitle)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if coordinator.isSystemProxyConfigured, let endpoint = liveEndpointText {
                        Text(endpoint)
                            .font(toolMetrics.secondaryFont(monospaced: true))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            if let failure = routingFailureMessage {
                routingFailureRow(failure)
            }

            HStack(spacing: toolMetrics.controlSpacing) {
                Button(coordinator.isSystemProxyConfigured
                    ? String(localized: "Disable macOS System Proxy", bundle: RockxyLocalization.bundle)
                    : String(localized: "Enable macOS System Proxy", bundle: RockxyLocalization.bundle))
                {
                    coordinator.toggleSystemProxyOverride()
                }
                .disabled(!coordinator.isProxyRunning)

                Spacer(minLength: 0)
            }

            if !coordinator.isProxyRunning {
                Text(String(
                    localized: "Start the proxy to route system traffic through Rockxy.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
            }
        }
        .padding(toolMetrics.formHorizontalPadding)
        .panelStyle()
    }

    // MARK: - Listener

    private var listenerSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
            Text(String(localized: "Listener", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.tableHeaderFont())

            if let endpoint = liveEndpointText {
                liveListenerRow(endpoint)
            }

            portRow

            Toggle(isOn: $draft.autoSelectPort) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(
                        localized: "Auto-select an available port at launch",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.font())
                    Text(String(
                        localized: "Automatically select a new available port if it's occupied at launch.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $draft.onlyListenOnLocalhost) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Only listen on localhost", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font())
                    Text(String(
                        localized: "Listen on 127.0.0.1 (localhost) instead of 0.0.0.0.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)

            if !draft.onlyListenOnLocalhost {
                Text(String(
                    localized: "Rockxy binds IPv4 only. IPv6 dual-stack listening isn't available yet.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.metadataFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if listenerChangeNeedsRestart {
                restartNoticeRow
            }
        }
        .padding(toolMetrics.formHorizontalPadding)
        .panelStyle()
    }

    private var portRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: toolMetrics.controlSpacing) {
                Text(String(localized: "Port Number", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))

                TextField("", text: $draft.portText)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .frame(width: toolMetrics.fieldWidth(110))
                    .frame(height: toolMetrics.formControlHeight)
                    .accessibilityLabel(String(localized: "Listener port number", bundle: RockxyLocalization.bundle))
                    .accessibilityHint(
                        String(
                            localized: "Enter a port between 1 and 65535. Applied changes take effect after the proxy restarts.",
                            bundle: RockxyLocalization.bundle
                        )
                    )

                Spacer(minLength: 0)
            }

            if !draft.isPortValid {
                Text(String(localized: "Enter a port between 1 and 65535.", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
            }
        }
    }

    private var restartNoticeRow: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
                .font(.system(size: toolMetrics.smallIconFontSize))

            Text(
                String(
                    localized: "Saved listener settings apply after the proxy restarts. The live endpoint above stays active until then.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Helper Tool

    private var helperToolSection: some View {
        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Privileged Helper Tool", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.tableHeaderFont())

            helperSummaryRow
            helperDiagnosticsGrid

            if let errorMessage = helperManager.lastErrorMessage {
                helperErrorDetail(errorMessage)
            }

            helperActions
        }
        .padding(toolMetrics.formHorizontalPadding)
        .panelStyle()
    }

    private var helperSummaryRow: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            Image(systemName: helperStatusIcon)
                .foregroundStyle(helperStatusColor)
                .font(.system(size: toolMetrics.compactIconFontSize))
            VStack(alignment: .leading, spacing: 2) {
                Text(helperStatusTitle)
                    .font(toolMetrics.font(weight: .medium))
                Text(helperStatusSubtitle)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var helperDiagnosticsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text(String(localized: "Bundled Version:", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text(helperManager.bundledHelperVersion)
                    .font(toolMetrics.metadataFont(monospaced: true))
            }
            GridRow {
                Text(String(localized: "Installed Version:", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                Text(helperManager.installedInfo?.binaryVersion ?? "\u{2014}")
                    .font(toolMetrics.metadataFont(monospaced: true))
                    .foregroundStyle(installedVersionColor)
            }
            GridRow {
                Text(String(localized: "Registration:", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                Text(helperManager.registrationStatus)
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(registrationColor)
            }
            GridRow {
                Text(String(localized: "XPC Reachability:", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
                Text(xpcReachabilityLabel)
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(xpcReachabilityColor)
            }
        }
        .padding(.leading, 4)
    }

    private var helperActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: toolMetrics.controlSpacing) {
                helperActionButtons
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                helperActionButtons
            }
        }
    }

    @ViewBuilder private var helperActionButtons: some View {
        if helperManager.isBusy {
            ProgressView()
                .controlSize(.small)
        }

        Group {
            switch helperManager.status {
            case .notInstalled:
                Button(String(localized: "Install Helper Tool", bundle: RockxyLocalization.bundle)) {
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
                    showingUninstallConfirmation = true
                }
                .disabled(helperManager.isBusy)

            case .installedOutdated:
                Button(String(localized: "Update Helper", bundle: RockxyLocalization.bundle)) {
                    updateHelper()
                }
                .disabled(helperManager.isBusy)

                Button(String(localized: "Uninstall", bundle: RockxyLocalization.bundle)) {
                    showingUninstallConfirmation = true
                }
                .disabled(helperManager.isBusy)

            case .installedIncompatible:
                Button(String(localized: "Check Again", bundle: RockxyLocalization.bundle)) {
                    Task { await helperManager.checkStatus() }
                }
                .disabled(helperManager.isBusy)

            case .unreachable:
                if helperManager.automaticRefreshRecoveryPending {
                    Button(String(localized: "Retry Automatic Update", bundle: RockxyLocalization.bundle)) {
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
                    showingUninstallConfirmation = true
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
                        showingUninstallConfirmation = true
                    }
                    .disabled(helperManager.isBusy)
                } else {
                    Button(String(localized: "Check Again", bundle: RockxyLocalization.bundle)) {
                        Task { await helperManager.checkStatus() }
                    }
                    .disabled(helperManager.isBusy)
                }
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

    // MARK: - Footer

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: toolMetrics.controlSpacing) {
                restoreDefaultsButton
                footerStatusText
                Spacer(minLength: 0)
                cancelButton
                applyButton
            }

            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                footerStatusText
                HStack(spacing: toolMetrics.controlSpacing) {
                    restoreDefaultsButton
                    Spacer(minLength: 0)
                    cancelButton
                    applyButton
                }
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var restoreDefaultsButton: some View {
        Button(String(localized: "Restore Defaults", bundle: RockxyLocalization.bundle)) {
            draft = .default
        }
    }

    private var footerStatusText: some View {
        Text(
            isDirty
                ? String(localized: "Unsaved listener changes", bundle: RockxyLocalization.bundle)
                : String(localized: "Listener settings saved", bundle: RockxyLocalization.bundle)
        )
        .font(toolMetrics.secondaryFont())
        .foregroundStyle(.secondary)
    }

    private var cancelButton: some View {
        Button {
            draft = savedDraft
            dismiss()
        } label: {
            footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
        }
        .keyboardShortcut(.cancelAction)
    }

    private var applyButton: some View {
        Button {
            applyListenerSettings()
        } label: {
            footerButtonLabel(String(localized: "Apply", bundle: RockxyLocalization.bundle))
        }
        .keyboardShortcut(.defaultAction)
        .rockxyGlassButtonStyle(prominent: true)
        .disabled(!isDirty || !draft.canApply)
    }

    private func liveListenerRow(_ endpoint: String) -> some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Live listener", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Text(endpoint)
                .font(toolMetrics.secondaryFont(monospaced: true))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Live proxy listener", bundle: RockxyLocalization.bundle))
        .accessibilityValue(endpoint)
    }

    private func routingFailureRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: toolMetrics.smallIconFontSize))

            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func helperErrorDetail(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Last Error", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.metadataFont(weight: .semibold))
            Text(errorMessage)
                .font(toolMetrics.metadataFont(monospaced: true))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(toolMetrics.controlSpacing)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(width: toolMetrics.footerButtonWidth - (toolMetrics.controlSpacing * 3))
    }

    private func reloadFromStorage() {
        let stored = AdvancedProxySettingsDraft(settings: AppSettingsManager.shared.settings)
        savedDraft = stored
        draft = stored
    }

    private func applyListenerSettings() {
        guard let updated = draft.applied(
            to: AppSettingsManager.shared.settings,
            changedFrom: savedDraft
        ) else {
            return
        }
        AppSettingsManager.shared.settings = updated
        AppSettingsManager.shared.save()
        savedDraft = AdvancedProxySettingsDraft(settings: updated)
        draft = savedDraft
    }

    private func installHelper() {
        Task {
            defer { coordinator.refreshProxyOverrideStatus() }
            do {
                try await helperManager.install()
            } catch {
                Self.logger.error("Failed to install helper: \(error.localizedDescription)")
            }
        }
    }

    private func updateHelper() {
        Task {
            defer { coordinator.refreshProxyOverrideStatus() }
            do {
                try await helperManager.update()
            } catch {
                Self.logger.error("Failed to update helper: \(error.localizedDescription)")
            }
        }
    }

    private func reinstallHelper() {
        Task {
            defer { coordinator.refreshProxyOverrideStatus() }
            do {
                try await helperManager.reinstall()
            } catch {
                Self.logger.error("Failed to reinstall helper: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - View + panelStyle

private extension View {
    func panelStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
