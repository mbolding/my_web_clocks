// DesktopClock — the floating window every clock here shares.
// Borderless, translucent, just above the desktop icons (or above every window with
// Float on Top), on every Space. Drag to move (position is remembered). Right-click
// for the clock's own options, Float on Top, and Quit.
// An interactive window (the command bar) also takes typing, resizes from its edges,
// and floats on top unless turned off. An app given `onOpen` receives files and folders
// opened with it (open -a, Open With) or sent from its Finder service, if its
// Info.plist declares them.

import SwiftUI
import AppKit

@MainActor
enum DesktopClock {
    /// Runs the app; never returns. `defaultTop` is the gap above the window on first
    /// launch, so clocks that share the top-right corner don't start out stacked.
    static func run<Face: View, Options: View>(size: CGSize, defaultTop: CGFloat = 24,
                                               interactive: Bool = false,
                                               onOpen: (([URL]) -> Void)? = nil,
                                               @ViewBuilder face: @escaping () -> Face,
                                               @ViewBuilder options: @escaping () -> Options) {
        // Registered once here, so the menu and any FloatPin agree on the default.
        UserDefaults.standard.register(defaults: ["floatOnTop": interactive])
        let app = NSApplication.shared
        let delegate = DesktopClockDelegate(size: size, defaultTop: defaultTop, interactive: interactive,
                                            onOpen: onOpen) { setFloatOnTop in
            AnyView(ClockMenu(setFloatOnTop: setFloatOnTop, face: face(), options: options()))
        }
        app.delegate = delegate
        app.servicesProvider = delegate
        app.setActivationPolicy(.accessory) // no Dock icon, no menu bar
        app.run()
    }

    static func run<Face: View>(size: CGSize, defaultTop: CGFloat = 24, interactive: Bool = false,
                                onOpen: (([URL]) -> Void)? = nil,
                                @ViewBuilder face: @escaping () -> Face) {
        run(size: size, defaultTop: defaultTop, interactive: interactive, onOpen: onOpen, face: face) { EmptyView() }
    }
}

struct ClockMenu<Face: View, Options: View>: View {
    @AppStorage("floatOnTop") private var floatOnTop = false // default registered in run
    var setFloatOnTop: (Bool) -> Void
    var face: Face
    var options: Options

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

/// A small pin a window can show: filled orange while it floats on top, a faint
/// crossed-out pin while it sits on the desktop. Click to toggle; it shares the menu's
/// Float on Top setting.
struct FloatPin: View {
    @AppStorage("floatOnTop") private var floatOnTop = false // default registered in run

    var body: some View {
        Button { floatOnTop.toggle() } label: {
            Image(systemName: floatOnTop ? "pin.fill" : "pin.slash")
                .font(.system(size: 9))
                .foregroundStyle(floatOnTop ? AnyShapeStyle(Color.orange.opacity(0.7)) : AnyShapeStyle(.tertiary))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(floatOnTop ? "Floating on top of other windows. Click to stop."
                         : "Sitting on the desktop, behind other windows. Click to float on top.")
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
    private let onOpen: (([URL]) -> Void)?
    private let makeContent: (@escaping (Bool) -> Void) -> AnyView
    private var panel: DesktopPanel!

    init(size: CGSize, defaultTop: CGFloat, interactive: Bool, onOpen: (([URL]) -> Void)?,
         makeContent: @escaping (@escaping (Bool) -> Void) -> AnyView) {
        self.size = size
        self.defaultTop = defaultTop
        self.interactive = interactive
        self.onOpen = onOpen
        self.makeContent = makeContent
    }

    // open -a, Open With, or dropping onto the app's icon. At launch this can arrive
    // before applicationDidFinishLaunching, so there may be no panel yet.
    func application(_ application: NSApplication, open urls: [URL]) {
        open(urls)
    }

    /// The Finder service: NSServices in Info.plist names this method (NSMessage openURLs).
    @objc func openURLs(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        open(pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
    }

    private func open(_ urls: [URL]) {
        guard let onOpen, !urls.isEmpty else { return }
        onOpen(urls)
        panel?.orderFrontRegardless()
        panel?.makeKey()
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
