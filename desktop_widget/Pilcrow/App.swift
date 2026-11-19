// Pilcrow — a Markdown editor that looks and works like Microsoft Word 5.1a for the
// Macintosh (1992): black and white, proportional type on a white page, the Ribbon and Ruler
// across the top. The file is plain Markdown; its markup is hidden, and Show ¶ (⌘J, as in
// Word 5.1) draws it in grey where it is, with ¶ at each return. Named for that ¶. It shares
// its engine and file with Reveal Codes, the WordPerfect 5.1-style editor, in Shared/Markup.

import SwiftUI

@main
struct PilcrowApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownFile() }) { file in
            WordWindow(document: file.document)
        }
        .defaultSize(width: 860, height: 760)
        .commands {
            CommandGroup(before: .toolbar) {
                send("Show ¶", "toggleShowMarks:", "j")
                Divider()
            }
            CommandMenu("Insert") {
                Button("Table") { NSApp.sendAction(#selector(PageTextView.insertTable(_:)), to: nil, from: nil) }
            }
            CommandMenu("Format") {
                send("Bold", "toggleBold:", "b")
                send("Italic", "toggleItalic:", "i")
                send("Strikethrough", "toggleStrikeout:", "x", [.command, .shift])
                send("Code", "toggleCode:", "k", [.command, .shift])
                Divider()
                Menu("Style") {
                    send("Normal", "styleNormal:", "0", [.command, .option])
                    send("heading 1", "styleHeading1:", "1", [.command, .option])
                    send("heading 2", "styleHeading2:", "2", [.command, .option])
                    send("heading 3", "styleHeading3:", "3", [.command, .option])
                    send("List Bullet", "styleBullet:", "8", [.command, .option])
                    send("List Number", "styleNumbered:", "9", [.command, .option])
                    send("Quote", "styleQuote:", "'", [.command, .option])
                    send("Code", "styleCodeBlock:", "k", [.command, .option])
                }
            }
            CommandGroup(replacing: .help) {
                Link("Markdown Syntax", destination: URL(string: "https://commonmark.org/help/")!)
            }
        }
    }

    private func send(_ title: String, _ action: String, _ key: Character,
                      _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { NSApp.sendAction(Selector(action), to: nil, from: nil) }
            .keyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
    }
}

struct WordWindow: View {
    @ObservedObject var document: MarkdownFile
    @StateObject private var state = PageState()
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            Ribbon(state: state)
            Rectangle().fill(.black).frame(height: 1)
            Ruler(state: state)
            Rectangle().fill(.black).frame(height: 1)
            PageScroll(document: document, state: state, undoManager: undoManager)
            Rectangle().fill(.black).frame(height: 1)
            PageBox(state: state)
        }
        .frame(minWidth: Page.textWidth + 2 * Page.margin + 20, minHeight: 360)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
