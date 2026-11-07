// Widget Bar — a menu bar item for opening the other desktop widgets, with a small
// floating toolbar of them that can be shown as well.

import SwiftUI

@main
enum WidgetBarApp {
    @MainActor static func main() {
        // Sized for the widgets installed when it starts, or folded away if it was left that
        // way; it floats on top by default and starts at the bottom of the right-hand
        // column, above the Dock. It stays hidden unless Show Floating Bar is on.
        let folded = UserDefaults.standard.bool(forKey: "collapsed")
        DesktopClock.run(size: folded ? LauncherBar.collapsedSize : LauncherBar.size(for: WidgetLauncher.shared.widgets.count),
                         defaultTop: .greatestFiniteMagnitude, floatsByDefault: true,
                         onLaunch: { StatusMenu.shared.install() },
                         onReopenWhileHidden: { StatusMenu.shared.popUp() }) {
            LauncherBar()
        } options: {
            Button("Update from GitHub…") { Updater.confirmAndRun() }
            Button("Hide Floating Bar") { StatusMenu.shared.setBarShown(false) }
            Divider()
        }
    }
}
