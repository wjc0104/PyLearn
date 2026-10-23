import SwiftUI

struct GitView: View {
    @EnvironmentObject private var store: LearningStore
    @EnvironmentObject private var session: PythonSession
    let project: ScriptProject
    @State private var remote = ""
    @State private var username = ""
    @State private var token = ""
    @State private var message = ""
    @State private var branch = ""
    @State private var branches: [String] = []
    @State private var report = ""
    var body: some View {
        Form {
            Section("仓库") {
                Button("初始化 Git") { perform("init") }
                HStack { Button("状态") { perform("status") }; Spacer(); Button("差异") { perform("diff") }; Spacer(); Button("历史") { perform("log") } }
            }
            Section("提交所有修改") {
                TextField("提交说明", text: $message)
                Button("保存一个提交") { perform("commit", extra: ["message":message]) }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("分支") {
                TextField("新分支名", text: $branch).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("创建分支") { perform("branch", extra: ["branch":branch]) }.disabled(branch.isEmpty)
                ForEach(branches, id: \.self) { name in Button("切换到 " + name) { perform("checkout", extra: ["branch":name]) } }
            }
            Section("HTTPS 同步") {
                TextField("https://github.com/用户名/仓库.git", text: $remote).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("用户名", text: $username).autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("访问令牌（公开克隆可留空）", text: $token)
                Button("保存远程配置") { saveCredentials() }
                HStack { Button("拉取（仅快进）") { perform("pull") }; Spacer(); Button("推送当前分支") { perform("push") } }
                Text("提交前可查看差异。拉取和切换分支前需要提交本地修改；分歧时保留代码。").font(.caption).foregroundColor(.secondary)
            }
            Section("结果") {
                if session.working { ProgressView("Git 操作中…") }
                Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button("复制结果") { UIPasteboard.general.string = report }
            }
        }.navigationTitle("Git · " + project.name).disabled(session.busy)
            .onAppear {
                remote = UserDefaults.standard.string(forKey: "git.remote." + project.id.uuidString) ?? ""
                username = UserDefaults.standard.string(forKey: "git.username") ?? ""
                token = SecretStore.read("git.token") ?? ""
                perform("status")
            }
    }
    private func saveCredentials() {
        guard let url = URLComponents(string: remote), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { report = "请填写不含账号密码的 HTTPS 仓库地址。"; return }
        do { try SecretStore.save(token, account: "git.token"); UserDefaults.standard.set(remote, forKey: "git.remote." + project.id.uuidString); UserDefaults.standard.set(username, forKey: "git.username"); report = "配置已保存。" } catch { report = error.localizedDescription }
    }
    private func perform(_ operation: String, extra: [String: Any] = [:]) {
        do { try store.flushOrThrow() } catch { report = "保存失败，已取消 Git 操作，请先导出代码。\n" + error.localizedDescription; return }
        var payload: [String: Any] = ["action":"git", "operation":operation, "directory":store.projectRoot(project.id).path, "remote":remote, "username":username, "token":token]
        for (key,value) in extra { payload[key] = value }
        session.perform(payload) { result in
            report = result["report"] as? String ?? "操作失败。"
            branches = result["branches"] as? [String] ?? branches
            store.refreshProject(project.id)
        }
    }
}
struct CloneRepositoryView: View {
    @EnvironmentObject private var store: LearningStore
    @EnvironmentObject private var session: PythonSession
    @Environment(\.dismiss) private var dismiss
    @State private var remote = ""
    @State private var username = ""
    @State private var token = ""
    @State private var report = ""
    var body: some View {
        Form {
            TextField("HTTPS 仓库地址", text: $remote).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
            TextField("用户名（公开仓库可留空）", text: $username).textInputAutocapitalization(.never)
            SecureField("访问令牌（公开仓库可留空）", text: $token)
            Button("克隆到本机项目") { clone() }.disabled(session.busy || remote.isEmpty)
            if session.working { ProgressView("正在克隆…") }
            Text(report).font(.caption).textSelection(.enabled)
        }.navigationTitle("克隆仓库").interactiveDismissDisabled(session.busy)
            .toolbar { Button("完成") { dismiss() }.disabled(session.busy) }
    }
    private func clone() {
        let project = ScriptProject(name: URL(string: remote)?.deletingPathExtension().lastPathComponent ?? "Git 项目")
        let root = store.projectRoot(project.id)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { report = error.localizedDescription; return }
        session.perform(["action":"git", "operation":"clone", "directory":root.path, "remote":remote, "username":username, "token":token]) { result in
            report = result["report"] as? String ?? "克隆失败"
            if result["status"] as? String == "success" {
                var saved = project
                saved.entry = (try? store.files(in: project).first(where: { $0.path == "main.py" || $0.path.hasSuffix(".py") })?.path) ?? nil
                store.projects.append(saved)
                do { try store.persist(); UserDefaults.standard.set(remote, forKey: "git.remote." + project.id.uuidString); dismiss() } catch { report = error.localizedDescription }
            }
        }
    }
}
