import SwiftUI

struct ScriptEditor: View {
    @EnvironmentObject private var store: LearningStore
    @EnvironmentObject private var session: PythonSession
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    var exercise: Exercise? = nil
    @StateObject private var editor = EditorController()
    @State private var text = ""
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var syntaxProblem: PythonProblem?
    @State private var completions: [String] = []
    @State private var analysisTask: Task<Void, Never>?
    @State private var input = ""
    @State private var exportPresented = false
    @State private var consolePresented = true
    @State private var loaded = false
    @State private var grade: String?
    @State private var fileError: String?
    private var currentProblem: PythonProblem? {
        if session.documentID == documentID && session.executedSource == text { return session.problem ?? syntaxProblem }
        return syntaxProblem
    }

    var body: some View {
        VStack(spacing: 0) {
            if let exercise {
                VStack(alignment: .leading, spacing: 5) {
                    Text(exercise.prompt).font(.subheadline)
                    if let grade { Text(grade).font(.caption).foregroundColor(.teal) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.teal.opacity(0.08))
            }
            CodeEditor(text: $text, selection: $selection, controller: editor, editable: !session.running, errorLine: currentProblem?.line)
                .frame(minHeight: 160)
            if !completions.isEmpty && !session.running {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(completions, id: \.self) { completion in
                            Button(completion) {
                                editor.replace(EditorText.prefixRange(in: text, selection: selection), with: completion)
                            }.font(.system(.caption, design: .monospaced)).buttonStyle(.bordered)
                        }
                    }.padding(.horizontal, 10)
                }.frame(height: 42)
            }
            symbolBar
            if let problem = currentProblem {
                Button {
                    if let line = problem.line, let range = EditorText.lineRange(in: text, line: line) { selection = range }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(problem.line.map { "第 \($0) 行 · " } ?? "")\(problem.kind)").font(.caption.bold())
                        Text(problem.hint).font(.caption)
                        Text(problem.message).font(.system(.caption2, design: .monospaced)).lineLimit(3)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.foregroundColor(.red).background(Color.red.opacity(0.07))
            }
            if consolePresented { console }
            if let error = store.error { Text(error).font(.caption2).foregroundColor(.red).padding(5) }
        }
        .navigationTitle(store.document(documentID)?.name ?? "Python")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button { exportPresented = true } label: { Label("导出 .py", systemImage: "square.and.arrow.up") }
                    Button { consolePresented.toggle() } label: { Label(consolePresented ? "隐藏控制台" : "显示控制台", systemImage: "terminal") }
                    if let exercise { Text("提示：" + exercise.hint) }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("编辑器选项")
                Button {
                    if session.running { session.stop() }
                    else { editor.dismissKeyboard(); consolePresented = true; grade = nil; session.run(source: text, documentID: documentID) }
                } label: { Image(systemName: session.running ? "stop.fill" : "play.fill") }
                    .accessibilityLabel(session.running ? "停止运行" : "运行脚本")
            }
        }
        .fileExporter(isPresented: $exportPresented, document: PythonFile(source: text), contentType: .pythonSource,
                      defaultFilename: store.document(documentID)?.name ?? "script.py") { result in
            if case .failure(let error) = result { fileError = error.localizedDescription }
        }
        .alert("导出失败", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("知道了") { fileError = nil }
        } message: { Text(fileError ?? "") }
        .onAppear { text = store.document(documentID)?.source ?? ""; loaded = true; analyze() }
        .onChange(of: text) { source in
            guard loaded else { return }
            store.update(documentID, source: source)
            grade = nil
            analyze()
        }
        .onChange(of: selection) { _ in analyze() }
        .onChange(of: session.sequence) { _ in
            guard let exercise, session.documentID == documentID, session.executedSource == text else { return }
            if session.resultStatus == "success" {
                if session.output.trimmingCharacters(in: .whitespacesAndNewlines) == exercise.expected.trimmingCharacters(in: .whitespacesAndNewlines) {
                    store.markComplete(exercise.id)
                    grade = "完成了！输出与预期一致。"
                } else { grade = "已经运行，输出还不一致，再检查一下。" }
            }
            analyze()
        }
        .onDisappear {
            analysisTask?.cancel()
            store.flush()
            if session.documentID == documentID && session.running { session.stop() }
        }
    }

    private var symbolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel("撤销")
                Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }.accessibilityLabel("重做")
                ForEach(["⇥", "(", ")", "[", "]", ":", "\"", "'", "=", "_", "#"], id: \.self) { symbol in
                    Button(symbol) { editor.insert(symbol == "⇥" ? "    " : symbol) }
                        .font(.system(.body, design: .monospaced)).frame(minWidth: 30, minHeight: 36)
                }
                Button { editor.dismissKeyboard() } label: { Image(systemName: "keyboard.chevron.compact.down") }.accessibilityLabel("收起键盘")
            }.buttonStyle(.borderless).padding(.horizontal, 10)
        }.frame(height: 40).background(Color(uiColor: .secondarySystemBackground)).disabled(session.running)
    }

    private var console: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("控制台", systemImage: "terminal").font(.caption.bold())
                Spacer()
                Text(session.status).font(.caption).foregroundColor(.secondary)
                Button { UIPasteboard.general.string = session.output } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("复制输出")
            }
            ScrollViewReader { reader in
                ScrollView {
                    Text(session.output.isEmpty ? "运行结果会显示在这里" : session.output)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .foregroundColor(session.output.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("end")
                }.frame(maxHeight: 130)
                    .onChange(of: session.output) { _ in reader.scrollTo("end", anchor: .bottom) }
            }
            if let prompt = session.prompt {
                Text(prompt.isEmpty ? "请输入内容" : prompt).font(.caption)
                HStack {
                    TextField("输入后点击发送", text: $input).textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .onSubmit { sendInput() }
                    Button("发送") { sendInput() }.buttonStyle(.borderedProminent)
                }
            }
        }.padding(12).background(Color(uiColor: .secondarySystemBackground))
    }

    private func sendInput() { let value = input; input = ""; session.submitInput(value) }

    private func analyze() {
        analysisTask?.cancel()
        guard !session.running else { completions = []; return }
        let snapshot = text
        let cursor = selection
        let prefix = (snapshot as NSString).substring(with: EditorText.prefixRange(in: snapshot, selection: cursor))
        analysisTask = Task {
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            session.analyze(source: snapshot, prefix: prefix) { error, names in
                guard text == snapshot && selection == cursor && !session.running else { return }
                syntaxProblem = error
                completions = names
            }
        }
    }
}
