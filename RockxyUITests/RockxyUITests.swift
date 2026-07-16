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
    func testExample() {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testQuickToolMenusOpenAcrossEntireField() {
        let app = XCUIApplication()
        app.launch()

        let customizeButton = app.buttons["More"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 5))
        customizeButton.click()

        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 2))

        for slot in 1...4 {
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
    func testLaunchPerformance() {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
