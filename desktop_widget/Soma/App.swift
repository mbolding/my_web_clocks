// Soma Player — a small SomaFM radio, as a floating window or, in drawer mode, as a tab at
// the edge of the screen that slides out to the player, like Text Drawer. The right-click
// menu switches between the two; the app starts again in the other, still playing.

import SwiftUI

@main
enum SomaPlayerApp {
    @MainActor static func main() {
        if PlayerMode.isDrawer {
            // Low on the edge, below Text Drawer's and SDF Post's tabs.
            EdgeDrawer.run(panelSize: CGSize(width: 330, height: 108), position: 0.85) {
                SomaView()
            } options: {
                SomaOptions()
                Button("Make a Floating Window Again") { PlayerMode.switchTo(drawer: false) }
                Divider()
            }
        } else {
            // Starts below the command bar.
            DesktopClock.run(size: CGSize(width: 330, height: 108),
                             defaultTop: 24 + 170 + 20 + 250 + 20 + 260 + 20, canSitBehindIcons: true) {
                SomaView()
            } options: {
                SomaOptions()
                Button("Put in a Drawer at the Screen Edge") { PlayerMode.switchTo(drawer: true) }
                Divider()
            }
        }
    }
}

/// Which window the player is in, kept in its settings as `drawerMode`, which Widget Bar
/// also reads to know it's a drawer.
@MainActor
enum PlayerMode {
    static var isDrawer: Bool { UserDefaults.standard.bool(forKey: "drawerMode") }

    /// Starts the app again in the other window, playing on if it was playing.
    static func switchTo(drawer: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(drawer, forKey: "drawerMode")
        let player = SomaPlayer.shared
        defaults.set(player.state == .playing || player.state == .connecting, forKey: "resumeOnLaunch")
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}

struct SomaOptions: View {
    @ObservedObject var player = SomaPlayer.shared

    var body: some View {
        Toggle("Mute", isOn: $player.isMuted)
        if let channel = player.channel {
            Button(channel.site == nil ? "Open \(channel.title) on somafm.com" : "Open \(channel.page.host() ?? channel.title)") {
                NSWorkspace.shared.open(channel.page)
            }
        }
        Button("Support SomaFM") { NSWorkspace.shared.open(URL(string: "https://somafm.com/support/")!) }
        Divider()
    }
}
