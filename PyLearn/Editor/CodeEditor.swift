import SwiftUI
import Runestone
import TreeSitterPythonRunestone

final class EditorController: ObservableObject {
    weak var view: TextView?
    var didEdit: (() -> Void)?
    func insert(_ text: String) { view?.insertText(text); didEdit?() }
    func replace(_ range: NSRange, with text: String) { view?.replace(range, withText: text); didEdit?() }
    func undo() { view?.undoManager?.undo(); didEdit?() }
    func redo() { view?.undoManager?.redo(); didEdit?() }
    func dismissKeyboard() { view?.resignFirstResponder() }
}

enum EditorText {
    static func prefixRange(in source: String, selection: NSRange) -> NSRange {
        let text = source as NSString
        let end = min(max(0, selection.location), text.length)
        let before = text.substring(to: end)
        let prefix = String(before.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" }.reversed())
        return NSRange(location: end - (prefix as NSString).length, length: (prefix as NSString).length)
    }

    static func lineRange(in source: String, line: Int) -> NSRange? {
        let text = source as NSString
        guard line > 0 else { return nil }
        var index = 0
        var current = 1
        while current < line && index < text.length {
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
            current += 1
        }
        guard current == line else { return nil }
        return text.lineRange(for: NSRange(location: index, length: 0))
    }
}

struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let controller: EditorController
    let editable: Bool
    let errorLine: Int?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> TextView {
        let view = TextView()
        view.setState(TextViewState(text: text, theme: PythonTheme(), language: .python))
        view.showLineNumbers = true
        view.lineSelectionDisplayType = .line
        view.lineHeightMultiplier = 1.35
        view.indentStrategy = .space(length: 4)
        view.backgroundColor = .systemBackground
        view.keyboardDismissMode = .interactive
        view.isFindInteractionEnabled = true
        view.editorDelegate = context.coordinator
        controller.view = view
        controller.didEdit = { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.textViewDidChange(view) }
        }
        view.accessibilityIdentifier = "pythonEditor"
        return view
    }

    func updateUIView(_ view: TextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updating = true
        if view.text != text { view.replace(NSRange(location: 0, length: (view.text as NSString).length), withText: text) }
        if view.selectedRange != selection && NSMaxRange(selection) <= (text as NSString).length {
            view.selectedRange = selection
            view.scrollRangeToVisible(selection)
        }
        view.isEditable = editable
        if let line = errorLine, let range = EditorText.lineRange(in: text, line: line) {
            view.highlightedRanges = [HighlightedRange(range: range, color: UIColor.systemRed.withAlphaComponent(.12))]
        } else { view.highlightedRanges = [] }
        context.coordinator.updating = false
    }

    final class Coordinator: NSObject, TextViewDelegate {
        var parent: CodeEditor
        var updating = false
        init(_ parent: CodeEditor) { self.parent = parent }
        func textViewDidChange(_ textView: TextView) {
            guard !updating else { return }
            parent.text = textView.text
            parent.selection = textView.selectedRange
        }
        func textViewDidChangeSelection(_ textView: TextView) {
            guard !updating else { return }
            parent.selection = textView.selectedRange
        }
        func textView(_ textView: TextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            (textView.text as NSString).replacingCharacters(in: range, with: replacement).utf8.count <= 524288
        }
    }
}

private final class PythonTheme: Theme {
    let font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    let textColor = UIColor.label
    let gutterBackgroundColor = UIColor.secondarySystemBackground
    let gutterHairlineColor = UIColor.separator
    let lineNumberColor = UIColor.secondaryLabel
    let lineNumberFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let selectedLineBackgroundColor = UIColor.tertiarySystemFill
    let selectedLinesLineNumberColor = UIColor.label
    let selectedLinesGutterBackgroundColor = UIColor.tertiarySystemFill
    let invisibleCharactersColor = UIColor.tertiaryLabel
    let pageGuideHairlineColor = UIColor.separator
    let pageGuideBackgroundColor = UIColor.clear
    let markedTextBackgroundColor = UIColor.systemBlue.withAlphaComponent(.15)
    func textColor(for highlightName: String) -> UIColor? {
        switch highlightName.components(separatedBy: ".").first {
        case "keyword": return .systemPurple
        case "string": return .systemGreen
        case "comment": return .secondaryLabel
        case "number", "constant": return .systemOrange
        case "function": return .systemBlue
        case "type", "constructor": return .systemTeal
        default: return nil
        }
    }
}
