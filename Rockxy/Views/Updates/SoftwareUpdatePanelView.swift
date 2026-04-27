import SwiftUI

struct SoftwareUpdatePanelView: View {
    @ObservedObject var controller: SoftwareUpdateController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 760, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: AppIconProvider.appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                Text(titleText)
                    .font(.system(size: 30, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(summaryText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    ForEach(headerBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .hidden:
            Color.clear

        case .checking:
            checkingContent

        case let .available(context):
            updateContent(context: context)

        case let .downloading(context, bytesReceived, expectedBytes):
            progressContent(
                context: context,
                title: String(localized: "Downloading update"),
                message: String(localized: "Rockxy is downloading the update package and verifying its signature."),
                progress: progressValue(received: bytesReceived, expected: expectedBytes),
                detail: downloadProgressDescription(received: bytesReceived, expected: expectedBytes)
            )

        case let .extracting(context, progress):
            progressContent(
                context: context,
                title: String(localized: "Preparing update"),
                message: String(localized: "Rockxy is extracting the update and getting it ready to install."),
                progress: progress,
                detail: String(localized: "You can keep working while preparation finishes.")
            )

        case let .readyToInstall(context):
            progressContent(
                context: context,
                title: String(localized: "Ready to install"),
                message: String(localized: "The update is downloaded and ready. Install it now to relaunch into the latest version."),
                progress: 1,
                detail: String(localized: "Sparkle has already verified the update package.")
            )

        case let .installing(context, applicationTerminated):
            progressContent(
                context: context,
                title: String(localized: "Installing update"),
                message: applicationTerminated
                    ? String(localized: "Rockxy is finishing installation in the background.")
                    : String(localized: "Rockxy is waiting for the app to terminate so installation can finish safely."),
                progress: nil,
                detail: applicationTerminated
                    ? String(localized: "The app will relaunch when installation completes.")
                    : String(localized: "If installation appears stuck, you can retry app termination.")
            )

        case let .noUpdate(context):
            noUpdateContent(context)

        case let .error(context):
            errorContent(context)
        }
    }

    private var footer: some View {
        HStack {
            if let supportingText {
                Text(supportingText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
                    Button(String(localized: "View Details")) {
                        controller.openDetailURL(url)
                    }
                }
                Button(primaryActionTitle) {
                    performAvailablePrimaryAction(context)
                }
                .keyboardShortcut(.defaultAction)

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
                    Button(String(localized: "View Details")) {
                        controller.openDetailURL(url)
                    }
                }
                Button(String(localized: "Install & Relaunch")) {
                    controller.chooseInstall()
                }
                .keyboardShortcut(.defaultAction)

            case let .installing(_, applicationTerminated):
                if !applicationTerminated {
                    Button(String(localized: "Retry Termination")) {
                        controller.retryTermination()
                    }
                }

            case .noUpdate, .error:
                if let url = detailURL {
                    Button(String(localized: "View Change Logs")) {
                        controller.openDetailURL(url)
                    }
                }
                Button(String(localized: "Done")) {
                    controller.acknowledgeAndDismiss()
                }
                .keyboardShortcut(.defaultAction)

            case .hidden:
                EmptyView()
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var checkingContent: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "Checking Rockxy’s signed update feed…"))
                .font(.system(size: 16, weight: .semibold))
            Text(
                String(
                    localized: "This may take a moment while we contact the update server and compare your current build."
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

    private func updateContent(context: SoftwareUpdateController.UpdateContext) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            metadataGrid(context)

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Release Notes"))
                    .font(.system(size: 15, weight: .semibold))

                releaseNotesView(context.releaseNotes)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(28)
    }

    private func progressContent(
        context: SoftwareUpdateController.UpdateContext,
        title: String,
        message: String,
        progress: Double?,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            metadataGrid(context)

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if let progress {
                    ProgressView(value: progress)
                        .controlSize(.large)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(28)
    }

    private func noUpdateContent(_ context: SoftwareUpdateController.NoUpdateContext) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            statusCard(
                icon: "checkmark.seal.fill",
                color: .green,
                title: context.title,
                message: context.summary
            )

            infoGrid(rows: [
                (String(localized: "Current Version"), context.currentVersion),
                (String(localized: "Latest Available"), context.latestVersion ?? String(localized: "This build"))
            ])

            Spacer(minLength: 0)
        }
        .padding(28)
    }

    private func errorContent(_ context: SoftwareUpdateController.ErrorContext) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            statusCard(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                title: context.title,
                message: context.summary
            )

            if let recoverySuggestion = context.recoverySuggestion {
                Text(recoverySuggestion)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .padding(28)
    }

    private func statusCard(icon: String, color: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metadataGrid(_ context: SoftwareUpdateController.UpdateContext) -> some View {
        infoGrid(rows: [
            (String(localized: "Current Version"), context.currentVersion),
            (String(localized: "Latest Version"), "\(context.latestVersion) (\(context.buildNumber))"),
            (String(localized: "Release Date"), context.publishedDate.map(formattedDate) ?? String(localized: "Not provided")),
            (String(localized: "Package Size"), context.downloadSize.map(formattedSize) ?? String(localized: "Not provided"))
        ])
    }

    private func infoGrid(rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(row.1)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

        case let .html(html, baseURL):
            HTMLPreviewView(html: html, baseURL: baseURL)

        case let .plainText(text):
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .background(Color(nsColor: .textBackgroundColor))

        case let .unavailable(message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if let detailURL {
                    Button(String(localized: "Open Full Details")) {
                        controller.openDetailURL(detailURL)
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
        }
    }

    private var titleText: String {
        switch controller.phase {
        case .checking:
            String(localized: "Checking for Updates")
        case let .available(context),
             let .downloading(context, _, _),
             let .extracting(context, _),
             let .readyToInstall(context),
             let .installing(context, _):
            context.title
        case let .noUpdate(context):
            context.title
        case let .error(context):
            context.title
        case .hidden:
            String(localized: "Software Update")
        }
    }

    private var summaryText: String {
        switch controller.phase {
        case .checking:
            String(localized: "Rockxy is reaching out to the signed update feed.")
        case let .available(context),
             let .downloading(context, _, _),
             let .extracting(context, _),
             let .readyToInstall(context),
             let .installing(context, _):
            context.summary
        case let .noUpdate(context):
            context.summary
        case let .error(context):
            context.summary
        case .hidden:
            controller.currentVersionSummary
        }
    }

    private var supportingText: String? {
        switch controller.phase {
        case .checking:
            String(localized: "You can cancel this check at any time.")
        case .available, .readyToInstall:
            String(localized: "Updates are signed and verified before Rockxy installs them.")
        case .downloading:
            String(localized: "Download progress is shown live from Sparkle’s updater.")
        case .extracting:
            String(localized: "Extraction runs locally on your Mac.")
        case .installing:
            String(localized: "Rockxy will relaunch after installation completes.")
        case .noUpdate:
            String(localized: "You can still review the latest release history.")
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

    private var headerBadges: [String] {
        switch controller.phase {
        case let .available(context),
             let .downloading(context, _, _),
             let .extracting(context, _),
             let .readyToInstall(context),
             let .installing(context, _):
            return [
                String(localized: "Current \(context.currentVersion)"),
                String(localized: "Latest \(context.latestVersion)")
            ]
        case let .noUpdate(context):
            return [String(localized: "Current \(context.currentVersion)")]
        default:
            return []
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
