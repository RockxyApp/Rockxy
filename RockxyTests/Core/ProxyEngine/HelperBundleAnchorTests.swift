import Foundation
@testable import Rockxy
import Testing

// MARK: - HelperBundleAnchorTests

struct HelperBundleAnchorTests {
    @Test("An installed copy can anchor a registration")
    func installedCopyIsStable() {
        #expect(HelperBundleAnchor.anchor(forBundlePath: "/Applications/Rockxy.app") == .stable)
        #expect(HelperBundleAnchor.anchor(forBundlePath: "/Users/someone/Applications/Rockxy.app") == .stable)
        #expect(HelperBundleAnchor.anchor(forBundlePath: "/Applications/Rockxy.app").canAnchorRegistration)
    }

    @Test("A translocated copy cannot anchor a registration")
    func translocatedCopyIsRefused() {
        // What macOS actually runs when a quarantined app is opened from Downloads: a read-only
        // copy at a randomised path that is discarded on quit, taking the anchor with it.
        let translocated = "/private/var/folders/qr/9x_1h4t17qq_r/T/AppTranslocation"
            + "/A1B2C3D4-0000-1111-2222-333344445555/d/Rockxy.app"
        #expect(HelperBundleAnchor.anchor(forBundlePath: translocated) == .translocated)
        #expect(!HelperBundleAnchor.anchor(forBundlePath: translocated).canAnchorRegistration)
    }

    @Test("A copy on a mounted volume cannot anchor a registration")
    func mountedVolumeIsRefused() {
        // The download flow this exists for: open the disk image, run Rockxy from it, then
        // eject. The registration would survive the eject and never resolve again.
        #expect(HelperBundleAnchor.anchor(forBundlePath: "/Volumes/Rockxy 0.42.0/Rockxy.app") == .mountedVolume)
        #expect(HelperBundleAnchor.anchor(forBundlePath: "/Volumes/External/Applications/Rockxy.app") == .mountedVolume)
        #expect(!HelperBundleAnchor.anchor(forBundlePath: "/Volumes/Rockxy/Rockxy.app").canAnchorRegistration)
    }

    @Test("A path that merely mentions a refused location is still stable")
    func lookalikePathsAreNotRefused() {
        // Substring checks are the kind that over-match; pin that they do not.
        #expect(HelperBundleAnchor.anchor(forBundlePath: "/Applications/Volumes Inspector.app") == .stable)
        #expect(HelperBundleAnchor.anchor(forBundlePath: "/Users/someone/Volumes/Rockxy.app") == .stable)
        #expect(HelperBundleAnchor.anchor(forBundlePath: "/Applications/AppTranslocation Helper.app") == .stable)
    }

    @Test("Every refused location says what to do, and the stable one says nothing")
    func refusalMessagesNameTheMove() {
        #expect(HelperBundleAnchor.stable.refusalMessage.isEmpty)
        for anchor in [HelperBundleAnchor.translocated, .mountedVolume] {
            let message = anchor.refusalMessage
            #expect(!message.isEmpty)
            // The action is the point of the message: without it the user is told only that
            // something is wrong. Two earlier versions of the sibling copy named actions that do
            // not exist, so pin that this one names the one that does.
            #expect(message.contains("Applications"))
        }
    }

    @Test("Install preflight refuses a bundle that cannot anchor the registration")
    func preflightRefusesUnanchorableBundle() {
        // A real bundle on a mounted volume is not constructible in a test, so drive the same
        // decision the preflight makes through the path it is given.
        let onVolume = HelperBundleAnchor.anchor(forBundlePath: "/Volumes/Rockxy/Rockxy.app")
        let error = HelperManager.HelperInstallPreflightError.unanchorableBundleLocation(onVolume)
        #expect(error.errorDescription == onVolume.refusalMessage)
        // A package problem and a location problem must not read the same, or the user is told
        // the download is corrupt when the download is fine.
        let packageProblem = HelperManager.HelperInstallPreflightError.invalidBundledHelperSignature
        #expect(error.errorDescription != packageProblem.errorDescription)
    }
}
