// Reveal Codes — a Markdown editor that looks and works like WordPerfect 5.1 for DOS: the
// blue screen, the status line, F6 for bold and Alt-F3 to reveal the codes. The file is
// plain Markdown, and the Markdown is the codes: `**` is [BOLD], `# ` is [Head 1]. An
// ordinary document app, like Markdown Editor, with New, Open, Save, Revert and recent files
// from DocumentGroup. MarkupEngine and MarkupEditor know nothing of WordPerfect, so a
// Word 5.1-style app can be built on them later.

import SwiftUI
import UniformTypeIdentifiers

@main
struct RevealCodesApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { RevealDocument() }) { file in
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

extension UTType {
    /// Declared in InfoPlistExtras.xml, with its file extensions.
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A Markdown or plain text file, written back as it came: the same encoding, and a byte
/// order mark only if it had one. A reference type, so the screen's own undo is what marks
/// it edited.
final class RevealDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown, .plainText] }

    var text: String
    private var encoding = String.Encoding.utf8
    private var byteOrderMark = false

    init(text: String = "") {
        self.text = text
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        if let text = String(data: data, encoding: .utf8) {
            self.text = text
            byteOrderMark = data.starts(with: [0xEF, 0xBB, 0xBF])
        } else if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            self.text = text
            encoding = .utf16
        } else if let text = String(data: data, encoding: .windowsCP1252) {
            self.text = text
            encoding = .windowsCP1252
        } else {
            text = String(decoding: data.map { UInt16($0) }, as: UTF16.self)
            encoding = .isoLatin1
        }
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        var data = snapshot.data(using: encoding) ?? Data(snapshot.utf8)
        if byteOrderMark, encoding == .utf8 { data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0) }
        return FileWrapper(regularFileWithContents: data)
    }
}

struct ScreenWindow: View {
    @ObservedObject var document: RevealDocument
    var fileURL: URL?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Screen(document: document, fileURL: fileURL, undoManager: undoManager)
            .frame(minWidth: 560, minHeight: 320)
            .background(Color(nsColor: WP.blue))
    }
}

struct Screen: NSViewRepresentable {
    let document: RevealDocument
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
