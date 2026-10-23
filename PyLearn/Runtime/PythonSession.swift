import Foundation
import Combine

struct PythonProblem: Decodable {
    let kind: String
    let message: String
    let line: Int?
    let hint: String
    var traceback: String? = nil
}

private struct PythonResponse: Decodable {
    let status: String?
    let error: PythonProblem?
    let completions: [String]?
    var signature: String? = nil
}

@MainActor
final class PythonSession: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var output = ""
    @Published private(set) var prompt: String?
    @Published private(set) var problem: PythonProblem?
    @Published private(set) var status = "准备就绪"
    @Published private(set) var resultStatus = ""
    @Published private(set) var sequence = 0
    @Published private(set) var working = false
    var busy: Bool { running || working }
    private var analyzing = false
    private(set) var documentID: UUID?
    private(set) var executedSource = ""
    private let runtime = PLPythonRuntime.shared()

    init() {
        runtime.outputHandler = { [weak self] value in self?.output = value }
        runtime.inputHandler = { [weak self] value in self?.prompt = value }
    }

    func run(source: String, documentID: UUID, directory: String? = nil, path: String? = nil) {
        guard !busy else { return }
        running = true
        output = ""
        problem = nil
        prompt = nil
        status = "运行中"
        resultStatus = ""
        self.documentID = documentID
        executedSource = source
        var extra: [String: Any] = [:]
        if let directory { extra["directory"] = directory }
        if let path { extra["path"] = path }
        request(action: "run", source: source, extra: extra) { [weak self] response in
            guard let self else { return }
            self.running = false
            self.prompt = nil
            self.problem = response.error
            self.resultStatus = response.status ?? "error"
            self.status = ["success":"运行完成", "stopped":"已停止", "timeout":"已超过 10 秒运行限制", "output_limit":"输出已达到 20,000 字符限制", "error":"运行出错"][self.resultStatus] ?? "运行出错"
            self.sequence += 1
        }
    }

    func stop() { runtime.cancel(); prompt = nil; status = "正在停止" }
    func submitInput(_ text: String) { prompt = nil; runtime.submitInput(text) }

    func clearOutput() { if !running { output = "" } }

    func perform(_ payload: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard !busy, let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        working = true
        runtime.performRequest(json) { [weak self] response in
            self?.working = false
            completion((try? JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any]) ?? ["status":"error", "report":"无法读取运行结果"])
        }
    }

    func analyze(source: String, prefix: String, line: Int, column: Int, directory: String? = nil, path: String? = nil, completion: @escaping (PythonProblem?, [String], String) -> Void) {
        guard !busy, !analyzing else { return }
        analyzing = true
        var extra: [String: Any] = ["line":line, "column":column]
        if let directory { extra["directory"] = directory }
        if let path { extra["path"] = path }
        request(action: "analyze", source: source, prefix: prefix, extra: extra) { [weak self] result in
            self?.analyzing = false
            completion(result.error, result.completions ?? [], result.signature ?? "")
        }
    }

    private func request(action: String, source: String, prefix: String = "", extra: [String: Any] = [:], completion: @escaping (PythonResponse) -> Void) {
        var payload: [String: Any] = ["action":action, "source":source, "prefix":prefix]
        for (key, value) in extra { payload[key] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: data, encoding: .utf8) else { return }
        runtime.performRequest(text) { response in
            if let result = try? JSONDecoder().decode(PythonResponse.self, from: Data(response.utf8)) {
                completion(result)
            } else {
                completion(PythonResponse(status: "error", error: PythonProblem(kind: "RuntimeError", message: "运行层返回的数据无法读取。", line: nil, hint: "请重新打开 App 后再试。"), completions: nil))
            }
        }
    }
}
