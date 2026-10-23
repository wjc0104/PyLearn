import SwiftUI
import CoreText
import Security
import UniformTypeIdentifiers

enum SecretStore {
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.wjc0104.pylearn", kSecAttrAccount as String:account, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ secret: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.wjc0104.pylearn", kSecAttrAccount as String:account]
        if secret.isEmpty { SecItemDelete(query as CFDictionary); return }
        let values: [String: Any] = [kSecValueData as String:Data(secret.utf8), kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(values) { _,v in v } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey:"密钥无法保存到设备钥匙串。"]) }
    }
}
enum FontRegistry {
    static var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PyLearn/fonts", isDirectory: true) }
    static func restore() {
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
    static func add(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 10 * 1024 * 1024 else { throw NSError(domain: "Font", code: 1, userInfo: [NSLocalizedDescriptionKey:"字体超过 10 MiB。"]) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
        try data.write(to: destination, options: .atomic)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(destination as CFURL) as? [CTFontDescriptor], let first = descriptors.first, let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else { try? FileManager.default.removeItem(at: destination); throw CocoaError(.fileReadCorruptFile) }
        CTFontManagerRegisterFontsForURL(destination as CFURL, .process, nil)
        var names = UserDefaults.standard.stringArray(forKey: "editor.importedFonts") ?? []
        if !names.contains(name) { names.append(name) }
        UserDefaults.standard.set(names, forKey: "editor.importedFonts")
        return name
    }
}
struct SettingsView: View {
    @AppStorage("editor.size") private var size = 16.0
    @AppStorage("editor.font") private var font = "SFMono"
    @AppStorage("editor.theme") private var theme = "system"
    @AppStorage("editor.foreground") private var foreground = "#DDE3ED"
    @AppStorage("editor.background") private var background = "#20232B"
    @State private var importing = false
    @State private var fonts: [String] = []
    @State private var message = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("编辑器外观") {
                    Stepper("字号 \(Int(size))", value: $size, in: 11...30)
                    Picker("字体", selection: $font) {
                        Text("系统等宽").tag("SFMono"); Text("Menlo").tag("Menlo"); Text("Courier").tag("Courier")
                        ForEach(fonts, id: \.self) { Text($0).tag($0) }
                    }
                    Button("导入 TTF / OTF 字体") { importing = true }
                    Picker("主题", selection: $theme) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("Darcula 深色").tag("dark"); Text("自定义颜色").tag("custom") }
                    if theme == "custom" {
                        ColorPicker("文字颜色", selection: Binding(get: { Color(UIColor(hex: foreground) ?? .white) }, set: { foreground = UIColor($0).hexValue }))
                        ColorPicker("背景颜色", selection: Binding(get: { Color(UIColor(hex: background) ?? .black) }, set: { background = UIColor($0).hexValue }))
                    }
                    Button("恢复默认外观") { size = 16; font = "SFMono"; theme = "system" }
                }
                Section("AI 出题与翻译") { NavigationLink("管理服务商与 API 配置") { AIProfilesView() } }
                Section("关于") {
                    Text("PyLearn 0.2.0 · CPython 3.15.1")
                    Text("Runestone 编辑器 · Jedi 补全 · Dulwich Git").font(.caption)
                    Text("由 OpenAI Codex 辅助开发与编辑。脚本在本机 App 进程内运行。").font(.caption).foregroundColor(.secondary)
                }
                if !message.isEmpty { Text(message).font(.caption).foregroundColor(.red) }
            }.navigationTitle("设置")
                .onAppear { FontRegistry.restore(); fonts = UserDefaults.standard.stringArray(forKey: "editor.importedFonts") ?? [] }
                .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "ttf") ?? .data, UTType(filenameExtension: "otf") ?? .data]) { result in
                    do { font = try FontRegistry.add(result.get()); fonts = UserDefaults.standard.stringArray(forKey: "editor.importedFonts") ?? [] } catch { message = error.localizedDescription }
                }
        }
    }
}
extension UIColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let n = UInt32(value, radix: 16) else { return nil }
        self.init(red: CGFloat((n >> 16) & 255)/255, green: CGFloat((n >> 8) & 255)/255, blue: CGFloat(n & 255)/255, alpha: 1)
    }
    var hexValue: String { var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; getRed(&r, green: &g, blue: &b, alpha: &a); return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255)) }
}
