import Foundation

@main
struct StorageRegression {
    @MainActor static func main() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: base) }
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        let real = base.appendingPathComponent("actual-library")
        try manager.createDirectory(at: real, withIntermediateDirectories: true)
        let alias = base.appendingPathComponent("short")
        try manager.createSymbolicLink(at: alias, withDestinationURL: real)
        let store = LearningStore(directory: alias)
        let project = try store.createProject(name: "中文项目")
        let root = store.projectRoot(project.id)
        try Data("print('中文')".utf8).write(to: root.appendingPathComponent("1字面量与变量.py"))
        let paths = try store.files(in: project).filter { !$0.isDirectory }.map(\.path)
        var failures: [String] = []
        if Set(paths) != Set(["main.py", "1字面量与变量.py"]) {
            failures.append("Alias enumeration returned incorrect relative paths: \(paths)")
        }
        for path in paths {
            do { _ = try store.openProjectFile(project, path: path) }
            catch { failures.append("Listed file cannot open: \(path): \(error)") }
        }
        let document = try store.openProjectFile(project, path: "main.py")
        store.update(document.id, source: "print('unsaved edit')")
        let reopened = try store.openProjectFile(project, path: "main.py")
        if reopened.source != "print('unsaved edit')" { failures.append("Reopening a project file discarded pending edits") }
        try store.flushOrThrow()
        if try String(contentsOf: root.appendingPathComponent("main.py"), encoding: .utf8) != "print('unsaved edit')" {
            failures.append("Edited text was not written to the repository worktree")
        }
        let source = base.appendingPathComponent("source")
        try manager.createDirectory(at: source.appendingPathComponent("模块"), withIntermediateDirectories: true)
        try Data("print(42)".utf8).write(to: source.appendingPathComponent("main.py"))
        try Data("value=42".utf8).write(to: source.appendingPathComponent("模块/辅助.py"))
        try Data([0,1,2,255]).write(to: source.appendingPathComponent("image.bin"))
        let sourceAlias = base.appendingPathComponent("导入链接")
        try manager.createSymbolicLink(at: sourceAlias, withDestinationURL: source)
        let imported = try store.importFolder(sourceAlias)
        if imported.entry != "main.py" { failures.append("Folder entry was not preserved") }
        let nested = try store.openProjectFile(imported, path: "模块/辅助.py")
        if nested.source != "value=42" { failures.append("Nested Chinese file did not import") }
        let resource = try Data(contentsOf: store.projectFile(imported.id, path: "image.bin"))
        if resource != Data([0,1,2,255]) { failures.append("Binary resource was changed") }
        let single = try store.importFile(source.appendingPathComponent("模块/辅助.py"))
        let copy = try store.addScript(single.id, to: imported, path: "新增/练习.py")
        if copy.projectID != imported.id || store.document(single.id)?.projectID != nil { failures.append("Adding a script did not preserve the standalone original") }
        store.update(copy.id, source: "print('项目编辑')")
        try store.flushOrThrow()
        if try String(contentsOf: store.projectFile(imported.id, path: "新增/练习.py"), encoding: .utf8) != "print('项目编辑')" { failures.append("Project copy edits did not reach disk") }
        do { _ = try store.addScript(single.id, to: imported, path: "新增/练习.py"); failures.append("Existing file was overwritten") } catch {}
        var broken = imported
        broken.entry = "B2F7A79/main.py"
        store.projects[store.projects.firstIndex(where: { $0.id == imported.id })!] = broken
        try store.repairProjectEntry(broken)
        if store.projects.first(where: { $0.id == imported.id })?.entry != "main.py" { failures.append("Existing malformed entry was not repaired") }
        do { _ = try store.projectFile(imported.id, path: "../outside.py"); failures.append("Path traversal accepted") } catch {}
        let restored = LearningStore(directory: alias)
        if restored.projects.count != 2 || restored.document(copy.id)?.source != "print('项目编辑')" { failures.append("Project state did not survive reopening") }
        if !failures.isEmpty {
            for failure in failures { print("FAIL: " + failure) }
            exit(1)
        }
        print("PASS: alias paths, folder/single import, Chinese nested files, binary resources, script copying, collision protection, entry repair and persistence")
    }
}
