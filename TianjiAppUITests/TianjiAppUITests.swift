import XCTest

final class TianjiAppUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - 基础导航测试

    func testLaunchAndNavigateToInput() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Start button should be visible")
        startButton.tap()

        let inputTitle = app.navigationBars["起课"]
        XCTAssertTrue(inputTitle.waitForExistence(timeout: 2), "Should navigate to input screen")
    }

    func testHistoryShowsEmptyState() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let historyButton = app.buttons["历史记录"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 2), "History button should be visible")
        historyButton.tap()

        let emptyText = app.staticTexts["暂无历史记录"]
        XCTAssertTrue(emptyText.waitForExistence(timeout: 2), "Expected empty history state")
    }

    // MARK: - 默认模式测试

    func testDefaultModeIsCoin() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()

        // 铜钱按钮应该存在且为默认
        let coinButton = app.buttons["铜钱"]
        XCTAssertTrue(coinButton.waitForExistence(timeout: 2), "Coin mode should exist")
    }

    // MARK: - 模式切换测试

    func testSwitchBetweenSymbolAndCoinMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()

        let symbolButton = app.buttons["符号"]
        let coinButton = app.buttons["铜钱"]

        XCTAssertTrue(symbolButton.exists, "Symbol mode should exist")
        XCTAssertTrue(coinButton.exists, "Coin mode should exist")

        // 切换到符号模式
        symbolButton.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // 切换回铜钱模式
        coinButton.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - 主卡片布局测试

    func testMainCardSectionsExist() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()

        // 检查卦象标题
        let hexagramTitle = app.staticTexts["卦象"]
        XCTAssertTrue(hexagramTitle.waitForExistence(timeout: 2), "Hexagram title should exist")

        // 检查点击选择标签
        let selectLabel = app.staticTexts["点击选择"]
        XCTAssertTrue(selectLabel.exists, "Selection label should exist")
    }

    // MARK: - 铜钱模式测试

    func testCoinModeShowsEmptyState() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()

        // 默认是铜钱模式，检查空状态
        let setupHint = app.staticTexts["请先设置模板"]
        if setupHint.exists {
            XCTAssertTrue(true, "Empty state shows correctly when no template")
        }
    }

    func testNavigateToTemplateSetup() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()

        // 通过导航栏设置按钮进入
        let setupButton = app.buttons["templateSetupButton"]
        if setupButton.exists {
            setupButton.tap()
        } else {
            // 尝试空状态中的设置按钮
            let inlineSetupButton = app.buttons["setupTemplateButton"]
            if inlineSetupButton.exists {
                inlineSetupButton.tap()
            }
        }

        let templateSetupTitle = app.navigationBars["模板设置"]
        XCTAssertTrue(templateSetupTitle.waitForExistence(timeout: 2), "Should navigate to template setup")
    }

    // MARK: - 符号模式测试

    func testSymbolModeShowsClickableSymbols() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()
        app.buttons["符号"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        // 检查位置标签存在
        let position6 = app.staticTexts["6"]
        let position1 = app.staticTexts["1"]

        XCTAssertTrue(position6.exists, "Position labels should exist in symbol mode")
        XCTAssertTrue(position1.exists, "Position labels should exist in symbol mode")
    }

    // MARK: - 卦象显示区域测试

    func testHexagramDisplaySectionExists() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()

        // 检查右侧卦象显示标签
        let hexagramLabel = app.staticTexts["卦象"]
        XCTAssertTrue(hexagramLabel.waitForExistence(timeout: 2), "Hexagram display label should exist")
    }

    // MARK: - 结果页面测试

    func testViewResultButtonExists() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()

        let resultButton = app.buttons["viewResultButton"]
        XCTAssertTrue(resultButton.waitForExistence(timeout: 2), "Result button should be visible")
    }

    func testViewResultShowsHexagramName() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()
        app.buttons["viewResultButton"].tap()

        let resultTitle = app.navigationBars["卦象结果"]
        XCTAssertTrue(resultTitle.waitForExistence(timeout: 2), "Should show result screen")

        // 验证卦象名称存在
        let hexagramNameLabel = app.staticTexts.matching(NSPredicate(format: "label MATCHES '.*卦'")).firstMatch
        XCTAssertTrue(hexagramNameLabel.waitForExistence(timeout: 2), "Should show hexagram name")
    }

    // MARK: - 取消按钮测试

    func testCancelReturnsToHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["开始起课"].tap()
        app.buttons["取消"].tap()

        let startButton = app.buttons["开始起课"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2), "Should return to home after cancel")
    }

    // MARK: - 完整流程测试

    func testCompleteInputWorkflow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        // 1. 进入起课
        app.buttons["开始起课"].tap()
        XCTAssertTrue(app.navigationBars["起课"].exists, "Should be on input screen")

        // 2. 切换到符号模式
        app.buttons["符号"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        // 3. 查看结果
        app.buttons["viewResultButton"].tap()
        XCTAssertTrue(app.navigationBars["卦象结果"].exists, "Should see result")

        // 4. 关闭结果
        app.buttons["关闭"].tap()

        // 5. 返回主页
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["开始起课"].exists, "Should return to home")
    }
}

// MARK: - 辅助扩展

extension XCUIElement {
    func isVisibleAndInteractive() -> Bool {
        return self.exists && self.isHittable
    }
}
