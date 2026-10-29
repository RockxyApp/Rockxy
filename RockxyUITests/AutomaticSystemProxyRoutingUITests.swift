import Foundation
import SystemConfiguration
import XCTest

/// Run only against the isolated QA product. Never launch the installed shipping app.
@MainActor
final class AutomaticSystemProxyRoutingUITests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPreferencePersistsAndManualCapturePreservesSystemProxy() throws {
        let identifier = ProcessInfo.processInfo.environment["ROCKXY_QA_BUNDLE_ID"] ?? ""
        guard identifier.hasPrefix("com.rockxy.qa."), identifier.count > "com.rockxy.qa.".count else {
            throw XCTSkip("Requires an isolated QA bundle identifier")
        }
        guard let appPath = ProcessInfo.processInfo.environment["ROCKXY_QA_APP_PATH"],
              appPath.hasPrefix("/"),
              let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
              bundle.bundleIdentifier == identifier,
              bundle.object(forInfoDictionaryKey: "RockxyDefaultsPrefix") as? String == identifier,
              (bundle.object(forInfoDictionaryKey: "RockxyFamilyNamespace") as? String)?
              .hasPrefix("com.rockxy.qa.") == true else
        {
            throw XCTSkip("Requires a fully isolated QA app identity and preferences")
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: identifier))
        let keys = [
            "\(identifier).automaticallySetSystemProxy", "\(identifier).recordOnLaunch",
            "\(identifier).proxyPort", "\(identifier).onlyListenOnLocalhost",
            "\(identifier).showAlertOnQuit", "\(identifier).onboardingCompletedOnce", "showWelcomeOnLaunch"
        ]
        let previous = keys.map { ($0, defaults.object(forKey: $0)) }
        let baseline = try XCTUnwrap(SCDynamicStoreCopyProxies(nil) as NSDictionary?)
        let app = XCUIApplication(bundleIdentifier: identifier)
        defer {
            app.terminate()
            for (key, value) in previous {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set(false, forKey: keys[0])
        defaults.set(false, forKey: keys[1])
        defaults.set(48_716, forKey: keys[2])
        defaults.set(true, forKey: keys[3])
        defaults.set(false, forKey: keys[4])
        defaults.set(true, forKey: keys[5])
        defaults.set(false, forKey: keys[6])
        defaults.synchronize()
        let safeLaunchArguments = [
            "-AppleLanguages", "(en)", "-showWelcomeOnLaunch", "NO",
            "-\(identifier).onboardingCompletedOnce", "YES",
            "-\(identifier).showAlertOnQuit", "NO",
            "-\(identifier).onlyListenOnLocalhost", "YES"
        ]
        // A sandboxed runner may not share the app's preferences domain. Never rely on
        // fixture writes to prevent the first launch from automatically changing routing.
        app.launchArguments = safeLaunchArguments + ["-\(identifier).recordOnLaunch", "NO"]
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        let setting = app.checkBoxes["settings.automaticallySetSystemProxy"].firstMatch
        XCTAssertTrue(setting.waitForExistence(timeout: 10))
        if setting.value as? String == "1" {
            setting.click()
        }
        XCTAssertEqual(setting.value as? String, "0")
        setting.click()
        XCTAssertEqual(setting.value as? String, "1")
        app.terminate()
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(setting.waitForExistence(timeout: 10))
        XCTAssertEqual(setting.value as? String, "1")
        setting.click()
        XCTAssertEqual(setting.value as? String, "0")
        app.typeKey("w", modifierFlags: .command)
        try assertSystemProxyEquals(baseline)

        for cycle in 0 ..< 2 {
            app.menuBars.menuBarItems["Tools"].click()
            let start = app.menuItems["Start Proxy"].firstMatch
            XCTAssertTrue(start.waitForExistence(timeout: 3))
            XCTAssertTrue(start.isEnabled)
            start.click()
            try waitForCapture(app: app, running: true)
            verifyManualCapturePath(app: app)
            try assertSystemProxyEquals(baseline)
            if cycle == 0 {
                app.buttons["capture.status"].firstMatch.click()
                app.buttons["Advanced Settings…"].firstMatch.click()
                let advanced = app.windows["Advanced Proxy Settings"]
                XCTAssertTrue(advanced.waitForExistence(timeout: 5))
                let port = advanced.textFields["Listener port number"].firstMatch
                XCTAssertTrue(port.waitForExistence(timeout: 5))
                let nextPort = port.value as? String == "48717" ? "48716" : "48717"
                port.click()
                app.typeKey("a", modifierFlags: .command)
                port.typeText(nextPort)
                advanced.buttons["Apply"].firstMatch.click()
                let restart = advanced.buttons["Restart proxy with saved listener settings"].firstMatch
                XCTAssertTrue(restart.waitForExistence(timeout: 5))
                XCTAssertTrue(restart.isEnabled)
                restart.click()
                try waitForCapture(app: app, running: true)
                XCTAssertTrue(advanced.staticTexts["127.0.0.1:\(nextPort)"].firstMatch.waitForExistence(timeout: 10))
                app.typeKey("w", modifierFlags: .command)
                verifyManualCapturePath(app: app)
                try assertSystemProxyEquals(baseline)
            }
            app.typeKey(".", modifierFlags: .command)
            try waitForCapture(app: app, running: false)
            try assertSystemProxyEquals(baseline)
        }

        app.typeKey(",", modifierFlags: .command)
        let recordOnLaunch = app.checkBoxes["Auto Start Recording Traffic at Launch"].firstMatch
        XCTAssertTrue(recordOnLaunch.waitForExistence(timeout: 5))
        XCTAssertEqual(recordOnLaunch.value as? String, "0")
        // The launch argument keeps this session stopped; clicking persists the next
        // launch's choice through the app itself, independent of the runner's sandbox.
        recordOnLaunch.click()
        app.terminate()
        app.launchArguments = safeLaunchArguments
        app.launch()
        try waitForCapture(app: app, running: true)
        verifyManualCapturePath(app: app)
        try assertSystemProxyEquals(baseline)
        app.typeKey(".", modifierFlags: .command)
        try waitForCapture(app: app, running: false)
        try assertSystemProxyEquals(baseline)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Isolated manual-routing capture"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: Private

    private enum QAError: Error { case captureTimeout }

    private func verifyManualCapturePath(app: XCUIApplication) {
        let status = app.buttons["capture.status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.click()
        let routing = app.descendants(matching: .any).matching(identifier: "capture.systemRouting").firstMatch
        XCTAssertTrue(routing.waitForExistence(timeout: 5))
        XCTAssertTrue(routing.label.contains("macOS proxy off"))
        let path = app.descendants(matching: .any).matching(identifier: "capture.path").firstMatch
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, !path.label.contains("Local path verified") {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(path.label.contains("Local path verified"), "The real listener capture probe must pass")
        app.typeKey(.escape, modifierFlags: [])
    }

    private func waitForCapture(app: XCUIApplication, running: Bool) throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            app.menuBars.menuBarItems["Tools"].click()
            let stop = app.menuItems["Stop Proxy"].firstMatch
            let start = app.menuItems["Start Proxy"].firstMatch
            let matches = running ? (stop.exists && stop.isEnabled)
                : (stop.exists && !stop.isEnabled && start.exists && start.isEnabled)
            app.typeKey(.escape, modifierFlags: [])
            if matches {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("Capture did not reach the requested state")
        throw QAError.captureTimeout
    }

    private func assertSystemProxyEquals(_ baseline: NSDictionary) throws {
        let current = try XCTUnwrap(SCDynamicStoreCopyProxies(nil) as NSDictionary?)
        // Compare without putting host proxy details in test diagnostics.
        XCTAssertTrue(baseline.isEqual(current), "The isolated capture changed macOS system proxy settings")
    }
}
