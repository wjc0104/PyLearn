import SwiftUI
import UniformTypeIdentifiers

struct CodeImportPicker: UIViewControllerRepresentable {
    let mode: CodeImportMode
    var onDismiss: () -> Void = {}
    let completion: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion, onDismiss: onDismiss) }
    func makeUIViewController(context: Context) -> CodeImportPickerController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: mode == .folder ? [.folder] : [.item], asCopy: false)
        picker.allowsMultipleSelection = mode == .files
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return CodeImportPickerController(picker: picker, cancel: { context.coordinator.finish([]) }, disappeared: { context.coordinator.didDisappear() })
    }
    func updateUIViewController(_ controller: CodeImportPickerController, context: Context) {
        context.coordinator.completion = completion
        context.coordinator.onDismiss = onDismiss
    }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var completion: ([URL]) -> Void
        var onDismiss: () -> Void
        private var finished = false
        private var disappeared = false
        private var dismissalDelivered = false
        init(_ completion: @escaping ([URL]) -> Void, onDismiss: @escaping () -> Void = {}) {
            self.completion = completion; self.onDismiss = onDismiss
        }
        func finish(_ urls: [URL]) {
            guard !finished else { return }
            finished = true
            completion(urls)
            finishDismissal()
        }
        func didDisappear() { disappeared = true; finishDismissal() }
        private func finishDismissal() {
            guard finished, disappeared, !dismissalDelivered else { return }
            dismissalDelivered = true
            onDismiss()
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish([]) }
    }
}

// App-owned cancellation stays outside the Files service's folder navigation.
final class CodeImportPickerController: UIViewController {
    private let picker: UIDocumentPickerViewController
    private let cancel: () -> Void
    private let disappeared: () -> Void
    private var dismissing = false
    init(picker: UIDocumentPickerViewController, cancel: @escaping () -> Void, disappeared: @escaping () -> Void) {
        self.picker = picker; self.cancel = cancel; self.disappeared = disappeared
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
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        dismissing = false
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // A provider's full-screen UI can cover the picker without closing it.
        dismissing = false
        var controller: UIViewController? = self
        while let current = controller {
            if current.isBeingDismissed { dismissing = true; break }
            controller = current.parent
        }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if dismissing { disappeared() }
    }
    @objc private func cancelImport() { cancel() }
}
