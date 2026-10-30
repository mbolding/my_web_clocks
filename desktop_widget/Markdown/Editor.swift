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
        // TextKit 1: with TextKit 2, the Find bar finds matches in the coloured text but
        // never highlights them or scrolls to them.
        let text = EditorTextView(usingTextLayoutManager: false)
        text.layoutManager?.allowsNonContiguousLayout = true
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = text
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

/// Takes the focus as it comes into its window, so Find works without a click first, even
/// in a window or tab that opens in the background.
final class EditorTextView: NSTextView {
    // No Touch Bar. On a Mac with one, AppKit refreshes the text view's formatting buttons
    // every time it lays out more text, converting the font of every coloured run as it
    // goes, which stalled scrolling and Find in a long file for seconds at a time.
    override func makeTouchBar() -> NSTouchBar? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}
