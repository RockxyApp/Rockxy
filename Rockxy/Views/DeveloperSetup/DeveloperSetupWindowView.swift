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
        VStack(spacing: 0) {
            toolbar
            Divider()
            infoBanner
            Divider()
            contentBody
            Divider()
            bottomBar
        }
        .frame(minWidth: 1_080, minHeight: 720)
        .task {
            await viewModel.refreshSnapshot()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showsAutomationSheet },
            set: { isPresented in
                if !isPresented {
                    viewModel.closeAutomationSheet()
                }
            }
        )) {
            if let preview = viewModel.currentAutomationPreview {
                DeveloperSetupAutomationSheet(
                    target: viewModel.selectedTarget,
                    preview: preview,
                    onContinueManual: {
                        viewModel.selectTab(.setup)
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionCleared)) { _ in
            viewModel.handleSessionCleared()
        }
        .onChange(of: coordinator.isProxyRunning) { _, _ in refreshSnapshot() }
        .onChange(of: coordinator.isRecording) { _, _ in refreshSnapshot() }
        .onChange(of: coordinator.activeProxyPort) { _, _ in refreshSnapshot() }
        .onChange(of: coordinator.sessionGeneration) { _, _ in refreshSnapshot() }
        .onChange(of: ReadinessCoordinator.shared.certReadiness) { refreshSnapshot() }
        .onChange(of: ReadinessCoordinator.shared.proxyMode) { refreshSnapshot() }
        .onChange(of: ReadinessCoordinator.shared.activeWarning) { refreshSnapshot() }
        .onDisappear {
            viewModel.cancelValidation(markCancelled: true)
        }
    }

    // MARK: Private

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel: DeveloperSetupViewModel

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Developer Setup Hub"))
                    .font(.headline)
                Text(viewModel.selectedTarget.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            toolbarSearchField

            Button(String(localized: "Copy")) {
                copySnippetToPasteboard()
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.toolbarCopyEnabled)

            Button(String(localized: "Verify")) {
                viewModel.selectTab(.validate)
                viewModel.startValidation()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.toolbarVerifyEnabled)

            Button(String(localized: "Open in Tools")) {
                openSelectedTool()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var infoBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.selectedTarget.supportStatus == .availableNow ? "checkmark.circle" : "info.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedTarget.supportStatus.bannerTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.infoBannerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }

    private var contentBody: some View {
        HStack(spacing: 0) {
            DeveloperSetupSourceList(
                selectedTarget: viewModel.selectedTarget,
                sections: viewModel.filteredTargetSections,
                isPinned: { target in
                    viewModel.isPinned(target)
                }
            ) { target in
                viewModel.selectTarget(target)
                refreshSnapshot()
            } onTogglePinned: { target in
                viewModel.togglePinned(target)
            }
            .frame(width: 240)

            Divider()

            VStack(spacing: 0) {
                centerHeader
                Divider()
                centerContent
            }

            Divider()

            DeveloperSetupInspector(
                target: viewModel.selectedTarget,
                snapshot: viewModel.snapshot,
                activeIssue: viewModel.activeIssue,
                automationPreview: viewModel.currentAutomationPreview,
                supportsValidation: viewModel.supportsValidation,
                validationInstruction: viewModel.validationInstruction,
                onRunTest: { viewModel.startValidation() },
                onOpenAutomation: { viewModel.openAutomationSheet() },
                onOpenCertificate: { openSettings() },
                onOpenTools: { openSelectedTool() },
                onRevealRequest: { viewModel.revealMatchedTransaction() }
            )
            .frame(width: 280)
        }
    }

    private var centerHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedTarget.title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(viewModel.selectedTarget.shortSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        supportBadge(
                            title: viewModel.selectedTarget.supportStatus.title,
                            fill: viewModel.selectedTarget.supportStatus == .availableNow
                                ? Color(nsColor: .systemGreen).opacity(0.12)
                                : Color(nsColor: .quaternaryLabelColor).opacity(0.12),
                            stroke: viewModel.selectedTarget.supportStatus == .availableNow
                                ? Color(nsColor: .systemGreen).opacity(0.28)
                                : Color(nsColor: .separatorColor).opacity(0.4),
                            textColor: viewModel.selectedTarget.supportStatus == .availableNow
                                ? Color(nsColor: .systemGreen)
                                : Color(nsColor: .secondaryLabelColor)
                        )

                        if viewModel.supportsAutomation {
                            supportBadge(
                                title: viewModel.selectedTarget.automationSupport.badgeTitle,
                                fill: Color(nsColor: .systemBlue).opacity(0.12),
                                stroke: Color(nsColor: .systemBlue).opacity(0.24),
                                textColor: Color(nsColor: .systemBlue)
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        Picker("", selection: Binding(
                            get: { viewModel.selectedTab },
                            set: { viewModel.selectTab($0) }
                        )) {
                            ForEach(SetupDetailTab.allCases) { tab in
                                Text(tab.title).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 430)

                        if viewModel.supportsAutomation {
                            Button(viewModel.selectedTarget.automationSupport.entryActionTitle) {
                                viewModel.openAutomationSheet()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var centerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            overviewGrid

            detailCard(
                title: String(localized: "Current support"),
                systemImage: "checkmark.shield"
            ) {
                Text(viewModel.selectedTarget.currentSupportSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(viewModel.selectedTarget.manualSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            statusCard(
                title: String(localized: "Proxy"),
                value: viewModel.snapshot.proxyRunning ? String(localized: "Running") : String(localized: "Stopped"),
                caption: String(localized: "\(viewModel.snapshot.effectiveListenAddress):\(viewModel.snapshot.activePort)")
            )
            statusCard(
                title: String(localized: "Recording"),
                value: viewModel.snapshot.recordingEnabled ? String(localized: "Enabled") : String(localized: "Paused"),
                caption: String(localized: "Requests must be recorded to validate the setup.")
            )
            statusCard(
                title: String(localized: "Listen Address"),
                value: viewModel.snapshot.effectiveListenAddress,
                caption: String(localized: "Validated runtime snippets target the local loopback address.")
            )
            statusCard(
                title: String(localized: "Certificate"),
                value: viewModel.snapshot.certificateTrusted ? String(localized: "Trusted") : String(localized: "Needs attention"),
                caption: viewModel.snapshot.certificateFileReady
                    ? String(localized: "A root certificate is available for your client configuration.")
                    : String(localized: "Generate or export the root certificate before validating HTTPS traffic.")
            )
        }
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.selectedTarget.supportStatus == .availableNow {
                ForEach(viewModel.currentSetupSteps) { step in
                    stepRow(step)
                }
            } else if let guideContent = viewModel.currentGuideContent {
                guideTipSection(
                    title: String(localized: "Manual guide"),
                    systemImage: "list.bullet.rectangle",
                    tips: guideContent.setupTips
                )
            } else {
                guideOnlyContent(
                    title: String(localized: "Manual guide"),
                    message: viewModel.selectedTarget.manualSummary
                )
            }
        }
    }

    private var snippetsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.selectedTarget.supportStatus == .availableNow, let currentSnippetText = viewModel.currentSnippetText {
                if viewModel.currentSnippetOptions.count > 1 {
                    UtilitySegmentedHeader(width: 420) {
                        Picker("", selection: $viewModel.selectedSnippetID) {
                            ForEach(viewModel.currentSnippetOptions) { snippet in
                                Text(snippet.title).tag(snippet.id)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, -16)
                    .padding(.top, -4)
                }

                snippetMetadata

                ScrollView(.horizontal) {
                    Text(currentSnippetText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.6))
                                )
                        )
                }
            } else {
                guideOnlyEmptyState(
                    title: String(localized: "No first-party snippet in Rockxy for this target yet"),
                    message: viewModel.selectedTarget.currentSupportSummary
                )
            }
        }
    }

    private var snippetMetadata: some View {
        HStack(spacing: 16) {
            metadataItem(title: String(localized: "Snippet"), value: viewModel.currentSnippetTitle)
            metadataItem(
                title: String(localized: "Trust"),
                value: viewModel.snapshot.certificateTrusted ? String(localized: "Trusted") : String(localized: "Needs attention")
            )
            metadataItem(title: String(localized: "Certificate file"), value: viewModel.certificatePathStatusText)
            metadataItem(title: String(localized: "Validation"), value: viewModel.snapshot.verificationState.title)
            Spacer(minLength: 0)
        }
    }

    private var validateContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.supportsValidation, let currentSnippetText = viewModel.currentValidationSnippetText {
                detailCard(
                    title: String(localized: "Validation request"),
                    systemImage: "bolt.horizontal.circle"
                ) {
                    Text(viewModel.validationInstruction)
                        .font(.subheadline)
                    Text(viewModel.snapshot.verificationState.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal) {
                    Text(currentSnippetText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.6))
                                )
                        )
                }

                HStack(spacing: 10) {
                    Button(String(localized: "Run Test")) {
                        viewModel.startValidation()
                    }
                    .buttonStyle(.borderedProminent)

                    if viewModel.snapshot.verificationState == .success, viewModel.snapshot.matchedTransactionID != nil {
                        Button(String(localized: "Reveal in Main Window")) {
                            viewModel.revealMatchedTransaction()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else if let guideContent = viewModel.currentGuideContent, !guideContent.validationTips.isEmpty {
                guideTipSection(
                    title: String(localized: "Manual validation"),
                    systemImage: "checklist",
                    tips: guideContent.validationTips
                )
            } else {
                guideOnlyEmptyState(
                    title: String(localized: "Interactive validation is not available for this target"),
                    message: viewModel.selectedTarget.manualSummary
                )
            }
        }
    }

    private var troubleshootingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.selectedTarget.supportStatus == .availableNow {
                ForEach(viewModel.troubleshootingIssues) { issue in
                    detailCard(title: issue.title, systemImage: "exclamationmark.triangle") {
                        Text(issue.message)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            Button(issue.actionTitle) {
                                handleIssueAction(issue)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else if let guideContent = viewModel.currentGuideContent, !guideContent.troubleshootingTips.isEmpty {
                guideTipSection(
                    title: String(localized: "Common issues"),
                    systemImage: "wrench.and.screwdriver",
                    tips: guideContent.troubleshootingTips
                )
            } else {
                guideOnlyContent(
                    title: String(localized: "Current limitation"),
                    message: viewModel.selectedTarget.currentSupportSummary
                )
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text(viewModel.bottomStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if let warning = viewModel.snapshot.readinessWarningMessage {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbarSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField(String(localized: "Search setups"), text: $viewModel.sourceListSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 180)

            if !viewModel.sourceListSearchText.isEmpty {
                Button {
                    viewModel.sourceListSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.85))
        )
    }

    private func statusCard(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func stepRow(_ step: SetupStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(step.isComplete ? .green : .secondary)
                .font(.system(size: 16, weight: .medium))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                Text(step.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(step.actionTitle) {
                handleStepAction(step)
            }
            .buttonStyle(.bordered)
            .disabled(!step.isEnabled)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func detailCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func supportBadge(title: String, fill: Color, stroke: Color, textColor: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(stroke)
            )
    }

    private func guideOnlyContent(title: String, message: String) -> some View {
        detailCard(title: title, systemImage: "info.circle") {
            Text(message)
                .font(.subheadline)
            Text(String(localized: "Rockxy shows this target now so the long-term hub taxonomy stays stable, but this target remains guidance-only today."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func guideTipSection(title: String, systemImage: String, tips: [SetupGuideTip]) -> some View {
        detailCard(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(tips) { tip in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tip.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(tip.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func guideOnlyEmptyState(title: String, message: String) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "square.dashed")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func metadataItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private func copySnippetToPasteboard() {
        guard let text = viewModel.copyTextForCurrentContext() else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func handleStepAction(_ step: SetupStep) {
        viewModel.performStepAction(step)

        switch step.actionKind {
        case .verifyProxy:
            refreshSnapshot()
        case .openCertificate:
            openSettings()
        case .copySnippet:
            copySnippetToPasteboard()
        case .runValidation:
            viewModel.startValidation()
        }
    }

    private func handleIssueAction(_ issue: SetupIssue) {
        switch issue {
        case .runtimeNotInstalled:
            viewModel.selectTab(.setup)
        case .proxyStopped,
             .recordingPaused:
            refreshSnapshot()
        case .certificateNotTrusted,
             .certificateExportUnavailable:
            openSettings()
        case .noTrafficDetected:
            viewModel.selectTab(.validate)
            viewModel.startValidation()
        case .wrongSnippetChosen:
            viewModel.selectTab(.snippets)
        case .targetIsGuideOnly:
            viewModel.selectTab(.overview)
        }
    }

    private func openSelectedTool() {
        if let issue = viewModel.activeIssue,
           issue == .certificateNotTrusted || issue == .certificateExportUnavailable
        {
            openSettings()
            return
        }
        openWindow(id: "advancedProxySettings")
    }

    private func refreshSnapshot() {
        Task { @MainActor in
            await viewModel.refreshSnapshot()
        }
    }
}
