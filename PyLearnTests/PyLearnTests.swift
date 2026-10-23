import XCTest
@testable import PyLearn

final class PyLearnTests: XCTestCase {
    @MainActor
    func testImportRejectsInvalidContentAndKeepsExistingDocuments() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directory: folder)
        let original = store.documents.count
        XCTAssertThrowsError(try store.importScript(name: "bad.txt", data: Data("print(1)".utf8)))
        XCTAssertThrowsError(try store.importScript(name: "bad.py", data: Data([0xff, 0xfe])))
        XCTAssertThrowsError(try store.importScript(name: "big.py", data: Data(repeating: 65, count: 524289)))
        XCTAssertEqual(store.documents.count, original)
        let imported = try store.importScript(name: "中文.py", data: Data("\u{feff}print('你好🐍')".utf8))
        XCTAssertEqual(imported.source, "print('你好🐍')")
        XCTAssertEqual(imported.name, "中文.py")
        let restored = LearningStore(directory: folder)
        XCTAssertEqual(restored.documents.first?.source, imported.source)
    }

    @MainActor
    func testCompletionReplacementPreservesEmojiBeforeCursor() {
        let source = "# 🐍\npri"
        let cursor = NSRange(location: (source as NSString).length, length: 0)
        let range = EditorText.prefixRange(in: source, selection: cursor)
        XCTAssertEqual((source as NSString).substring(with: range), "pri")
        XCTAssertEqual((source as NSString).replacingCharacters(in: range, with: "print"), "# 🐍\nprint")
    }

    func testEmbeddedPythonLoadsStandardLibraryAndRunsUnicode() {
        let done = expectation(description: "Embedded runtime")
        var output = ""
        let runtime = PLPythonRuntime.shared()
        runtime.outputHandler = { output = $0 }
        runtime.performRequest("{\"action\":\"run\",\"source\":\"import math\\nprint('你好🐍', math.isqrt(81))\"}") { response in
            let data = Data(response.utf8)
            let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertEqual(result?["status"] as? String, "success", response)
            XCTAssertEqual(output, "你好🐍 9\n")
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    func testEmbeddedInputCanBeStoppedAndNextRunStillWorks() {
        let stopped = expectation(description: "Stopped input")
        let runtime = PLPythonRuntime.shared()
        runtime.inputHandler = { _ in runtime.cancel() }
        runtime.performRequest("{\"action\":\"run\",\"source\":\"input('名字')\"}") { response in
            XCTAssertTrue(response.contains("stopped"), response)
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 30)
        let next = expectation(description: "Next run after stopping")
        runtime.performRequest("{\"action\":\"run\",\"source\":\"print(42)\"}") { response in
            XCTAssertTrue(response.contains("success"), response)
            next.fulfill()
        }
        wait(for: [next], timeout: 10)
    }

    func testConsoleMenuIsVisibleBeforeInputIsRequested() {
        let done = expectation(description: "Input with flushed output")
        let runtime = PLPythonRuntime.shared()
        var output = ""
        runtime.outputHandler = { output = $0 }
        runtime.inputHandler = { _ in
            XCTAssertTrue(output.contains("2. 返回"), output)
            runtime.cancel()
        }
        runtime.performRequest("{\"action\":\"run\",\"source\":\"print('菜单')\\nprint('1. 学习')\\nprint('2. 返回')\\ninput('请选择：')\"}") { _ in done.fulfill() }
        wait(for: [done], timeout: 30)
    }
}
