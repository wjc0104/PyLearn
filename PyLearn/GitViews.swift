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
    @State private var editingCredentials = true
    @State private var loadedHost = ""
    var body: some View {
        Form {
            Section("仓库") {
                Button("初始化 Git") { perform("init") }
                HStack { Button("状态") { perform("status") }; Spacer(); Button("差异") { perform("diff") }; Spacer(); Button("历史") { perform("log") } }
            }
            Section("提交所有修改") {
                TextField("提交说明", text: $message)
                Button("保存一个提交") { perform("commit", extra: ["message":message]) }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("提交并推送") { perform("commit_push", extra: ["message":message]) }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || remote.isEmpty)
                Text("提交会记录项目中新建、修改和删除的文件。“保存一个提交”只保存在本机；“提交并推送”成功后，电脑或其他设备就能拉取。").font(.caption).foregroundColor(.secondary)
            }
            Section("分支") {
                TextField("新分支名", text: $branch).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("创建分支") { perform("branch", extra: ["branch":branch]) }.disabled(branch.isEmpty)
                ForEach(branches, id: \.self) { name in Button("切换到 " + name) { perform("checkout", extra: ["branch":name]) } }
            }
            syncSection
            Section("结果") {
                if session.working { ProgressView("Git 操作中…") }
                Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button("复制结果") { UIPasteboard.general.string = report }
            }
        }.navigationTitle("Git · " + project.name).disabled(session.busy)
            .onAppear {
                remote = UserDefaults.standard.string(forKey: "git.remote." + project.id.uuidString) ?? ""
                loadCredentials()
                editingCredentials = remote.isEmpty || token.isEmpty
                perform("status")
            }
            .onChange(of: remote) { _ in loadCredentials() }
    }
    private var syncSection: some View {
        Section("HTTPS 同步") {
            if !remote.isEmpty { Text(remote).font(.caption).textSelection(.enabled) }
            DisclosureGroup("远程配置与已保存凭据", isExpanded: $editingCredentials) {
                TextField("https://github.com/用户名/仓库.git", text: $remote).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("用户名", text: $username).autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("访问令牌（公开克隆可留空）", text: $token)
                Button("保存远程配置") { do { try saveCredentials(); report = "配置已保存，以后同步自动使用。" } catch { report = error.localizedDescription } }
                Text("按 Git 服务地址保存，克隆、拉取和推送自动复用。令牌只保存在本机钥匙串。").font(.caption).foregroundColor(.secondary)
            }
            HStack { Button("拉取（仅快进）") { perform("pull") }; Spacer(); Button("推送当前分支") { perform("push") } }
            Text("提交前可查看差异。拉取和切换分支前需要提交本地修改；分歧时保留代码。").font(.caption).foregroundColor(.secondary)
        }
    }
    private func loadCredentials() {
        guard let host = try? GitCredentials.host(remote), host != loadedHost else { return }
        loadedHost = host
        let saved = GitCredentials.load(remote); username = saved.username; token = saved.token
    }
    private func saveCredentials() throws {
        remote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        try GitCredentials.save(remote, username: username, token: token)
        UserDefaults.standard.set(remote, forKey: "git.remote." + project.id.uuidString)
        editingCredentials = false
    }
    private func perform(_ operation: String, extra: [String: Any] = [:]) {
        do {
            try store.flushOrThrow()
            if operation == "pull" || operation == "push" || operation == "commit_push" { try saveCredentials() }
        } catch { report = "已取消 Git 操作，请先检查保存状态或远程配置。\n" + error.localizedDescription; return }
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
    @State private var loadedHost = ""
    var body: some View {
        Form {
            TextField("HTTPS 仓库地址", text: $remote).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
            TextField("用户名（公开仓库可留空）", text: $username).autocorrectionDisabled().textInputAutocapitalization(.never)
            SecureField("访问令牌（公开仓库可留空）", text: $token)
            Text("凭据只需填写一次，同一 Git 服务的其他仓库自动复用；令牌保存在本机钥匙串。").font(.caption).foregroundColor(.secondary)
            Button("克隆到本机项目") { clone() }.disabled(session.busy || remote.isEmpty)
            if session.working { ProgressView("正在克隆…") }
            Text(report).font(.caption).textSelection(.enabled)
        }.navigationTitle("克隆仓库").disabled(session.busy).interactiveDismissDisabled(session.busy)
            .toolbar { Button("完成") { dismiss() }.disabled(session.busy) }
            .onChange(of: remote) { _ in
                guard let host = try? GitCredentials.host(remote), host != loadedHost else { return }
                loadedHost = host
                let saved = GitCredentials.load(remote); username = saved.username; token = saved.token
            }
    }
    private func clone() {
        remote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try GitCredentials.save(remote, username: username, token: token) } catch { report = error.localizedDescription; return }
        let project = ScriptProject(name: URL(string: remote)?.deletingPathExtension().lastPathComponent ?? "Git 项目")
        let root = store.projectRoot(project.id)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { report = error.localizedDescription; return }
        session.perform(["action":"git", "operation":"clone", "directory":root.path, "remote":remote, "username":username, "token":token]) { result in
            report = result["report"] as? String ?? "克隆失败"
            guard result["status"] as? String == "success" else { try? FileManager.default.removeItem(at: root); return }
            store.projects.append(project)
            do {
                try store.repairProjectEntry(project)
                try store.persist()
                UserDefaults.standard.set(remote, forKey: "git.remote." + project.id.uuidString)
                dismiss()
            } catch {
                store.projects.removeAll { $0.id == project.id }
                report = "项目未能保存，请重试。\n" + error.localizedDescription
                try? FileManager.default.removeItem(at: root)
            }
        }
    }
}
