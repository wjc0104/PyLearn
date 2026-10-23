import XCTest
@testable import PyLearn

final class PyLearnTests: XCTestCase {
    @MainActor
    func testFolderImportPreservesResourcesAndEntryAndDeletesPersistently() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("tools"), withIntermediateDirectories: true)
        try Data("from tools.helper import value\nprint(value)".utf8).write(to: source.appendingPathComponent("main.py"))
        try Data("value = 42".utf8).write(to: source.appendingPathComponent("tools/helper.py"))
        try Data("{\"n\":42}".utf8).write(to: source.appendingPathComponent("data.json"))
        let store = LearningStore(directory: base.appendingPathComponent("library"))
        let project = try store.importFolder(source)
        XCTAssertEqual(project.entry, "main.py")
        XCTAssertTrue(try store.files(in: project).contains { $0.path == "tools/helper.py" })
        XCTAssertThrowsError(try store.projectFile(project.id, path: "../escape.py"))
        let document = try store.openProjectFile(project, path: "main.py")
        store.update(document.id, source: "print(99)"); store.flush()
        XCTAssertEqual(try String(contentsOf: store.projectFile(project.id, path: "main.py")), "print(99)")
        _ = try store.openProjectFile(project, path: "data.json")
        try Data("{\"n\":99}".utf8).write(to: store.projectFile(project.id, path: "data.json"), options: .atomic)
        store.flush()
        XCTAssertEqual(try String(contentsOf: store.projectFile(project.id, path: "data.json")), "{\"n\":99}")
        XCTAssertEqual(LearningStore(directory: base.appendingPathComponent("library")).projects.count, 1)
        try store.deleteProject(project)
        XCTAssertTrue(LearningStore(directory: base.appendingPathComponent("library")).projects.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("main.py").path))
    }

    @MainActor
    func testOriginalLibraryMigratesAndKeepsBackup() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: ["documents":[["id":id.uuidString,"name":"old.py","source":"print(7)"]],"completed":["old-exercise"]])
        try data.write(to: base.appendingPathComponent("library.json"))
        let store = LearningStore(directory: base)
        XCTAssertEqual(store.document(id)?.source, "print(7)")
        XCTAssertTrue(store.completed.contains("old-exercise"))
        store.flush()
        XCTAssertEqual(try Data(contentsOf: base.appendingPathComponent("library-v1-backup.json")), data)
    }

    func testAIProtocolsRejectUnsafeEndpoints() throws {
        for format in AIProtocol.allCases {
            var profile = AIProfile(baseURL: "https://example.com/v1", format: format)
            XCTAssertEqual(try AIClient.endpoint(profile, path: "models").host, "example.com")
            profile.baseURL = "https://key:secret@example.com/v1"
            XCTAssertThrowsError(try AIClient.endpoint(profile, path: "models"))
            profile.baseURL = "http://example.com/v1"; profile.allowLocalHTTP = true
            XCTAssertThrowsError(try AIClient.endpoint(profile, path: "models"))
            for host in ["10.example.com", "192.168.example.com", "172.16.example.com", "10.999.0.1"] {
                profile.baseURL = "http://" + host + "/v1"
                XCTAssertThrowsError(try AIClient.endpoint(profile, path: "models"))
            }
            profile.baseURL = "http://192.168.1.10:11434/v1"
            XCTAssertNoThrow(try AIClient.endpoint(profile, path: "models"))
        }
    }

    @MainActor
    func testFailedSaveDoesNotAllowRefreshToDiscardDirtyText() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = LearningStore(directory: base)
        let project = try store.createProject(name: "测试")
        let document = try store.openProjectFile(project, path: "main.py")
        let url = try store.projectFile(project.id, path: "main.py")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        store.update(document.id, source: "未保存的内容")
        XCTAssertThrowsError(try store.flushOrThrow())
        store.refreshProject(project.id)
        XCTAssertEqual(store.document(document.id)?.source, "未保存的内容")
    }

    @MainActor
    func testImportRejectsInvalidContentAndKeepsExistingDocuments() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LearningStore(directory: folder)
        let original = store.documents.count
        XCTAssertThrowsError(try store.importScript(name: "bad.exe", data: Data("print(1)".utf8)))
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
