// DesktopClock — the floating window every clock here shares.
// Borderless, translucent, just above the desktop icons (or above every window with
// Float on Top), on every Space. Drag to move (position is remembered). Right-click
// for the clock's own options, Float on Top, and Quit.
// An interactive window (the command bar) also takes typing, resizes from its edges,
// and floats on top unless turned off.

import SwiftUI
import AppKit

@MainActor
enum DesktopClock {
    /// Runs the app; never returns. `defaultTop` is the gap above the window on first
    /// launch, so clocks that share the top-right corner don't start out stacked.
    static func run<Face: View, Options: View>(size: CGSize, defaultTop: CGFloat = 24,
                                               interactive: Bool = false,
                                               @ViewBuilder face: @escaping () -> Face,
                                               @ViewBuilder options: @escaping () -> Options) {
        let app = NSApplication.shared
        let delegate = DesktopClockDelegate(size: size, defaultTop: defaultTop, interactive: interactive) { setFloatOnTop in
            AnyView(ClockMenu(floatsByDefault: interactive, setFloatOnTop: setFloatOnTop,
                              face: face(), options: options()))
        }
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon, no menu bar
        app.run()
    }

    static func run<Face: View>(size: CGSize, defaultTop: CGFloat = 24, interactive: Bool = false,
                                @ViewBuilder face: @escaping () -> Face) {
        run(size: size, defaultTop: defaultTop, interactive: interactive, face: face) { EmptyView() }
    }
}

struct ClockMenu<Face: View, Options: View>: View {
    @AppStorage private var floatOnTop: Bool
    var setFloatOnTop: (Bool) -> Void
    var face: Face
    var options: Options

    init(floatsByDefault: Bool, setFloatOnTop: @escaping (Bool) -> Void, face: Face, options: Options) {
        _floatOnTop = AppStorage(wrappedValue: floatsByDefault, "floatOnTop")
        self.setFloatOnTop = setFloatOnTop
        self.face = face
        self.options = options
    }

    var body: some View {
        face
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()) // right-click anywhere, not just on the drawn marks
            .onChange(of: floatOnTop, initial: true) { setFloatOnTop(floatOnTop) }
            .contextMenu {
                options
                Toggle("Float on Top", isOn: $floatOnTop)
                Divider()
                Button("Quit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Clock")") {
                    NSApp.terminate(nil)
                }
            }
    }
}

// MARK: - Desktop window

final class DesktopPanel: NSPanel {
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}

final class DesktopClockDelegate: NSObject, NSApplicationDelegate {
    private let size: CGSize
    private let defaultTop: CGFloat
    private let interactive: Bool
    private let makeContent: (@escaping (Bool) -> Void) -> AnyView
    private var panel: DesktopPanel!

    init(size: CGSize, defaultTop: CGFloat, interactive: Bool,
         makeContent: @escaping (@escaping (Bool) -> Void) -> AnyView) {
        self.size = size
        self.defaultTop = defaultTop
        self.interactive = interactive
        self.makeContent = makeContent
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let corner: CGFloat = 24

        // Non-activating, so typing into it doesn't pull focus from the app you were in.
        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if interactive { style.insert(.resizable) }
        panel = DesktopPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: style, backing: .buffered, defer: false)
        panel.acceptsKeyboard = interactive
        panel.contentMinSize = interactive ? NSSize(width: 260, height: 140) : size
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
        let host = NSHostingView(rootView: makeContent { [weak self] onTop in
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
        let autosaveName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "Clock"
        if !panel.setFrameUsingName(autosaveName), let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - size.width - 24, y: v.maxY - size.height - defaultTop))
        }
        panel.setFrameAutosaveName(autosaveName)
        panel.orderFrontRegardless()
    }
}

extension NSImage {
    func with(_ configure: (NSImage) -> Void) -> NSImage { configure(self); return self }
}
