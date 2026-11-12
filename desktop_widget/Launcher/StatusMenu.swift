// StatusMenu — Widget Bar's menu bar item, which lists the widgets so the bar itself can
// stay hidden. Each widget is a row with its icon, a tick while it runs, and a pin in
// place of the tick while it floats on top. A widget that isn't running opens with a
// click; a running one has a submenu to show it, flip Float on Top, or quit it. Below
// them: Show Floating Bar, Update from GitHub, and Quit.

import AppKit

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    static let shared = StatusMenu()
    private static let showBarKey = "showBar"

    private var item: NSStatusItem?
    private var icons: [String: NSImage] = [:] // menu-sized copies, by bundle id

    private var launcher: WidgetLauncher { .shared }

    /// Adds the item to the menu bar, and hides the floating bar unless it was left shown.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Widget Bar")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        setBarShown(UserDefaults.standard.bool(forKey: Self.showBarKey))
    }

    /// Opened again from Finder or with open -a while the bar is hidden: drop the menu
    /// down instead, as the nearest thing to bringing a window up.
    func popUp() {
        item?.button?.performClick(nil)
    }

    private var bar: NSWindow? { NSApp.windows.first { $0 is DesktopPanel } }

    func setBarShown(_ shown: Bool) {
        UserDefaults.standard.set(shown, forKey: Self.showBarKey)
        if shown { bar?.orderFrontRegardless() } else { bar?.orderOut(nil) }
    }

    // MARK: - Building the menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        launcher.refreshWidgets()
        if launcher.widgets.isEmpty {
            menu.addItem(withTitle: "No Widgets Installed", action: nil, keyEquivalent: "")
        }
        for widget in launcher.widgets {
            menu.addItem(row(for: widget))
        }
        menu.addItem(.separator())

        let showBar = NSMenuItem(title: "Show Floating Bar", action: #selector(toggleBar), keyEquivalent: "")
        showBar.target = self
        showBar.state = bar?.isVisible == true ? .on : .off
        menu.addItem(showBar)
        let update = NSMenuItem(title: "Update from GitHub…", action: #selector(update), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Widget Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func row(for widget: Widget) -> NSMenuItem {
        let isRunning = launcher.running.contains(widget.id)
        let isFloating = launcher.floating.contains(widget.id)
        let row = NSMenuItem(title: widget.name, action: nil, keyEquivalent: "")
        row.image = icon(for: widget)
        row.representedObject = widget.id

        guard isRunning else {
            row.action = #selector(open(_:))
            row.target = self
            row.toolTip = "Open \(widget.name)"
            return row
        }
        row.state = .on
        if isFloating {
            row.onStateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Floats on top")
        }

        let submenu = NSMenu()
        func add(_ title: String, _ action: Selector, state: NSControl.StateValue = .off) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = widget.id
            item.state = state
            submenu.addItem(item)
        }
        add("Show \(widget.name)", #selector(open(_:)))
        if !WidgetLauncher.isDrawer(widget) {
            add("Float on Top", #selector(toggleFloat(_:)), state: isFloating ? .on : .off)
        }
        submenu.addItem(.separator())
        add("Quit \(widget.name)", #selector(quit(_:)))
        row.submenu = submenu
        return row
    }

    private func icon(for widget: Widget) -> NSImage {
        if let icon = icons[widget.id] { return icon }
        let icon = widget.icon.copy() as! NSImage
        icon.size = NSSize(width: 18, height: 18)
        icons[widget.id] = icon
        return icon
    }

    // MARK: - Actions

    private func widget(_ sender: NSMenuItem) -> Widget? {
        launcher.widgets.first { $0.id == sender.representedObject as? String }
    }

    @objc private func open(_ sender: NSMenuItem) {
        widget(sender).map(launcher.open)
    }

    @objc private func toggleFloat(_ sender: NSMenuItem) {
        widget(sender).map(launcher.toggleFloat)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        widget(sender).map(launcher.quit)
    }

    @objc private func toggleBar() {
        setBarShown(bar?.isVisible != true)
    }

    @objc private func update() {
        Updater.confirmAndRun()
    }
}
