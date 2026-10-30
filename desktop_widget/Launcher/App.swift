// Widget Bar — a small floating toolbar for opening the other desktop widgets.

import SwiftUI

@main
enum WidgetBarApp {
    @MainActor static func main() {
        // Sized for the widgets installed when it starts, or folded away if it was left that
        // way; it floats on top by default and starts at the bottom of the right-hand
        // column, above the Dock.
        let folded = UserDefaults.standard.bool(forKey: "collapsed")
        DesktopClock.run(size: folded ? LauncherBar.collapsedSize : LauncherBar.size(for: WidgetLauncher.shared.widgets.count),
                         defaultTop: .greatestFiniteMagnitude, floatsByDefault: true) {
            LauncherBar()
        } options: {
            Button("Update from GitHub…") { Updater.confirmAndRun() }
            Divider()
        }
    }
}
