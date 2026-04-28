import SwiftUI

struct SoftwareUpdatePanelView: View {
    @ObservedObject var controller: SoftwareUpdateController
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 780, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .hidden:
            Color.clear

        case .checking:
            checkingContent

        case let .available(context):
            updateDialog(
                symbol: "arrow.down.circle.fill",
                symbolTint: .accentColor,
                title: String(localized: "A new version of Rockxy is available."),
                summary: context.summary,
                notesLabel: String(localized: "Release Notes"),
                notesCaption: String(
                    localized: "Show the current version changelog inline so the first useful update details are visible immediately."
                ),
                notesVersionLabel: versionPanelLabel(
                    version: context.latestVersion,
                    buildNumber: context.buildNumber,
                    fallback: String(localized: "Latest")
                ),
                notes: context.releaseNotes,
                progress: nil
            )

        case let .downloading(context, bytesReceived, expectedBytes):
            progressDialog(
                context: context,
                title: String(localized: "Downloading Rockxy \(context.latestVersion)…"),
                summary: String(
                    localized: "Rockxy is downloading the signed update package and verifying it before installation."
                ),
                detailLabel: String(localized: "Download Details"),
                detailCaption: String(
                    localized: "The installer is being fetched now. Release notes stay in the same place so the dialog does not jump around."
                ),
                detailMessage: downloadProgressDescription(received: bytesReceived, expected: expectedBytes),
                progress: progressValue(received: bytesReceived, expected: expectedBytes)
            )

        case let .extracting(context, progress):
            progressDialog(
                context: context,
                title: String(localized: "Preparing Rockxy \(context.latestVersion)…"),
                summary: String(
                    localized: "Rockxy is extracting the update and preparing the signed app bundle for installation."
                ),
                detailLabel: String(localized: "Preparation Details"),
                detailCaption: String(
                    localized: "Preparation runs locally on your Mac. The update has already been validated by Sparkle."
                ),
                detailMessage: String(localized: "Preparing the app bundle and installation metadata."),
                progress: progress
            )

        case let .readyToInstall(context):
            updateDialog(
                symbol: "checkmark.circle.fill",
                symbolTint: .green,
                title: String(localized: "Rockxy \(context.latestVersion) is ready to install."),
                summary: String(
                    localized: "The update has been downloaded and verified. Install now to relaunch into the latest version."
                ),
                notesLabel: String(localized: "Release Notes"),
                notesCaption: String(
                    localized: "Keep the latest notes visible here so the user can review them one last time before relaunching."
                ),
                notesVersionLabel: versionPanelLabel(
                    version: context.latestVersion,
                    buildNumber: context.buildNumber,
                    fallback: String(localized: "Ready")
                ),
                notes: context.releaseNotes,
                progress: nil
            )

        case let .installing(context, applicationTerminated):
            progressDialog(
                context: context,
                title: String(localized: "Installing Rockxy \(context.latestVersion)…"),
                summary: applicationTerminated
                    ? String(localized: "Rockxy is finishing the installation in the background and will relaunch automatically.")
                    : String(localized: "Rockxy is waiting for the app to terminate so installation can finish safely."),
                detailLabel: String(localized: "Installation Details"),
                detailCaption: String(
                    localized: "This keeps the same structured panel shape as the release notes view, but shifts the content toward installation progress."
                ),
                detailMessage: applicationTerminated
                    ? String(localized: "Installing the new app bundle and refreshing the helper.")
                    : String(localized: "Waiting for the running app process to exit before replacing the bundle."),
                progress: applicationTerminated ? 0.8 : nil
            )

        case let .noUpdate(context):
            updateDialog(
                symbol: "checkmark.circle.fill",
                symbolTint: .green,
                title: String(localized: "Rockxy is up to date."),
                summary: context.summary,
                notesLabel: String(localized: "Release Notes"),
                notesCaption: String(
                    localized: "Keep the current release notes visible here so a successful check still feels informative."
                ),
                notesVersionLabel: versionPanelLabel(
                    version: context.latestVersion,
                    buildNumber: nil,
                    fallback: context.currentVersion
                ),
                notes: context.releaseNotes,
                progress: nil
            )

