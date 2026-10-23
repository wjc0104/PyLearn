import XCTest
@testable import PyLearn

final class PyLearnTests: XCTestCase {
    @MainActor
    func testModelTestDoesNotSwitchUntilUserConfirmsAndRejectsStaleResults() async throws {
        let suite = "PyLearn-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = AIProfiles(defaults: defaults)
        let original = AIProfile(name: "current", model: "old")
        let candidate = AIProfile(name: "candidate", baseURL: "https://models.test.invalid/v1", model: "saved")
        profiles.items = [original, candidate]; profiles.selected = original.id.uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelTestProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        ModelTestProtocol.status = 200
        let verified = try await profiles.testModel(candidate, model: "working", transport: transport)
        XCTAssertEqual(verified.response, "OK")
        XCTAssertEqual(profiles.active?.id, original.id, "Testing must not change the active model")
        try profiles.use(verified)
        XCTAssertEqual(profiles.active?.model, "working")
        let second = try await profiles.testModel(profiles.items[1], model: "another", transport: transport)
        profiles.items[1].baseURL = "https://changed.test.invalid/v1"
        XCTAssertThrowsError(try profiles.use(second), "A result from an edited configuration must not be activated")
        XCTAssertEqual(profiles.active?.model, "working")
    }

    @MainActor
    func testProjectFileAndFolderDeletionClearsCacheAndRepairsEntry() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = LearningStore(directory: base)
        let project = try store.createProject(name: "删除测试")
        let main = try store.openProjectFile(project, path: "main.py")
        let nested = try store.createProjectFile(project, path: "模块/辅助.py", source: "value=1")
        _ = try store.createProjectFile(project, path: "保留.py", source: "print(1)")
        store.update(nested.id, source: "value=99")
        try store.deleteProjectFile(project, path: "模块")
        try store.delete(main.id)
        try store.flushOrThrow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.projectRoot(project.id).appendingPathComponent("模块").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.projectRoot(project.id).appendingPathComponent("main.py").path))
        let restored = LearningStore(directory: base)
        XCTAssertNil(restored.document(main.id)); XCTAssertNil(restored.document(nested.id))
        XCTAssertEqual(restored.projects.first?.entry, "保留.py")
        let backups = FileManager.default.enumerator(at: base.appendingPathComponent("deleted-project-files"), includingPropertiesForKeys: nil)!
        let savedHelper = backups.compactMap { $0 as? URL }.first { $0.lastPathComponent == "辅助.py" }
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(savedHelper), encoding: .utf8), "value=99")
        XCTAssertThrowsError(try store.deleteProjectFile(project, path: "../outside"))
        XCTAssertThrowsError(try store.deleteProjectFile(project, path: ".git/config"))
    }

    @MainActor
    func testDeletionIsCancelledWhenPendingSaveFails() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = LearningStore(directory: base)
        let project = try store.createProject(name: "回滚测试")
        let document = try store.openProjectFile(project, path: "main.py")
        let metadata = base.appendingPathComponent("library.json")
        let original = try Data(contentsOf: metadata)
        store.update(document.id, source: "print('pending edit')")
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.deleteProjectFile(project, path: "main.py"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.projectFile(project.id, path: "main.py").path))
        XCTAssertEqual(store.document(document.id)?.source, "print('pending edit')")
        XCTAssertEqual(store.projects.first?.entry, "main.py")
        try FileManager.default.removeItem(at: metadata)
        try original.write(to: metadata)
        try store.flushOrThrow()
    }

    func testEmbeddedGitCommitsHistoryAndDeletedFiles() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        func git(_ operation: String, message: String = "") async throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: ["action":"git", "operation":operation, "directory":base.path, "message":message])
            let response = await withCheckedContinuation { continuation in
                PLPythonRuntime.shared().performRequest(String(decoding: data, as: UTF8.self)) { continuation.resume(returning: $0) }
            }
            let result = try JSONSerialization.jsonObject(with: Data(response.utf8)) as! [String: Any]
            XCTAssertEqual(result["status"] as? String, "success", response)
            return result
        }
        _ = try await git("init")
        let file = base.appendingPathComponent("中文练习.py")
        try Data("print(42)".utf8).write(to: file)
        _ = try await git("commit", message: "iOS first commit")
        let history = try await git("log")
        XCTAssertTrue((history["report"] as? String)?.contains("iOS first commit") == true)
        try FileManager.default.removeItem(at: file)
        _ = try await git("commit", message: "iOS delete file")
        let secondHistory = try await git("log")
        XCTAssertTrue((secondHistory["report"] as? String)?.contains("iOS delete file") == true)
        let state = try await git("status")
        XCTAssertEqual(state["report"] as? String, "工作区干净。")
    }

    func testEmbeddedGitCanCloneOverRealHTTPS() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let data = try JSONSerialization.data(withJSONObject: ["action":"git", "operation":"clone", "directory":base.path, "remote":"https://github.com/octocat/Hello-World.git"])
        let response = await withCheckedContinuation { continuation in
            PLPythonRuntime.shared().performRequest(String(decoding: data, as: UTF8.self)) { continuation.resume(returning: $0) }
        }
        let result = try JSONSerialization.jsonObject(with: Data(response.utf8)) as! [String: Any]
        XCTAssertEqual(result["status"] as? String, "success", response)
        XCTAssertTrue(FileManager.default.fileExists(atPath: base.appendingPathComponent("README").path))
    }

    @MainActor
    func testModelMustRespondBeforeItCanReplaceCurrentSelection() async throws {
        let suite = "PyLearn-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = AIProfiles(defaults: defaults)
        let original = AIProfile(name: "original", model: "old")
        let candidate = AIProfile(name: "test", baseURL: "https://models.test.invalid/v1", model: "saved")
        profiles.items = [original, candidate]; profiles.selected = original.id.uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelTestProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        ModelTestProtocol.status = 403
        do { try await profiles.useVerified(candidate, model: "unavailable", transport: transport); XCTFail("Unavailable model selected") } catch {}
        XCTAssertEqual(profiles.active?.id, original.id)
        XCTAssertEqual(profiles.items[1].model, "saved")
        ModelTestProtocol.status = 200
        try await profiles.useVerified(candidate, model: "working", transport: transport)
        XCTAssertEqual(profiles.active?.model, "working")
        XCTAssertEqual(AIProfiles(defaults: defaults).active?.model, "working")
        let cancelled = Task { try await profiles.useVerified(candidate, model: "late-response", transport: transport) }
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("Cancelled model switch was saved") } catch {}
        XCTAssertEqual(profiles.active?.model, "working")
        profiles.remove(candidate.id)
        XCTAssertNil(profiles.active, "Deleting the active profile must not silently select an untested model")
    }

    @MainActor
    func testGitCredentialsAreReusedPerHostWithoutCrossHostLeak() throws {
        let host = UUID().uuidString.lowercased() + ".test.invalid"
        let remote = "https://" + host + "/one.git"
        defer {
            try? SecretStore.save("", account: "git.token." + host)
            UserDefaults.standard.removeObject(forKey: "git.username." + host)
        }
        try GitCredentials.save(remote, username: "fixture", token: "fixture-token")
        XCTAssertEqual(GitCredentials.load("https://" + host + "/two.git").username, "fixture")
        XCTAssertEqual(GitCredentials.load("https://" + host + "/two.git").token, "fixture-token")
        XCTAssertTrue(GitCredentials.load("https://other.test.invalid/two.git").token.isEmpty)
        XCTAssertThrowsError(try GitCredentials.save("http://" + host, username: "fixture", token: "fixture-token"))
        try GitCredentials.save(remote, username: "fixture", token: "")
        XCTAssertTrue(GitCredentials.load(remote).token.isEmpty)
    }

    @MainActor
    func testLastCompletionRequestIsDeliveredWhenAnalysisIsInFlight() async {
        let session = PythonSession()
        let first = expectation(description: "First analysis")
        let latest = expectation(description: "Latest analysis survives pending request")
        session.analyze(source: "value='abc'\nvalue.lo", prefix: "lo", line: 2, column: 8) { _, _, _ in first.fulfill() }
        session.analyze(source: "value='abc'\nvalue.up", prefix: "up", line: 2, column: 8) { _, names, _ in
            XCTAssertTrue(names.contains("upper")); latest.fulfill()
        }
        await fulfillment(of: [first, latest], timeout: 30)
    }

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

    func testEmbeddedLatestPythonSyntaxAndJedi() throws {
        let runtime = PLPythonRuntime.shared()
        let done = expectation(description: "Python 3.15 and templates")
        var output = ""
        runtime.outputHandler = { output = $0 }
        let source = "import sys\nfrom string.templatelib import Template\nx=7\nvalue=t'{x}'\nprint(sys.version.split()[0], isinstance(value, Template))"
        let data = try JSONSerialization.data(withJSONObject: ["action":"run", "source":source])
        runtime.performRequest(String(decoding: data, as: UTF8.self)) { response in
            XCTAssertTrue(response.contains("success"), response)
            XCTAssertEqual(output, "3.15.1 True\n")
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        let completion = expectation(description: "Embedded static member completion")
        let analysis = try JSONSerialization.data(withJSONObject: ["action":"analyze", "source":"value='abc'\nvalue.up", "prefix":"up", "line":2, "column":8])
        runtime.performRequest(String(decoding: analysis, as: UTF8.self)) { response in
            XCTAssertTrue(response.contains("upper"), response)
            completion.fulfill()
        }
        wait(for: [completion], timeout: 30)
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

private final class ModelTestProtocol: URLProtocol {
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "models.test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"choices\":[{\"message\":{\"content\":\"OK\"}}]}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
