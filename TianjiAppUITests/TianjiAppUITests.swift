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

    func testManualInputShowsResult() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let manualButton = app.buttons["手动输入"]
        XCTAssertTrue(manualButton.waitForExistence(timeout: 2), "Manual input entry should be visible on camera screen")
        manualButton.tap()

        let resultButton = app.buttons["查看结果"]
        XCTAssertTrue(resultButton.waitForExistence(timeout: 2), "Result button should be visible on manual input")
        resultButton.tap()

        let resultNavBar = app.navigationBars["卦象结果"]
        XCTAssertTrue(resultNavBar.waitForExistence(timeout: 2), "Expected result screen after manual input")
    }

    func testHistoryShowsEmptyState() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let historyButton = app.buttons["历史记录"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 2), "History button should be visible on launch")
        historyButton.tap()

        let emptyText = app.staticTexts["暂无历史记录"]
        XCTAssertTrue(emptyText.waitForExistence(timeout: 2), "Expected empty history state when no sessions exist")
    }
}
