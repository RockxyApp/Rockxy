import XCTest

/// UI test suite for Rockxy. Validates app launch and measures launch performance.
final class RockxyUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests
        // before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = try isolatedQAApplication()
        defer { app.terminate() }
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testQuickToolMenusOpenAcrossEntireField() throws {
        let app = try isolatedQAApplication()
        defer { app.terminate() }
        app.launch()

        let customizeButton = app.buttons["More"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 5))
        customizeButton.click()

        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 2))

        for slot in 1 ... 4 {
            let field = popover.menuButtons
                .matching(identifier: "footerQuickTools.slot\(slot)")
                .firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 2))

            for horizontalOffset in [0.03, 0.97] {
                field.coordinate(
                    withNormalizedOffset: CGVector(dx: horizontalOffset, dy: 0.5)
                ).click()

                let menuItem = app.menuItems["Block List"]
                XCTAssertTrue(
                    menuItem.waitForExistence(timeout: 2),
                    "Slot \(slot) did not open from horizontal offset \(horizontalOffset)"
                )
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(menuItem.waitForNonExistence(timeout: 2))
            }
        }
    }

    @MainActor
    func testSettingsSidebarToggleStaysInLeadingTitlebar() throws {
        let app = try isolatedQAApplication()
        defer { app.terminate() }
        app.launch()
        app.typeKey(",", modifierFlags: .command)

        let settingsWindow = app.windows["Rockxy Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))

        let sidebarToggle = settingsWindow.buttons["Toggle Settings Sidebar"]
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 3))

        let closeButton = settingsWindow.buttons[XCUIIdentifierCloseWindow]
        let minimizeButton = settingsWindow.buttons[XCUIIdentifierMinimizeWindow]
        let zoomButton = settingsWindow.buttons[XCUIIdentifierZoomWindow]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
        XCTAssertTrue(minimizeButton.waitForExistence(timeout: 2))
        XCTAssertTrue(zoomButton.waitForExistence(timeout: 2))

        let toggleFrame = sidebarToggle.frame
        let closeFrame = closeButton.frame
        let minimizeFrame = minimizeButton.frame
        let zoomFrame = zoomButton.frame
        let sidebar = settingsWindow.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 2))
        let sidebarFrame = sidebar.frame
        let firstSidebarLabel = sidebar.staticTexts["General"].firstMatch
        XCTAssertTrue(firstSidebarLabel.waitForExistence(timeout: 2))
        let firstSidebarLabelFrame = firstSidebarLabel.frame

        XCTAssertLessThan(
            abs(closeFrame.midY - minimizeFrame.midY),
            2,
            "Traffic-light controls must share one titlebar baseline"
        )
        XCTAssertLessThan(
            abs(minimizeFrame.midY - zoomFrame.midY),
            2,
            "Traffic-light controls must share one titlebar baseline"
        )
        XCTAssertLessThan(
            abs(toggleFrame.midY - zoomFrame.midY),
            3,
            "Native toolbar items must share the titlebar control baseline"
        )
        XCTAssertGreaterThan(
            toggleFrame.minX,
            zoomFrame.maxX + 36,
            "Sidebar toggle must align to the sidebar edge, not the traffic lights"
        )
        XCTAssertGreaterThan(
            toggleFrame.midX,
            sidebarFrame.midX,
            "Sidebar toggle must live in the trailing half of the sidebar"
        )
        XCTAssertLessThanOrEqual(
            toggleFrame.maxX,
            sidebarFrame.maxX,
            "Sidebar toggle must remain inside the sidebar boundary"
        )
        XCTAssertGreaterThan(
            sidebarFrame.maxX - toggleFrame.maxX,
            0,
            "Sidebar toggle hit area must not cross the rounded trailing edge"
        )
        XCTAssertLessThan(
            sidebarFrame.maxX - toggleFrame.maxX,
            24,
            "Sidebar toggle must stay close to the sidebar's trailing edge"
        )
        XCTAssertGreaterThan(
            firstSidebarLabelFrame.minY - toggleFrame.maxY,
            14,
            "Sidebar items need breathing room below the titlebar control"
        )

        sidebarToggle.click()
        XCTAssertTrue(sidebar.waitForNonExistence(timeout: 2))
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 2))

        sidebarToggle.click()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        let app = try isolatedQAApplication()
        defer { app.terminate() }
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            app.terminate()
        }
    }
}
