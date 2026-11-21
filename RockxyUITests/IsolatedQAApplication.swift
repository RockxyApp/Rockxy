import Foundation
import XCTest

/// Every UI test must use its own product and preferences, including launch measurements.
@MainActor
extension XCTestCase {
    func isolatedQAApplication() throws -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        let identifier = environment["ROCKXY_QA_BUNDLE_ID"] ?? ""
        guard identifier.hasPrefix("com.rockxy.qa."),
              identifier.count > "com.rockxy.qa.".count,
              let path = environment["ROCKXY_QA_APP_PATH"], path.hasPrefix("/"),
              let bundle = Bundle(url: URL(fileURLWithPath: path)),
              bundle.bundleIdentifier == identifier,
              bundle.object(forInfoDictionaryKey: "RockxyDefaultsPrefix") as? String == identifier,
              (bundle.object(forInfoDictionaryKey: "RockxyFamilyNamespace") as? String)?
              .hasPrefix("com.rockxy.qa.") == true else
        {
            throw XCTSkip("Requires a fully isolated QA app identity and preferences")
        }
        let app = XCUIApplication(bundleIdentifier: identifier)
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-showWelcomeOnLaunch", "NO",
            "-\(identifier).onboardingCompletedOnce", "YES",
            "-\(identifier).showAlertOnQuit", "NO",
            "-\(identifier).recordOnLaunch", "NO",
            "-\(identifier).automaticallySetSystemProxy", "NO",
            "-\(identifier).onlyListenOnLocalhost", "YES"
        ]
        return app
    }
}
