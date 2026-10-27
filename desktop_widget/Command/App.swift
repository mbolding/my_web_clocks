// Command Bar — a small floating shell you can type into and drop folders onto.

import SwiftUI

@main
enum CommandBarApp {
    @MainActor static func main() {
        // Starts below the two clocks, and floats on top until turned off.
        DesktopClock.run(size: CGSize(width: 420, height: 260), defaultTop: 24 + 170 + 20 + 250 + 20,
                         interactive: true) {
            CommandBar()
        } options: {
            Button("Clear Output") { CommandSession.shared.clear() }
            Button("Open Folder in Finder") { CommandSession.shared.revealFolder() }
            Divider()
        }
    }
}
