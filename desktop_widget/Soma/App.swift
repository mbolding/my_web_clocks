// Soma Player — a small floating SomaFM radio.

import SwiftUI

@main
enum SomaPlayerApp {
    @MainActor static func main() {
        // Starts below the command bar.
        DesktopClock.run(size: CGSize(width: 330, height: 108),
                         defaultTop: 24 + 170 + 20 + 250 + 20 + 260 + 20, canSitBehindIcons: true) {
            SomaView()
        } options: {
            SomaOptions()
        }
    }
}

struct SomaOptions: View {
    @ObservedObject var player = SomaPlayer.shared

    var body: some View {
        Toggle("Mute", isOn: $player.isMuted)
        if let channel = player.channel {
            Button("Open \(channel.title) on somafm.com") { NSWorkspace.shared.open(channel.page) }
        }
        Button("Support SomaFM") { NSWorkspace.shared.open(URL(string: "https://somafm.com/support/")!) }
        Divider()
    }
}