        case let .error(context):
            errorContent(context)
        }
    }

    private var checkingContent: some View {
        VStack(spacing: 14) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text(String(localized: "Checking for updates"))
                .font(.system(size: 22, weight: .semibold))

            Text(
                String(
                    localized: "Rockxy is reaching out to the signed update feed and comparing your current build."
                )
            )
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func updateDialog(
        symbol: String,
        symbolTint: Color,
        title: String,
        summary: String,
        notesLabel: String,
        notesCaption: String,
        notesVersionLabel: String,
        notes: SoftwareUpdateReleaseNotesContent,
        progress: ProgressPresentation?
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            hero(symbol: symbol, symbolTint: symbolTint, title: title, summary: summary)
            releaseNotesGroup(
                label: notesLabel,
                caption: notesCaption,
                versionLabel: notesVersionLabel,
                content: notes,
                minHeight: 300
            )

            if let progress {
                progressStrip(progress)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private func progressDialog(
        context: SoftwareUpdateController.UpdateContext,
        title: String,
        summary: String,
        detailLabel: String,
        detailCaption: String,
        detailMessage: String,
        progress: Double?
    ) -> some View {
        updateDialog(
            symbol: "clock.arrow.circlepath",
            symbolTint: .secondary,
            title: title,
            summary: summary,
            notesLabel: detailLabel,
            notesCaption: detailCaption,
            notesVersionLabel: versionPanelLabel(
                version: context.latestVersion,
                buildNumber: context.buildNumber,
                fallback: String(localized: "Installing")
            ),
            notes: .plainText(detailMessage),
            progress: ProgressPresentation(
                label: String(localized: "Installing update and refreshing helper…"),
                detail: progressDetail(for: controller.phase),
                value: progress
            )
        )
    }

    private func errorContent(_ context: SoftwareUpdateController.ErrorContext) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            hero(
                symbol: "exclamationmark.triangle.fill",
                symbolTint: .orange,
                title: context.title,
                summary: context.summary
            )

            if let recoverySuggestion = context.recoverySuggestion {
                releaseNotesGroup(
                    label: String(localized: "Recovery Suggestion"),
                    caption: String(localized: "Rockxy could not complete the update flow. Review the recovery guidance below."),
                    versionLabel: String(localized: "Error Details"),
                    content: .plainText(recoverySuggestion),
                    minHeight: 220
                )
            } else {
                releaseNotesGroup(
                    label: String(localized: "Update Details"),
                    caption: String(localized: "No additional recovery suggestion was provided for this failure."),
                    versionLabel: String(localized: "Error Details"),
                    content: .unavailable(
                        String(localized: "No additional recovery guidance is available for this error.")
                    ),
                    minHeight: 220
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private func hero(
        symbol: String,
        symbolTint: Color,
        title: String,
        summary: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            appIcon

            statusBadge(symbol: symbol, tint: symbolTint)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private var appIcon: some View {
        Image(nsImage: AppIconProvider.appIcon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusBadge(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.12), in: Circle())
            .overlay(
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
    }

    private func releaseNotesGroup(
        label: String,
        caption: String,
        versionLabel: String,
        content: SoftwareUpdateReleaseNotesContent,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                HStack {
                    Text(versionLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                releaseNotesView(content)
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private func releaseNotesView(_ content: SoftwareUpdateReleaseNotesContent) -> some View {
        switch content {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(String(localized: "Loading release notes…"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)

        case .html, .plainText:
            if let attributedText = content.nativeDisplayAttributedString(
                fallbackMessage: String(localized: "Release notes are unavailable for this update.")
            ) {
                NativeReleaseNotesTextView(attributedText: attributedText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Release notes are unavailable for this update."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(18)
            }

        case let .unavailable(message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let detailURL {
                    Button(String(localized: "Open Full Change Log")) {
                        controller.openDetailURL(detailURL)
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
        }
    }

    private func progressStrip(_ progress: ProgressPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(progress.label)
                .font(.system(size: 13, weight: .medium))

            if let value = progress.value {
                ProgressView(value: value)
                    .controlSize(.large)
            } else {
                ProgressView()
                    .controlSize(.large)
            }

            if let detail = progress.detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerLeadingContent

            Spacer()

            footerButtons
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var footerLeadingContent: some View {
        switch controller.phase {
        case .available:
            if updater.supportsAutomaticChecks, updater.allowsAutomaticUpdates {
                Toggle(
                    isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticallyDownloadsUpdates($0) }
                    )
                ) {
                    Text(String(localized: "Automatically download and install future updates"))
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
            } else if let supportingText {
                Text(supportingText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

        default:
            if let supportingText {
                Text(supportingText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch controller.phase {
        case .checking:
            Button(String(localized: "Cancel")) {
                controller.chooseLater()
            }

        case let .available(context):
            Button(String(localized: "Skip This Version")) {
                controller.chooseSkip()
            }
            if let url = detailURL {
                Button(String(localized: "View Full Change Log")) {
                    controller.openDetailURL(url)
                }
            }
            Button(primaryActionTitle) {
                performAvailablePrimaryAction(context)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)

        case .downloading:
            Button(String(localized: "Cancel Download")) {
                controller.chooseLater()
            }

        case .extracting:
            EmptyView()

        case .readyToInstall:
            Button(String(localized: "Later")) {
                controller.chooseLater()
            }
            if let url = detailURL {
                Button(String(localized: "View Full Change Log")) {
                    controller.openDetailURL(url)
                }
            }
            Button(String(localized: "Install and Relaunch")) {
                controller.chooseInstall()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)

        case let .installing(_, applicationTerminated):
            if !applicationTerminated {
                Button(String(localized: "Retry Termination")) {
                    controller.retryTermination()
                }
            }

        case .noUpdate:
            if let url = detailURL {
                Button(String(localized: "View Full Change Log")) {
                    controller.openDetailURL(url)
                }
            }
            Button(String(localized: "Done")) {
                controller.acknowledgeAndDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)

        case .error:
            if let url = detailURL {
                Button(String(localized: "Open Change Log")) {
                    controller.openDetailURL(url)
                }
            }
            Button(String(localized: "Done")) {
                controller.acknowledgeAndDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)

        case .hidden:
            EmptyView()
        }
    }

    private var supportingText: String? {
        switch controller.phase {
        case .checking:
            String(localized: "You can cancel this check at any time.")
        case .available, .readyToInstall:
            String(localized: "Updates are signed and verified before Rockxy installs them.")
        case .downloading:
            String(localized: "Download progress is reported live by Sparkle.")
        case .extracting:
            String(localized: "Preparation runs locally on your Mac.")
        case .installing:
            String(localized: "Rockxy will relaunch after installation completes.")
        case .noUpdate:
            String(localized: "You can still review the full release history.")
        case .error:
            String(localized: "No captured traffic or license data is sent as part of update errors.")
        case .hidden:
            nil
        }
    }

    private var detailURL: URL? {
        switch controller.phase {
        case let .available(context),
             let .downloading(context, _, _),
             let .extracting(context, _),
             let .readyToInstall(context),
             let .installing(context, _):
            context.detailURL
        case let .noUpdate(context):
            context.detailURL
        case .error:
            AppUpdater.fullChangelogURL
        case .checking, .hidden:
            nil
        }
    }

    private var primaryActionTitle: String {
        switch controller.phase {
        case let .available(context):
            if context.isInformationOnly {
                String(localized: "Learn More")
            } else {
                String(localized: "Install Update")
            }
        default:
            String(localized: "Continue")
        }
    }

    private func versionPanelLabel(version: String?, buildNumber: String?, fallback: String) -> String {
        if let version, let buildNumber, !buildNumber.isEmpty {
            return String(localized: "Version \(version) (\(buildNumber))")
        }
        if let version, !version.isEmpty {
            return String(localized: "Version \(version)")
        }
        return fallback
    }

    private func progressValue(received: Int64, expected: Int64?) -> Double? {
        guard let expected, expected > 0 else {
            return nil
        }
        return min(max(Double(received) / Double(expected), 0), 1)
    }

    private func downloadProgressDescription(received: Int64, expected: Int64?) -> String {
        if let expected, expected > 0 {
            return "\(formattedSize(received)) / \(formattedSize(expected))"
        }
        return formattedSize(received)
    }

    private func progressDetail(for phase: SoftwareUpdateController.Phase) -> String? {
        switch phase {
        case let .downloading(_, bytesReceived, expectedBytes):
            downloadProgressDescription(received: bytesReceived, expected: expectedBytes)
        case .extracting:
            String(localized: "Preparing the new app bundle and installation metadata.")
        case let .installing(_, applicationTerminated):
            if applicationTerminated {
                String(localized: "Finishing installation and relaunch preparation.")
            } else {
                String(localized: "Waiting for the running app process to terminate safely.")
            }
        default:
            nil
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func performAvailablePrimaryAction(_ context: SoftwareUpdateController.UpdateContext) {
        if context.isInformationOnly {
            if let url = context.detailURL {
                controller.openDetailURL(url)
            }
            controller.chooseLater()
            return
        }

        controller.chooseInstall()
    }
}

private struct ProgressPresentation {
    let label: String
    let detail: String?
    let value: Double?
}

private struct NativeReleaseNotesTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindPanel = false
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.usesDefaultHyphenation = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.textStorage?.setAttributedString(attributedText)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        guard let textStorage = textView.textStorage else {
            return
        }
        if textStorage.isEqual(to: attributedText) {
            return
        }
        textStorage.setAttributedString(attributedText)
    }
}
