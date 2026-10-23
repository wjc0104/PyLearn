import SwiftUI
import Runestone
import TreeSitterPythonRunestone

final class EditorController: ObservableObject {
    weak var view: TextView?
    var didEdit: (() -> Void)?
    var acceptCompletion: (() -> Void)?
    func insert(_ text: String) { view?.insertText(text); didEdit?() }
    func replace(_ range: NSRange, with text: String) { view?.replace(range, withText: text); didEdit?() }
    func undo() { view?.undoManager?.undo(); didEdit?() }
    func redo() { view?.undoManager?.redo(); didEdit?() }
    func dismissKeyboard() { view?.resignFirstResponder() }
    func selectAll() { if let view { view.selectedRange = NSRange(location: 0, length: (view.text as NSString).length) } }
}

private struct PythonPair: CharacterPair { let leading: String; let trailing: String }

private final class CompletionTextView: TextView {
    var acceptCompletion: (() -> Void)?
    override var keyCommands: [UIKeyCommand]? {
        let tab = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(complete))
        tab.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [tab]
    }
    @objc private func complete() { acceptCompletion?() }
}

enum EditorText {
    static func prefixRange(in source: String, selection: NSRange) -> NSRange {
        let text = source as NSString
        let end = min(max(0, selection.location), text.length)
        let allowed = CharacterSet.alphanumerics.union(.nonBaseCharacters).union(CharacterSet(charactersIn: "_"))
        let boundary = text.rangeOfCharacter(from: allowed.inverted, options: .backwards, range: NSRange(location: 0, length: end))
        let start = boundary.location == NSNotFound ? 0 : NSMaxRange(boundary)
        return NSRange(location: start, length: end - start)
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
    @AppStorage("editor.size") private var size = 16.0
    @AppStorage("editor.font") private var font = "SFMono"
    @AppStorage("editor.theme") private var themeName = "system"
    @AppStorage("editor.foreground") private var foreground = "#DDE3ED"
    @AppStorage("editor.background") private var background = "#20232B"

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> TextView {
        let view = CompletionTextView()
        view.acceptCompletion = { [weak controller] in controller?.acceptCompletion?() }
        view.setState(TextViewState(text: text, theme: PythonTheme(size: size, fontName: font, mode: themeName, foreground: foreground, background: background), language: .python))
        view.showLineNumbers = true
        view.lineSelectionDisplayType = .line
        view.lineHeightMultiplier = 1.35
        view.indentStrategy = .space(length: 4)
        view.backgroundColor = .systemBackground
        view.keyboardDismissMode = .interactive
        view.isFindInteractionEnabled = true
        view.characterPairs = [PythonPair(leading: "(", trailing: ")"), PythonPair(leading: "[", trailing: "]"), PythonPair(leading: "{", trailing: "}"), PythonPair(leading: "\"", trailing: "\""), PythonPair(leading: "'", trailing: "'")]
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
        let key = "\(size)|\(font)|\(themeName)|\(foreground)|\(background)"
        if context.coordinator.appearanceKey != key {
            let theme = PythonTheme(size: size, fontName: font, mode: themeName, foreground: foreground, background: background)
            view.theme = theme
            view.backgroundColor = theme.editorBackground
            context.coordinator.appearanceKey = key
        }
        if let line = errorLine, let range = EditorText.lineRange(in: text, line: line) {
            view.highlightedRanges = [HighlightedRange(id: "syntax-error", range: range, color: UIColor.systemRed.withAlphaComponent(0.12))]
        } else { view.highlightedRanges = [] }
        context.coordinator.updating = false
    }

    final class Coordinator: NSObject, TextViewDelegate {
        var parent: CodeEditor
        var updating = false
        var appearanceKey = ""
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
    let font: UIFont
    let textColor: UIColor
    let editorBackground: UIColor
    let gutterBackgroundColor: UIColor
    let gutterHairlineColor = UIColor.separator
    let lineNumberColor = UIColor.secondaryLabel
    let lineNumberFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let selectedLineBackgroundColor = UIColor.tertiarySystemFill
    let selectedLinesLineNumberColor = UIColor.label
    let selectedLinesGutterBackgroundColor = UIColor.tertiarySystemFill
    let invisibleCharactersColor = UIColor.tertiaryLabel
    let pageGuideHairlineColor = UIColor.separator
    let pageGuideBackgroundColor = UIColor.clear
    let markedTextBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
    init(size: Double, fontName: String, mode: String, foreground: String, background: String) {
        font = UIFont(name: fontName, size: CGFloat(size)) ?? UIFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
        if mode == "custom" {
            textColor = UIColor(hex: foreground) ?? .label; editorBackground = UIColor(hex: background) ?? .systemBackground
        } else if mode == "dark" {
            textColor = UIColor(hex: "#DDE3ED")!; editorBackground = UIColor(hex: "#20232B")!
        } else if mode == "light" {
            textColor = .black; editorBackground = .white
        } else { textColor = .label; editorBackground = .systemBackground }
        gutterBackgroundColor = editorBackground
    }
    func textColor(for highlightName: String) -> UIColor? {
        switch highlightName.components(separatedBy: ".").first {
        case "keyword": return .systemPurple
        case "string": return .systemGreen
        case "comment": return .systemGray
        case "number", "constant": return .systemOrange
        case "function": return .systemBlue
        case "type", "constructor": return .systemTeal
        default: return nil
        }
    }
}
