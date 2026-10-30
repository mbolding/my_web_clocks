// The editor: an AppKit text view, since SwiftUI's TextEditor can't colour its text.

import SwiftUI
import AppKit

struct EditorView: View {
    @ObservedObject var document: MarkdownDocument
    @Environment(\.undoManager) private var undoManager
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("monospaced") private var monospaced = true
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange

    var body: some View {
        MarkdownTextView(document: document, undoManager: undoManager,
                         theme: MarkdownTheme(fontSize: fontSize, monospaced: monospaced, accent: accent.nsColor))
            .frame(minWidth: 360, minHeight: 240)
    }
}

struct MarkdownTextView: NSViewRepresentable {
    let document: MarkdownDocument
    let undoManager: UndoManager?
    let theme: MarkdownTheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isRichText = false
        text.allowsUndo = true
        text.usesFindBar = true
        text.isIncrementalSearchingEnabled = true
        // Smart quotes, dashes and the like rewrite Markdown's own punctuation.
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticDataDetectionEnabled = false
        text.smartInsertDeleteEnabled = false
        text.textContainerInset = NSSize(width: 18, height: 16)
        text.delegate = context.coordinator
        text.textStorage?.delegate = context.coordinator.highlighter
        context.coordinator.textView = text
        update(context.coordinator)
        DispatchQueue.main.async { text.window?.makeFirstResponder(text) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        update(context.coordinator)
    }

    private func update(_ coordinator: Coordinator) {
        guard let text = coordinator.textView, let storage = text.textStorage else { return }
        coordinator.undoManager = undoManager
        if coordinator.highlighter.theme != theme {
            coordinator.highlighter.theme = theme
            text.typingAttributes = theme.baseAttributes
            coordinator.highlighter.highlightAll(storage)
        }
        // A new document object means the file was opened, or reverted or changed on disk.
        // A reload keeps the cursor where it was, as near as the new text allows.
        if coordinator.document !== document {
            let reload = coordinator.document != nil
            let cursor = reload ? min(text.selectedRange().location, (document.text as NSString).length) : 0
            coordinator.document = document
            text.string = document.text
            text.setSelectedRange(NSRange(location: cursor, length: 0))
            text.scrollRangeToVisible(NSRange(location: cursor, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let highlighter = MarkdownHighlighter()
        weak var textView: NSTextView?
        var document: MarkdownDocument?
        var undoManager: UndoManager?

        func textDidChange(_ notification: Notification) {
            guard let text = textView else { return }
            document?.text = text.string
        }

        // Typing goes on the document's own undo stack, which is how it knows it's edited.
        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }
    }
}
