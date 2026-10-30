// Markdown Editor — a plain text editor for Markdown files, with light syntax colouring
// and no preview. An ordinary document app, like Map Browser is an ordinary app: New,
// Open, Save, Revert, recent files and window tabs all come from DocumentGroup.

import SwiftUI

@main
struct MarkdownEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            EditorView(document: file.document)
        }
        .defaultSize(width: 760, height: 820)
        .commands {
            TextEditingCommands()
            TextSizeCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct TextSizeCommands: Commands {
    @AppStorage("fontSize") private var fontSize = 13.0

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Make Text Bigger") { fontSize = min(fontSize + 1, 36) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Make Text Smaller") { fontSize = max(fontSize - 1, 9) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Make Text Normal Size") { fontSize = 13 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }
    }
}

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("monospaced") private var monospaced = true
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange

    var body: some View {
        Form {
            Picker("Font", selection: $monospaced) {
                Text("Monospaced").tag(true)
                Text("System").tag(false)
            }
            Stepper(value: $fontSize, in: 9...36) {
                LabeledContent("Size", value: "\(Int(fontSize)) pt")
            }
            // The same colour the widgets share, so changing it here recolours them too.
            Picker("Accent color", selection: $accent) {
                ForEach(Accent.allCases) { accent in
                    Label { Text(accent.name) } icon: { Image(nsImage: accent.swatch) }
                        .tag(accent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}
