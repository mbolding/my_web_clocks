// Dock Load — CPU load and memory pressure in the Dock icon, with no window. The icon
// redraws every two seconds while the app runs; right-click it for the numbers and the
// busiest processes, and click it to open Activity Monitor.

import SwiftUI
import AppKit

@main
enum DockLoadApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = DockLoad()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class DockLoad: NSObject, NSApplicationDelegate {
    private var accent: Accent {
        Accent(rawValue: Accent.defaults.string(forKey: "accent") ?? "") ?? .orange
    }

    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private let sampler = Sampler()
    private var load = Load()
    private var timer: Timer?
    private var accentWatch: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.mainMenu = mainMenu()
        let tile = NSApp.dockTile
        host.frame = NSRect(origin: .zero, size: tile.size)
        tile.contentView = host

        // The first sample only sets the counters going; the CPU reading needs two.
        _ = sampler.sample()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.tick() }

        // Watch the shared accent by key-value observing, as Dock Clock does, to hear
        // another app change it.
        accentWatch = Accent.defaults.observe(\.accent, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.draw() }
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }

    /// A click on the Dock icon opens Activity Monitor, to see what's behind the numbers.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openActivityMonitor()
        return false
    }

    private func tick() {
        load = sampler.sample()
        draw()
    }

    private func draw() {
        host.rootView = AnyView(LoadTile(load: load).environment(\.accent, accent.color))
        NSApp.dockTile.display()
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Menus

    private func mainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Dock Load",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Dock Load", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Dock Load", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(item)
        return menu
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        func note(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
        let gb = { (bytes: UInt64) in (Double(bytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(1))) }

        note("CPU \(percent(load.cpu)): user \(percent(load.user)), system \(percent(load.system))")
        note("Memory pressure \(load.pressure.name), \(percent(load.memoryPressure))")
        note("Memory used \(gb(load.memoryUsed)) of \(gb(load.memoryTotal)) GB")
        menu.addItem(.separator())

        note("Busiest processes")
        for process in Sampler.topProcesses(5) {
            let item = NSMenuItem(title: "\(process.cpu.formatted(.number.precision(.fractionLength(0))))%  \(process.name)",
                                  action: #selector(openActivityMonitor), keyEquivalent: "")
            item.target = self
            item.indentationLevel = 1
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let monitor = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
        monitor.target = self
        menu.addItem(monitor)

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

    @objc private func pickAccent(_ item: NSMenuItem) {
        Accent.defaults.set(item.representedObject as? String, forKey: "accent")
        draw()
    }
}

extension UserDefaults {
    /// The shared accent's key, exposed for key-value observing.
    @objc dynamic var accent: String? { string(forKey: "accent") }
}
