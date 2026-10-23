import Foundation
import SwiftUI

struct Exercise: Codable, Identifiable {
    let id: String
    let title: String
    let prompt: String
    let starter: String
    let expected: String
    let hint: String
    let solution: String
}

struct Lesson: Codable, Identifiable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    let body: String
    let example: String
    let exercises: [Exercise]
    let stage: String?
}

struct ScriptDocument: Codable, Identifiable {
    var id = UUID()
    var name: String
    var source: String
    var exerciseID: String?
    var projectID: UUID?
    var relativePath: String?
}

@MainActor
final class LearningStore: ObservableObject {
    @Published var documents: [ScriptDocument] = []
    @Published private(set) var completed: Set<String> = []
    @Published var projects: [ScriptProject] = []
    @Published var error: String?
    let lessons: [Lesson]
    let directory: URL
    private var canSave = true
    private var saveTask: Task<Void, Never>?
    private var dirtyDocuments: Set<UUID> = []
    private struct Saved: Codable {
        var documents: [ScriptDocument]
        var completed: Set<String>
        var projects: [ScriptProject]?
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PyLearn", isDirectory: true)
        if let url = Bundle.main.url(forResource: "lessons", withExtension: "json"),
           let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([Lesson].self, from: data) {
            lessons = items
        } else {
            lessons = []
            error = "课程资源读取失败，请检查安装包。"
        }
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let file = self.directory.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
                documents = saved.documents
                completed = saved.completed
                projects = saved.projects ?? []
                if saved.projects == nil {
                    let backup = self.directory.appendingPathComponent("library-v1-backup.json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: file, to: backup) }
                }
            } else {
                documents = [ScriptDocument(name: "你好，Python.py", source: "# 从这里开始你的 Python 学习\nname = input(\"你叫什么名字？\")\nprint(\"你好，\" + name)\n")]
                try persist()
            }
        } catch {
            canSave = false
            self.error = "无法读取学习记录，已暂停写入以保护原有文件：\(error.localizedDescription)"
        }
    }

    func document(_ id: UUID) -> ScriptDocument? { documents.first { $0.id == id } }

    @discardableResult
    func create(name: String = "新脚本.py", source: String = "", exerciseID: String? = nil) throws -> ScriptDocument {
        var unique = URL(fileURLWithPath: name).lastPathComponent
        let base = URL(fileURLWithPath: unique).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: unique).pathExtension
        var number = 2
        while documents.contains(where: { $0.name == unique }) {
            unique = "\(base) \(number).\(ext.isEmpty ? "py" : ext)"
            number += 1
        }
        let document = ScriptDocument(name: unique, source: source, exerciseID: exerciseID)
        documents.insert(document, at: 0)
        do { try persist() }
        catch { documents.removeAll { $0.id == document.id }; throw error }
        return document
    }

    func openExercise(_ exercise: Exercise) throws -> ScriptDocument {
        if let existing = documents.first(where: { $0.exerciseID == exercise.id }) { return existing }
        return try create(name: exercise.title + ".py", source: exercise.starter, exerciseID: exercise.id)
    }

    func importScript(name: String, data: Data) throws -> ScriptDocument {
        guard ["py", "txt", "json", "csv", "md", "toml", "yaml", "yml", "ini"].contains(URL(fileURLWithPath: name).pathExtension.lowercased()) else { throw failure("请选择 Python 或常见文本文件；二进制资源请通过文件夹导入。") }
        guard data.count <= 524288 else { throw failure("文件超过 512 KiB，首版暂不支持。") }
        guard var source = String(data: data, encoding: .utf8) else { throw failure("文件不是 UTF-8 编码，请转换编码后重新导入。") }
        if source.first == "\u{feff}" { source.removeFirst() }
        return try create(name: name, source: source)
    }

    func importFile(_ url: URL) throws -> ScriptDocument {
        try readExternal(url) { readable in
            let handle = try FileHandle(forReadingFrom: readable)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 524289) ?? Data()
            return try importScript(name: url.lastPathComponent, data: data)
        }
    }

    func update(_ id: UUID, source: String) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].source = source
        dirtyDocuments.insert(id)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            self?.flush()
        }
    }

    func delete(_ id: UUID) throws {
        let previous = documents
        documents.removeAll { $0.id == id }
        do { try persist() } catch { documents = previous; throw error }
    }

    func markComplete(_ id: String) {
        completed.insert(id)
        flush()
    }

    func flush() {
        do { try flushOrThrow() } catch { self.error = "保存失败，请先导出代码：\(error.localizedDescription)" }
    }

    func flushOrThrow() throws {
        saveTask?.cancel()
        try persist()
    }

    func persist() throws {
        guard canSave else { throw failure("学习记录读取失败，暂时不能覆盖原文件。") }
        for document in documents where dirtyDocuments.contains(document.id) && projects.contains(where: { $0.id == document.projectID }) {
            if let projectID = document.projectID, let path = document.relativePath {
                let file = try projectFile(projectID, path: path)
                try Data(document.source.utf8).write(to: file, options: .atomic)
            }
        }
        let data = try JSONEncoder().encode(Saved(documents: documents, completed: completed, projects: projects))
        try data.write(to: directory.appendingPathComponent("library.json"), options: .atomic)
        dirtyDocuments.removeAll()
    }

    func failure(_ message: String) -> NSError { NSError(domain: "PyLearn", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

    func openProjectFile(_ project: ScriptProject, path: String) throws -> ScriptDocument {
        try flushOrThrow()
        let url = try projectFile(project.id, path: path)
        let data = try Data(contentsOf: url)
        guard data.count <= 524288, let text = String(data: data, encoding: .utf8) else { throw failure("该文件为二进制、非 UTF-8 文本或超过 512 KiB。文件已保留，可由脚本读取。") }
        if let index = documents.firstIndex(where: { $0.projectID == project.id && $0.relativePath == path }) {
            documents[index].source = text
            return documents[index]
        }
        let document = ScriptDocument(name: url.lastPathComponent, source: text, projectID: project.id, relativePath: path)
        documents.append(document)
        try persist()
        return document
    }

    func refreshProject(_ id: UUID) {
        documents.removeAll { document in
            if dirtyDocuments.contains(document.id) { return false }
            guard document.projectID == id, let path = document.relativePath else { return false }
            guard let url = try? projectFile(id, path: path) else { return true }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        for index in documents.indices where documents[index].projectID == id {
            if dirtyDocuments.contains(documents[index].id) { continue }
            if let path = documents[index].relativePath, let url = try? projectFile(id, path: path),
               let source = try? String(contentsOf: url, encoding: .utf8) { documents[index].source = source }
        }
    }
}
