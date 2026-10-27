// Widget Bar — a small floating toolbar for opening the other desktop widgets.

import SwiftUI

@main
enum WidgetBarApp {
    @MainActor static func main() {
        // Sized for the widgets installed when it starts; it floats on top by default and
        // starts at the bottom of the right-hand column, above the Dock.
        DesktopClock.run(size: LauncherBar.size(for: WidgetLauncher.shared.widgets.count),
                         defaultTop: .greatestFiniteMagnitude, floatsByDefault: true) {
            LauncherBar()
        }
    }
}
