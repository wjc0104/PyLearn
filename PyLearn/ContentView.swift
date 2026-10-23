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
    @EnvironmentObject private var store: LearningStore
    @State private var importPresented = false
    @State private var selected: ScriptDocument?
    @State private var deleting: ScriptDocument?

    var body: some View {
        TabView {
            LearningView().tabItem { Label("学习", systemImage: "book.closed") }
            ExerciseListView().tabItem { Label("练习", systemImage: "checkmark.circle") }
            NavigationStack {
                List {
                    Section {
                        Label("脚本在手机本地运行", systemImage: "iphone")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    Section("我的脚本") {
                        if store.documents.isEmpty { Text("创建一个脚本，或从文件 App 导入 .py 文件。") }
                        ForEach(store.documents) { document in
                            Button { selected = document } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text").foregroundColor(.teal)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(document.name).foregroundColor(.primary)
                                        Text("\(document.source.components(separatedBy: "\n").count) 行 · 保存在本机")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                }.padding(.vertical, 5)
                            }
                            .swipeActions {
                                Button(role: .destructive) { deleting = document } label: { Label("删除", systemImage: "trash") }
                            }
                        }
                    }
                    Section {
                        Button { importPresented = true } label: { Label("导入 .py 文件", systemImage: "square.and.arrow.down") }
                        Text("支持 UTF-8 编码，最大 512 KiB。导入时保存副本，原文件保持不变。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("关于") {
                        Text("PyLearn · Python 学习").font(.headline)
                        Text("Runestone 编辑器 · CPython 3.13\n离线学习，无广告。首版提供标准库和基础补全。")
                            .font(.caption).foregroundColor(.secondary)
                        Text("请只运行你信任的脚本。脚本运行在 App 自身进程中。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .navigationTitle("我的代码")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            do { selected = try store.create() } catch { store.error = error.localizedDescription }
                        } label: { Image(systemName: "plus") }.accessibilityLabel("新建脚本")
                    }
                }
                .fileImporter(isPresented: $importPresented, allowedContentTypes: [.pythonSource], allowsMultipleSelection: false) { result in
                    do { if let url = try result.get().first { selected = try store.importFile(url) } }
                    catch { store.error = error.localizedDescription }
                }
                .sheet(item: $selected) { document in
                    NavigationStack { ScriptEditor(documentID: document.id) }
                }
                .confirmationDialog("删除 \(deleting?.name ?? "脚本")？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("删除脚本", role: .destructive) {
                        if let id = deleting?.id {
                            do { try store.delete(id) } catch { store.error = error.localizedDescription }
                        }
                        deleting = nil
                    }
                    Button("取消", role: .cancel) { deleting = nil }
                }
                .alert("文件提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("知道了") { store.error = nil }
                } message: { Text(store.error ?? "") }
            }.tabItem { Label("代码", systemImage: "chevron.left.forwardslash.chevron.right") }
        }
    }
}
