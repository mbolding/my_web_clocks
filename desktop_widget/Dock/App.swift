// Dock Clock — a clock that lives in its Dock icon. There's no window: the app draws an
// analog dial or the digital time into its Dock tile once a second (or minute, without
// seconds) while it runs. Right-click the icon for Analog or Digital, Show Seconds and
// the shared accent colour.

import SwiftUI
import AppKit

@main
enum DockClockApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = DockClock()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class DockClock: NSObject, NSApplicationDelegate {
    private var showSeconds: Bool {
        get { UserDefaults.standard.object(forKey: "showSeconds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showSeconds"); schedule() }
    }

    private var face: DockFace {
        get { DockFace(rawValue: UserDefaults.standard.string(forKey: "face") ?? "") ?? .analog }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "face"); draw() }
    }

    private var accent: Accent {
        Accent(rawValue: Accent.defaults.string(forKey: "accent") ?? "") ?? .orange
    }

    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var timer: Timer?
    private var accentWatch: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.mainMenu = mainMenu()
        let tile = NSApp.dockTile
        host.frame = NSRect(origin: .zero, size: tile.size)
        tile.contentView = host
        schedule()
        // Watch the shared accent by key-value observing, as @AppStorage does in the
        // widgets: that's what hears another process change it, where reading the
        // defaults on each tick only sees this process's cached value.
        accentWatch = Accent.defaults.observe(\.accent, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.draw() }
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }

    /// Ticks on the second (or minute), so the hand moves when the system clock does.
    private func schedule() {
        timer?.invalidate()
        draw()
        let step: TimeInterval = showSeconds ? 1 : 60
        let now = Date().timeIntervalSinceReferenceDate
        let next = Date(timeIntervalSinceReferenceDate: (now / step).rounded(.down) * step + step)
        let t = Timer(fire: next, interval: step, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.draw() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func draw() {
        host.rootView = AnyView(DockTile(date: .now, showSeconds: showSeconds, face: face)
            .environment(\.accent, accent.color))
        NSApp.dockTile.display()
    }

    // MARK: Menus

    private func mainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Dock Clock",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Dock Clock", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Dock Clock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(item)
        return menu
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for f in DockFace.allCases {
            let item = NSMenuItem(title: f.name, action: #selector(pickFace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = f.rawValue
            item.state = f == face ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let seconds = NSMenuItem(title: "Show Seconds", action: #selector(toggleSeconds), keyEquivalent: "")
        seconds.target = self
        seconds.state = showSeconds ? .on : .off
        menu.addItem(seconds)

        let colors = NSMenu()
        for a in Accent.allCases {
            let item = NSMenuItem(title: a.name, action: #selector(pickAccent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = a.rawValue
            item.image = a.swatch
            item.state = a == accent ? .on : .off
            colors.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Accent Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colors
        menu.addItem(colorItem)
        return menu
    }

    @objc private func toggleSeconds() { showSeconds.toggle() }

    @objc private func pickFace(_ item: NSMenuItem) {
        if let f = DockFace(rawValue: item.representedObject as? String ?? "") { face = f }
    }

    @objc private func pickAccent(_ item: NSMenuItem) {
        Accent.defaults.set(item.representedObject as? String, forKey: "accent")
        draw()
    }
}

extension UserDefaults {
    /// The shared accent's key, exposed for key-value observing.
    @objc dynamic var accent: String? { string(forKey: "accent") }
}
