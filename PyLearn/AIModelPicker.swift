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
            }
            if profile != nil {
                Section("模型列表") {
                    Button("刷新可选模型") { fetchModels() }.disabled(loading || testing != nil)
                    if loading { ProgressView("正在读取模型…") }
                    ForEach(candidates, id: \.self) { model in modelRow(model) }
                }
                Section("手动填写模型 ID") {
                    TextField("服务未提供列表时填写", text: $manualModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("测试并使用此模型") { verify(manualModel) }.disabled(manualModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testing != nil)
                }
            }
            Section {
                Text("切换前会用一次小请求测试。失败不会替换当前模型，可查看原因后重试；测试可能产生少量费用。可用状态只代表本次请求成功。").font(.caption).foregroundColor(.secondary)
                if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
            }
        }
        .navigationTitle("选择 AI 模型")
        .toolbar { Button("完成") { dismiss() }.disabled(testing != nil) }
        .interactiveDismissDisabled(testing != nil)
        .onAppear { if profileID == nil { profileID = profiles.active?.id } }
        .onChange(of: profileID) { _ in models = []; failures = [:]; message = ""; fetchModels() }
        .onDisappear { modelTask?.cancel() }
    }
    private func modelRow(_ model: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model).font(.subheadline)
            if testing == model { ProgressView("正在测试…") }
            else if let failure = failures[model] { Text("本次测试失败：" + failure).font(.caption).foregroundColor(.red).textSelection(.enabled) }
            else { Text("未测试；点击验证后切换").font(.caption).foregroundColor(.secondary) }
            Button(failures[model] == nil ? "测试并切换" : "重新测试") { verify(model) }.disabled(testing != nil)
        }
    }
    private func fetchModels() {
        guard let profile else { return }
        modelTask?.cancel()
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
        testing = model; failures.removeValue(forKey: model)
        Task {
            do {
                try await profiles.useVerified(profile, model: model)
                message = "本次测试可用，已切换为 " + model
                testing = nil
                dismiss()
            } catch {
                failures[model] = error.localizedDescription
                message = "切换失败，继续使用原模型。"
                testing = nil
            }
        }
    }
}
