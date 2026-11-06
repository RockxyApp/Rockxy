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
