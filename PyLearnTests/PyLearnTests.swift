import XCTest
import SwiftUI
import Runestone
@testable import PyLearn

final class PyLearnTests: XCTestCase {
    @MainActor
    func testPickerDeliversOnlyOneSelectionOrCancellation() {
        var received: [[URL]] = []
        let picker = CodeImportPicker(mode: .files) { received.append($0) }
        let coordinator = picker.makeCoordinator()
        let native = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        let file = URL(fileURLWithPath: "/tmp/selected.py")
        coordinator.documentPicker(native, didPickDocumentsAt: [file])
        coordinator.documentPickerWasCancelled(native)
        coordinator.documentPicker(native, didPickDocumentsAt: [file])
        XCTAssertEqual(received, [[file]], "A late Files callback must not import twice or replace the selected result with cancellation")
    }

    @MainActor
    func testImportConsumesSelectionBeforeOpeningDestinationInEitherDismissalOrder() async throws {
        func present(_ controller: UIViewController, from parent: UIViewController) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                parent.present(controller, animated: false) { continuation.resume() }
            }
        }
        func dismiss(_ controller: UIViewController) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                controller.dismiss(animated: false) { continuation.resume() }
            }
        }
        for scenario in 0..<3 {
            var events: [String] = []
            let picker = CodeImportPicker(mode: .files, onDismiss: { events.append("open destination") }) { urls in
                XCTAssertEqual(urls.count, 1)
                events.append("consume selection")
            }
            let coordinator = picker.makeCoordinator()
            let native = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
            let container = CodeImportPickerController(picker: native, cancel: { coordinator.finish([]) }, disappeared: { coordinator.didDisappear() })
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIViewController()
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            host.view.layoutIfNeeded()
            await present(container, from: host)
            let cover = UIViewController()
            if scenario == 2 {
                cover.modalPresentationStyle = .fullScreen
                await present(cover, from: container)
                XCTAssertNil(container.view.window, "Exercise a real full-screen cover, not dismissal")
            }
            if scenario == 0 { await dismiss(container) }
            coordinator.documentPicker(native, didPickDocumentsAt: [URL(fileURLWithPath: "/tmp/selected.py")])
            if scenario != 0 {
                XCTAssertEqual(events, ["consume selection"], "Do not present an editor while the picker is open or covered")
                if scenario == 2 { await dismiss(cover) }
                await dismiss(container)
            }
            coordinator.documentPickerWasCancelled(native)
            XCTAssertEqual(events, ["consume selection", "open destination"], "Consume the selection and navigate exactly once, regardless of native dismissal order")
        }
    }

    @MainActor
    func testImportCancelStaysOutsideFilesBrowserAndFinishesOnce() throws {
        for mode in [CodeImportMode.files, .folder] {
            var received: [[URL]] = []
            let host = UIHostingController(rootView: CodeImportPicker(mode: mode) { received.append($0) })
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            host.view.layoutIfNeeded()
            func button(in root: UIView) -> UIButton? {
                if let button = root as? UIButton, button.accessibilityIdentifier == "code.import.cancel" { return button }
                return root.subviews.compactMap { button(in: $0) }.first
            }
            func picker(in root: UIViewController) -> UIDocumentPickerViewController? {
                if let picker = root as? UIDocumentPickerViewController { return picker }
                return root.children.compactMap { picker(in: $0) }.first
            }
            let native = try XCTUnwrap(picker(in: host))
            let cancel = try XCTUnwrap(button(in: host.view), "Cancellation must remain available outside the Files navigation hierarchy")
            XCTAssertFalse(cancel.isDescendant(of: native.view))
            cancel.sendActions(for: .touchUpInside)
            native.delegate?.documentPickerWasCancelled?(native)
            cancel.sendActions(for: .touchUpInside)
            XCTAssertEqual(received.count, 1)
            XCTAssertTrue(received.first?.isEmpty == true)
        }
    }

    @MainActor
    func testActualEditorTypingPairsUndoCompositionAndExternalReplacement() throws {
        var source = ""
        var selection = NSRange(location: 0, length: 0)
        let controller = EditorController()
        func editor() -> CodeEditor {
            CodeEditor(text: Binding(get: { source }, set: { source = $0 }), selection: Binding(get: { selection }, set: { selection = $0 }), controller: controller, editable: true, errorLine: nil)
        }
        let host = UIHostingController(rootView: editor())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let view = try XCTUnwrap(controller.view)
        let coordinator = try XCTUnwrap(view.editorDelegate as? CodeEditor.Coordinator)
        XCTAssertEqual(view.autocorrectionType, .no)
        XCTAssertEqual(view.autocapitalizationType, .none)
        XCTAssertEqual(view.smartQuotesType, .no)
        XCTAssertEqual(view.spellCheckingType, .no)
        view.selectedRange = NSRange(location: 0, length: 0)
        for chunk in ["print", "(", "'", "中文🐍", "'", ")", "\n"] {
            controller.insert(chunk)
            XCTAssertEqual(source, view.text)
        }
        XCTAssertEqual(source, "print('中文🐍')\n")
        let beforeUndo = source
        controller.undo()
        XCTAssertNotEqual(source, beforeUndo)
        XCTAssertEqual(source, view.text)
        controller.redo()
        XCTAssertEqual(source, beforeUndo)
        XCTAssertEqual(source, view.text)

        view.becomeFirstResponder()
        view.selectedRange = NSRange(location: 0, length: 0)
        func input(in root: UIView) -> (UIView & UITextInput)? {
            if let input = root as? (UIView & UITextInput) { return input }
            return root.subviews.compactMap { input(in: $0) }.first
        }
        let textInput = try XCTUnwrap(input(in: view))
        textInput.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(view.markedTextRange)
        let markedSelection = view.selectedRange
        selection = NSRange(location: 0, length: 0)
        coordinator.parent = editor()
        coordinator.synchronize(view)
        XCTAssertEqual(view.selectedRange, markedSelection)
        textInput.setMarkedText("你", selectedRange: NSRange(location: 1, length: 0))
        textInput.unmarkText()
        XCTAssertEqual(source, "你print('中文🐍')\n")
        XCTAssertEqual(source, view.text)

        // Replacing the document while the input method still owns marked text.
        textInput.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(view.markedTextRange)
        source = "external replacement"
        selection = NSRange(location: 0, length: 0)
        coordinator.parent = editor()
        coordinator.synchronize(view)
        XCTAssertNil(view.markedTextRange, "External reload must finish composition before replacing the document")
        XCTAssertEqual(view.text, "external replacement")
        XCTAssertEqual(source, "external replacement")
        for replacement in ["(", "a\r\nb\r\n"] {
            source = replacement
            coordinator.parent = editor()
            coordinator.synchronize(view)
            XCTAssertEqual(view.text, replacement, "External reload must not pair symbols or normalize line endings")
            XCTAssertEqual(source, replacement)
        }

        source = String(repeating: String(repeating: "x", count: 127) + "\n", count: 4096)
        coordinator.parent = editor()
        coordinator.synchronize(view)
        XCTAssertEqual(view.text, source)
        view.selectedRange = NSRange(location: (source as NSString).length, length: 0)
        controller.insert("x")
        XCTAssertEqual(view.text.utf8.count, 524288, "External replacement must refresh the byte-limit cache")
        source = "# replace after full file\n"
        selection = NSRange(location: (source as NSString).length, length: 0)
        coordinator.parent = editor()
        coordinator.synchronize(view)
        controller.insert("🐍")
        XCTAssertEqual(source, "# replace after full file\n🐍")
        XCTAssertEqual(source, view.text)
    }

    @MainActor
    func testLongFileInputValidationDoesNotCopyWholeDocumentPerKey() {
        let source = String(repeating: "# 中文abcdef0123456789\n", count: 16000)
        let controller = EditorController()
        let editor = CodeEditor(text: .constant(source), selection: .constant(NSRange(location: 0, length: 0)), controller: controller, editable: true, errorLine: nil)
        let coordinator = editor.makeCoordinator()
        let view = TextView()
        view.text = source
        let insertion = NSRange(location: (source as NSString).length, length: 0)
        let started = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1000 {
            XCTAssertTrue(coordinator.textView(view, shouldChangeTextIn: insertion, replacementText: "x"))
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        print("EDITOR_INPUT_VALIDATION_1000_MS: \(elapsed * 1000)")
        XCTAssertLessThan(elapsed, 0.25, "A small key validation must not copy/encode the entire 400 KiB file")
    }

    @MainActor
    func testEditorByteLimitHandlesUnicodeReplacementAndUpdatedText() {
        var source = String(repeating: "x", count: 524284) + "🐍"
        let editor = CodeEditor(text: Binding(get: { source }, set: { source = $0 }), selection: .constant(NSRange(location: 0, length: 0)), controller: EditorController(), editable: true, errorLine: nil)
        let coordinator = editor.makeCoordinator()
        let view = TextView()
        view.text = source
        XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 524286, length: 0), replacementText: "a"))
        XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 524284, length: 2), replacementText: "中文"))
        XCTAssertTrue(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 524284, length: 2), replacementText: "é"))
        view.text = "abc"
        coordinator.textViewDidChange(view)
        XCTAssertEqual(source, "abc")
        XCTAssertTrue(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 3, length: 0), replacementText: "中文🐍"))
    }

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
    func testBatchScriptDeletionProtectsUnselectedAndProjectFilesAndRollsBackOnSaveFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directory: directory)
        let first = try store.create(name: "first.py", source: "print(1)")
        let second = try store.create(name: "second.py", source: "print(2)")
        let keep = try store.create(name: "keep.py", source: "print(3)")
        let project = try store.createProject(name: "keep project")
        let projectFile = try store.openProjectFile(project, path: "main.py")
        let before = Set(store.documents.map(\.id))
        XCTAssertThrowsError(try store.deleteScripts([first.id, projectFile.id]))
        XCTAssertEqual(Set(store.documents.map(\.id)), before, "Invalid selections must not partially delete scripts")
        try store.deleteScripts([first.id, second.id])
        let restored = LearningStore(directory: directory)
        XCTAssertNil(restored.document(first.id)); XCTAssertNil(restored.document(second.id))
        XCTAssertEqual(restored.document(keep.id)?.source, "print(3)")
        XCTAssertNotNil(restored.document(projectFile.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.projectFile(project.id, path: "main.py").path))
        let saved = directory.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: saved)
        try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.deleteScripts([keep.id]))
        XCTAssertEqual(store.document(keep.id)?.source, "print(3)", "A failed batch save must preserve all selected source in memory")
        XCTAssertNotNil(store.document(projectFile.id))
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
