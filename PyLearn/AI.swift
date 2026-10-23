import SwiftUI
import Foundation

enum AIProtocol: String, Codable, CaseIterable {
    case chat = "OpenAI 兼容", responses = "OpenAI Responses", anthropic = "Claude 原生", gemini = "Gemini 原生"
}
struct AIProfile: Codable, Identifiable {
    var id = UUID()
    var name = "新配置"
    var baseURL = "https://api.deepseek.com/v1"
    var model = ""
    var format: AIProtocol = .chat
    var allowLocalHTTP = false
    static let presets: [(String, String, AIProtocol)] = [
        ("OpenAI", "https://api.openai.com/v1", .responses),
        ("DeepSeek", "https://api.deepseek.com/v1", .chat),
        ("通义千问", "https://dashscope.aliyuncs.com/compatible-mode/v1", .chat),
        ("智谱", "https://open.bigmodel.cn/api/paas/v4", .chat),
        ("硅基流动", "https://api.siliconflow.cn/v1", .chat),
        ("Moonshot / Kimi", "https://api.moonshot.cn/v1", .chat),
        ("Google Gemini", "https://generativelanguage.googleapis.com/v1beta", .gemini),
        ("Anthropic Claude", "https://api.anthropic.com/v1", .anthropic),
        ("Ollama 局域网", "http://192.168.1.100:11434/v1", .chat),
        ("自定义", "", .chat)
    ]
}
@MainActor final class AIProfiles: ObservableObject {
    static let shared = AIProfiles()
    @Published var items: [AIProfile] = []
    @Published var selected = ""
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "ai.profiles"), let value = try? JSONDecoder().decode([AIProfile].self, from: data) { items = value }
        selected = defaults.string(forKey: "ai.selected") ?? ""
    }
    var active: AIProfile? { items.first { $0.id.uuidString == selected } ?? items.first }
    private func save(_ profile: AIProfile, key: String) throws {
        try SecretStore.save(key, account: "ai." + profile.id.uuidString)
        if let index = items.firstIndex(where: { $0.id == profile.id }) { items[index] = profile } else { items.append(profile) }
        selected = profile.id.uuidString
        try persist()
    }
    func saveVerified(_ profile: AIProfile, key: String, transport: URLSession? = nil) async throws {
        _ = try await AIClient.text(profile, key: key, prompt: "请只回复 OK。", maxTokens: 256, transport: transport)
        try Task.checkCancellation()
        try save(profile, key: key)
    }
    func persist() throws {
        defaults.set(try JSONEncoder().encode(items), forKey: "ai.profiles")
        defaults.set(selected, forKey: "ai.selected")
    }
    func useVerified(_ profile: AIProfile, model: String, transport: URLSession? = nil) async throws {
        var candidate = profile
        candidate.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard items.contains(where: { $0.id == profile.id }) else { throw AIClient.failure("该配置已被删除。") }
        try await saveVerified(candidate, key: SecretStore.read("ai." + profile.id.uuidString) ?? "", transport: transport)
    }
    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        try? SecretStore.save("", account: "ai." + id.uuidString)
        if selected == id.uuidString { selected = items.first?.id.uuidString ?? "" }
        try? persist()
    }
}
private final class APIRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let original = task.originalRequest?.url
        completionHandler(request.url?.host == original?.host && request.url?.scheme == original?.scheme && request.url?.port == original?.port ? request : nil)
    }
}
enum AIClient {
    private static let session = URLSession(configuration: .ephemeral, delegate: APIRedirectGuard(), delegateQueue: nil)
    static func failure(_ text: String) -> NSError { NSError(domain: "AI", code: 1, userInfo: [NSLocalizedDescriptionKey:text]) }
    static func endpoint(_ profile: AIProfile, path: String) throws -> URL {
        guard let base = URLComponents(string: profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), let host = base.host, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw failure("API 地址无效，请勿把密钥放在地址中。") }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part), (0...255).contains(value) else { return nil }
            return value
        }
        let privateIP = parts.count == 4 && octets.count == 4 && (octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])))
        let local = privateIP || host == "localhost" || host.hasSuffix(".local")
        guard base.scheme == "https" || (base.scheme == "http" && profile.allowLocalHTTP && local) else { throw failure("云服务必须使用 HTTPS；局域网 HTTP 需要显式启用。") }
        guard let url = URL(string: profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path) else { throw failure("API 地址无效。") }
        return url
    }
    static func request(_ profile: AIProfile, key: String, path: String, body: [String: Any]? = nil, transport: URLSession? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: try endpoint(profile, path: path))
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch profile.format {
        case .gemini: request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        default: if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        }
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (bytes, response) = try await (transport ?? session).bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw failure([401:"密钥无效或与服务地址不匹配。",403:"服务拒绝访问，请检查权限。",404:"接口或模型不存在，请检查地址和请求格式。",429:"达到服务限额，请稍后重试或检查余额。"][code] ?? "服务请求失败（HTTP \(code)）。")
        }
        var data = Data()
        for try await byte in bytes { data.append(byte); guard data.count <= 2 * 1024 * 1024 else { throw failure("服务返回内容过大。") } }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("服务返回的 JSON 无法读取。") }
        return json
    }
    static func models(_ profile: AIProfile, key: String) async throws -> [String] {
        let json = try await request(profile, key: key, path: "models")
        let rows = (json["data"] ?? json["models"]) as? [[String: Any]] ?? []
        return rows.compactMap { ($0["id"] ?? $0["name"]) as? String }.map { $0.replacingOccurrences(of: "models/", with: "") }.sorted()
    }
    static func text(_ profile: AIProfile, key: String, prompt: String, maxTokens: Int = 4096, transport: URLSession? = nil) async throws -> String {
        guard !profile.model.isEmpty else { throw failure("先在设置中填写模型名称。") }
        var body: [String: Any] = ["model":profile.model]
        let path: String
        switch profile.format {
        case .chat:
            path = "chat/completions"; body["messages"] = [["role":"user","content":prompt]]; body["max_tokens"] = maxTokens
        case .responses:
            path = "responses"; body["input"] = prompt; body["store"] = false; body["max_output_tokens"] = maxTokens
        case .anthropic:
            path = "messages"; body["max_tokens"] = maxTokens; body["messages"] = [["role":"user","content":prompt]]
        case .gemini:
            guard profile.model.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw failure("Gemini 模型名称格式无效。") }
            path = "models/" + profile.model + ":generateContent"
            body = ["contents":[["parts":[["text":prompt]]]], "generationConfig":["maxOutputTokens":maxTokens]]
        }
        let json = try await request(profile, key: key, path: path, body: body, transport: transport)
        var value: String?
        switch profile.format {
        case .chat:
            let choices = json["choices"] as? [[String: Any]]
            value = (choices?.first?["message"] as? [String: Any])?["content"] as? String
        case .responses:
            let output = json["output"] as? [[String: Any]] ?? []
            value = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { $0["text"] as? String }.joined()
        case .anthropic:
            value = (json["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        case .gemini:
            let candidate = (json["candidates"] as? [[String: Any]])?.first
            value = ((candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        }
        guard let value, !value.isEmpty else { throw failure("服务没有返回文字，请检查模型和协议。") }
        return value
    }
}
struct AIProfilesView: View {
    @ObservedObject private var profiles = AIProfiles.shared
    @State private var editing: AIProfile?
    @State private var testing = false
    @State private var message = ""
    @State private var selectionTask: Task<Void, Never>?
    var body: some View {
        List {
            Section("当前出题配置") {
                ForEach(profiles.items) { profile in
                    Button {
                        testing = true
                        selectionTask = Task {
                            do { try await profiles.useVerified(profile, model: profile.model); message = "本次请求成功，已切换。" }
                            catch { if !Task.isCancelled { message = "切换失败，继续使用原模型。\n" + error.localizedDescription } }
                            testing = false
                        }
                    } label: { Label(profile.name, systemImage: profiles.active?.id == profile.id ? "checkmark.circle.fill" : "circle") }
                        .contextMenu {
                            Button("编辑") { editing = profile }
                            Button("删除配置", role: .destructive) { profiles.remove(profile.id) }
                        }
                }
                if profiles.items.isEmpty { Text("先添加服务商。不开启 AI 也能使用现有题库。") }
            }
            Section("添加配置") {
                ForEach(AIProfile.presets.indices, id: \.self) { index in
                    Button(AIProfile.presets[index].0) {
                        let preset = AIProfile.presets[index]
                        editing = AIProfile(name: preset.0, baseURL: preset.1, format: preset.2, allowLocalHTTP: preset.0.contains("Ollama"))
                    }
                }
            }
            if testing { ProgressView("正在测试模型…") }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
            Text("长按配置可编辑或删除。切换、保存配置、出题和翻译会调用服务；模型测试可能产生少量费用。").font(.caption).foregroundColor(.secondary)
        }.navigationTitle("AI 服务商").disabled(testing)
            .onDisappear { selectionTask?.cancel(); testing = false }
            .sheet(item: $editing) { profile in NavigationStack { AIProfileEditor(profile: profile) } }
    }
}
struct AIProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: AIProfile
    @State private var key = ""
    @State private var message = ""
    @State private var models: [String] = []
    @State private var loading = false
    @State private var saveTask: Task<Void, Never>?
    var body: some View {
        Form {
            TextField("配置名称", text: $profile.name)
            TextField("API Base URL（不含具体请求路径）", text: $profile.baseURL).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
            Picker("请求格式", selection: $profile.format) { ForEach(AIProtocol.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            SecureField("API Key", text: $key).autocorrectionDisabled().textInputAutocapitalization(.never)
            TextField("模型 ID", text: $profile.model).autocorrectionDisabled().textInputAutocapitalization(.never)
            Toggle("允许局域网 HTTP（明文连接）", isOn: $profile.allowLocalHTTP)
            Button("读取可选模型") {
                loading = true
                Task { do { models = try await AIClient.models(profile, key: key); message = models.isEmpty ? "连接成功；服务未提供模型列表，可手动填写。" : "连接成功，点击下方模型即可选择。" } catch { message = error.localizedDescription }; loading = false }
            }.disabled(loading)
            if loading { ProgressView() }
            ForEach(models.prefix(100), id: \.self) { model in Button(model) { profile.model = model } }
            Text(message).font(.caption).textSelection(.enabled)
            Text("保存前会实际请求所选模型，成功后保存并使用；测试可能产生少量费用。").font(.caption).foregroundColor(.secondary)
            Button("测试并保存配置") {
                loading = true
                saveTask = Task {
                    do { try await AIProfiles.shared.saveVerified(profile, key: key); dismiss() }
                    catch { if !Task.isCancelled { message = error.localizedDescription } }
                    loading = false
                }
            }.disabled(loading)
        }.navigationTitle(profile.name).onAppear { key = SecretStore.read("ai." + profile.id.uuidString) ?? "" }
            .onDisappear { saveTask?.cancel() }
            .toolbar { Button("取消") { dismiss() } }
    }
}
