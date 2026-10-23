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
    func readExternal<T>(_ url: URL, body: (URL) throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var result: Result<T, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            result = Result { try body(readable) }
        }
        if let coordinationError { throw failure("无法读取所选文件，请先在“文件”App 中确认已下载到本机，再重试。\n" + coordinationError.localizedDescription) }
        guard let result else { throw failure("文件提供程序没有返回可读取的内容，请重新选择。") }
        return try result.get()
    }

    func relativePath(of url: URL, inside directory: URL) throws -> String {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let file = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard file.count > root.count, Array(file.prefix(root.count)) == root else { throw failure("文件路径超出了项目文件夹。") }
        return file.dropFirst(root.count).joined(separator: "/")
    }

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
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return [] }
        var files: [ProjectFile] = []
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if [".git", ".venv", "__pycache__", "node_modules", "venv"].contains(url.lastPathComponent) { iterator.skipDescendants(); continue }
            files.append(ProjectFile(path: try relativePath(of: url, inside: root), isDirectory: values.isDirectory == true))
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func importFolder(_ url: URL) throws -> ScriptProject {
        try readExternal(url) { try copyFolder($0) }
    }

    private func copyFolder(_ url: URL) throws -> ScriptProject {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw failure("请选择文件夹。") }
        let project = ScriptProject(name: url.lastPathComponent)
        let target = projectRoot(project.id)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        do {
            var enumerationError: Error?
            guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], errorHandler: { _, error in enumerationError = error; return false }) else { throw failure("无法读取文件夹。") }
            var count = 0, bytes = 0
            for case let item as URL in iterator {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true else { throw failure("文件夹含符号链接，请移除链接后导入。") }
                if ["__pycache__", "node_modules", ".venv", "venv"].contains(item.lastPathComponent) { iterator.skipDescendants(); continue }
                let relative = try relativePath(of: item, inside: url)
                let destination = try projectFile(project.id, path: relative)
                if values.isDirectory == true { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
                else {
                    count += 1; bytes += values.fileSize ?? 0
                    guard count <= 1000, bytes <= 50 * 1024 * 1024 else { throw failure("项目超过 1000 个文件或 50 MiB，请精简后再导入。") }
                    try FileManager.default.copyItem(at: item, to: destination)
                }
            }
            if let enumerationError { throw failure("文件夹有内容无法读取，已取消导入。\n" + enumerationError.localizedDescription) }
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
        let file = try projectFile(project.id, path: path)
        guard FileManager.default.fileExists(atPath: file.path) else { throw failure("运行入口不存在，请重新选择项目中的 Python 文件。") }
        guard path.hasSuffix(".py"), let index = projects.firstIndex(where: { $0.id == project.id }) else { throw failure("请选择 Python 文件作为运行入口。") }
        projects[index].entry = path
        try persist()
    }

    @discardableResult
    func createProjectFile(_ project: ScriptProject, path: String, source: String = "") throws -> ScriptDocument {
        try flushOrThrow()
        guard projects.contains(where: { $0.id == project.id }), source.utf8.count <= 524288 else { throw failure("项目不存在或文件超过 512 KiB。") }
        let file = try projectFile(project.id, path: path)
        guard !FileManager.default.fileExists(atPath: file.path) else { throw failure("同名文件已存在，请换个名称；不会覆盖原文件。") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(source.utf8).write(to: file, options: .withoutOverwriting)
        let oldDocuments = documents
        do { return try openProjectFile(project, path: path) }
        catch { documents = oldDocuments; try? FileManager.default.removeItem(at: file); throw error }
    }

    @discardableResult
    func addScript(_ documentID: UUID, to project: ScriptProject, path: String) throws -> ScriptDocument {
        guard let document = document(documentID), document.projectID == nil else { throw failure("请选择“我的脚本”中的文件。") }
        return try createProjectFile(project, path: path, source: document.source)
    }

    func repairProjectEntry(_ project: ScriptProject) throws {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        if let entry = project.entry, let url = try? projectFile(project.id, path: entry), FileManager.default.fileExists(atPath: url.path) { return }
        let candidates = try files(in: project).filter { !$0.isDirectory && $0.path.lowercased().hasSuffix(".py") }.map(\.path)
        let suffixMatches = candidates.filter { path in project.entry?.hasSuffix("/" + path) == true }
        let entry = suffixMatches.count == 1 ? suffixMatches[0] : candidates.first(where: { $0 == "main.py" }) ?? candidates.first
        if projects[index].entry != entry { projects[index].entry = entry; try persist() }
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
