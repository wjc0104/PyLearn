import Foundation

struct CodeSnippet: Codable, Identifiable {
    let id: String
    let title: String
    let category: String
    let source: String
    static let categories = ["基础语法", "循环与容器", "函数与类", "文件与数据", "实用工具"]
    static let all: [CodeSnippet] = {
        guard let url = Bundle.main.url(forResource: "snippets", withExtension: "json"),
              let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([CodeSnippet].self, from: data) else { return [] }
        return items
    }()
}
