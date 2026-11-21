import Foundation
@testable import Rockxy
import Testing

// MARK: - RockxyIdentityTestHostTests

/// Pins that `RockxyIdentity.isRunningTests` cannot be set from outside the process.
///
/// A shipped Rockxy that read as a test host redirected its saved column layout to a throwaway
/// per-pid defaults domain, so anything another process can plant (`launchctl setenv XCTest...`
/// persists across logins; a file named `*.xctest` or `*XCTest*` reaches argv) must never count.
struct RockxyIdentityTestHostTests {
    // MARK: Internal

    @Test("a process whose images are all ordinary is not a test host")
    func ordinaryImagesAreNotATestHost() {
        let images = [
            "/Applications/Rockxy.app/Contents/MacOS/Rockxy",
            "/usr/lib/libSystem.B.dylib",
            "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
        ]
        #expect(!RockxyIdentity.isTestHost(imagePaths: images))
        #expect(!RockxyIdentity.isTestHost(imagePaths: []))
    }

    @Test("a loaded XCTest or Swift Testing image makes a test host")
    func loadedFrameworkImageIsATestHost() {
        #expect(RockxyIdentity.isTestHost(imagePaths: [
            "/Applications/Rockxy.app/Contents/MacOS/Rockxy",
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer"
                + "/Library/Frameworks/XCTest.framework/Versions/A/XCTest",
        ]))
        #expect(RockxyIdentity.isTestHost(imagePaths: [
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer"
                + "/Library/Frameworks/Testing.framework/Versions/A/Testing",
        ]))
    }

    @Test("image names that merely mention XCTest or .xctest are not test frameworks")
    func lookalikePathsAreNotTestFrameworks() {
        #expect(!RockxyIdentity.isTestFrameworkImagePath("/Users/me/Downloads/XCTest-notes.har"))
        #expect(!RockxyIdentity.isTestFrameworkImagePath("/tmp/Planted.xctest/Contents/MacOS/Planted"))
    }

    /// Measured on macOS: a binary copied into a directory named `Testing.framework` is reported
    /// by `_dyld_get_image_name(0)` at that path, so matching the framework name anywhere in the
    /// path would hand the decision to anyone who can place a copy of the app. A symlink does not
    /// do it, because dyld reports the resolved path, but a copy does.
    @Test("an app relocated under a directory named like a test framework is not a test host")
    func relocatedBundleIsNotATestHost() {
        let relocated = "/Users/me/Library/Caches/Testing.framework/Rockxy.app/Contents/MacOS/Rockxy"
        #expect(!RockxyIdentity.isTestFrameworkImagePath(relocated))
        #expect(!RockxyIdentity.isTestFrameworkImagePath(
            "/Users/me/XCTest.framework/Rockxy.app/Contents/MacOS/Rockxy"
        ))
        #expect(!RockxyIdentity.isTestHost(imagePaths: [relocated, "/usr/lib/libSystem.B.dylib"]))
    }

    /// The main executable is the one image whose path someone outside the process chooses — a
    /// shipped Rockxy is image 0 — and it can never be a test framework, so the scan skips it.
    ///
    /// Asserted as "image 0 and nothing else is missing" rather than by name: under a test host
    /// image 0 is the runner, not the app, and naming either would pin the harness instead of the
    /// behaviour.
    @Test("the loaded-image scan leaves out the main executable")
    func loadedImagePathsLeaveOutTheMainExecutable() {
        let images = RockxyIdentity.loadedImagePaths()
        let mainExecutable = _dyld_get_image_name(0).map { String(cString: $0) }

        #expect(!images.isEmpty)
        #expect(images.count == Int(_dyld_image_count()) - 1)
        #expect(images.first != mainExecutable)
        #expect(images.first == _dyld_get_image_name(1).map { String(cString: $0) })
    }

    @Test("the test-host decision takes only loaded images, never environment or arguments")
    func decisionDoesNotReadEnvironmentOrArguments() throws {
        let source = try String(contentsOf: Self.identitySourceURL(), encoding: .utf8)
        let start = try #require(source.range(of: "static let isRunningTests"))
        let end = try #require(source.range(
            of: "static func loadedImagePaths",
            range: start.upperBound ..< source.endIndex
        ))
        let declarations = String(source[start.lowerBound ..< end.upperBound])
        let code = declarations
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        for forbidden in ["environment", "arguments", "XCTestConfigurationFilePath", "hasPrefix", "\".xctest\""] {
            #expect(!code.contains(forbidden), "isRunningTests must not consult \(forbidden)")
        }
    }

    @Test("the real test process is detected through its loaded images")
    func currentProcessIsATestHost() {
        #expect(RockxyIdentity.isRunningTests)
        #expect(RockxyIdentity.isTestHost(imagePaths: RockxyIdentity.loadedImagePaths()))
    }

    @Test("both definitions of test host agree")
    func helperGuardDelegatesToIdentity() {
        #expect(HelperRegistrationGuard.isCurrentProcessTestHost == RockxyIdentity.isRunningTests)
    }

    // MARK: Private

    private static func identitySourceURL(filePath: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: filePath)
        for _ in 0 ..< 3 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("Shared/RockxyIdentity.swift")
    }
}
