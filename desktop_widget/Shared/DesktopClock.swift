// DesktopClock — the floating window every clock here shares.
// Borderless, translucent, just above the desktop icons (or above every window with
// Float on Top), on every Space. Drag to move (position is remembered). Right-click
// for the clock's own options, the accent colour all the widgets share, Float on Top,
// and Quit. ⌘-click or force click anywhere flips Float on Top, and a brief label says
// which it is now. An interactive window (the command bar) also takes typing, resizes
// from its edges, and floats on top unless turned off. An app given `onOpen` receives
// files and folders opened with it (open -a, Open With) or sent from its Finder service,
// if its Info.plist declares them. A round window is cut to a circle; one whose face has
// gestures of its own turns off dragging by the background and uses MovesWindow on the
// parts that should move it instead.

import SwiftUI
import AppKit

@MainActor
enum DesktopClock {
    /// Runs the app; never returns. `defaultTop` and `defaultRight` are the gaps above and
    /// to the right of the window on first launch, so clocks that share the top-right
    /// corner don't start out stacked.
    static func run<Face: View, Options: View>(size: CGSize, defaultTop: CGFloat = 24,
                                               defaultRight: CGFloat = 24,
                                               interactive: Bool = false,
                                               round: Bool = false,
                                               movableByBackground: Bool = true,
                                               floatsByDefault: Bool? = nil, // nil: only if interactive
                                               onOpen: (([URL]) -> Void)? = nil,
                                               @ViewBuilder face: @escaping () -> Face,
                                               @ViewBuilder options: @escaping () -> Options) {
        // Registered once here, so the menu and any FloatPin agree on the default.
        UserDefaults.standard.register(defaults: ["floatOnTop": floatsByDefault ?? interactive])
        let app = NSApplication.shared
        let delegate = DesktopClockDelegate(size: size, defaultTop: defaultTop, defaultRight: defaultRight,
                                            interactive: interactive,
                                            round: round, movableByBackground: movableByBackground,
                                            onOpen: onOpen) { setFloatOnTop in
            AnyView(ClockMenu(round: round, setFloatOnTop: setFloatOnTop, face: face(), options: options()))
        }
        app.delegate = delegate
        app.servicesProvider = delegate
        app.setActivationPolicy(.accessory) // no Dock icon, no menu bar
        app.run()
    }

    static func run<Face: View>(size: CGSize, defaultTop: CGFloat = 24, defaultRight: CGFloat = 24,
                                interactive: Bool = false,
                                round: Bool = false, movableByBackground: Bool = true,
                                floatsByDefault: Bool? = nil, onOpen: (([URL]) -> Void)? = nil,
                                @ViewBuilder face: @escaping () -> Face) {
        run(size: size, defaultTop: defaultTop, defaultRight: defaultRight, interactive: interactive, round: round,
            movableByBackground: movableByBackground, floatsByDefault: floatsByDefault,
            onOpen: onOpen, face: face) { EmptyView() }
    }
}

struct ClockMenu<Face: View, Options: View>: View {
    @AppStorage("floatOnTop") private var floatOnTop = false // default registered in run
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    var round: Bool
    var setFloatOnTop: (Bool) -> Void
    var face: Face
    var options: Options
    // A brief label after Float on Top changes, however it was changed, since most of the
    // windows have no pin to show it. Each change gets a new number, so only the latest
    // one's timer hides it.
    @State private var levelNote: (onTop: Bool, number: Int)?

    var body: some View {
        face
            .environment(\.accent, accent.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let levelNote {
                    Label(levelNote.onTop ? "Floating on top" : "On the desktop",
                          systemImage: levelNote.onTop ? "pin.fill" : "pin.slash")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thickMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            // Right-click anywhere on the window, not just on the drawn marks.
            .contentShape(round ? AnyShape(Circle()) : AnyShape(Rectangle()))
            .onChange(of: floatOnTop, initial: true) { setFloatOnTop(floatOnTop) }
            .onChange(of: floatOnTop) {
                let number = (levelNote?.number ?? 0) + 1
                withAnimation(.easeOut(duration: 0.15)) { levelNote = (floatOnTop, number) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    if levelNote?.number == number { withAnimation(.easeIn(duration: 0.3)) { levelNote = nil } }
                }
            }
            .contextMenu {
                options
                Picker("Accent Color", selection: $accent) {
                    ForEach(Accent.allCases) { accent in
                        Label { Text(accent.name) } icon: { Image(nsImage: accent.swatch) }
                            .tag(accent)
                    }
                }
                Toggle("Float on Top", isOn: $floatOnTop)
                Divider()
                Button("Quit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Clock")") {
                    NSApp.terminate(nil)
                }
            }
    }
}

/// A small pin a window can show: filled in the accent colour while it floats on top, a
/// faint crossed-out pin while it sits on the desktop. Click to toggle; it shares the
/// menu's Float on Top setting.
struct FloatPin: View {
    @AppStorage("floatOnTop") private var floatOnTop = false // default registered in run
    @Environment(\.accent) private var accent

