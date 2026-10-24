import SwiftUI

struct ScriptEditor: View {
    @EnvironmentObject private var store: LearningStore
    @EnvironmentObject private var session: PythonSession
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    var exercise: Exercise? = nil
    var bankExercise: BankExercise? = nil
    @StateObject private var editor = EditorController()
    @State private var text = ""
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var syntaxProblem: PythonProblem?
    @State private var completions: [String] = []
    @State private var signature = ""
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisID = UUID()
    @State private var pendingCompletion: (source: String, cursor: NSRange)?
    @State private var completionMessage = ""
    @State private var input = ""
    @State private var exporting = false
    @State private var expanded = true
    @State private var loaded = false
    @State private var grade = ""
    @State private var gradeReport = ""
    @State private var fileError: String?
    private var completing: Bool { pendingCompletion != nil }
    private var document: ScriptDocument? { store.document(documentID) }
    private var directory: String? { document?.projectID.map { store.projectRoot($0).path } }
    private var path: String? { if let id = document?.projectID, let path = document?.relativePath { return try? store.projectFile(id, path: path).path }; return nil }
    private var isPython: Bool { document?.name.lowercased().hasSuffix(".py") ?? true }
    private var problem: PythonProblem? {
        if session.documentID == documentID && session.executedSource == text { return session.problem ?? syntaxProblem }
        return syntaxProblem
    }
    var body: some View {
        VStack(spacing: 0) {
            if let prompt = bankExercise?.prompt ?? exercise?.prompt {
                DisclosureGroup("练习任务与提示") {
                    ScrollView { Text(prompt + "\n\n" + (bankExercise?.hint ?? exercise?.hint ?? "")).font(.subheadline).textSelection(.enabled) }.frame(maxHeight: 160)
                }.padding(10)
            }
            if !grade.isEmpty { Text(grade).font(.caption).foregroundColor(.teal).padding(5) }
            CodeEditor(text: $text, selection: $selection, controller: editor, editable: !session.busy, errorLine: isPython ? problem?.line : nil).frame(minHeight: 120)
            if !signature.isEmpty { Text(signature).font(.system(.caption2, design: .monospaced)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8) }
            if isPython {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        if completing { ProgressView(); Text("正在获取补全…").font(.caption) }
                        else if !completionMessage.isEmpty { Text(completionMessage).font(.caption).foregroundColor(.secondary) }
                        ForEach(completions, id: \.self) { item in Button(item) { accept(item) }.font(.system(.caption, design: .monospaced)).buttonStyle(.bordered) }
                    }.padding(.horizontal, 8)
                }.frame(height: 40).disabled(session.busy)
            }
            symbolBar
            if let problem, isPython { problemView(problem) }
            console
            if let error = store.error { Text(error).font(.caption2).foregroundColor(.red).padding(4) }
        }.navigationTitle(document?.name ?? "Python").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button("复制全部代码") { UIPasteboard.general.string = text }
                        Button("全选") { editor.selectAll() }
                        Button("粘贴") { if let value = UIPasteboard.general.string { editor.insert(value) } }.disabled(session.busy)
                        Button("导出文件") { exporting = true }
                        if bankExercise != nil { Button("运行测试") { checkExercise() }.disabled(session.busy) }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("编辑器选项")
                    if bankExercise != nil { Button("运行测试") { checkExercise() }.disabled(session.busy) }
                    Button { run() } label: { Image(systemName: session.running ? "stop.fill" : "play.fill") }
                        .accessibilityLabel(session.running ? "停止运行" : "运行脚本").disabled(!isPython || session.working)
                }
            }
            .fileExporter(isPresented: $exporting, document: PythonFile(source: text), contentType: isPython ? .pythonSource : .plainText, defaultFilename: document?.name ?? "script.py") { result in if case .failure(let error) = result { fileError = error.localizedDescription } }
            .alert("文件提示", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) { Button("知道了") { fileError = nil } } message: { Text(fileError ?? "") }
            .onAppear {
                text = document?.source ?? ""; loaded = true
                editor.acceptCompletion = { acceptOrIndent() }
                analyze()
            }
            .onChange(of: text) { _ in guard loaded else { return }; store.update(documentID, source: text); grade = ""; gradeReport = ""; syntaxProblem = nil; completions = []; analyze() }
            .onChange(of: selection) { _ in analyze() }
            .onChange(of: session.prompt) { value in if value != nil { expanded = true } }
            .onChange(of: session.sequence) { _ in
                if let id = document?.projectID, session.documentID == documentID {
                    store.refreshProject(id)
                    text = document?.source ?? text
                }
                if let exercise, session.documentID == documentID, session.executedSource == text, session.resultStatus == "success" {
                    if session.output.trimmingCharacters(in: .whitespacesAndNewlines) == exercise.expected.trimmingCharacters(in: .whitespacesAndNewlines) {
                        store.markComplete(exercise.id); grade = "完成了！输出与预期一致。"
                    } else { grade = "输出还不一致，请检查代码。" }
                }
                analyze()
            }
            .onDisappear { analysisTask?.cancel(); analysisID = UUID(); pendingCompletion = nil; editor.acceptCompletion = nil; store.flush(); if session.documentID == documentID && session.running { session.stop() } }
    }
    private func problemView(_ problem: PythonProblem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(problem.line.map { "第 \($0) 行 · " } ?? "")\(problem.kind)").font(.caption.bold())
                Spacer()
                Button("定位") { if let line = problem.line, let range = EditorText.lineRange(in: text, line: line) { selection = range } }
                Button("复制错误") { UIPasteboard.general.string = problem.hint + "\n" + (problem.traceback ?? problem.message) }.accessibilityIdentifier("copyError")
            }
            Text(problem.hint).font(.caption).textSelection(.enabled)
            DisclosureGroup("英文原文与详细信息") {
                ScrollView { Text(problem.traceback ?? problem.message).font(.system(.caption2, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100)
            }.font(.caption)
        }.padding(10).foregroundColor(.red).background(Color.red.opacity(0.07))
    }
    private var symbolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel("撤销")
                Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }.accessibilityLabel("重做")
                Button("补全 ⇥") { complete() }.disabled(completing).accessibilityHint("获取并接受当前名称的第一个补全候选")
                ForEach(["⇥","(",")","[","]","{","}",":",",",".","\"","'","=","+","-","*","/","%","**","//","==","!=","<",">","<=",">=","_","#","\\","@","&","|","~",";"], id: \.self) { symbol in
                    Button(symbol) { editor.insert(symbol == "⇥" ? "    " : symbol) }.font(.system(.body, design: .monospaced)).frame(minWidth: 30, minHeight: 36)
                }
                Menu("模板") {
                    ForEach(CodeSnippet.categories, id: \.self) { category in
                        Menu(category) {
                            ForEach(CodeSnippet.all.filter { $0.category == category }) { snippet in
                                Button(snippet.title) { editor.insert(snippet.source) }
                            }
                        }
                    }
                }
                Button { editor.dismissKeyboard() } label: { Image(systemName: "keyboard.chevron.compact.down") }.accessibilityLabel("收起键盘")
            }.buttonStyle(.borderless).padding(.horizontal, 8)
        }.frame(height: 42).background(Color(uiColor: .secondarySystemBackground)).disabled(session.busy)
    }
    private var console: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("控制台", systemImage: "terminal").font(.caption.bold())
                Spacer()
                Text(session.working ? "处理中" : session.status).font(.caption).foregroundColor(.secondary)
                Button { UIPasteboard.general.string = gradeReport.isEmpty ? session.output : gradeReport } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("复制输出")
                Button { session.clearOutput(); gradeReport = "" } label: { Image(systemName: "trash") }.disabled(session.running).accessibilityLabel("清空输出")
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.up") }.accessibilityLabel(expanded ? "收起控制台" : "展开控制台")
            }
            if expanded {
                ScrollViewReader { reader in
                    ScrollView {
                        Text(gradeReport.isEmpty ? (session.output.isEmpty ? (session.documentID == documentID && session.resultStatus == "success" ? "运行完成，没有 print 输出。定义函数后需要调用，例如 print(函数名(参数))。" : "运行结果会显示在这里") : session.output) : gradeReport)
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("end")
                    }.frame(maxHeight: 130).onChange(of: session.output) { _ in reader.scrollTo("end", anchor: .bottom) }
                }
                if let prompt = session.prompt {
                    Text(prompt.isEmpty ? "请输入内容" : prompt).font(.caption)
                    HStack {
                        TextField("输入后点击发送", text: $input).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never).onSubmit { sendInput() }
                        Button("发送") { sendInput() }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }.padding(10).background(Color(uiColor: .secondarySystemBackground))
    }
    private func accept(_ value: String) {
        let cursor = editor.view?.selectedRange ?? selection
        editor.replace(EditorText.prefixRange(in: text, selection: cursor), with: value)
    }
    private func complete() {
        guard !session.busy, !completing else { return }
        analyze(completeFirst: true)
    }
    private func acceptOrIndent() {
        let range = EditorText.prefixRange(in: text, selection: editor.view?.selectedRange ?? selection)
        let source = text as NSString
        if range.length == 0 && (range.location == 0 || source.substring(with: NSRange(location: range.location - 1, length: 1)) != ".") {
            editor.insert("    ")
            return
        }
        complete()
    }
    private func sendInput() { let value = input; input = ""; session.submitInput(value) }
    private func run() {
        if session.running { session.stop(); return }
        do { try store.flushOrThrow() } catch { fileError = "保存失败，已取消运行。请先导出代码。"; return }
        analysisTask?.cancel(); analysisID = UUID(); pendingCompletion = nil
        editor.dismissKeyboard(); expanded = true; grade = ""; gradeReport = ""
        session.run(source: text, documentID: documentID, directory: directory, path: path)
    }
    private func checkExercise() {
        guard let bankExercise else { return }
        guard !bankExercise.id.hasPrefix("ai.") || bankExercise.verified == true else { grade = "先返回题目页验证参考答案，再进行判题。"; return }
        expanded = true; editor.dismissKeyboard()
        let snapshot = text
        do { try store.flushOrThrow() } catch { fileError = "保存失败，已取消运行。请先导出代码。"; return }
        analysisTask?.cancel(); analysisID = UUID(); pendingCompletion = nil
        session.perform(["action":"grade","source":snapshot,"module":bankExercise.module,"tests":bankExercise.tests]) { response in
            gradeReport = response["report"] as? String ?? "无法判题"
            let success = response["status"] as? String == "success"
            grade = success ? "通过当前测试用例！" : "还有用例没有通过，展开控制台查看。"
            if success && text == snapshot { store.markComplete(bankExercise.id) }
        }
    }
    private func analyze(completeFirst: Bool = false) {
        let snapshot = text, cursor = editor.view?.selectedRange ?? selection
        // A delayed selection notification must not cancel an unchanged manual request.
        if !completeFirst, let pendingCompletion, pendingCompletion.source == snapshot, pendingCompletion.cursor == cursor { return }
        analysisTask?.cancel()
        let requestID = UUID()
        analysisID = requestID
        completions = []; completionMessage = ""; pendingCompletion = nil
        guard !session.busy, isPython else { return }
        if completeFirst { pendingCompletion = (snapshot, cursor) }
        analysisTask = Task {
            if !completeFirst {
                do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let position = await Task.detached(priority: .utility) {
                let source = snapshot as NSString
                let prefix = source.substring(with: EditorText.prefixRange(in: snapshot, selection: cursor))
                let before = source.substring(to: min(max(0, cursor.location), source.length))
                let lines = before.components(separatedBy: "\n")
                return (prefix: prefix, line: lines.count, column: lines.last?.unicodeScalars.count ?? 0)
            }.value
            guard !Task.isCancelled, analysisID == requestID, text == snapshot, (editor.view?.selectedRange ?? selection) == cursor else { return }
            session.analyze(source: snapshot, prefix: position.prefix, line: position.line, column: position.column, directory: directory, path: path) { error, names, help in
                guard analysisID == requestID, text == snapshot, (editor.view?.selectedRange ?? selection) == cursor, !session.busy else { return }
                syntaxProblem = error; completions = names; signature = help
                if completeFirst {
                    pendingCompletion = nil
                    if let first = names.first { accept(first) }
                    else { completionMessage = "没有可用的补全候选" }
                }
            }
        }
    }
}
