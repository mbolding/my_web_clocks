// PostView — the widget: a title, the text, and a Post button, with what happened shown
// beneath. Text can be typed, pasted, or dropped in; a dropped file fills it while it's
// empty. After posting, the three addresses are links.

import SwiftUI
import UniformTypeIdentifiers

struct PostView: View {
    @ObservedObject var poster = Poster.shared
    @FocusState private var bodyFocused: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title (or the first line)", text: $poster.title)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .onSubmit { bodyFocused = true }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider()
            TextEditor(text: $poster.body)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($bodyFocused)
                .overlay {
                    if poster.body.isEmpty { dropZone }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
            Divider()
            footer
        }
    }

    /// While the text is empty: the hint, and a target for a dropped file.
    private var dropZone: some View {
        Text("Type, paste or drop text here, or drop a text file. It goes to your blog, phlog and gemlog on SDF.")
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { bodyFocused = true }
            .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in poster.load(url) } }
                    }
                } else {
                    _ = provider.loadObject(ofClass: String.self) { text, _ in
                        if let text { Task { @MainActor in poster.body = text } }
                    }
                }
                return true
            }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            status
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { poster.post() } label: {
                Text("Post")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent.readableText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(poster.isEmpty || poster.busy)
            .opacity(poster.isEmpty || poster.busy ? 0.4 : 1)
            .help("Post to SDF (⌘↩)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var status: some View {
        switch poster.state {
        case .idle:
            Text(poster.login).foregroundStyle(.tertiary).lineLimit(1)
        case .working(let message):
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(message).foregroundStyle(.secondary)
            }
        case .posted(_, let web, let gopher, let gemini):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                Link("web", destination: URL(string: web)!)
                Link("gopher", destination: URL(string: gopher)!)
                Link("gemini", destination: URL(string: gemini)!)
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red).lineLimit(2).help(message)
        }
    }
}
