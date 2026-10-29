// ScratchView — the scratch pad's window: a header with the word count and two buttons,
// Copy All and Save to Desktop, over the text. Drag the header to move the window.

import SwiftUI

struct ScratchView: View {
    @ObservedObject var pad = ScratchPad.shared
    @FocusState private var focused: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TextEditor(text: $pad.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($focused)
                .overlay(alignment: .topLeading) {
                    if pad.text.isEmpty {
                        Text("Type or paste anything")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5) // the text view's own inset
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
        }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let notice = pad.notice {
                Text(notice)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(wordCount)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            button("doc.on.doc", help: "Copy everything to the clipboard") { pad.copyAll() }
            button("square.and.arrow.down", help: "Save to the Desktop as a new Markdown file (⌘S)") { pad.saveToDesktop() }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    private var wordCount: String {
        let words = pad.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return words == 1 ? "1 word" : "\(words) words"
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(pad.isEmpty)
        .help(help)
    }
}
