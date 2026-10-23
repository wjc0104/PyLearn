import SwiftUI
import Combine

struct BankExercise: Codable, Identifiable {
    var id: String
    var title: String
    var prompt: String
    var original: String?
    var starter: String
    var solution: String
    var module: String
    var tests: String
    var hint: String
    var tags: [String]
    var difficulty: Int
    var source: String
    var sourceURL: String
    var revision: String
    var authors: [String]
    var verified: Bool? = nil
    func validate() throws {
        guard !id.isEmpty, id.count <= 200, !title.isEmpty, !prompt.isEmpty,
              module.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil,
              starter.utf8.count <= 524288, solution.utf8.count <= 524288, !tests.isEmpty, tests.utf8.count <= 200000,
              (1...10).contains(difficulty) else { throw AIClient.failure("题目格式不完整或超出限制。") }
    }
}
struct BankCatalog: Codable { let schema: Int; let revision: String; let exercises: [BankExercise] }
@MainActor final class ExerciseBank: ObservableObject {
    static let shared = ExerciseBank()
    @Published private(set) var exercises: [BankExercise] = []
    @Published private(set) var custom: [BankExercise] = []
    @Published var message = ""
    @Published var updating = false
    private let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PyLearn-bank.json")
    private let saved = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PyLearn/ai-exercises.json")
    init() {
        let bundled = Bundle.main.url(forResource: "bank", withExtension: "json")
        if let data = try? Data(contentsOf: cache), let catalog = try? Self.decode(data) { exercises = catalog.exercises }
        else if let bundled, let data = try? Data(contentsOf: bundled), let catalog = try? Self.decode(data) { exercises = catalog.exercises }
        if let data = try? Data(contentsOf: saved), let value = try? JSONDecoder().decode([BankExercise].self, from: data) { custom = value }
    }
    static func decode(_ data: Data) throws -> BankCatalog {
        guard data.count <= 12 * 1024 * 1024 else { throw AIClient.failure("题库文件过大。") }
        let catalog = try JSONDecoder().decode(BankCatalog.self, from: data)
        guard catalog.schema == 1, catalog.exercises.count <= 1000, Set(catalog.exercises.map(\.id)).count == catalog.exercises.count else { throw AIClient.failure("题库版本或题目编号无效。") }
        for exercise in catalog.exercises { try exercise.validate() }
        return catalog
    }
    func refresh() async {
        guard !updating else { return }
        updating = true; defer { updating = false }
        do {
            var request = URLRequest(url: URL(string: "https://raw.githubusercontent.com/wjc0104/PyLearn/main/catalog/bank.json")!)
            request.timeoutInterval = 30; request.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIClient.failure("题库暂时无法更新。") }
            var data = Data()
            for try await byte in bytes { data.append(byte); guard data.count <= 12 * 1024 * 1024 else { throw AIClient.failure("题库文件过大。") } }
            let catalog = try Self.decode(data)
            try data.write(to: cache, options: .atomic)
            exercises = catalog.exercises
            message = "已同步 \(exercises.count) 道题，可离线练习。"
        } catch { message = "更新失败，继续使用本地题库。\n" + error.localizedDescription }
    }
    func add(_ exercise: BankExercise) throws {
        try exercise.validate()
        var next = custom
        next.removeAll { $0.id == exercise.id }; next.insert(exercise, at: 0)
        try FileManager.default.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: saved, options: .atomic)
        custom = next
    }
    func generate(topic: String, profile: AIProfile) async throws -> BankExercise {
        let prompt = """
        为 Python 3.15 初学者生成一道中文练习，主题：\(topic.prefix(500))。
        只返回一个JSON对象，不要Markdown，字段：title,prompt,hint,starter,solution,module,tests,tags,difficulty。
        前七个字段为字符串，tags为字符串数组，difficulty为1到10的整数。
        module固定为answer。starter提供函数接口和pass，solution提供可运行参考答案。
        tests使用标准库unittest，from answer import需要测试的函数，至少3个不同输入和边界测试。
        不得使用input、网络、系统命令、第三方包、无限循环或外部文件。只做确定性的函数题。
        题目必须明确输入输出和边界规则，不能把答案写进starter，不能只检查打印输出。
        """
        let value = try await AIClient.text(profile, key: SecretStore.read("ai." + profile.id.uuidString) ?? "", prompt: prompt)
        guard let first = value.firstIndex(of: "{"), let last = value.lastIndex(of: "}"), first <= last,
              let data = String(value[first...last]).data(using: .utf8),
              var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIClient.failure("AI 返回格式无效，请重新生成。") }
        json["id"] = "ai." + UUID().uuidString; json["source"] = "AI 生成 · 尚未验证"
        json["sourceURL"] = ""; json["revision"] = profile.model; json["authors"] = [profile.name]
        let exercise = try JSONDecoder().decode(BankExercise.self, from: JSONSerialization.data(withJSONObject: json))
        try add(exercise)
        return exercise
    }
}
struct BankSearchView: View {
    @ObservedObject private var bank = ExerciseBank.shared
    @ObservedObject private var profiles = AIProfiles.shared
    @EnvironmentObject private var store: LearningStore
    @State private var query = ""
    @State private var level = 0
    @State private var generating = false
    @State private var generated: BankExercise?
    @State private var error = ""
    private var results: [BankExercise] {
        let all: [BankExercise] = bank.custom + bank.exercises
        let words: [String] = query.lowercased().split(separator: " ").map(String.init)
        return all.filter { item in
            var fields: [String] = [item.title, item.prompt, item.module]
            fields.append(contentsOf: item.tags)
            let content: String = fields.joined(separator: " ").lowercased()
            let matchesQuery = words.allSatisfy { word in content.contains(word) }
            let matchesLevel: Bool
            switch level {
            case 1: matchesLevel = item.difficulty <= 2
            case 2: matchesLevel = item.difficulty > 2
            default: matchesLevel = true
            }
            return matchesQuery && matchesLevel
        }
    }
    var body: some View {
        List {
            introduction
            generationSection
            questions
        }
        .searchable(text: $query, prompt: "搜索列表、循环、文件、函数…")
        .navigationTitle("编程练习")
        .toolbar {
            Button { Task { await bank.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(bank.updating).accessibilityLabel("更新在线题库")
        }
        .refreshable { await bank.refresh() }
        .sheet(item: $generated) { item in NavigationStack { BankExerciseDetail(exercise: item) } }
        .alert("AI 提示", isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })) {
            Button("知道了") { error = "" }
        } message: { Text(error) }
    }
    private var introduction: some View {
        Section {
            Text("\(bank.exercises.count) 道在线题库练习 · 下载后离线使用").font(.subheadline)
            Picker("难度", selection: $level) {
                Text("全部").tag(0)
                Text("入门").tag(1)
                Text("进阶").tag(2)
            }.pickerStyle(.segmented)
            NavigationLink("原有入门章节练习") { LegacyExercisesView() }
            if !bank.message.isEmpty { Text(bank.message).font(.caption).foregroundColor(.secondary) }
        }
    }
    @ViewBuilder private var generationSection: some View {
        if !query.isEmpty {
            Section("按关键词出题") {
                if let profile = profiles.active {
                    Button(generating ? "生成中…" : "用 \(profile.name) 生成“\(query)”练习") { generate(profile) }
                        .disabled(generating)
                    Text("此操作调用你配置的服务，可能产生费用；生成后需验证参考答案。").font(.caption).foregroundColor(.secondary)
                } else { Text("可在设置中添加 AI 服务，按任意关键词出题。").font(.caption) }
            }
        }
    }
    private var questions: some View {
        Section("题目 · \(results.count)") {
            ForEach(results) { item in
                NavigationLink { BankExerciseDetail(exercise: item) } label: { questionLabel(item) }
            }
            if results.isEmpty { Text("没有匹配题目。可以换个关键词，或用 AI 生成。").foregroundColor(.secondary) }
        }
    }
    private func questionLabel(_ item: BankExercise) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(item.title, systemImage: store.completed.contains(item.id) ? "checkmark.circle.fill" : "circle")
            Text(item.tags.joined(separator: " · ") + " · 难度 \(item.difficulty)").font(.caption).foregroundColor(.secondary)
        }
    }
    private func generate(_ profile: AIProfile) {
        generating = true
        Task {
            do { generated = try await bank.generate(topic: query, profile: profile) }
            catch { self.error = error.localizedDescription }
            generating = false
        }
    }
}
struct BankExerciseDetail: View {
    @EnvironmentObject private var store: LearningStore
    @EnvironmentObject private var session: PythonSession
    @ObservedObject private var profiles = AIProfiles.shared
    @State var exercise: BankExercise
    @State private var script: ScriptDocument?
    @State private var report = ""
    @State private var translation = ""
    @State private var translating = false
    var body: some View {
        List {
            Section("任务") { Text(exercise.prompt).lineSpacing(5).textSelection(.enabled) }
            Section("知识点") { Text(exercise.tags.joined(separator: " · ")); Text(exercise.source).font(.caption) }
            if let original = exercise.original {
                Section {
                    DisclosureGroup("完整题目原文") { Text(original).font(.caption).textSelection(.enabled) }
                    if let profile = profiles.active {
                        Button(translating ? "翻译中…" : "AI 翻译完整题目（使用 \(profile.name)）") {
                            translating = true
                            Task { do { translation = try await AIClient.text(profile, key: SecretStore.read("ai." + profile.id.uuidString) ?? "", prompt: "将下面的编程题完整翻译为简体中文，保留函数名和测试字符串，不增加未说明的规则：\n" + String(original.prefix(20000))) } catch { translation = error.localizedDescription }; translating = false }
                        }.disabled(translating)
                    }
                    if !translation.isEmpty { Text(translation).textSelection(.enabled) }
                }
            }
            Section {
                Button("开始练习") { do { script = try store.openBankExercise(exercise) } catch { report = error.localizedDescription } }
                    .disabled(exercise.id.hasPrefix("ai.") && exercise.verified != true)
                if exercise.id.hasPrefix("ai.") && exercise.verified != true { Text("先点击下方“验证参考答案”，通过后即可开始练习和判题。").font(.caption) }
                DisclosureGroup("提示") { Text(exercise.hint) }
                DisclosureGroup("参考答案") {
                    Text(exercise.solution).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("复制参考答案") { UIPasteboard.general.string = exercise.solution }
                }
                DisclosureGroup("测试用例") { Text(exercise.tests).font(.system(.caption2, design: .monospaced)).textSelection(.enabled) }
                Button("验证参考答案") {
                    session.perform(["action":"grade","source":exercise.solution,"module":exercise.module,"tests":exercise.tests]) { result in
                        let success = result["status"] as? String == "success"
                        report = (success ? "参考答案通过当前测试。\n" : "参考答案未通过，请勿据此判定你的代码错误。\n") + (result["report"] as? String ?? "")
                        if exercise.id.hasPrefix("ai.") {
                            exercise.verified = success
                            exercise.source = success ? "AI 生成 · 通过当前测试" : "AI 生成 · 验证失败"
                            do { try ExerciseBank.shared.add(exercise) } catch { report += "\n验证状态保存失败。"; exercise.verified = false }
                        }
                    }
                }.disabled(session.busy)
                Text("验证会在本机运行参考答案和测试代码。通过当前用例并不代表覆盖所有情况。").font(.caption).foregroundColor(.secondary)
            }
            if !report.isEmpty { Section("验证结果") { Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled); Button("复制验证结果") { UIPasteboard.general.string = report } } }
            if let url = URL(string: exercise.sourceURL), url.scheme == "https" { Section("来源与许可") { Link("查看原始开源题目（MIT）", destination: url); Text(exercise.authors.joined(separator: ", ")).font(.caption) } }
        }.navigationTitle(exercise.title).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $script) { document in NavigationStack { ScriptEditor(documentID: document.id, bankExercise: exercise) } }
    }
}
extension LearningStore {
    func openBankExercise(_ exercise: BankExercise) throws -> ScriptDocument {
        if let document = documents.first(where: { $0.exerciseID == exercise.id }) { return document }
        return try create(name: exercise.module + ".py", source: exercise.starter, exerciseID: exercise.id)
    }
}
