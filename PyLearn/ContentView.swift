import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var pythonSource: UTType { UTType(filenameExtension: "py") ?? .sourceCode }
}

struct PythonFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pythonSource] }
    var source: String
    init(source: String) { self.source = source }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        source = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(source.utf8))
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            LearningView().tabItem { Label("学习", systemImage: "book.closed") }
            ExerciseListView().tabItem { Label("练习", systemImage: "checkmark.circle") }
            CodeLibraryView().tabItem { Label("代码", systemImage: "chevron.left.forwardslash.chevron.right") }
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
struct CodeLibraryView: View {
    @EnvironmentObject private var store: LearningStore
    @State private var importing = false
    @State private var selected: ScriptDocument?
    @State private var deleting: ScriptDocument?
    @State private var deletingProject: ScriptProject?
    @State private var cloning = false
    var body: some View {
        NavigationStack {
            List {
                Section { Label("本机运行 · Python 3.15.1", systemImage: "iphone").font(.subheadline) }
                Section("我的项目 · 长按操作") {
                    ForEach(store.projects) { project in
                        NavigationLink { ProjectView(projectID: project.id) } label: { Label(project.name, systemImage: "folder") }
                            .contextMenu { Button(role: .destructive) { deletingProject = project } label: { Label("删除项目", systemImage: "trash") } }
                    }
                    Button { do { _ = try store.createProject(name: "新项目") } catch { store.error = error.localizedDescription } } label: { Label("新建项目", systemImage: "folder.badge.plus") }
                    Button { cloning = true } label: { Label("克隆 Git 仓库", systemImage: "arrow.down.doc") }
                }
                Section("我的脚本 · 长按操作") {
                    ForEach(store.documents.filter { $0.projectID == nil }) { document in
                        Button { selected = document } label: {
                            HStack {
                                Image(systemName: "doc.text").foregroundColor(.teal)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.name).foregroundColor(.primary)
                                    Text("\(document.source.components(separatedBy: "\n").count) 行 · 保存在本机").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(.vertical, 5)
                        }.contextMenu {
                            Button("打开") { selected = document }
                            Button { UIPasteboard.general.string = document.source } label: { Label("复制代码", systemImage: "doc.on.doc") }
                            Button(role: .destructive) { deleting = document } label: { Label("删除脚本", systemImage: "trash") }
                        }
                    }
                }
                Section {
                    Button { importing = true } label: { Label("导入文件或文件夹", systemImage: "square.and.arrow.down") }
                    Text("文件夹保留模块和资源，导入本机副本。最多 1000 个文件 / 50 MiB；文本编辑支持 UTF-8，单文件最大 512 KiB。").font(.caption).foregroundColor(.secondary)
                }
            }.navigationTitle("我的代码")
                .toolbar { Button {
                    do { selected = try store.create() } catch { store.error = error.localizedDescription }
                } label: { Image(systemName: "plus") }.accessibilityLabel("新建脚本") }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, .pythonSource, .plainText, .json, .commaSeparatedText, .data], allowsMultipleSelection: true) { result in
                    do { for url in try result.get() {
                        if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true { _ = try store.importFolder(url) }
                        else { selected = try store.importFile(url) }
                    }} catch { store.error = error.localizedDescription }
                }
                .sheet(item: $selected) { document in NavigationStack { ScriptEditor(documentID: document.id) } }
                .sheet(isPresented: $cloning) { NavigationStack { CloneRepositoryView() } }
                .confirmationDialog("删除 \(deleting?.name ?? "脚本")？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("删除脚本", role: .destructive) {
                        if let id = deleting?.id { do { try store.delete(id) } catch { store.error = error.localizedDescription } }
                        deleting = nil
                    }
                    Button("取消", role: .cancel) { deleting = nil }
                }
                .confirmationDialog("删除项目 \(deletingProject?.name ?? "")？", isPresented: Binding(get: { deletingProject != nil }, set: { if !$0 { deletingProject = nil } }), titleVisibility: .visible) {
                    Button("删除项目", role: .destructive) {
                        if let project = deletingProject { do { try store.deleteProject(project) } catch { store.error = error.localizedDescription } }
                        deletingProject = nil
                    }
                }
                .alert("文件提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
        }
    }
}
struct ProjectView: View {
    @EnvironmentObject private var store: LearningStore
    @State private var selected: ScriptDocument?
    @State private var files: [ProjectFile] = []
    @State private var newPath = ""
    @State private var adding = false
    let projectID: UUID
    private var project: ScriptProject? { store.projects.first { $0.id == projectID } }
    var body: some View {
        List {
            if let project {
                Section {
                    Text("入口：\(project.entry ?? "长按 .py 文件设为入口")").font(.caption)
                    if let entry = project.entry { Button("打开运行入口") { open(project, path: entry) } }
                    NavigationLink("Git 版本管理") { GitView(project: project) }
                }
                Section("项目文件 · 长按操作") {
                    ForEach(files) { file in
                        Button { if !file.isDirectory { open(project, path: file.path) } } label: {
                            Label(file.path.split(separator: "/").last.map(String.init) ?? file.path, systemImage: file.isDirectory ? "folder" : "doc.text")
                                .padding(.leading, CGFloat(min(file.depth, 8)) * 14).foregroundColor(.primary)
                        }.contextMenu {
                            if !file.isDirectory {
                                Button("复制相对路径") { UIPasteboard.general.string = file.path }
                                if file.path.hasSuffix(".py") {
                                    Button("设为运行入口") { do { try store.setEntry(project, path: file.path) } catch { store.error = error.localizedDescription } }
                                }
                            }
                        }
                    }
                }
            }
        }.navigationTitle(project?.name ?? "项目")
            .toolbar { Button("新建文件") { adding = true } }
            .alert("新建文件", isPresented: $adding) {
                TextField("例如 tools/helper.py", text: $newPath)
                Button("创建") { do {
                    let url = try store.projectFile(projectID, path: newPath)
                    guard !FileManager.default.fileExists(atPath: url.path) else { throw store.failure("同名文件已存在。") }
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data().write(to: url, options: .withoutOverwriting)
                    refresh()
                } catch { store.error = error.localizedDescription } }
                Button("取消", role: .cancel) {}
            }
            .onAppear { refresh() }
            .sheet(item: $selected, onDismiss: { refresh() }) { document in NavigationStack { ScriptEditor(documentID: document.id) } }
            .alert("项目提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private func refresh() { if let project { do { files = try store.files(in: project) } catch { store.error = error.localizedDescription } } }
    private func open(_ project: ScriptProject, path: String) { do { selected = try store.openProjectFile(project, path: path) } catch { store.error = error.localizedDescription } }
}
