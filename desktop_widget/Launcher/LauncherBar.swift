// LauncherBar — Widget Bar's window: a row of widget icons with a dot under each one
// that's running, in the accent colour if it floats on top. Click to open a widget, or to flip a
// running one's Float on Top; right-click an icon to show it for a moment or quit it.
// The chevron at the end folds the bar into a small square at its right edge, out of the
// way; clicking the square opens it out again.

import SwiftUI

struct LauncherBar: View {
    static let iconSize: CGFloat = 36, spacing: CGFloat = 10, padding: CGFloat = 14, height: CGFloat = 62

    /// The window's size for `count` icons, plus the divider, pin and chevron at the end.
    static func size(for count: Int) -> CGSize {
        guard count > 0 else { return CGSize(width: 260, height: height) }
        let icons = CGFloat(count) * iconSize + CGFloat(count - 1) * spacing
        return CGSize(width: padding * 2 + icons + spacing * 3 + 1 + 14 + 14, height: height)
    }

    static let collapsedSize = CGSize(width: height, height: height)

    @ObservedObject var launcher = WidgetLauncher.shared
    @AppStorage("collapsed") private var collapsed = false
    @Environment(\.accent) private var accent

    var body: some View {
        Group {
            if collapsed { folded } else { bar }
        }
        // Resized after SwiftUI finishes this update, not in the middle of it.
        .onChange(of: collapsed) { DispatchQueue.main.async { fitWindow(animate: true) } }
        .onAppear {
            // After the window has restored its saved frame, which may be either size.
            DispatchQueue.main.async { fitWindow(animate: false) }
        }
    }

    private var bar: some View {
        HStack(spacing: Self.spacing) {
            if launcher.widgets.isEmpty {
                Text("No widgets installed")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ForEach(launcher.widgets) { widget in
                let isRunning = launcher.running.contains(widget.id)
                let isFloating = launcher.floating.contains(widget.id)
                Button {
                    if isRunning { launcher.toggleFloat(widget) } else { launcher.open(widget) }
                } label: {
                    VStack(spacing: 3) {
                        Image(nsImage: widget.icon)
                            .resizable()
                            .frame(width: Self.iconSize, height: Self.iconSize)
                        Circle()
                            .fill(isFloating ? AnyShapeStyle(accent)
                                  : isRunning ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.clear))
                            .frame(width: isFloating ? 5 : 4, height: isFloating ? 5 : 4)
                    }
                }
                .buttonStyle(PressStyle())
                .help(!isRunning ? "Open \(widget.name)"
                      : isFloating ? "\(widget.name) floats on top. Click to put it on the desktop."
                      : "\(widget.name) is on the desktop. Click to float it on top.")
                .contextMenu {
                    if isRunning {
                        Button(isFloating ? "Put on Desktop" : "Float on Top") { launcher.toggleFloat(widget) }
                        Button("Show \(widget.name)") { launcher.open(widget) }
                        Divider()
                        Button("Quit \(widget.name)") { launcher.quit(widget) }
                    } else {
                        Button("Open \(widget.name)") { launcher.open(widget) }
                    }
                }
            }
            Divider().frame(height: 30)
            FloatPin()
            Button { collapsed = true } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Fold the bar away to the right")
        }
        .padding(.horizontal, Self.padding)
        .fixedSize()
        // Kept to the right edge, so while the window grows or shrinks from the left
        // the bar slides in and out rather than squashing.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    // Only the middle is a button, so the rim still drags the window.
    private var folded: some View {
        Button { collapsed = false } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help("Open Widget Bar")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Sizes the window to the bar or the folded square, keeping its right edge where it is,
    /// but on screen.
    private func fitWindow(animate: Bool) {
        guard let window = NSApp.windows.first(where: { $0 is DesktopPanel }) else { return }
        let size = collapsed ? Self.collapsedSize : Self.size(for: launcher.widgets.count)
        var frame = window.frame
        frame.origin.x = frame.maxX - size.width
        frame.origin.y = frame.midY - size.height / 2
        frame.size = size
        if let visible = window.screen?.visibleFrame {
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - size.width))
        }
        guard frame != window.frame else { return }
        window.contentMinSize = Self.collapsedSize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.2 : 0
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            window.invalidateShadow()
        }
    }
}

/// Shrinks a little while pressed.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
