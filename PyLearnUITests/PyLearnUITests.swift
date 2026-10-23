import XCTest

final class PyLearnUITests: XCTestCase {
    func testLearningAndEditorScreens() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Python 学习"].waitForExistence(timeout: 15))
        attach("learning", app: app)
        app.tabBars.buttons["练习"].tap()
        XCTAssertTrue(app.navigationBars["编程练习"].exists)
        attach("exercises", app: app)
        app.tabBars.buttons["代码"].tap()
        app.buttons["新建脚本"].tap()
        XCTAssertTrue(app.buttons["运行脚本"].waitForExistence(timeout: 5))
        attach("editor", app: app)
        app.buttons["运行脚本"].tap()
        XCTAssertTrue(app.staticTexts["运行完成"].waitForExistence(timeout: 20))
        attach("console", app: app)
        app.buttons["收起控制台"].tap()
        XCTAssertTrue(app.buttons["展开控制台"].exists)
        app.buttons["展开控制台"].tap()
        app.buttons["完成"].tap()
        let script = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "新脚本")).firstMatch
        XCTAssertTrue(script.waitForExistence(timeout: 5))
        script.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["删除脚本"].waitForExistence(timeout: 3))
        app.buttons["删除脚本"].tap()
        app.buttons["取消"].tap()
        XCTAssertTrue(script.exists)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["编辑器外观"].waitForExistence(timeout: 5))
        attach("settings", app: app)
    }

    private func attach(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
