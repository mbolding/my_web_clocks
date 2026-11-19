// Reveal Codes — a Markdown editor that looks and works like WordPerfect 5.1 for DOS: the
// blue screen, the status line, F6 for bold and Alt-F3 to reveal the codes. The file is
// plain Markdown, and the Markdown is the codes: `**` is [BOLD], `# ` is [Head 1]. An
// ordinary document app, like Markdown Editor, with New, Open, Save, Revert and recent files
// from DocumentGroup. The engine (MarkupEngine, MarkupEditor) and the file (MarkdownFile) are
// in Shared/Markup, which Pilcrow, the Word 5.1-style editor, builds on too.

import SwiftUI
import UniformTypeIdentifiers

@main
struct RevealCodesApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownFile() }) { file in
            ScreenWindow(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 960, height: 600)
        .commands {
            CommandMenu("Format") {
                send("Bold", "toggleBold:", "b")
                send("Italic", "toggleItalic:", "i")
                send("Strikeout", "toggleStrikeout:", "x", [.command, .shift])
                send("Code", "toggleCode:", "k", [.command, .shift])
                Divider()
                Menu("Style") {
                    send("Heading 1", "styleHeading1:", "1", [.command, .option])
                    send("Heading 2", "styleHeading2:", "2", [.command, .option])
                    send("Heading 3", "styleHeading3:", "3", [.command, .option])
                    send("Bulleted List", "styleBullet:", "8", [.command, .option])
                    send("Numbered List", "styleNumbered:", "9", [.command, .option])
                    send("Quote", "styleQuote:", "'", [.command, .option])
                    send("Code Block", "styleCodeBlock:", "k", [.command, .option])
                    send("Normal", "styleNormal:", "0", [.command, .option])
                }
                Divider()
                send("Block On/Off", "toggleBlock:", "b", [.command, .option])
                Button("Insert Table") { NSApp.sendAction(#selector(ScreenView.insertTable(_:)), to: nil, from: nil) }
            }
            CommandGroup(before: .toolbar) {
                send("Reveal Codes", "toggleRevealCodes:", "r", [.command, .option])
                send("Show or Hide Key Template", "toggleKeyTemplate:", "t", [.command, .option])
                Divider()
            }
            CommandGroup(replacing: .help) {
                send("Reveal Codes Help", "showHelp:", "?", [.command])
                Link("Markdown Syntax", destination: URL(string: "https://commonmark.org/help/")!)
            }
        }
    }

    /// A menu item that sends its action to the screen with the keyboard, as the
    /// WordPerfect keys do.
    private func send(_ title: String, _ action: String, _ key: Character,
                      _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { NSApp.sendAction(Selector(action), to: nil, from: nil) }
            .keyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
    }
}

struct ScreenWindow: View {
    @ObservedObject var document: MarkdownFile
    var fileURL: URL?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Screen(document: document, fileURL: fileURL, undoManager: undoManager)
            .frame(minWidth: 560, minHeight: 320)
            .background(Color(nsColor: WP.blue))
    }
}

struct Screen: NSViewRepresentable {
    let document: MarkdownFile
    var fileURL: URL?
    var undoManager: UndoManager?

    func makeNSView(context: Context) -> ScreenView {
        let view = ScreenView(text: document.text)
        view.onChange = { [document] text in document.text = text }
        update(view)
        return view
    }

    func updateNSView(_ view: ScreenView, context: Context) {
        update(view)
        view.reload(document.text)
    }

    private func update(_ view: ScreenView) {
        view.documentUndo = undoManager
        // WordPerfect showed the file's whole path at the bottom left.
        view.fileName = fileURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
    }
}
