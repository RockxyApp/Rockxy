import Foundation
@testable import Rockxy
import Testing

// MARK: - HelperRegistrationGuardTests

struct HelperRegistrationGuardTests {
    @Test("a plain launch is not a test host")
    func plainLaunchIsNotATestHost() {
        #expect(!HelperRegistrationGuard.isTestHost(isTestFrameworkLoaded: false))
    }

    @Test("a loaded test framework is a test host on its own")
    func loadedFrameworkIsSufficient() {
        // The image scan is the only signal, and it is sufficient. A hardened-runtime app with
        // library validation does not load a foreign framework and has DYLD_INSERT_LIBRARIES
        // stripped, so a shipped Rockxy cannot reach this state.
        #expect(HelperRegistrationGuard.isTestHost(isTestFrameworkLoaded: true))
    }

    @Test("test framework images are recognised by path")
    func frameworkImagePaths() {
        let xctest = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer"
            + "/Library/Frameworks/XCTest.framework/Versions/A/XCTest"
        let testing = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer"
            + "/Library/Frameworks/Testing.framework/Versions/A/Testing"
        #expect(HelperRegistrationGuard.isTestFrameworkImagePath(xctest))
        #expect(HelperRegistrationGuard.isTestFrameworkImagePath(testing))
        #expect(!HelperRegistrationGuard.isTestFrameworkImagePath("/usr/lib/libSystem.B.dylib"))
        #expect(!HelperRegistrationGuard.isTestFrameworkImagePath("/Applications/Rockxy.app/Contents/MacOS/Rockxy"))
    }

    @Test("nothing outside the process can mark a test host")
    func onlyTheImageScanDecides() {
        // The decision takes no environment and no arguments, so neither a planted
        // `launchctl setenv XCTestConfigurationFilePath` -- which persists for every future launch
        // and once disabled the helper permanently -- nor opening a file named "XCTest-notes.har"
        // can trip it. Pin that the signature carries no input a caller does not control.
        #expect(!HelperRegistrationGuard.isTestHost(isTestFrameworkLoaded: false))
        #expect(HelperRegistrationGuard.isTestHost(isTestFrameworkLoaded: true))
    }

    @Test("the decision refuses only for a test host")
    func decisionFollowsTestHost() {
        #expect(HelperRegistrationGuard.refuses(operation: "install", isTestHost: true))
        #expect(!HelperRegistrationGuard.refuses(operation: "install", isTestHost: false))
    }

    @Test("the running test process is detected as a test host")
    func currentProcessIsATestHost() {
        #expect(HelperRegistrationGuard.isCurrentProcessTestHost)
        #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try HelperRegistrationGuard.refuseIfTestHost(operation: "install")
        }
    }

    @Test("every registration mutation is refused before touching SMAppService")
    @MainActor
    func registrationMutationsAreRefusedUnderTest() async {
        let manager = HelperManager.shared
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.performInstall()
        }
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.performUninstall()
        }
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.ensureHelperMutationCanProceed()
        }
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.install()
        }
        await #expect(throws: HelperRegistrationGuard.RefusedUnderTestError.self) {
            try await manager.forceResetRegistration()
        }
    }
}
