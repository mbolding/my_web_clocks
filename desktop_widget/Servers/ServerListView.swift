// ServerListView — Server List's window: a row per saved server, with an icon for its
// kind (a display for Screen Sharing, a terminal for SSH) and its host. Click a row to
// connect. With no servers yet, it offers to add one.

import SwiftUI

struct ServerListView: View {
    static let width: CGFloat = 240, rowHeight: CGFloat = 28, padding: CGFloat = 8

    /// The window's size for `count` rows; the empty list gets two rows' room.
    static func size(for count: Int) -> CGSize {
        CGSize(width: width, height: padding * 2 + CGFloat(max(count, 2)) * rowHeight)
    }

    @ObservedObject var list = ServerList.shared
    @Environment(\.accent) private var accent

    var body: some View {
        Group {
            if list.servers.isEmpty { empty } else { rows }
        }
        // Resized after SwiftUI finishes this update, not in the middle of it.
        .onChange(of: list.servers.count) { DispatchQueue.main.async { fitWindow(animate: true) } }
        .onAppear {
            // After the window has restored its saved frame, which may be another size.
            DispatchQueue.main.async { fitWindow(animate: false) }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(list.servers) { server in
                ServerRow(server: server)
            }
        }
        .padding(Self.padding)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("No servers")
                .foregroundStyle(.secondary)
            Button("Add Server…") { list.promptToAdd() }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
        }
        .font(.system(size: 12, design: .rounded))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Sizes the window to the list, keeping its top edge where it is, but on screen.
    private func fitWindow(animate: Bool) {
        guard let window = NSApp.windows.first(where: { $0 is DesktopPanel }) else { return }
        let size = Self.size(for: list.servers.count)
        var frame = window.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        if let visible = window.screen?.visibleFrame {
            frame.origin.y = max(visible.minY, frame.origin.y)
        }
        guard frame != window.frame else { return }
        window.contentMinSize = size
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.2 : 0
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            window.invalidateShadow()
        }
    }
}

struct ServerRow: View {
    let server: Server
    @Environment(\.accent) private var accent
    @State private var hovering = false

    var body: some View {
        Button { ServerList.shared.open(server) } label: {
            HStack(spacing: 8) {
                Image(systemName: server.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
                    .frame(width: 18)
                Text(server.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, design: .rounded))
            .padding(.horizontal, 8)
            .frame(height: ServerListView.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle(hovering: hovering))
        .onHover { hovering = $0 }
        .help("Connect to \(server.id)")
    }
}

/// A faint accent-coloured tile behind the row under the mouse, stronger while pressed.
private struct RowStyle: ButtonStyle {
    var hovering: Bool
    @Environment(\.accent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accent.opacity(configuration.isPressed ? 0.3 : hovering ? 0.15 : 0)))
    }
}
