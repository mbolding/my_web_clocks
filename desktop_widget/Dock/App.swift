// Dock Clock — an analog clock that lives in its Dock icon. There's no window: the app
// draws the dial into its Dock tile once a second (or minute, without the second hand)
// while it runs. Right-click the icon for Show Seconds and the shared accent colour.

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

    private var accent: Accent {
        Accent(rawValue: Accent.defaults.string(forKey: "accent") ?? "") ?? .orange
    }

    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.mainMenu = mainMenu()
        let tile = NSApp.dockTile
        host.frame = NSRect(origin: .zero, size: tile.size)
        tile.contentView = host
        schedule()
        // Another widget changing the accent shows on the next tick anyway; this makes it
        // immediate.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: Accent.defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.draw() }
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
        host.rootView = AnyView(DockTile(date: .now, showSeconds: showSeconds)
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

    @objc private func pickAccent(_ item: NSMenuItem) {
        Accent.defaults.set(item.representedObject as? String, forKey: "accent")
        draw()
    }
}
