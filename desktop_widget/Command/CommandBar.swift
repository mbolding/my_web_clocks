// CommandBar — the command bar's window: the current folder, each command with its
// output, and an input line. Drop a folder anywhere on it to cd there, or a file to
// cd to the folder that holds it.

import SwiftUI

struct CommandBar: View {
    @ObservedObject var session = CommandSession.shared
    @State private var dropTargeted = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            output
            if !session.hint.isEmpty {
                Text(session.hint)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            Divider()
            HStack(spacing: 6) {
                Text("›").foregroundStyle(.orange)
                TextField("", text: $session.line,
                          prompt: Text(session.isRunning ? "running…  ⌃C to stop" : "type a command, or drop a folder"))
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { session.submit() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .font(.system(size: 12, design: .monospaced))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Color.orange, lineWidth: 3).padding(3)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            session.go(to: url)
            NSApp.windows.first { $0.canBecomeKey }?.makeKey()
            focused = true
            return true
        } isTargeted: { dropTargeted = $0 }
        .onAppear { focused = true }
    }

    // The folder; drag here to move the window.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(abbreviated(session.folder))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            if session.isRunning {
                ProgressView().controlSize(.mini)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    private var output: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.blocks) { block in
                        BlockView(block: block)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.blocks.last?.lines) { scroller.scrollTo("end", anchor: .bottom) }
            .onChange(of: session.blocks.count) { scroller.scrollTo("end", anchor: .bottom) }
        }
    }

    private func abbreviated(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

struct BlockView: View {
    var block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("$ " + block.command)
                .foregroundStyle(.orange)
            if !block.output.isEmpty {
                Text(block.output.hasSuffix("\n") ? String(block.output.dropLast()) : block.output)
            }
            if let status = block.status, status != 0 {
                Text("exit \(status)").foregroundStyle(.red)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
