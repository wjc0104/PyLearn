import SwiftUI

struct LearningView: View {
    @EnvironmentObject private var store: LearningStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("每天写一点，\n让 Python 跑起来。")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("从第一行输出，到多文件项目、测试和现代 Python。")
                            .foregroundColor(.secondary)
                        ProgressView(value: Double(store.lessons.flatMap(\.exercises).filter { store.completed.contains($0.id) }.count), total: Double(max(1, store.lessons.flatMap(\.exercises).count))).tint(.teal)
                        Text("\(store.lessons.count) 章 · 章节练习已完成 \(store.lessons.flatMap(\.exercises).filter { store.completed.contains($0.id) }.count) / \(store.lessons.flatMap(\.exercises).count) 道")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(.vertical, 12)
                }
                ForEach(["基础入门", "进阶语法", "项目实践"], id: \.self) { stage in
                Section(stage) {
                    ForEach(store.lessons.filter { ($0.stage ?? "基础入门") == stage }) { lesson in
                        NavigationLink { LessonDetail(lesson: lesson) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: lesson.symbol).font(.title3).foregroundColor(.teal).frame(width: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(lesson.title).font(.headline)
                                    Text(lesson.summary).font(.caption).foregroundColor(.secondary)
                                }
                            }.padding(.vertical, 7)
                        }
                    }
                }
                }
            }.navigationTitle("Python 学习")
        }
    }
}

private struct LessonDetail: View {
    @EnvironmentObject private var store: LearningStore
    let lesson: Lesson
    @State private var script: ScriptDocument?
    var body: some View {
        List {
            Section("理解一下") { Text(lesson.body).lineSpacing(6).padding(.vertical, 8) }
            Section("试着运行") {
                Text(lesson.example).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
                Button {
                    do { script = try store.create(name: lesson.title + ".py", source: lesson.example) }
                    catch { store.error = error.localizedDescription }
                } label: { Label("在编辑器中打开", systemImage: "play.circle.fill") }
            }
            Section("动手练习") {
                ForEach(lesson.exercises) { exercise in
                    NavigationLink { ExerciseDetail(exercise: exercise) } label: { Text(exercise.title) }
                }
            }
            if let error = store.error { Text(error).foregroundColor(.red).font(.caption) }
        }
        .navigationTitle(lesson.title).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $script) { document in NavigationStack { ScriptEditor(documentID: document.id) } }
    }
}

struct ExerciseListView: View {
    var body: some View { NavigationStack { BankSearchView() } }
}

struct LegacyExercisesView: View {
    @EnvironmentObject private var store: LearningStore
    var body: some View {
            List {
                ForEach(store.lessons) { lesson in
                    Section(lesson.title) {
                        ForEach(lesson.exercises) { exercise in
                            NavigationLink { ExerciseDetail(exercise: exercise) } label: {
                                Label(exercise.title, systemImage: store.completed.contains(exercise.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }
            }.navigationTitle("章节练习")
    }
}

private struct ExerciseDetail: View {
    @EnvironmentObject private var store: LearningStore
    let exercise: Exercise
    @State private var script: ScriptDocument?
    var body: some View {
        List {
            Section("任务") { Text(exercise.prompt).lineSpacing(5) }
            Section("预期输出") { Text(exercise.expected).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
            Section {
                Button {
                    do { script = try store.openExercise(exercise) }
                    catch { store.error = error.localizedDescription }
                } label: { Label("开始练习", systemImage: "pencil.and.outline") }
                DisclosureGroup("需要一点提示？") { Text(exercise.hint) }
                DisclosureGroup("查看参考答案") { Text(exercise.solution).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            }
            if store.completed.contains(exercise.id) { Label("这道练习已经完成", systemImage: "checkmark.seal.fill").foregroundColor(.teal) }
            if let error = store.error { Text(error).font(.caption).foregroundColor(.red) }
        }.navigationTitle(exercise.title)
            .sheet(item: $script) { document in NavigationStack { ScriptEditor(documentID: document.id, exercise: exercise) } }
    }
}