    var body: some View {
        Button { floatOnTop.toggle() } label: {
            Image(systemName: floatOnTop ? "pin.fill" : "pin.slash")
                .font(.system(size: 9))
                .foregroundStyle(floatOnTop ? AnyShapeStyle(accent.opacity(0.7)) : AnyShapeStyle(.tertiary))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(floatOnTop ? "Floating on top of other windows. Click to stop."
                         : "Sitting on the desktop, behind other windows. Click to float on top.")
    }
}

/// Drags the window by hand, following the mouse in screen coordinates, for windows run
/// with movableByBackground: false. Put it on the parts that should move the window.
struct MovesWindow: ViewModifier {
    @State private var grab: CGPoint? // mouse position within the window when the drag began

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    guard let window = NSApp.windows.first(where: { $0 is DesktopPanel }) else { return }
                    let mouse = NSEvent.mouseLocation
                    let grab = grab ?? CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
                    self.grab = grab
                    window.setFrameOrigin(NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
                }
                .onEnded { _ in grab = nil }
        )
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
    private let defaultRight: CGFloat
    private let interactive: Bool
    private let round: Bool
    private let movableByBackground: Bool
    private let onOpen: (([URL]) -> Void)?
    private let makeContent: (@escaping (Bool) -> Void) -> AnyView
    private var panel: DesktopPanel!
    private var clickMonitor: Any?

    init(size: CGSize, defaultTop: CGFloat, defaultRight: CGFloat, interactive: Bool, round: Bool,
         movableByBackground: Bool, onOpen: (([URL]) -> Void)?,
         makeContent: @escaping (@escaping (Bool) -> Void) -> AnyView) {
        self.size = size
        self.defaultTop = defaultTop
        self.defaultRight = defaultRight
        self.interactive = interactive
        self.round = round
        self.movableByBackground = movableByBackground
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

    /// Opened again while running (Widget Bar, Finder, open -a): a window on the desktop
    /// comes up above the other windows for a few seconds so it can be found.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard let panel else { return false }
        panel.orderFrontRegardless()
        if panel.level != .floating {
            panel.level = .floating
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.panel.level = UserDefaults.standard.bool(forKey: "floatOnTop") ? .floating : Self.desktopLevel
            }
        }
        return false
    }

    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

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
        panel.isMovableByWindowBackground = movableByBackground

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        if round {
            // Drawn at the window's own size; round windows don't resize.
            blur.maskImage = NSImage(size: size, flipped: false) { rect in
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
        } else {
            blur.maskImage = NSImage(size: NSSize(width: corner * 2 + 1, height: corner * 2 + 1), flipped: false) { rect in
                NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
                return true
            }.with { $0.capInsets = NSEdgeInsets(top: corner, left: corner, bottom: corner, right: corner) }
        }

        // Just above the desktop icons, or above every normal window when floating.
        // The setting is also written out explicitly, even when it's only the registered
        // default, so Widget Bar (another process, which can't see this app's registered
        // defaults) reads the real value; it toggles it by writing to this app's domain.
        let host = NSHostingView(rootView: makeContent { [weak self] onTop in
            self?.panel.level = onTop ? .floating : Self.desktopLevel
            UserDefaults.standard.set(onTop, forKey: "floatOnTop")
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

        // Default to the top-right corner, stepped in by defaultRight and down by defaultTop
        // but never off a smaller screen; afterwards restore wherever it was dragged.
        let autosaveName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "Clock"
        if !panel.setFrameUsingName(autosaveName), let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: max(v.minX + 24, v.maxX - size.width - defaultRight),
                                         y: max(v.minY + 24, v.maxY - size.height - defaultTop)))
        }
        panel.setFrameAutosaveName(autosaveName)
        panel.orderFrontRegardless()
        // The shadow follows the drawn shape, which only exists once the content has drawn.
        DispatchQueue.main.async { [panel] in panel?.invalidateShadow() }

        // ⌘-click anywhere on the window flips Float on Top, before the face sees the
        // click, and so does a force click on a trackpad, once the press deepens. That
        // click began as an ordinary one, so its mouse-up is moved far off the window,
        // where a button it pressed lets go without acting. The menu and any pin follow
        // the setting, and set the window's level.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .pressure, .leftMouseUp]) { [weak self] event in
            guard let self, let panel, event.window === panel else { return event }
            switch event.type {
            case .leftMouseDown where event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command:
                flipFloatOnTop()
                return nil
            case .pressure:
                // A press sends a stream of these; act once, as it first reaches stage 2.
                defer { pressStage = event.stage }
                guard event.stage == 2, pressStage < 2 else { return event }
                forceClicked = true
                flipFloatOnTop()
                return nil
            case .leftMouseUp where forceClicked:
                forceClicked = false
                return NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000),
                                          modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                                          windowNumber: event.windowNumber, context: nil,
                                          eventNumber: event.eventNumber, clickCount: event.clickCount,
                                          pressure: 0)
            default:
                return event
            }
        }
    }

    private var forceClicked = false
    private var pressStage = 0

    private func flipFloatOnTop() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "floatOnTop"), forKey: "floatOnTop")
    }
}

extension NSImage {
    func with(_ configure: (NSImage) -> Void) -> NSImage { configure(self); return self }
}
