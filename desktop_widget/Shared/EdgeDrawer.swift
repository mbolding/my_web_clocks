// EdgeDrawer — the window the drawer widgets share (Text Drawer, SDF Post): a thin tab in
// the accent colour peeking in from the left, right or bottom edge of the main screen,
// floating above other windows, which slides out into the app's panel. Hover the tab or
// click it to open; move off the panel, click elsewhere or press Esc to close. While
// something is being dragged near the tab it slides out a little to take a drop. Drag the
// tab, or the open drawer's grip along the screen edge, to move it along the edge;
// right-click either for the edge, the app's own options, the accent colour and Quit.
// Each app keeps its own edge and place on it, and starts at a different place so two
// drawers on one edge sit apart.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DrawerEdge: String, CaseIterable, Identifiable {
    case left, right, bottom
    var id: Self { self }
    var name: String { rawValue.capitalized }

    /// The tab lies along the bottom, and the drawer slides up.
    var isBottom: Bool { self == .bottom }
    /// Against the screen edge, within the window.
    var outer: Alignment { switch self { case .left: .leading; case .right: .trailing; case .bottom: .bottom } }
    /// Away from the screen edge: the side of the panel that comes out first.
    var inner: Alignment { switch self { case .left: .trailing; case .right: .leading; case .bottom: .top } }

    /// A rectangle rounded on the corners away from the screen edge.
    func shape(radius r: CGFloat) -> UnevenRoundedRectangle {
        switch self {
        case .left: UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        case .right: UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, style: .continuous)
        case .bottom: UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r, style: .continuous)
        }
    }
}

/// Where the drawer is, for the app's views: they can open or close it, and know when
/// it's open.
@MainActor
final class DrawerState: ObservableObject {
    static let shared = DrawerState()

    enum Phase { case peek, hint, open }
    @Published fileprivate(set) var phase: Phase = .peek
    /// The panel is drawn from the moment it starts opening until it has finished closing.
    @Published fileprivate(set) var showsPanel = false
    fileprivate weak var controller: DrawerController?

    func open(focus: Bool = true) { controller?.open(focus: focus) }
    func close() { controller?.close() }
}

