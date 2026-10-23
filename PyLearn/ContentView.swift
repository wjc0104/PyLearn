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
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        source = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(source.utf8)) }
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

enum CodeImportMode: String, Identifiable {
    case files, folder
    var id: String { rawValue }
}

struct CodeImportPicker: UIViewControllerRepresentable {
    let mode: CodeImportMode
    let completion: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: mode == .folder ? [.folder] : [.item], asCopy: false)
        picker.allowsMultipleSelection = mode == .files
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        init(_ completion: @escaping ([URL]) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion([]) }
    }
}

struct CodeLibraryView: View {
    @EnvironmentObject private var store: LearningStore
    @State private var importMode: CodeImportMode?
    @State private var selected: ScriptDocument?
    @State private var deleting: ScriptDocument?
    @State private var deletingProject: ScriptProject?
    @State private var addingScript: ScriptDocument?
    @State private var cloning = false
    @State private var navigation: [UUID] = []
    @State private var importMessage = ""
    @State private var importedDocument: ScriptDocument?
    @State private var importedProject: UUID?
    var body: some View {
        NavigationStack(path: $navigation) {
            List {
                Section { Label("本机运行 · Python 3.15.1", systemImage: "iphone").font(.subheadline) }
                projectsSection
                scriptsSection
                Section {
                    Button { importMode = .files } label: { Label("导入文件（可多选）", systemImage: "doc.badge.plus") }
                    Button { importMode = .folder } label: { Label("导入整个文件夹", systemImage: "folder.badge.plus") }
                    Text("选择文件夹后点“打开”，自动导入其中所有子目录、模块与资源。最多 1000 个文件 / 50 MiB；文本编辑支持 UTF-8、单文件最大 512 KiB。").font(.caption).foregroundColor(.secondary)
                    if !importMessage.isEmpty { Text(importMessage).font(.caption).textSelection(.enabled).accessibilityIdentifier("importResult") }
                }
            }
            .navigationTitle("我的代码")
            .navigationDestination(for: UUID.self) { ProjectView(projectID: $0) }
            .toolbar { Button {
                do { selected = try store.create() } catch { store.error = error.localizedDescription }
            } label: { Image(systemName: "plus") }.accessibilityLabel("新建脚本") }
            .sheet(item: $importMode, onDismiss: finishImport) { mode in
                CodeImportPicker(mode: mode) { urls in importURLs(urls, mode: mode); importMode = nil }
            }
            .sheet(item: $selected) { document in NavigationStack { ScriptEditor(documentID: document.id) } }
            .sheet(item: $addingScript) { document in NavigationStack { AddScriptToProjectView(documentID: document.id) } }
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
    private var projectsSection: some View {
        Section("我的项目 · 长按操作") {
            ForEach(store.projects) { project in
                NavigationLink(value: project.id) { Label(project.name, systemImage: "folder") }
                    .contextMenu { Button(role: .destructive) { deletingProject = project } label: { Label("删除项目", systemImage: "trash") } }
            }
            Button {
                do { navigation.append(try store.createProject(name: "新项目").id) } catch { store.error = error.localizedDescription }
            } label: { Label("新建项目", systemImage: "folder.badge.plus") }
            Button { cloning = true } label: { Label("克隆 Git 仓库", systemImage: "arrow.down.doc") }
        }
    }
    private var scriptsSection: some View {
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
                    Button { addingScript = document } label: { Label("添加到项目 / Git 仓库", systemImage: "folder.badge.plus") }
                    Button { UIPasteboard.general.string = document.source } label: { Label("复制代码", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { deleting = document } label: { Label("删除脚本", systemImage: "trash") }
                }
            }
        }
    }
    private func importURLs(_ urls: [URL], mode: CodeImportMode) {
        guard !urls.isEmpty else { return }
        var successes = 0
        var errors: [String] = []
        for url in urls {
            do {
                if mode == .folder { importedProject = try store.importFolder(url).id }
                else { importedDocument = try store.importFile(url) }
                successes += 1
            } catch { errors.append(url.lastPathComponent + "：" + error.localizedDescription) }
        }
        importMessage = "成功导入 \(successes) 个\(mode == .folder ? "文件夹项目" : "文件")。" + (errors.isEmpty ? "" : "\n导入失败：\n" + errors.joined(separator: "\n"))
    }
    private func finishImport() {
        if let id = importedProject { navigation.append(id); importedProject = nil }
        else if let document = importedDocument { selected = document }
        importedDocument = nil
    }
}

struct ProjectView: View {
    @EnvironmentObject private var store: LearningStore
    @State private var selected: ScriptDocument?
    @State private var files: [ProjectFile] = []
    @State private var newPath = ""
    @State private var adding = false
    @State private var addingFolder = false
    @State private var addingScript = false
    @State private var deletingFile: ProjectFile?
    let projectID: UUID
    var folder = ""
    private var project: ScriptProject? { store.projects.first { $0.id == projectID } }
    private var children: [ProjectFile] { files.filter { path in
        let parent = path.path.split(separator: "/").dropLast().joined(separator: "/")
        return parent == folder
    } }
    var body: some View {
        List {
            if let project {
                if folder.isEmpty {
                    Section {
                        Text("入口：\(project.entry ?? "长按 .py 文件设为入口")").font(.caption)
                        if let entry = project.entry { Button("打开运行入口") { open(project, path: entry) } }
                        NavigationLink("Git 版本管理") { GitView(project: project) }
                        Button("添加我的脚本") { addingScript = true }
                    }
                }
                Section("项目文件 · 长按操作") {
                    ForEach(children) { file in
                        if file.isDirectory {
                            NavigationLink { ProjectView(projectID: projectID, folder: file.path) } label: { Label(fileName(file.path), systemImage: "folder") }
                                .contextMenu {
                                    Button("复制相对路径") { UIPasteboard.general.string = file.path }
                                    Button(role: .destructive) { deletingFile = file } label: { Label("删除文件夹", systemImage: "trash") }
                                }
                        } else {
                            Button { open(project, path: file.path) } label: { Label(fileName(file.path), systemImage: "doc.text").foregroundColor(.primary) }
                            .contextMenu {
                                Button("打开编辑") { open(project, path: file.path) }
                                Button("复制相对路径") { UIPasteboard.general.string = file.path }
                                if file.path.lowercased().hasSuffix(".py") {
                                    Button("设为运行入口") { do { try store.setEntry(project, path: file.path) } catch { store.error = error.localizedDescription } }
                                }
                                Button(role: .destructive) { deletingFile = file } label: { Label("删除文件", systemImage: "trash") }
                            }
                        }
                    }
                    if children.isEmpty { Text("文件夹为空，点右上角添加文件。").foregroundColor(.secondary) }
                }
            }
        }
        .navigationTitle(folder.isEmpty ? project?.name ?? "项目" : fileName(folder))
        .toolbar {
            Menu {
                Button("新建文件") { newPath = ""; adding = true }
                Button("新建文件夹") { newPath = ""; addingFolder = true }
                Button("添加我的脚本") { addingScript = true }
            } label: { Image(systemName: "plus") }.accessibilityLabel("添加项目文件")
        }
        .alert("新建文件", isPresented: $adding) {
            TextField("例如 tools/helper.py", text: $newPath)
            Button("创建") { if let project { do {
                selected = try store.createProjectFile(project, path: destination(newPath))
                refresh()
            } catch { store.error = error.localizedDescription } } }
            Button("取消", role: .cancel) {}
        }
        .alert("新建文件夹", isPresented: $addingFolder) {
            TextField("文件夹名称", text: $newPath)
            Button("创建") { do {
                let url = try store.projectFile(projectID, path: destination(newPath))
                guard !FileManager.default.fileExists(atPath: url.path) else { throw store.failure("同名文件或文件夹已存在。") }
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                refresh()
            } catch { store.error = error.localizedDescription } }
            Button("取消", role: .cancel) {}
        }
        .onAppear { refresh() }
        .confirmationDialog("删除项目中的“\(deletingFile.map { fileName($0.path) } ?? "")”？", isPresented: Binding(get: { deletingFile != nil }, set: { if !$0 { deletingFile = nil } }), titleVisibility: .visible) {
            Button("确认删除", role: .destructive) {
                if let project, let file = deletingFile {
                    do { try store.deleteProjectFile(project, path: file.path); refresh() }
                    catch { store.error = error.localizedDescription }
                }
                deletingFile = nil
            }
            Button("取消", role: .cancel) { deletingFile = nil }
        } message: { Text("文件夹中的内容也会一起删除。本机保留恢复副本；Git 仓库中的删除需要提交并推送后才会同步到远端。") }
        .sheet(item: $selected, onDismiss: refresh) { document in NavigationStack { ScriptEditor(documentID: document.id) } }
        .sheet(isPresented: $addingScript, onDismiss: refresh) { NavigationStack { AddScriptToProjectView(projectID: projectID, folder: folder) } }
        .alert("项目提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private func fileName(_ path: String) -> String { path.split(separator: "/").last.map(String.init) ?? path }
    private func destination(_ path: String) -> String { folder.isEmpty ? path : folder + "/" + path }
    private func refresh() {
        if let project { do {
            try store.repairProjectEntry(project)
            files = try store.files(in: project)
        } catch { store.error = error.localizedDescription } }
    }
    private func open(_ project: ScriptProject, path: String) {
        do { selected = try store.openProjectFile(project, path: path) }
        catch { store.error = "无法打开 \(path)。请确认文件已完整导入或拉取。\n" + error.localizedDescription }
    }
}

struct AddScriptToProjectView: View {
    @EnvironmentObject private var store: LearningStore
    @Environment(\.dismiss) private var dismiss
    var documentID: UUID? = nil
    var projectID: UUID? = nil
    var folder = ""
    @State private var chosenDocument: UUID?
    @State private var chosenProject: UUID?
    @State private var path = ""
    @State private var error = ""
    var body: some View {
        Form {
            Section("选择脚本与项目") {
                Picker("脚本", selection: $chosenDocument) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(store.documents.filter { $0.projectID == nil }) { Text($0.name).tag(Optional($0.id)) }
                }.disabled(documentID != nil)
                Picker("目标项目", selection: $chosenProject) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
                }.disabled(projectID != nil)
                if store.projects.isEmpty {
                    Button("新建项目") { do { chosenProject = try store.createProject(name: "我的项目").id } catch { self.error = error.localizedDescription } }
                }
                TextField("项目内路径，例如 tools/demo.py", text: $path).autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("复制到项目，保留“我的脚本”中的原件。同名文件不会被覆盖；之后在项目内编辑并通过 Git 提交推送。").font(.caption).foregroundColor(.secondary)
            }
            Button("添加到项目") { add() }.disabled(chosenDocument == nil || chosenProject == nil || path.isEmpty)
            if !error.isEmpty { Text(error).font(.caption).foregroundColor(.red) }
        }
        .navigationTitle("添加脚本到项目")
        .toolbar { Button("取消") { dismiss() } }
        .onAppear {
            chosenProject = projectID ?? store.projects.first?.id
            chosenDocument = documentID ?? store.documents.first(where: { $0.projectID == nil })?.id
            updatePath()
        }
        .onChange(of: chosenDocument) { _ in updatePath() }
    }
    private func updatePath() { if let id = chosenDocument, let document = store.document(id) { path = folder.isEmpty ? document.name : folder + "/" + document.name } }
    private func add() {
        guard let id = chosenDocument, let project = store.projects.first(where: { $0.id == chosenProject }) else { return }
        do { try store.addScript(id, to: project, path: path); dismiss() } catch { self.error = error.localizedDescription }
    }
}
