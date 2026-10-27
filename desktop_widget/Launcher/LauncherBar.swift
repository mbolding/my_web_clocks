// LauncherBar — Widget Bar's window: a row of widget icons with a dot under each one
// that's running, orange if it floats on top. Click to open a widget, or to flip a
// running one's Float on Top; right-click an icon to show it for a moment or quit it.

import SwiftUI

struct LauncherBar: View {
    static let iconSize: CGFloat = 36, spacing: CGFloat = 10, padding: CGFloat = 14

    /// The window's size for `count` icons, plus the divider and pin at the end.
    static func size(for count: Int) -> CGSize {
        guard count > 0 else { return CGSize(width: 240, height: 62) }
        let icons = CGFloat(count) * iconSize + CGFloat(count - 1) * spacing
        return CGSize(width: padding * 2 + icons + spacing * 2 + 1 + 14, height: 62)
    }

    @ObservedObject var launcher = WidgetLauncher.shared

    var body: some View {
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
                            .fill(isFloating ? AnyShapeStyle(Color.orange)
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
        }
        .padding(.horizontal, Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
