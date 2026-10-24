import SwiftUI
import UniformTypeIdentifiers

struct CodeImportPicker: UIViewControllerRepresentable {
    let mode: CodeImportMode
    let completion: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> CodeImportPickerController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: mode == .folder ? [.folder] : [.item], asCopy: false)
        picker.allowsMultipleSelection = mode == .files
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return CodeImportPickerController(picker: picker) { context.coordinator.finish([]) }
    }
    func updateUIViewController(_ controller: CodeImportPickerController, context: Context) {
        context.coordinator.completion = completion
    }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var completion: ([URL]) -> Void
        private var finished = false
        init(_ completion: @escaping ([URL]) -> Void) { self.completion = completion }
        func finish(_ urls: [URL]) {
            guard !finished else { return }
            finished = true
            completion(urls)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish([]) }
    }
}

// App-owned cancellation stays outside the Files service's folder navigation.
final class CodeImportPickerController: UIViewController {
    private let picker: UIDocumentPickerViewController
    private let cancel: () -> Void
    init(picker: UIDocumentPickerViewController, cancel: @escaping () -> Void) {
        self.picker = picker; self.cancel = cancel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let button = UIButton(type: .system)
        button.setTitle("取消导入", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = "code.import.cancel"
        button.addTarget(self, action: #selector(cancelImport), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        addChild(picker)
        picker.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker.view)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            picker.view.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 4),
            picker.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        picker.didMove(toParent: self)
    }
    @objc private func cancelImport() { cancel() }
}
