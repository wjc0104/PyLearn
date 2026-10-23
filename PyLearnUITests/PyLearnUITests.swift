import XCTest

final class PyLearnUITests: XCTestCase {
    func testProjectFilesAndImportAndModelEntryPoints() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["代码"].tap()
        app.buttons["新建项目"].tap()
        XCTAssertTrue(app.buttons["打开运行入口"].waitForExistence(timeout: 5))
        app.buttons["打开运行入口"].tap()
        XCTAssertTrue(app.buttons["运行脚本"].waitForExistence(timeout: 5))
        app.buttons["运行脚本"].tap()
        XCTAssertTrue(app.staticTexts["运行完成"].waitForExistence(timeout: 20))
        app.buttons["完成"].tap()
        app.buttons["添加项目文件"].tap()
        app.buttons["新建文件"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("nested/sample.py")
        app.alerts.buttons["创建"].tap()
        XCTAssertTrue(app.navigationBars["sample.py"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["导入整个文件夹"].waitForExistence(timeout: 5))
        let script = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "你好，Python.py")).firstMatch
        XCTAssertTrue(script.exists)
        script.press(forDuration: 1.2)
        app.buttons["添加到项目 / Git 仓库"].tap()
        XCTAssertTrue(app.navigationBars["添加脚本到项目"].waitForExistence(timeout: 5))
        app.buttons["添加到项目"].tap()
        app.buttons["新项目"].firstMatch.tap()
        XCTAssertTrue(app.buttons["你好，Python.py"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["导入整个文件夹"].tap()
        attach("folder-picker", app: app)
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 5) || app.buttons["Cancel"].exists)
        let cancel = app.buttons["取消"].exists ? app.buttons["取消"] : app.buttons["Cancel"]
        cancel.tap()
        app.tabBars.buttons["练习"].tap()
        app.buttons["切换 / 测试 AI 模型"].tap()
        XCTAssertTrue(app.navigationBars["选择 AI 模型"].waitForExistence(timeout: 5))
        attach("model-picker", app: app)
        app.buttons["完成"].tap()
    }

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
