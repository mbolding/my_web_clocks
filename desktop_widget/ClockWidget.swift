// ClockWidget — a small analog clock that sits on the macOS desktop.
// Borderless, translucent, below all normal windows, on every Space.
// Drag to move (position is remembered). Right-click for options.

import SwiftUI
import AppKit

struct WidgetView: View {
    @AppStorage("showSeconds") private var showSeconds = true
    @AppStorage("floatOnTop") private var floatOnTop = false
    var setFloatOnTop: (Bool) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: showSeconds ? 1 : 15)) { timeline in
            ClockFace(date: timeline.date, showSeconds: showSeconds)
                .padding(14)
        }
        .onChange(of: floatOnTop, initial: true) { setFloatOnTop(floatOnTop) }
        .contextMenu {
            Toggle("Show Seconds", isOn: $showSeconds)
            Toggle("Float on Top", isOn: $floatOnTop)
            Divider()
            Button("Quit Clock Widget") { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Desktop window

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: DesktopPanel!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon, no menu bar
        app.run()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let size: CGFloat = 170
        let corner: CGFloat = 24

        panel = DesktopPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = NSImage(size: NSSize(width: corner * 2 + 1, height: corner * 2 + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
            return true
        }.with { $0.capInsets = NSEdgeInsets(top: corner, left: corner, bottom: corner, right: corner) }

        // Just above the desktop icons, or above every normal window when floating.
        let host = NSHostingView(rootView: WidgetView { [weak self] onTop in
            self?.panel.level = onTop ? .floating
                : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        })
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur

        // Default to the top-right corner; afterwards restore wherever it was dragged.
        if !panel.setFrameUsingName("ClockWidget"), let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - size - 24, y: v.maxY - size - 24))
        }
        panel.setFrameAutosaveName("ClockWidget")
        panel.orderFrontRegardless()
    }
}

extension NSImage {
    func with(_ configure: (NSImage) -> Void) -> NSImage { configure(self); return self }
}
