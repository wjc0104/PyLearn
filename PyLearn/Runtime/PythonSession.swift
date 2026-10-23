import Foundation
import Combine

struct PythonProblem: Decodable {
    let kind: String
    let message: String
    let line: Int?
    let hint: String
}

private struct PythonResponse: Decodable {
    let status: String?
    let error: PythonProblem?
    let completions: [String]?
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
    private(set) var documentID: UUID?
    private(set) var executedSource = ""
    private let runtime = PLPythonRuntime.shared()

    init() {
        runtime.outputHandler = { [weak self] value in self?.output = value }
        runtime.inputHandler = { [weak self] value in self?.prompt = value }
    }

    func run(source: String, documentID: UUID) {
        guard !running else { return }
        running = true
        output = ""
        problem = nil
        prompt = nil
        status = "运行中"
        resultStatus = ""
        self.documentID = documentID
        executedSource = source
        request(action: "run", source: source) { [weak self] response in
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

    func analyze(source: String, prefix: String, completion: @escaping (PythonProblem?, [String]) -> Void) {
        guard !running else { return }
        request(action: "analyze", source: source, prefix: prefix) { result in completion(result.error, result.completions ?? []) }
    }

    private func request(action: String, source: String, prefix: String = "", completion: @escaping (PythonResponse) -> Void) {
        let payload = ["action":action, "source":source, "prefix":prefix]
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
