import AppKit
import SwiftUI

// MARK: - DeveloperSetupWindowView

struct DeveloperSetupWindowView: View {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        _viewModel = State(initialValue: DeveloperSetupViewModel(coordinator: coordinator))
    }

    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        NavigationSplitView {
            DeveloperSetupSourceList(
                selection: targetSelectionBinding,
                sections: viewModel.filteredTargetSections,
                isPinned: { viewModel.isPinned($0) },
                onTogglePinned: { viewModel.togglePinned($0) }
            )
            .searchable(
                text: $viewModel.sourceListSearchText,
                isPresented: $searchPresented,
                placement: .sidebar,
                prompt: Text(String(localized: "Search setups", bundle: RockxyLocalization.bundle))
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailColumn
                .inspector(isPresented: $inspectorPresented) {
                    inspectorColumn
                        .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
                }
        }
        .navigationTitle(String(localized: "Developer Setup", bundle: RockxyLocalization.bundle))
        .toolbar { toolbarContent }
        .frame(minHeight: 560)
        .background {
            Button("") {
                searchPresented = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
            .accessibilityHidden(true)
        }
        .task {
            if let route = routeStore.consumeHubRoute() {
                await viewModel.applyHubRoute(route)
            } else {
                await viewModel.refreshSnapshot()
            }
        }
        .sheet(item: $presentedShareSession, onDismiss: {
            stopPresentedCertificateSharing()
        }) { shareSession in
            RootCAShareSheet(
                session: shareSession,
                fingerprint: caShareController.currentFingerprint,
                onCopyURL: { copyRootCAShareURL(shareSession.publicURL) },
                onStop: {
                    stopPresentedCertificateSharing(expectedSessionID: shareSession.id)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionCleared)) { _ in
            viewModel.handleSessionCleared()
        }
        .onChange(of: coordinator.isProxyRunning) { _, _ in refreshSnapshot() }
        .onChange(of: coordinator.isRecording) { _, _ in refreshSnapshot() }
        .onChange(of: coordinator.activeProxyPort) { _, _ in refreshSnapshot() }
        .onChange(of: coordinator.sessionGeneration) { _, _ in refreshSnapshot() }
        .onChange(of: ReadinessCoordinator.shared.certReadiness) { _, _ in refreshSnapshot() }
        .onChange(of: ReadinessCoordinator.shared.proxyMode) { _, _ in refreshSnapshot() }
        .onChange(of: ReadinessCoordinator.shared.activeWarning) { _, _ in refreshSnapshot() }
        .onChange(of: routeStore.hubRoute) { _, _ in
            let route = routeStore.consumeHubRoute()
            Task { await viewModel.applyHubRoute(route) }
        }
        .onChange(of: viewModel.selectedTarget.id) { _, _ in
            stopAllCertificateSharing()
            actionStatusMessage = nil
        }
        .onDisappear {
            viewModel.cancelValidation(markCancelled: true)
            stopAllCertificateSharing()
            Task { await viewModel.stopValidationProbe() }
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: DeveloperSetupViewModel
    @State private var routeStore = DeveloperSetupRouteStore.shared
    @StateObject private var caShareController = CAShareController()
    @State private var certificateShareStatusMessage: String?
    @State private var certificateShareGeneration = 0
    @State private var actionStatusMessage: String?
    @State private var presentedShareSession: RootCADownloadSession?
    @State private var presentedShareSessionID: RootCADownloadSession.ID?
    @State private var inspectorPresented = false
    @State private var searchPresented = false

    private var setupMetrics: DeveloperSetupDisplayMetrics {
        DeveloperSetupDisplayMetrics(appMetrics: appMetrics)
    }

    private var targetSelectionBinding: Binding<SetupTarget.ID?> {
        Binding(
            get: { viewModel.selectedTarget.id },
            set: { newValue in
                guard let newValue, newValue != viewModel.selectedTarget.id,
                      let target = SetupTarget.target(for: newValue) else
                {
                    return
                }
                Task { @MainActor in
                    await viewModel.selectTarget(target)
                    await viewModel.refreshSnapshot()
                }
            }
        )
    }

    /// The device endpoint is what someone types into a phone's proxy settings, so it must show
    /// the port alongside the host; the caption already promises "this host and port".
    private var deviceProxyHostText: String {
        guard let host = viewModel.snapshot.reachableLANAddress else {
            return String(localized: "Unavailable", bundle: RockxyLocalization.bundle)
        }
        return "\(host):\(String(viewModel.snapshot.activePort))"
    }

    private var deviceProxyCaption: String {
        if viewModel.snapshot.effectiveListenAddress == "127.0.0.1" {
            return String(
                localized: """
                Devices outside this Mac cannot reach localhost-only mode. Turn off Only listen on localhost \
                in Settings > General > Advanced Proxy Setting…, then restart the proxy.
                """,
                bundle: RockxyLocalization.bundle
            )
        }
        guard viewModel.snapshot.reachableLANAddress != nil else {
            return String(
                localized: "Connect this Mac to Wi-Fi or Ethernet to expose a reachable LAN IP.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "Use this host and port when configuring a device, simulator, or client on the same network.",
            bundle: RockxyLocalization.bundle
        )
    }

    // MARK: Toolbar

    /// Toolbar items use the system's toolbar item styling only, and the section switcher lives
    /// in the detail column like the main window's view switcher. A custom Liquid Glass surface or
    /// a centered principal item in this `NSToolbar` was hosted through AppKit platform views whose
    /// sizes fed back into toolbar layout; on macOS 26 that oscillated until AppKit aborted the
    /// window with an "Update Constraints in Window" exception on open or on a readiness refresh.
    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button(String(localized: "Open Setup Guide…", bundle: RockxyLocalization.bundle)) {
                    openManualSetup()
                }
                if viewModel.selectedTarget.isRuntimeTerminalTarget {
                    Button(String(localized: "Open Configured Terminal…", bundle: RockxyLocalization.bundle)) {
                        openAutomaticSetup()
                    }
                }
            } label: {
                Label(
                    String(localized: "Set Up…", bundle: RockxyLocalization.bundle),
                    systemImage: "play.circle"
                )
            }
            .help(String(
                localized: "Open a guided or configured setup for this target",
                bundle: RockxyLocalization.bundle
            ))

            Button {
                inspectorPresented.toggle()
            } label: {
                Label(
                    String(localized: "Readiness Inspector", bundle: RockxyLocalization.bundle),
                    systemImage: "sidebar.trailing"
                )
            }
            .help(String(localized: "Toggle the readiness inspector", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Toggle readiness inspector", bundle: RockxyLocalization.bundle))
        }
    }

    // MARK: Bottom feedback

    private var feedbackMessage: String? {
        actionStatusMessage ?? certificateShareStatusMessage ?? viewModel.snapshot.readinessWarningMessage
    }

    private var proxyOverviewCaption: String {
        viewModel.snapshot.proxyRunning
            ? String(localized: "Rockxy is capturing traffic on this Mac.", bundle: RockxyLocalization.bundle)
            : String(localized: "Start Rockxy before pointing traffic at the proxy.", bundle: RockxyLocalization.bundle)
    }

    private var proxyOverviewAction: (title: String, perform: () -> Void)? {
        guard !viewModel.snapshot.proxyRunning else {
            return nil
        }
        return (String(localized: "Start Proxy", bundle: RockxyLocalization.bundle), { coordinator.startProxy() })
    }

    private var endpointOverviewValue: String {
        "\(viewModel.snapshot.effectiveListenAddress):\(viewModel.snapshot.activePort)"
    }

    private var endpointOverviewCaption: String {
        viewModel.snapshot.proxyRunning
            ? String(localized: "Rockxy is listening on this address now.", bundle: RockxyLocalization.bundle)
            : String(
                localized: "Rockxy will bind this address when the proxy starts.",
                bundle: RockxyLocalization.bundle
            )
    }

    private var recordingOverviewCaption: String {
        String(localized: "Requests must be recorded to run the capture check.", bundle: RockxyLocalization.bundle)
    }

    private var recordingOverviewAction: (title: String, perform: () -> Void)? {
        guard !viewModel.snapshot.recordingEnabled else {
            return nil
        }
        return (String(localized: "Resume Recording", bundle: RockxyLocalization.bundle), {
            if !coordinator.isRecording {
                coordinator.toggleRecording()
            }
        })
    }

    private var certificateOverviewValue: String {
        viewModel.snapshot.certificateTrusted
            ? String(localized: "Trusted", bundle: RockxyLocalization.bundle)
            : String(localized: "Needs attention", bundle: RockxyLocalization.bundle)
    }

    private var certificateOverviewCaption: String {
        viewModel.snapshot.certificateFileReady
            ? String(
                localized: "A root certificate is available for your client configuration.",
                bundle: RockxyLocalization.bundle
            )
            : String(
                localized: "Generate or export the root certificate before validating HTTPS traffic.",
                bundle: RockxyLocalization.bundle
            )
    }

    private var certificateOverviewAction: (title: String, perform: () -> Void)? {
        guard !viewModel.snapshot.certificateTrusted else {
            return nil
        }
        let title = viewModel.selectedTarget.supportsCertificateSharing
            ? String(localized: "Share Certificate", bundle: RockxyLocalization.bundle)
            : String(localized: "Open Certificate", bundle: RockxyLocalization.bundle)
        return (title, {
            if viewModel.selectedTarget.supportsCertificateSharing {
                shareRootCAForSelectedTarget()
            } else {
                openWindow(id: "certificateSetup")
            }
        })
    }

    private var deviceEndpointOverviewAction: (title: String, perform: () -> Void)? {
        guard viewModel.snapshot.reachableLANAddress == nil else {
            return nil
        }
        return (
            String(localized: "Open Proxy Settings", bundle: RockxyLocalization.bundle),
            { openWindow(id: "advancedProxySettings") }
        )
    }

    // MARK: Guide

    private var setupSteps: [SetupStep] {
        viewModel.currentWorkflow.supportsSnippets ? viewModel.currentSetupSteps : []
    }

    private var setupGuideTips: [SetupGuideTip] {
        viewModel.currentGuideContent?.setupTips ?? []
    }

    // MARK: Help

    private var troubleshootingGuideTips: [SetupGuideTip] {
        viewModel.currentGuideContent?.troubleshootingTips ?? []
    }

    private var selectedTabBinding: Binding<SetupDetailTab> {
        Binding(
            get: { viewModel.selectedTab },
            set: { newValue in
                guard newValue != viewModel.selectedTab else {
                    return
                }
                viewModel.selectTab(newValue)
            }
        )
    }

    // MARK: Detail column

    /// The detail column carries its own minimum width. A minimum applied to the whole
    /// `NavigationSplitView` over-constrained the window once the inspector column opened
    /// (sidebar + detail + inspector exceeded the window), and an over-constrained split view
    /// with content that re-measures itself on every proposed width never settles.
    private var detailColumn: some View {
        // Resolve the column against the space the split view actually offers. Measured
        // through its own ideal size, the stacked scroll view + feedback bar reported the
        // scroll content's natural height, the window adopted that taller layout, and the
        // sidebar search field, first targets, and detail header ended up hidden above the
        // title bar at the default window size.
        GeometryReader { proxy in
            VStack(spacing: 0) {
                UtilitySegmentedHeader(width: 460) {
                    detailTabPicker
                }
                Divider()
                centerContent
                if let message = feedbackMessage {
                    Divider()
                    feedbackBar(message)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minWidth: 440)
    }

    private var detailTabPicker: some View {
        Picker(String(localized: "Section", bundle: RockxyLocalization.bundle), selection: selectedTabBinding) {
            ForEach(SetupDetailTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(String(localized: "Section", bundle: RockxyLocalization.bundle))
    }

    private var centerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch viewModel.selectedTab {
                case .overview:
                    overviewContent
                case .setup:
                    setupContent
                case .snippets:
                    snippetsContent
                case .validate:
                    validateContent
                case .troubleshooting:
                    troubleshootingContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var inspectorColumn: some View {
        DeveloperSetupInspector(
            snapshot: viewModel.snapshot,
            activeIssue: viewModel.activeIssue,
            onIssueAction: { handleIssueAction($0) },
            onReveal: { viewModel.revealMatchedTransaction() }
        )
    }

    // MARK: Overview

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            overviewRow(
                label: String(localized: "Proxy", bundle: RockxyLocalization.bundle),
                value: viewModel.snapshot.proxyRunning
                    ? String(localized: "Running", bundle: RockxyLocalization.bundle)
                    : String(localized: "Stopped", bundle: RockxyLocalization.bundle),
                caption: proxyOverviewCaption,
                action: proxyOverviewAction
            )
            Divider()
            overviewRow(
                label: String(localized: "Endpoint", bundle: RockxyLocalization.bundle),
                value: endpointOverviewValue,
                caption: endpointOverviewCaption,
                action: nil
            )
            Divider()
            overviewRow(
                label: String(localized: "Recording", bundle: RockxyLocalization.bundle),
                value: viewModel.snapshot.recordingEnabled
                    ? String(localized: "Enabled", bundle: RockxyLocalization.bundle)
                    : String(localized: "Paused", bundle: RockxyLocalization.bundle),
                caption: recordingOverviewCaption,
                action: recordingOverviewAction
            )
            Divider()
            overviewRow(
                label: String(localized: "Certificate", bundle: RockxyLocalization.bundle),
                value: certificateOverviewValue,
                caption: certificateOverviewCaption,
                action: certificateOverviewAction
            )
            if viewModel.selectedTarget.requiresReachableLANProxy {
                Divider()
                overviewRow(
                    label: String(localized: "Device Endpoint", bundle: RockxyLocalization.bundle),
                    value: deviceProxyHostText,
                    caption: deviceProxyCaption,
                    action: deviceEndpointOverviewAction
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.selectedTarget.supportStatus == .availableNow {
                ForEach(Array(setupSteps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 {
                        Divider()
                    }
                    stepRow(step)
                }

                if !setupGuideTips.isEmpty {
                    if !setupSteps.isEmpty {
                        Divider()
                    }
                    tipSection(
                        title: String(localized: "Manual guide", bundle: RockxyLocalization.bundle),
                        tips: setupGuideTips
                    )
                }

                if viewModel.selectedTarget.supportsCertificateSharing {
                    if !setupSteps.isEmpty || !setupGuideTips.isEmpty {
                        Divider()
                    }
                    certificateShareSection
                }
            } else {
                guideOnlySection(
                    title: String(localized: "Manual guide", bundle: RockxyLocalization.bundle),
                    message: viewModel.selectedTarget.manualSummary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var certificateShareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Device certificate", bundle: RockxyLocalization.bundle))
            Text(
                String(
                    localized: """
                    Share the public Rockxy Root CA from this Mac as a temporary local QR code and link, \
                    then finish the platform trust steps on the device or simulator.
                    """, bundle: RockxyLocalization.bundle
                )
            )
            .font(setupMetrics.font())
            .fixedSize(horizontal: false, vertical: true)

            Text(
                String(
                    localized: "The link only serves the public PEM, expires automatically, and stops when this sheet closes.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(setupMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(String(localized: "Share Certificate", bundle: RockxyLocalization.bundle)) {
                    shareRootCAForSelectedTarget()
                }
                .rockxyGlassButtonStyle()

                Button(String(localized: "Open Certificate Guide", bundle: RockxyLocalization.bundle)) {
                    openWindow(id: "certificateSetup")
                }
            }

            if viewModel.selectedTarget.id == .iosSimulator {
                simulatorInstallRow
            }
            if viewModel.selectedTarget.id == .androidEmulator {
                androidEmulatorRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private var androidEmulatorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                String(
                    localized: """
                    Or let Rockxy use adb to point running emulators at this Mac and copy the certificate \
                    to them. Revert when you finish so the emulator keeps its connection after Rockxy quits.
                    """,
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(setupMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(String(localized: "Route Emulators Through Rockxy…", bundle: RockxyLocalization.bundle)) {
                    let port = viewModel.snapshot.activePort
                    let running = viewModel.snapshot.proxyRunning
                    Task { @MainActor in
                        await AndroidEmulatorSetupFlow.route(proxyPort: port, proxyRunning: running)
                    }
                }
                Button(String(localized: "Revert Emulator Proxy", bundle: RockxyLocalization.bundle)) {
                    Task { @MainActor in
                        await AndroidEmulatorSetupFlow.revert()
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var simulatorInstallRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                String(
                    localized: "Or install it directly into every booted simulator with simctl. Rockxy asks before changing a simulator's trust.",
                    bundle: RockxyLocalization.bundle
                )
            )
            .font(setupMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button(String(localized: "Install in Booted Simulators…", bundle: RockxyLocalization.bundle)) {
                Task { @MainActor in
                    await SimulatorCertificateInstallFlow.run()
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Snippets

    private var snippetsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.selectedTarget.supportStatus == .availableNow,
               let currentSnippetText = viewModel.currentSnippetText
            {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    snippetSelector
                    Spacer(minLength: 12)
                    copySnippetButton
                }

                snippetBox(currentSnippetText)
            } else {
                emptyStateSection(
                    title: viewModel.usesGuideSetupContent
                        ? String(
                            localized: "No runtime snippet needed for this device flow",
                            bundle: RockxyLocalization.bundle
                        )
                        : String(
                            localized: "No first-party snippet in Rockxy for this target yet",
                            bundle: RockxyLocalization.bundle
                        ),
                    message: viewModel.selectedTarget.currentSupportSummary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var snippetSelector: some View {
        Picker(
            String(localized: "Snippet", bundle: RockxyLocalization.bundle),
            selection: $viewModel.selectedSnippetID
        ) {
            ForEach(viewModel.currentSnippetOptions) { snippet in
                Text(snippet.title).tag(snippet.id)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(viewModel.currentSnippetOptions.count <= 1)
    }

    private var copySnippetButton: some View {
        Button(String(localized: "Copy Snippet", bundle: RockxyLocalization.bundle)) {
            copySnippetToPasteboard()
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
    }

    // MARK: Check

    private var validateContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.supportsValidation, let currentSnippetText = viewModel.currentValidationSnippetText {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "Run this probe while Rockxy waits for the request.",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(setupMetrics.font())
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        String(
                            localized: "Checks proxy capture only; it does not identify the source app or process.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    .font(setupMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                snippetBox(currentSnippetText)

                HStack(spacing: 10) {
                    checkActions
                }

                Text(viewModel.snapshot.verificationState.title)
                    .font(setupMetrics.secondaryFont())
                    .foregroundStyle(.secondary)

                if let issue = viewModel.activeIssue {
                    Divider()
                    issueBlock(issue)
                }
            } else if let guideContent = viewModel.currentGuideContent, !guideContent.validationTips.isEmpty {
                tipSection(
                    title: String(localized: "Manual validation", bundle: RockxyLocalization.bundle),
                    tips: guideContent.validationTips
                )
            } else {
                emptyStateSection(
                    title: String(
                        localized: "Interactive validation is not available for this target",
                        bundle: RockxyLocalization.bundle
                    ),
                    message: viewModel.selectedTarget.manualSummary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var checkActions: some View {
        Button(String(localized: "Copy Command", bundle: RockxyLocalization.bundle)) {
            copySnippetToPasteboard()
        }

        Button(String(localized: "Start Check", bundle: RockxyLocalization.bundle)) {
            viewModel.startValidation()
        }
        .rockxyGlassButtonStyle(prominent: true)
        .disabled(!viewModel.toolbarVerifyEnabled || viewModel.activeIssue != nil)
        .keyboardShortcut("r", modifiers: .command)

        if viewModel.snapshot.verificationState == .success,
           viewModel.snapshot.matchedTransactionID != nil
        {
            Button(String(localized: "Reveal in Main Window", bundle: RockxyLocalization.bundle)) {
                viewModel.revealMatchedTransaction()
            }
        }
    }

    private var troubleshootingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !troubleshootingGuideTips.isEmpty {
                tipSection(
                    title: String(localized: "Common issues", bundle: RockxyLocalization.bundle),
                    tips: troubleshootingGuideTips
                )
            }

            if viewModel.selectedTarget.supportStatus == .availableNow, viewModel.supportsValidation {
                ForEach(Array(viewModel.troubleshootingIssues.enumerated()), id: \.element.id) { index, issue in
                    if index > 0 || !troubleshootingGuideTips.isEmpty {
                        Divider()
                    }
                    issueBlock(issue)
                }
            } else if troubleshootingGuideTips.isEmpty {
                guideOnlySection(
                    title: String(localized: "Current limitation", bundle: RockxyLocalization.bundle),
                    message: viewModel.selectedTarget.currentSupportSummary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Status text outside the scroll view must not derive its height from the column width:
    /// a wrapped label here changes the detail column's minimum size, the split view resizes
    /// the column, the label re-wraps, and AppKit aborts the window after 257 layout passes.
    /// Keep it to one truncated line and expose the full text through the tooltip.
    private func feedbackBar(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(setupMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(message)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func stepRow(_ step: SetupStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(step.isComplete ? .green : .secondary)
                .font(setupMetrics.font(size: setupMetrics.iconFontSize, weight: .medium))
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 12) {
                stepText(step)
                Spacer(minLength: 12)
                stepButton(step)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func stepText(_ step: SetupStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(step.title)
                .font(setupMetrics.font(weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(step.description)
                .font(setupMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepButton(_ step: SetupStep) -> some View {
        Button(step.actionTitle) {
            handleStepAction(step)
        }
        .disabled(!step.isEnabled)
    }

    private func issueBlock(_ issue: SetupIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.title)
                .font(setupMetrics.font(weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(issue.message)
                .font(setupMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(issue.actionTitle) {
                handleIssueAction(issue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    // MARK: Reusable components

    private func overviewRow(
        label: String,
        value: String,
        caption: String?,
        action: (title: String, perform: () -> Void)?
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                overviewRowLabel(label)
                Spacer(minLength: 12)
                overviewRowValue(value)
                if let action {
                    Button(action.title) { action.perform() }
                }
            }

            if let caption {
                Text(caption)
                    .font(setupMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func overviewRowLabel(_ label: String) -> some View {
        Text(label)
            .font(setupMetrics.font(weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func overviewRowValue(_ value: String) -> some View {
        Text(value)
            .font(setupMetrics.font(weight: .semibold))
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func snippetBox(_ text: String) -> some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(setupMetrics.font(size: setupMetrics.snippetFontSize, monospaced: true))
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.6))
                        )
                )
        }
        .accessibilityLabel(String(localized: "Generated setup snippet", bundle: RockxyLocalization.bundle))
        .accessibilityValue(text)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(setupMetrics.font(size: setupMetrics.sectionTitleFontSize, weight: .semibold))
    }

    private func tipSection(title: String, tips: [SetupGuideTip]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title)
            ForEach(tips) { tip in
                VStack(alignment: .leading, spacing: 3) {
                    Text(tip.title)
                        .font(setupMetrics.font(weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tip.message)
                        .font(setupMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func guideOnlySection(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title)
            Text(message)
                .font(setupMetrics.font())
                .fixedSize(horizontal: false, vertical: true)
            Text(viewModel.selectedTarget.currentSupportSummary)
                .font(setupMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func emptyStateSection(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(setupMetrics.font(size: setupMetrics.sectionTitleFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(setupMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func openManualSetup() {
        routeStore.requestManual(targetID: viewModel.selectedTarget.id)
        openWindow(id: "manualSetup")
    }

    private func openAutomaticSetup() {
        // Unsupported (non runtime-terminal) targets are rejected by the store, so
        // the automatic window never opens for a device/browser/framework target.
        guard routeStore.requestAutomatic(targetID: viewModel.selectedTarget.id) else {
            return
        }
        openWindow(id: "automaticSetup")
    }

    private func copySnippetToPasteboard() {
        guard let text = viewModel.copyTextForCurrentContext() else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        actionStatusMessage = viewModel.selectedTab == .validate
            ? String(localized: "Probe command copied.", bundle: RockxyLocalization.bundle)
            : String(localized: "Snippet copied.", bundle: RockxyLocalization.bundle)
    }

    private func handleStepAction(_ step: SetupStep) {
        switch step.actionKind {
        case .verifyProxy:
            if !coordinator.isProxyRunning {
                coordinator.startProxy()
            } else if !coordinator.isRecording {
                coordinator.toggleRecording()
            } else {
                refreshSnapshot()
            }
        case .openCertificate:
            if viewModel.selectedTarget.supportsCertificateSharing {
                shareRootCAForSelectedTarget()
            } else {
                openWindow(id: "certificateSetup")
            }
        case .copySnippet:
            viewModel.selectTab(.snippets)
        case .runValidation:
            viewModel.selectTab(.validate)
        }
    }

    private func handleIssueAction(_ issue: SetupIssue) {
        switch issue {
        case .runtimeNotInstalled:
            viewModel.selectTab(.setup)
        case .proxyStopped:
            coordinator.startProxy()
        case .recordingPaused:
            if !coordinator.isRecording {
                coordinator.toggleRecording()
            }
        case .deviceProxyUnreachable:
            openWindow(id: "advancedProxySettings")
        case .certificateNotTrusted,
             .certificateExportUnavailable:
            if viewModel.selectedTarget.supportsCertificateSharing {
                shareRootCAForSelectedTarget()
            } else {
                openWindow(id: "certificateSetup")
            }
        case .noTrafficDetected,
             .localProbeUnavailable,
             .localProbeNotCaptured:
            viewModel.selectTab(.validate)
            viewModel.startValidation()
        case .allowListBlockedValidation:
            NotificationCenter.default.post(name: .openAllowListWindow, object: nil)
        case .wrongSnippetChosen:
            viewModel.selectTab(.snippets)
        case .manualValidationOnly:
            viewModel.selectTab(.validate)
        case .targetIsGuideOnly:
            viewModel.selectTab(.overview)
        }
    }

    private func shareRootCAForSelectedTarget() {
        certificateShareGeneration += 1
        let generation = certificateShareGeneration
        Task { @MainActor in
            do {
                certificateShareStatusMessage = String(
                    localized: "Preparing certificate sharing link...",
                    bundle: RockxyLocalization.bundle
                )
                let session = try await caShareController.startSharing()
                guard certificateShareGeneration == generation else {
                    return
                }
                presentedShareSession = session
                presentedShareSessionID = session.id
                certificateShareStatusMessage =
                    String(
                        localized: "Certificate sharing link started for \(viewModel.selectedTarget.title).",
                        bundle: RockxyLocalization.bundle
                    )
                await viewModel.refreshSnapshot()
            } catch {
                guard certificateShareGeneration == generation else {
                    return
                }
                certificateShareStatusMessage = certificateShareFailureMessage(for: error)
            }
        }
    }

    private func stopPresentedCertificateSharing(
        expectedSessionID: RootCADownloadSession.ID? = nil
    ) {
        let sessionID = expectedSessionID ?? presentedShareSessionID
        guard let sessionID else {
            return
        }
        certificateShareGeneration += 1
        presentedShareSession = nil
        presentedShareSessionID = nil
        certificateShareStatusMessage = nil
        Task {
            await caShareController.stopSharing(
                clearSession: true,
                expectedSessionID: sessionID
            )
        }
    }

    private func stopAllCertificateSharing() {
        certificateShareGeneration += 1
        presentedShareSession = nil
        presentedShareSessionID = nil
        certificateShareStatusMessage = nil
        Task { await caShareController.stopSharing(clearSession: true) }
    }

    private func copyRootCAShareURL(_ url: URL) {
        do {
            try caShareController.copyShareURL(sessionURL: url)
            certificateShareStatusMessage = String(
                localized: "Certificate sharing URL copied.",
                bundle: RockxyLocalization.bundle
            )
        } catch {
            certificateShareStatusMessage = certificateShareFailureMessage(for: error)
        }
    }

    private func certificateShareFailureMessage(for error: Error) -> String {
        switch error {
        case let error as RootCADownloadError:
            CAShareController.userFacingMessage(for: error)
        case let error as RootCAShareValidationError:
            error.localizedDescription
        default:
            String(
                localized: "Certificate sharing could not be started for \(viewModel.selectedTarget.title). Check your network and try again.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private func refreshSnapshot() {
        Task { @MainActor in
            await viewModel.refreshSnapshot()
        }
    }
}
