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
        if !failures.isEmpty {
            for failure in failures { print("FAIL: " + failure) }
            exit(1)
        }
        print("PASS: aliased project listing, Chinese paths, opening, pending edits and disk persistence")
    }
}
