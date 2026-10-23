import Foundation

enum GitCredentials {
    static func host(_ remote: String) throws -> String {
        guard let url = URLComponents(string: remote), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
            throw NSError(domain: "Git", code: 1, userInfo: [NSLocalizedDescriptionKey:"请填写不含账号密码的 HTTPS 仓库地址。"])
        }
        return host.lowercased() + (url.port.map { ":\($0)" } ?? "")
    }
    static func load(_ remote: String) -> (username: String, token: String) {
        guard let host = try? host(remote) else { return ("", "") }
        let legacy = host == "github.com"
        let username = UserDefaults.standard.string(forKey: "git.username." + host)
            ?? (legacy ? UserDefaults.standard.string(forKey: "git.username") : nil) ?? ""
        let token = SecretStore.read("git.token." + host) ?? (legacy ? SecretStore.read("git.token") : nil) ?? ""
        return (username, token)
    }
    static func save(_ remote: String, username: String, token: String) throws {
        let host = try host(remote)
        try SecretStore.save(token, account: "git.token." + host)
        UserDefaults.standard.set(username, forKey: "git.username." + host)
        if host == "github.com" {
            try SecretStore.save("", account: "git.token")
            UserDefaults.standard.removeObject(forKey: "git.username")
        }
    }
}
