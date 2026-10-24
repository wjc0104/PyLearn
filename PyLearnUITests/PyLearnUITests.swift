import XCTest

final class PyLearnUITests: XCTestCase {
    func testModelResultStaysVisibleAndSwitchRequiresConfirmation() {
        // Simulator keyboard quiescence can consume two 60-second waits before any request.
        executionTimeAllowance = 300
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.buttons["管理服务商与 API 配置"].tap()
        let localPreset = app.buttons["Ollama 局域网"]
        if !localPreset.isHittable { app.swipeUp() }
        localPreset.tap()
        let address = app.textFields["API Base URL（不含具体请求路径）"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        let oldAddress = address.value as? String ?? ""
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldAddress.count) + "http://127.0.0.1:18764/v1")
        let model = app.textFields["模型 ID"]
        model.tap(); model.typeText("ui-original\n")
        app.buttons["测试并保存配置"].tap()
        XCTAssertTrue(app.alerts["配置测试通过"].waitForExistence(timeout: 15))
        app.alerts.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["Ollama 局域网"].waitForNonExistence(timeout: 5))
        app.tabBars.buttons["练习"].tap()
        app.buttons["切换 / 测试 AI 模型"].tap()
        let second = app.cells.containing(.staticText, identifier: "ui-second").firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        second.buttons["测试模型"].tap()
        XCTAssertTrue(app.alerts["模型测试通过"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["正在使用：Ollama 局域网 · ui-original"].exists)
        attach("model-test-passed-confirmation", app: app)
        app.alerts.buttons["暂不切换"].tap()
        XCTAssertTrue(app.staticTexts["正在使用：Ollama 局域网 · ui-original"].exists)
        second.buttons["测试模型"].tap()
        XCTAssertTrue(app.alerts["模型测试通过"].waitForExistence(timeout: 10))
        app.alerts.buttons["使用此模型"].tap()
        XCTAssertTrue(app.staticTexts["正在使用：Ollama 局域网 · ui-second"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["选择 AI 模型"].exists)
        let unavailable = app.cells.containing(.staticText, identifier: "ui-unavailable").firstMatch
        if !unavailable.isHittable { app.swipeUp() }
        unavailable.buttons["测试模型"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本次测试失败")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["正在使用：Ollama 局域网 · ui-second"].exists)
        attach("model-test-failed-keeps-selection", app: app)
        app.buttons["完成"].tap()
    }

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
        XCTAssertTrue(app.navigationBars["main.py"].waitForNonExistence(timeout: 5))
        let addFile = app.buttons["添加项目文件"]
        XCTAssertTrue(addFile.waitForExistence(timeout: 5))
        addFile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["新建文件"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap(); name.typeText("nested/sample.py")
        app.alerts.buttons["创建"].tap()
        XCTAssertTrue(app.navigationBars["sample.py"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["sample.py"].waitForNonExistence(timeout: 5))
        app.buttons["nested"].tap()
        let projectFile = app.buttons["sample.py"]
        XCTAssertTrue(projectFile.waitForExistence(timeout: 5))
        projectFile.press(forDuration: 1.2)
        app.buttons["删除文件"].tap()
        app.buttons["取消"].tap()
        XCTAssertTrue(projectFile.exists)
        projectFile.press(forDuration: 1.2)
        app.buttons["删除文件"].tap()
        app.buttons["确认删除"].tap()
        XCTAssertTrue(projectFile.waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let folder = app.buttons["nested"]
        folder.press(forDuration: 1.2)
        app.buttons["删除文件夹"].tap()
        app.buttons["确认删除"].tap()
        XCTAssertTrue(folder.waitForNonExistence(timeout: 5))
        app.buttons["Git 版本管理"].tap()
        app.buttons["初始化 Git"].tap()
        let commitMessage = app.textFields["提交说明"]
        XCTAssertTrue(commitMessage.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: commitMessage)], timeout: 10), .completed)
        commitMessage.tap(); commitMessage.typeText("UI first commit\n")
        app.buttons["保存一个提交"].tap()
        let historyButton = app.buttons["历史"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: historyButton)], timeout: 10), .completed)
        historyButton.tap()
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UI first commit")).firstMatch
        if !result.isHittable { app.swipeUp(); app.swipeUp() }
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        attach("git-history", app: app)
        app.navigationBars.buttons.firstMatch.tap()
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
