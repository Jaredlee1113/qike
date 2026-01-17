import XCTest

final class TianjiAppUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testNoTemplateAlertNavigatesToSetup() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let alert = app.alerts["提示"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2), "Missing alert when no templates exist")
        alert.buttons["确定"].tap()

        XCTAssertTrue(app.textFields["配置名称"].waitForExistence(timeout: 2), "Expected setup form after confirming the alert")
    }
}
