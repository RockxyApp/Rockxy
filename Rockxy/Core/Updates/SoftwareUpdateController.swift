import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class SoftwareUpdateController: NSObject, ObservableObject, NSWindowDelegate {
    struct UpdateContext: Equatable {
        let title: String
        let summary: String
        let currentVersion: String
        let latestVersion: String
        let buildNumber: String
        let updateStageDescription: String
        let publishedDate: Date?
        let releaseNotes: SoftwareUpdateReleaseNotesContent
        let detailURL: URL?
        let isInformationOnly: Bool
        let downloadSize: Int64?
    }

    struct NoUpdateContext: Equatable {
        let title: String
        let summary: String
        let currentVersion: String
        let latestVersion: String?
        let releaseNotes: SoftwareUpdateReleaseNotesContent
        let detailURL: URL?
    }

    struct ErrorContext: Equatable {
        let title: String
        let summary: String
        let recoverySuggestion: String?
    }

    enum Phase: Equatable {
        case hidden
        case checking
        case available(UpdateContext)
        case downloading(UpdateContext, bytesReceived: Int64, expectedBytes: Int64?)
        case extracting(UpdateContext, progress: Double?)
        case readyToInstall(UpdateContext)
        case installing(UpdateContext, applicationTerminated: Bool)
        case noUpdate(NoUpdateContext)
        case error(ErrorContext)
    }

    @Published private(set) var phase: Phase = .hidden

    let configuration: RockxyUpdateConfiguration

    init(configuration: RockxyUpdateConfiguration) {
        self.configuration = configuration
        super.init()
    }

    var currentVersionSummary: String {
        "\(configuration.appVersion) (\(configuration.buildNumber))"
    }

    func showChecking(cancel: @escaping () -> Void) {
        resetCallbacks()
        activeDismiss = cancel
        phase = .checking
        showWindow()
    }

    func showAvailable(
        item: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let context = makeUpdateContext(from: item, state: state)
        showAvailable(context: context, reply: reply)
    }

    func showAvailable(
        context: UpdateContext,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        resetCallbacks()
        activeChoiceReply = reply
        activeDismiss = { reply(.dismiss) }
        activeUpdateContext = context
        phase = .available(context)
        showWindow()
    }

    func updateReleaseNotes(_ content: SoftwareUpdateReleaseNotesContent) {
        updatePhaseContext { context in
            let newReleaseNotes = preferredReleaseNotes(
                current: context.releaseNotes,
                incoming: content
            )
            return context.replacingReleaseNotes(with: newReleaseNotes)
        }
    }

    func showDownloading(cancel: @escaping () -> Void) {
        guard let context = refreshedUpdateContext(for: .notDownloaded) else {
            return
        }

        activeDismiss = cancel
        phase = .downloading(context, bytesReceived: 0, expectedBytes: context.downloadSize)
        showWindow()
    }

    func updateDownload(expectedBytes: UInt64) {
        guard case let .downloading(context, bytesReceived, _) = phase else {
            return
        }

        phase = .downloading(
            context,
            bytesReceived: bytesReceived,
            expectedBytes: Int64(clamping: expectedBytes)
        )
    }

    func updateDownloadedBytes(_ bytes: UInt64) {
        guard case let .downloading(context, bytesReceived, expectedBytes) = phase else {
            return
        }

        phase = .downloading(
            context,
            bytesReceived: bytesReceived + Int64(clamping: bytes),
            expectedBytes: expectedBytes
        )
    }

    func showExtracting() {
        guard let context = refreshedUpdateContext(for: .downloaded) else {
            return
        }

        activeDismiss = nil
        phase = .extracting(context, progress: nil)
        showWindow()
    }

    func updateExtractionProgress(_ progress: Double) {
        guard case let .extracting(context, _) = phase else {
            return
        }

        phase = .extracting(context, progress: min(max(progress, 0), 1))
    }

    func showReadyToInstall(reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let context = refreshedUpdateContext(for: .downloaded) else {
            return
        }

        activeChoiceReply = reply
        activeDismiss = { reply(.dismiss) }
        phase = .readyToInstall(context)
        showWindow()
    }

    func showInstalling(applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        guard let context = refreshedUpdateContext(for: .installing) else {
            return
        }

        activeDismiss = nil
        activeRetryTermination = retryTerminatingApplication
        phase = .installing(context, applicationTerminated: applicationTerminated)
        showWindow()
    }

    func showNoUpdate(error: NSError, acknowledgement: @escaping () -> Void) {
        resetCallbacks()
        activeAcknowledge = acknowledgement
        phase = .noUpdate(makeNoUpdateContext(from: error))
        showWindow()
    }

    func showError(_ error: NSError, acknowledgement: @escaping () -> Void) {
        resetCallbacks()
        activeAcknowledge = acknowledgement
        phase = .error(
            ErrorContext(
                title: String(localized: "Software update couldn’t be completed"),
                summary: error.localizedDescription,
                recoverySuggestion: error.localizedRecoverySuggestion
            )
        )
        showWindow()
    }

    func acknowledgeAndDismiss() {
        activeAcknowledge?()
        dismiss()
    }

    func dismiss() {
        programmaticClose = true
        windowController?.close()
        programmaticClose = false
        windowController = nil
        phase = .hidden
        activeUpdateContext = nil
        resetCallbacks()
    }

    func showInFocus() {
        showWindow()
    }

    func openDetailURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func chooseInstall() {
        activeChoiceReply?(.install)
        activeChoiceReply = nil
        activeDismiss = nil
    }

    func chooseSkip() {
        activeChoiceReply?(.skip)
        dismiss()
    }

    func chooseLater() {
        activeDismiss?()
        dismiss()
    }

    func retryTermination() {
        activeRetryTermination?()
    }

    func makeNoUpdateContext(from error: NSError) -> NoUpdateContext {
        let latestItem = error.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem
        let latestVersion = latestItem?.displayVersionString
        let latestPublishedFallback = String(
            localized: "Release notes are unavailable for the latest published version."
        )
        let localBuildFallback = String(
            localized: "Release notes for this local build are unavailable because this version is not published to the update feed yet."
        )
        let matchesRunningVersion = latestItem.map {
            $0.displayVersionString == configuration.appVersion && $0.versionString == configuration.buildNumber
        } ?? false
        let releaseNotes: SoftwareUpdateReleaseNotesContent
        let detailURL: URL?

        if let latestItem, matchesRunningVersion {
            releaseNotes = SoftwareUpdateReleaseNotesContent.from(appcastItem: latestItem)
                .resolvedForStaticDisplay(fallbackMessage: latestPublishedFallback)
            detailURL = latestItem.fullReleaseNotesURL ?? latestItem.releaseNotesURL ?? latestItem.infoURL ?? AppUpdater.fullChangelogURL
        } else {
            releaseNotes = .unavailable(matchesRunningVersion ? latestPublishedFallback : localBuildFallback)
            detailURL = matchesRunningVersion
                ? (latestItem?.fullReleaseNotesURL ?? latestItem?.releaseNotesURL ?? latestItem?.infoURL ?? AppUpdater.fullChangelogURL)
                : AppUpdater.fullChangelogURL
        }

        return NoUpdateContext(
            title: String(localized: "Rockxy is up to date"),
            summary: error.localizedDescription,
            currentVersion: currentVersionSummary,
            latestVersion: latestVersion,
            releaseNotes: releaseNotes,
            detailURL: detailURL
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard !programmaticClose else {
            return
        }

        if phase.requiresAcknowledgement {
            activeAcknowledge?()
        } else if phase.canDismissInteractively {
            activeDismiss?()
        }

        phase = .hidden
        activeUpdateContext = nil
        windowController = nil
        resetCallbacks()
    }

    private var windowController: NSWindowController?
    private var activeChoiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var activeDismiss: (() -> Void)?
    private var activeAcknowledge: (() -> Void)?
    private var activeRetryTermination: (() -> Void)?
    private var activeUpdateContext: UpdateContext?
    private var programmaticClose = false

    private func showWindow() {
        if windowController == nil {
            let rootView = SoftwareUpdatePanelView(controller: self)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = String(localized: "Software Update")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.isReleasedWhenClosed = false
            window.center()
            window.setContentSize(NSSize(width: 780, height: 610))
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.toolbarStyle = .unifiedCompact
            window.delegate = self
            windowController = NSWindowController(window: window)
        }

        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resetCallbacks() {
        activeChoiceReply = nil
        activeDismiss = nil
        activeAcknowledge = nil
        activeRetryTermination = nil
    }

    private func preferredReleaseNotes(
        current: SoftwareUpdateReleaseNotesContent,
        incoming: SoftwareUpdateReleaseNotesContent
    ) -> SoftwareUpdateReleaseNotesContent {
        switch (current, incoming) {
        case (.loading, _),
             (.unavailable, _):
            return incoming
        case (.html, .loading),
             (.html, .unavailable),
             (.plainText, .loading),
             (.plainText, .unavailable):
            return current
        case (.html, .html),
             (.html, .plainText),
             (.plainText, .html),
             (.plainText, .plainText):
            // Keep the appcast body instead of overwriting it with a full external release page.
            return current
        }
    }

    private func makeUpdateContext(from item: SUAppcastItem, state: SPUUserUpdateState) -> UpdateContext {
        let preferredTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = if let preferredTitle, !preferredTitle.isEmpty {
            preferredTitle
        } else {
            String(localized: "A new version of Rockxy is available")
        }

        let context = UpdateContext(
            title: title,
            summary: item.isInformationOnlyUpdate
                ? String(localized: "Review the latest release details for Rockxy.")
                : String(localized: "Rockxy \(item.displayVersionString) is now available. You’re currently using \(configuration.appVersion)."),
            currentVersion: configuration.appVersion,
            latestVersion: item.displayVersionString,
            buildNumber: item.versionString,
            updateStageDescription: updateStageDescription(for: state.stage),
            publishedDate: item.date as Date?,
            releaseNotes: SoftwareUpdateReleaseNotesContent.from(appcastItem: item),
            detailURL: item.fullReleaseNotesURL ?? item.releaseNotesURL ?? item.infoURL,
            isInformationOnly: item.isInformationOnlyUpdate,
            downloadSize: item.contentLength > 0 ? Int64(item.contentLength) : nil
        )
        return context
    }

    private func updatePhaseContext(_ transform: (UpdateContext) -> UpdateContext) {
        switch phase {
        case let .available(context):
            let newContext = transform(context)
            activeUpdateContext = newContext
            phase = .available(newContext)
        case let .downloading(context, bytesReceived, expectedBytes):
            let newContext = transform(context)
            activeUpdateContext = newContext
            phase = .downloading(newContext, bytesReceived: bytesReceived, expectedBytes: expectedBytes)
        case let .extracting(context, progress):
            let newContext = transform(context)
            activeUpdateContext = newContext
            phase = .extracting(newContext, progress: progress)
        case let .readyToInstall(context):
            let newContext = transform(context)
            activeUpdateContext = newContext
            phase = .readyToInstall(newContext)
        case let .installing(context, applicationTerminated):
            let newContext = transform(context)
            activeUpdateContext = newContext
            phase = .installing(newContext, applicationTerminated: applicationTerminated)
        default:
            break
        }
    }

    private func refreshedUpdateContext(for stage: SPUUserUpdateStage) -> UpdateContext? {
        guard let context = activeUpdateContext else {
            return nil
        }

        let newContext = context.replacingStageDescription(with: updateStageDescription(for: stage))
        activeUpdateContext = newContext
        return newContext
    }

    private func updateStageDescription(for stage: SPUUserUpdateStage) -> String {
        switch stage {
        case .notDownloaded:
            String(localized: "Not downloaded")
        case .downloaded:
            String(localized: "Downloaded")
        case .installing:
            String(localized: "Installing")
        @unknown default:
            String(localized: "Preparing update")
        }
    }
}

private extension SoftwareUpdateController.UpdateContext {
    func replacingReleaseNotes(with notes: SoftwareUpdateReleaseNotesContent) -> Self {
        .init(
            title: title,
            summary: summary,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            buildNumber: buildNumber,
            updateStageDescription: updateStageDescription,
            publishedDate: publishedDate,
            releaseNotes: notes,
            detailURL: detailURL,
            isInformationOnly: isInformationOnly,
            downloadSize: downloadSize
        )
    }

    func replacingStageDescription(with stageDescription: String) -> Self {
        .init(
            title: title,
            summary: summary,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            buildNumber: buildNumber,
            updateStageDescription: stageDescription,
            publishedDate: publishedDate,
            releaseNotes: releaseNotes,
            detailURL: detailURL,
            isInformationOnly: isInformationOnly,
            downloadSize: downloadSize
        )
    }
}

private extension SoftwareUpdateController.Phase {
    var canDismissInteractively: Bool {
        switch self {
        case .checking, .available, .readyToInstall:
            true
        default:
            false
        }
    }

    var requiresAcknowledgement: Bool {
        switch self {
        case .noUpdate, .error:
            true
        default:
            false
        }
    }
}
