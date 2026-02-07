import XCTest

final class TianjiAppUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testNoTemplateAlertNavigatesToTemplateCenter() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let alert = app.alerts["提示"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2), "Missing alert when no templates exist")
        alert.buttons["确定"].tap()

        let templateCenterTitle = app.navigationBars["模板中心"]
        XCTAssertTrue(templateCenterTitle.waitForExistence(timeout: 2), "Expected template center after confirming the alert")
    }

    func testTemplateCenterShowsEmptyStateFromHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let templateCenterButton = app.buttons["模板中心"]
        XCTAssertTrue(templateCenterButton.waitForExistence(timeout: 2), "Template center entry should be visible on launch")
        templateCenterButton.tap()

        XCTAssertTrue(app.navigationBars["模板中心"].waitForExistence(timeout: 2), "Expected template center screen")
        XCTAssertTrue(app.staticTexts["暂无模板"].waitForExistence(timeout: 2), "Expected empty template center state")
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

    func testManualInputCreatesHistoryRecordAndDetail() {
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
        XCTAssertTrue(app.navigationBars["卦象结果"].waitForExistence(timeout: 2), "Expected result screen after manual input")

        let backToManual = app.navigationBars["卦象结果"].buttons["手动输入"]
        XCTAssertTrue(backToManual.waitForExistence(timeout: 2), "Expected back button to manual input screen")
        backToManual.tap()

        let cancelButton = app.navigationBars["手动输入"].buttons["取消"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2), "Expected cancel button on manual input screen")
        cancelButton.tap()

        let backToHome = app.navigationBars["起课"].buttons.firstMatch
        XCTAssertTrue(backToHome.waitForExistence(timeout: 2), "Expected back button from camera to home")
        backToHome.tap()

        let historyButton = app.buttons["历史记录"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 2), "History button should be visible on launch")
        historyButton.tap()

        let manualSourceText = app.staticTexts["手动输入"]
        XCTAssertTrue(manualSourceText.waitForExistence(timeout: 2), "Expected manual source text in history row")
        manualSourceText.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["起课详情"].waitForExistence(timeout: 2), "Expected session detail screen")
        XCTAssertTrue(app.staticTexts["来源"].waitForExistence(timeout: 2), "Expected source section in session detail")
        XCTAssertTrue(app.staticTexts["未关联模板"].waitForExistence(timeout: 2), "Expected manual session profile fallback text")
        XCTAssertTrue(app.staticTexts["占卜图解"].waitForExistence(timeout: 2), "Expected reused result component in session detail")
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

    func testMockUncertainResultsStillEnterConfirm() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-mock-confirm-uncertain"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let confirmTitle = app.navigationBars["确认卦象"]
        XCTAssertTrue(confirmTitle.waitForExistence(timeout: 2), "Expected confirm screen even when some sides are uncertain")

        let uncertainHint = app.staticTexts["建议：不确定，请调整光线或重录模板"]
        XCTAssertTrue(uncertainHint.waitForExistence(timeout: 2), "Expected uncertain hint in confirmation list")
    }

    func testLayoutCheckShowsFullHeightCoverage() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-layout-check"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let layoutStatus = app.staticTexts["LAYOUT_OK"]
        XCTAssertTrue(layoutStatus.waitForExistence(timeout: 2), "Slot layout should cover full vertical guide range")
    }

    func testPresenceCheckShowsRelaxedThresholdStatus() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-presence-check"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let presenceStatus = app.staticTexts["PRESENCE_OK"]
        XCTAssertTrue(presenceStatus.waitForExistence(timeout: 2), "Presence classifier regression check should pass")
    }

    func testQualityCheckShowsStatus() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-quality-check"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let qualityStatus = app.staticTexts["QUALITY_OK"]
        XCTAssertTrue(qualityStatus.waitForExistence(timeout: 2), "Quality gate regression check should pass")
    }

    func testStabilityCheckShowsStatus() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-stability-check"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let stabilityStatus = app.staticTexts["STABILITY_OK"]
        XCTAssertTrue(stabilityStatus.waitForExistence(timeout: 2), "Stability lock regression check should pass")
    }

    func testMatchCheckShowsStatus() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-match-check"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let matchStatus = app.staticTexts["MATCH_OK"]
        XCTAssertTrue(matchStatus.waitForExistence(timeout: 2), "Match decision regression check should pass")
    }

    func testReliabilityCheckShowsStatus() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reliability-check"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let reliabilityStatus = app.staticTexts["RELIABILITY_OK"]
        XCTAssertTrue(reliabilityStatus.waitForExistence(timeout: 2), "Result reliability regression check should pass")
    }

    func testLowLightHintShowsTorchPrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-low-light-hint-check"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let hintText = app.staticTexts["光线偏暗，建议打开闪光灯"]
        XCTAssertTrue(hintText.waitForExistence(timeout: 2), "Low-light hint should be visible")
        XCTAssertTrue(app.buttons["打开闪光灯"].waitForExistence(timeout: 2), "Torch quick action should be visible")
    }

    func testConfirmCloseReturnsToHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-seed-profile", "-ui-testing-mock-confirm-uncertain"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible on launch")
        startButton.tap()

        let confirmTitle = app.navigationBars["确认卦象"]
        XCTAssertTrue(confirmTitle.waitForExistence(timeout: 2), "Expected confirm screen")

        let confirmButton = app.buttons["确认"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 2), "Expected confirm action")
        confirmButton.tap()

        let resultTitle = app.navigationBars["卦象结果"]
        XCTAssertTrue(resultTitle.waitForExistence(timeout: 2), "Expected result screen after confirm")

        let closeButton = app.buttons["关闭"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2), "Expected close button on result screen")
        closeButton.tap()

        XCTAssertTrue(app.buttons["开始起课"].waitForExistence(timeout: 2), "Expected to return to home after closing result")
    }

}