@MainActor
enum EdgeDrawer {
    /// Runs the app; never returns. `position` is where the tab starts along the edge, from
    /// 0 at the top to 1 at the bottom (along the bottom edge, 0 at the left to 1 at the
    /// right). With `stayOpenWhileTyping`, an open drawer that has
    /// the keyboard stays open when the mouse moves off, until you click elsewhere or press
    /// Esc. `dropTypes` and `onDrop` let the tab take a drop while it's peeking out.
    /// `keyDown` sees keys pressed while the drawer has the keyboard, before its views;
    /// return true to take the key.
    static func run<Content: View, Options: View>(panelSize: CGSize,
                                                  position: Double = 0.4,
                                                  stayOpenWhileTyping: Bool = false,
                                                  dropTypes: [UTType] = [],
                                                  onDrop: (([NSItemProvider]) -> Bool)? = nil,
                                                  keyDown: ((NSEvent) -> Bool)? = nil,
                                                  @ViewBuilder content: @escaping () -> Content,
                                                  @ViewBuilder options: @escaping () -> Options) {
        UserDefaults.standard.register(defaults: ["drawerEdge": DrawerEdge.right.rawValue, "drawerPosition": position])
        let app = NSApplication.shared
        let controller = DrawerController(panelSize: panelSize, stayOpenWhileTyping: stayOpenWhileTyping,
                                          keyDown: keyDown) { controller in
            AnyView(DrawerRoot(panelSize: panelSize, dropTypes: dropTypes, onDrop: onDrop,
                               moveTab: { controller.moveTab() }, endMove: { controller.endMove() },
                               content: content(), options: options()))
        }
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - Views

private struct DrawerRoot<Content: View, Options: View>: View {
    @ObservedObject private var state = DrawerState.shared
    @AppStorage("drawerEdge") private var edgeName = DrawerEdge.right.rawValue
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    var panelSize: CGSize
    var dropTypes: [UTType]
    var onDrop: (([NSItemProvider]) -> Bool)?
    var moveTab: () -> Void
    var endMove: () -> Void
    var content: Content
    var options: Options

    private var edge: DrawerEdge { DrawerEdge(rawValue: edgeName) ?? .right }

    var body: some View {
        // The panel is laid out at its full size against the screen edge and clipped by the
        // window, so it slides in from the edge as the window grows.
        ZStack(alignment: edge.inner) {
            if state.showsPanel {
                panel
                    .frame(width: panelSize.width, height: panelSize.height)
            }
            if !state.showsPanel {
                DrawerTab(edge: edge, hint: state.phase == .hint, dropTypes: dropTypes, onDrop: onDrop,
                          moveTab: moveTab, endMove: endMove, options: options)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.inner)
        .clipped()
        .environment(\.accent, accent.color)
    }

    private var panel: some View {
        let shape = edge.shape(radius: 10)
        return content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
            // A strip of the accent along the screen edge, where the tab was.
            .overlay(alignment: edge.outer) {
                Rectangle().fill(accent.color)
                    .frame(width: edge.isBottom ? nil : 3, height: edge.isBottom ? 3 : nil)
            }
            .clipShape(shape)
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
            // The grip: the strip and a little either side of it, to drag the drawer
            // along the edge or right-click for its menu, as on the tab.
            .overlay(alignment: edge.outer) {
                Color.clear
                    .frame(width: edge.isBottom ? nil : 8, height: edge.isBottom ? 8 : nil)
                    .contentShape(Rectangle())
                    .drawerHandle(moveTab: moveTab, endMove: endMove, options: options)
                    .onHover { inside in
                        if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                    }
            }
    }
}

private struct DrawerTab<Options: View>: View {
    var edge: DrawerEdge
    var hint: Bool
    var dropTypes: [UTType]
    var onDrop: (([NSItemProvider]) -> Bool)?
    var moveTab: () -> Void
    var endMove: () -> Void
    var options: Options
    @Environment(\.accent) private var accent
    @State private var targeted = false
    @State private var hoverOpen: DispatchWorkItem?

    var body: some View {
        edge.shape(radius: 6)
            .fill(accent.opacity(targeted ? 1 : hint ? 0.9 : 0.85))
            .overlay {
                if hint {
                    Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent.readableText)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                hoverOpen?.cancel()
                guard inside, !hint else { return }
                // Not while a button is down: that's a drag along the edge starting.
                let work = DispatchWorkItem {
                    if NSEvent.pressedMouseButtons == 0 { DrawerState.shared.open(focus: false) }
                }
                hoverOpen = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
            .onTapGesture {
                hoverOpen?.cancel()
                DrawerState.shared.open()
            }
            .drawerHandle(moveTab: moveTab, endMove: endMove, options: options)
            .onDrop(of: dropTypes, isTargeted: $targeted) { providers in
                onDrop?(providers) ?? false
            }
            .help("Click or hover to open. Drag to move along the edge; right-click for options.")
    }
}

/// Dragging along the edge and the drawer's menu, for the tab and the open drawer's grip.
private struct DrawerHandle<Options: View>: ViewModifier {
    var moveTab: () -> Void
    var endMove: () -> Void
    var options: Options
    @AppStorage("drawerEdge") private var edgeName = DrawerEdge.right.rawValue
    @AppStorage("accent", store: Accent.defaults) private var accentChoice = Accent.orange

    func body(content: Content) -> some View {
        content
            // Ahead of the tab's click, which would otherwise take the press. The window
            // moves under the pointer as it's dragged, so the controller follows the
            // pointer on the screen rather than the gesture's own numbers.
            .highPriorityGesture(DragGesture(minimumDistance: 3)
                .onChanged { _ in moveTab() }
                .onEnded { _ in endMove() })
            .contextMenu {
                options
                Picker("Edge", selection: $edgeName) {
                    ForEach(DrawerEdge.allCases) { Text($0.name).tag($0.rawValue) }
                }
                Picker("Accent Color", selection: $accentChoice) {
                    ForEach(Accent.allCases) { accent in
                        Label { Text(accent.name) } icon: { Image(nsImage: accent.swatch) }
                            .tag(accent)
                    }
                }
                Divider()
                Button("Quit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Drawer")") {
                    NSApp.terminate(nil)
                }
            }
    }
}

private extension View {
    func drawerHandle<Options: View>(moveTab: @escaping () -> Void, endMove: @escaping () -> Void,
                                     options: Options) -> some View {
        modifier(DrawerHandle(moveTab: moveTab, endMove: endMove, options: options))
    }
}

// MARK: - Window

/// Takes the first click even while the drawer isn't the key window, as it never is until
/// clicked, so a press on the tab can start a drag along the edge straight away.
private final class FirstMouseHostingView<Root: View>: NSHostingView<Root> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class DrawerController: NSObject, NSApplicationDelegate {
    static let peekWidth: CGFloat = 7
    static let hintWidth: CGFloat = 44
    static let tabLength: CGFloat = 96

    private let panelSize: CGSize
    private let stayOpenWhileTyping: Bool
    private let keyDown: ((NSEvent) -> Bool)?
    private let makeContent: (DrawerController) -> AnyView
    private var panel: DesktopPanel!
    private var monitors: [Any] = []
    private var closeTimer: Timer?
    private var outsideSince: Date?
    private var menuOpen = false
    private var dragCount = 0 // the drag pasteboard's change count when the mouse went down
    private var defaultsWatch: NSObjectProtocol?
    private var lastEdge = ""

    private let state = DrawerState.shared
    private var defaults: UserDefaults { .standard }
    private var edge: DrawerEdge { DrawerEdge(rawValue: defaults.string(forKey: "drawerEdge") ?? "") ?? .right }

    init(panelSize: CGSize, stayOpenWhileTyping: Bool, keyDown: ((NSEvent) -> Bool)?,
         makeContent: @escaping (DrawerController) -> AnyView) {
        self.panelSize = panelSize
        self.stayOpenWhileTyping = stayOpenWhileTyping
        self.keyDown = keyDown
        self.makeContent = makeContent
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        state.controller = self
        panel = DesktopPanel(contentRect: frame(for: .peek), styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.acceptsKeyboard = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.contentView = FirstMouseHostingView(rootView: makeContent(self))
        panel.orderFrontRegardless()
        lastEdge = edge.rawValue

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place(animated: false) }
        }
        defaultsWatch = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.edge.rawValue != self.lastEdge else { return }
                self.lastEdge = self.edge.rawValue
                self.place(animated: false)
            }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuOpen = true }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuOpen = false }
        }
        watchMouse()
    }

    /// Opened again while running (Widget Bar, Finder, open -a): slide out.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        open(focus: true)
        return false
    }

    // MARK: Opening and closing

    func open(focus: Bool) {
        if focus { panel.makeKey() }
        guard state.phase != .open else { return }
        state.showsPanel = true
        state.phase = .open
        outsideSince = nil
        place(animated: true)
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMouse() }
        }
    }

    func close() {
        guard state.phase == .open else { return }
        closeTimer?.invalidate()
        closeTimer = nil
        state.phase = .peek
        if panel.isKeyWindow { panel.resignKey() }
        place(animated: true) { [weak self] in
            guard let self, self.state.phase != .open else { return }
            self.state.showsPanel = false
        }
    }

    private func setHint(_ on: Bool) {
        guard state.phase != .open, (state.phase == .hint) != on else { return }
        state.phase = on ? .hint : .peek
        place(animated: true)
    }

    /// Closes an open drawer once the mouse has been off it for a moment, unless a menu is
    /// up, or it has the keyboard and is meant to stay open while you type.
    private func checkMouse() {
        guard state.phase == .open else { return }
        let inside = panel.frame.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation)
        if inside || menuOpen || (stayOpenWhileTyping && panel.isKeyWindow) || NSEvent.pressedMouseButtons != 0 {
            outsideSince = nil
            return
        }
        if let since = outsideSince {
            if Date.now.timeIntervalSince(since) > 0.5 { close() }
        } else {
            outsideSince = .now
        }
    }

    private func watchMouse() {
        // Clicks and drags going to other apps: a click elsewhere closes the drawer, and a
        // drag (the drag pasteboard changes once one has begun) near the tab brings it out.
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.otherAppMouse(event) }
        }
        if let global { monitors.append(global) }
        // Keys while the drawer has the keyboard: Esc closes, the rest go to the app first.
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.keyCode == 53 { self.close(); return nil }
            if self.keyDown?(event) == true { return nil }
            return MainActor.assumeIsolated { Self.editKey(event) } ? nil : event
        }
        if let keys { monitors.append(keys) }
    }

    /// The edit keys. With no Edit menu (the app has no menu bar) nothing sends ⌘V and the
    /// rest to the text being typed in, so send them here.
    private static func editKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods == [.command, .shift], key == "z" { return NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
        guard mods == .command else { return false }
        let actions: [String: Selector] = ["x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
                                           "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
                                           "z": Selector(("undo:"))]
        guard let action = actions[key] else { return false }
        return NSApp.sendAction(action, to: nil, from: nil)
    }

    private func otherAppMouse(_ event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            dragCount = NSPasteboard(name: .drag).changeCount
            if state.phase == .open, !panel.frame.contains(mouse) { close() }
        case .leftMouseDragged:
            guard state.phase != .open, NSPasteboard(name: .drag).changeCount != dragCount else { return }
            setHint(nearTab(mouse))
        case .leftMouseUp:
            if state.phase == .hint {
                // Give a drop on the tab a moment to land before it tucks back in.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.setHint(false) }
            }
        default:
            break
        }
    }

    private func nearTab(_ point: NSPoint) -> Bool {
        let tab = frame(for: .peek)
        let reach: NSRect
        switch edge {
        case .left: reach = NSRect(x: tab.minX, y: tab.minY - 50, width: 120, height: tab.height + 100)
        case .right: reach = NSRect(x: tab.maxX - 120, y: tab.minY - 50, width: 120, height: tab.height + 100)
        case .bottom: reach = NSRect(x: tab.minX - 50, y: tab.minY, width: tab.width + 100, height: 120)
        }
        return reach.contains(point)
    }

    // MARK: Moving the tab

    private var moveStart: (mouse: CGFloat, position: Double)?

    /// Follows the pointer along the edge while the tab or grip is dragged.
    func moveTab() {
        guard let v = screen?.visibleFrame else { return }
        // Along the bottom the position counts from the left; up a side, down from the top.
        let mouse = edge.isBottom ? NSEvent.mouseLocation.x : -NSEvent.mouseLocation.y
        let start = moveStart ?? (mouse, defaults.double(forKey: "drawerPosition"))
        moveStart = start
        let range = max(1, (edge.isBottom ? v.width : v.height) - Self.tabLength)
        let p = start.position + Double((mouse - start.mouse) / range)
        defaults.set(min(1, max(0, p)), forKey: "drawerPosition")
        place(animated: false)
    }

    func endMove() { moveStart = nil }

    // MARK: Frames

    private var screen: NSScreen? { NSScreen.screens.first ?? NSScreen.main }

    /// The tab's centre on the edge, from the saved position: a y up a side, an x along the
    /// bottom.
    private func tabCentre(in v: NSRect) -> CGFloat {
        let p = CGFloat(defaults.double(forKey: "drawerPosition"))
        return edge.isBottom
            ? v.minX + Self.tabLength / 2 + p * max(0, v.width - Self.tabLength)
            : v.maxY - Self.tabLength / 2 - p * max(0, v.height - Self.tabLength)
    }

    private func frame(for phase: DrawerState.Phase) -> NSRect {
        guard let v = screen?.visibleFrame else { return .zero }
        let centre = tabCentre(in: v)
        // How far it comes out from the edge, and how long it is along it.
        let depth: CGFloat, length: CGFloat
        switch phase {
        case .peek: (depth, length) = (Self.peekWidth, Self.tabLength)
        case .hint: (depth, length) = (Self.hintWidth, Self.tabLength)
        case .open: (depth, length) = edge.isBottom ? (panelSize.height, panelSize.width) : (panelSize.width, panelSize.height)
        }
        switch edge {
        case .bottom:
            let x = min(max(v.minX, centre - length / 2), v.maxX - length)
            return NSRect(x: x, y: v.minY, width: length, height: depth)
        case .left, .right:
            let y = min(max(v.minY, centre - length / 2), v.maxY - length)
            let x = edge == .left ? v.minX : v.maxX - depth
            return NSRect(x: x, y: y, width: depth, height: length)
        }
    }

    private func place(animated: Bool, then done: (() -> Void)? = nil) {
        guard let panel else { return }
        let target = frame(for: state.phase)
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(target, display: true)
            done?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.invalidateShadow()
                done?()
            }
        })
    }
}
