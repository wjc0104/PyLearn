import SwiftUI

struct AIModelPicker: View {
    @ObservedObject private var profiles = AIProfiles.shared
    @Environment(\.dismiss) private var dismiss
    @State private var profileID: UUID?
    @State private var models: [String] = []
    @State private var manualModel = ""
    @State private var loading = false
    @State private var testing: String?
    @State private var failures: [String: String] = [:]
    @State private var message = ""
    @State private var modelTask: Task<Void, Never>?
    @State private var testTask: Task<Void, Never>?
    @State private var verification: AIModelVerification?
    @State private var passed: Set<String> = []
    private var profile: AIProfile? { profiles.items.first { $0.id == profileID } }
    private var candidates: [String] {
        Array(Set(models + [profile?.model ?? ""])).filter { !$0.isEmpty }.sorted()
    }
    var body: some View {
        List {
            Section("服务配置") {
                Picker("服务商", selection: $profileID) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(profiles.items) { Text($0.name).tag(Optional($0.id)) }
                }.disabled(testing != nil)
                NavigationLink("添加或编辑服务配置") { AIProfilesView() }.disabled(testing != nil || loading)
                if let active = profiles.active { Text("正在使用：" + active.name + " · " + active.model).font(.caption) }
                if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
                if let testing { ProgressView("正在测试：" + testing); Button("取消测试", role: .cancel) { cancelTest() } }
            }
            if profile != nil {
                Section("模型列表") {
                    Button("刷新可选模型") { fetchModels() }.disabled(loading || testing != nil)
                    if loading { ProgressView("正在读取模型…") }
                    ForEach(candidates, id: \.self) { model in modelRow(model) }
                }
                Section("手动填写模型 ID") {
                    TextField("服务未提供列表时填写", text: $manualModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("测试此模型") { verify(manualModel) }.disabled(manualModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testing != nil)
                }
            }
            Section {
                Text("先发起小请求测试，看到测试通过后再点“使用此模型”。失败或取消不切换。测试可能产生少量费用；通过仅代表本次文字请求成功，出题结果仍需验证。").font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("选择 AI 模型")
        .toolbar { Button("完成") { dismiss() }.disabled(testing != nil) }
        .interactiveDismissDisabled(testing != nil)
        .onAppear { passed = []; verification = nil; if profileID == nil { profileID = profiles.active?.id } }
        .onChange(of: profileID) { _ in models = []; failures = [:]; passed = []; verification = nil; message = ""; fetchModels() }
        .onDisappear { modelTask?.cancel(); testTask?.cancel() }
        .alert("模型测试通过", isPresented: Binding(get: { verification != nil }, set: { if !$0 { verification = nil } }), presenting: verification) { verified in
            Button("使用此模型") {
                do { try profiles.use(verified); message = "已切换为 " + verified.candidate.model }
                catch { message = "未能切换，继续使用原模型。\n" + error.localizedDescription }
            }
            Button("暂不切换", role: .cancel) { message = "测试通过，尚未切换；继续使用原模型。" }
        } message: { verified in
            Text(verified.candidate.model + " 本次文字请求成功。\n返回：" + String(verified.response.prefix(160)) + "\n点击“使用此模型”才会切换。")
        }
    }
    private func modelRow(_ model: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model).font(.subheadline)
            if testing == model { ProgressView("正在测试…") }
            else if let failure = failures[model] { Text("本次测试失败：" + failure).font(.caption).foregroundColor(.red).textSelection(.enabled) }
            else if passed.contains(model) { Label("本次文字请求测试通过", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green) }
            else { Text("未测试；点击验证后切换").font(.caption).foregroundColor(.secondary) }
            Button(failures[model] == nil ? "测试模型" : "重新测试") { verify(model) }.disabled(testing != nil)
        }
    }
    private func fetchModels() {
        modelTask?.cancel()
        loading = false
        guard let profile else { return }
        loading = true
        modelTask = Task {
            do {
                let fetched = try await AIClient.models(profile, key: SecretStore.read("ai." + profile.id.uuidString) ?? "")
                guard !Task.isCancelled, profile.id == profileID else { return }
                models = fetched
                if models.isEmpty { message = "服务未提供模型列表，可手动填写 ID 后测试。" }
            } catch {
                guard !Task.isCancelled, profile.id == profileID else { return }
                message = "模型列表读取失败，可手动填写 ID 后测试。\n" + error.localizedDescription
            }
            loading = false
        }
    }
    private func verify(_ model: String) {
        guard let profile else { return }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        modelTask?.cancel(); loading = false
        testing = model; failures.removeValue(forKey: model); passed.remove(model); verification = nil
        message = "正在发送测试请求，当前模型仍在使用。"
        testTask = Task {
            do {
                let verified = try await profiles.testModel(profile, model: model)
                guard !Task.isCancelled else { return }
                passed.insert(model); verification = verified
                message = "测试通过，等待你确认是否使用。"
                testing = nil
            } catch {
                guard !Task.isCancelled else { return }
                failures[model] = error.localizedDescription
                message = "测试失败，未切换；继续使用原模型。\n" + error.localizedDescription
                testing = nil
            }
        }
    }
    private func cancelTest() {
        testTask?.cancel(); testing = nil; verification = nil
        message = "测试已取消，继续使用原模型。"
    }
}
