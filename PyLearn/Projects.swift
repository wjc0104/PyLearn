import Foundation

struct ScriptProject: Codable, Identifiable {
    var id = UUID()
    var name: String
    var entry: String?
}

struct ProjectFile: Identifiable {
    let path: String
    let isDirectory: Bool
    var id: String { path }
    var depth: Int { path.split(separator: "/").count - 1 }
}

extension LearningStore {
    func projectRoot(_ id: UUID) -> URL { directory.appendingPathComponent("projects", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true) }

    func projectFile(_ id: UUID, path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw failure("文件路径无效。") }
        let root = projectRoot(id).standardizedFileURL.resolvingSymlinksInPath()
        let file = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/") else { throw failure("文件路径超出了项目文件夹。") }
        return file
    }

    func files(in project: ScriptProject) throws -> [ProjectFile] {
        let root = projectRoot(project.id)
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [ProjectFile] = []
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if ["__pycache__", "node_modules", "venv"].contains(url.lastPathComponent) { iterator.skipDescendants(); continue }
            files.append(ProjectFile(path: String(url.path.dropFirst(root.path.count + 1)), isDirectory: values.isDirectory == true))
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func importFolder(_ url: URL) throws -> ScriptProject {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw failure("请选择文件夹。") }
        let project = ScriptProject(name: url.lastPathComponent)
        let target = projectRoot(project.id)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        do {
            guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else { throw failure("无法读取文件夹。") }
            var count = 0, bytes = 0
            for case let item as URL in iterator {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true else { throw failure("文件夹含符号链接，请移除链接后导入。") }
                if ["__pycache__", "node_modules", ".venv", "venv"].contains(item.lastPathComponent) { iterator.skipDescendants(); continue }
                let relative = String(item.path.dropFirst(url.path.count + 1))
                let destination = try projectFile(project.id, path: relative)
                if values.isDirectory == true { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
                else {
                    count += 1; bytes += values.fileSize ?? 0
                    guard count <= 1000, bytes <= 50 * 1024 * 1024 else { throw failure("项目超过 1000 个文件或 50 MiB，请精简后再导入。") }
                    try FileManager.default.copyItem(at: item, to: destination)
                }
            }
            var saved = project
            let python = try files(in: project).filter { !$0.isDirectory && $0.path.hasSuffix(".py") }.map(\.path)
            saved.entry = python.first(where: { $0 == "main.py" }) ?? python.first
            projects.append(saved)
            do { try persist() } catch { projects.removeAll { $0.id == project.id }; throw error }
            return saved
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    func createProject(name: String) throws -> ScriptProject {
        let project = ScriptProject(name: name.isEmpty ? "新项目" : name, entry: "main.py")
        let root = projectRoot(project.id)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("# 从这里开始\nprint('你好，Python')\n".utf8).write(to: root.appendingPathComponent("main.py"), options: .atomic)
        projects.append(project)
        do { try persist() } catch { projects.removeAll { $0.id == project.id }; throw error }
        return project
    }

    func setEntry(_ project: ScriptProject, path: String) throws {
        _ = try projectFile(project.id, path: path)
        guard path.hasSuffix(".py"), let index = projects.firstIndex(where: { $0.id == project.id }) else { throw failure("请选择 Python 文件作为运行入口。") }
        projects[index].entry = path
        try persist()
    }

    func deleteProject(_ project: ScriptProject) throws {
        let trash = directory.appendingPathComponent("deleted-projects", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let source = projectRoot(project.id)
        let target = trash.appendingPathComponent(project.id.uuidString + "-" + UUID().uuidString)
        try FileManager.default.moveItem(at: source, to: target)
        let before = projects
        let previousDocuments = documents
        projects.removeAll { $0.id == project.id }
        documents.removeAll { $0.projectID == project.id }
        do { try persist() } catch { projects = before; documents = previousDocuments; try? FileManager.default.moveItem(at: target, to: source); throw error }
    }
}
