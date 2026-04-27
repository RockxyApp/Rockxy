import Foundation
import Sparkle

@MainActor
final class RockxyUpdateUserDriver: NSObject, SPUUserDriver {
    init(hostBundle: Bundle, configuration: RockxyUpdateConfiguration) {
        standardUserDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        controller = SoftwareUpdateController(configuration: configuration)
        super.init()
    }

    let controller: SoftwareUpdateController

    private let standardUserDriver: SPUStandardUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standardUserDriver.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        controller.showChecking(cancel: cancellation)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        controller.showAvailable(item: appcastItem, state: state, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        controller.updateReleaseNotes(.from(downloadData: downloadData))
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        controller.updateReleaseNotes(
            .unavailable(
                String(localized: "Release notes couldn’t be loaded for this update.")
            )
        )
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        controller.showNoUpdate(error: error as NSError, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        controller.showError(error as NSError, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        controller.showDownloading(cancel: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        controller.updateDownload(expectedBytes: expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        controller.updateDownloadedBytes(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        controller.showExtracting()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        controller.updateExtractionProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        controller.showReadyToInstall(reply: reply)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        controller.showInstalling(
            applicationTerminated: applicationTerminated,
            retryTerminatingApplication: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        controller.dismiss()
    }

    func dismissUpdateInstallation() {
        controller.dismiss()
    }

    func showUpdateInFocus() {
        controller.showInFocus()
    }
}
