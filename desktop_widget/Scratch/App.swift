// Scratch Pad — a floating text pad that keeps what you type, with buttons to copy it
// all or save it to the Desktop.

import SwiftUI

@main
enum ScratchPadApp {
    @MainActor static func main() {
        // Starts beside Command Bar, to its left, and floats on top until turned off.
        DesktopClock.run(size: CGSize(width: 320, height: 240), defaultTop: 24 + 170 + 20 + 250 + 20,
                         defaultRight: 24 + 420 + 20, interactive: true) {
            ScratchView()
        } options: {
            ScratchOptions()
        }
    }
}

struct ScratchOptions: View {
    @ObservedObject var pad = ScratchPad.shared

    var body: some View {
        Button("Copy All") { pad.copyAll() }
            .disabled(pad.isEmpty)
        Button("Save to Desktop") { pad.saveToDesktop() }
            .disabled(pad.isEmpty)
        if pad.lastSaved != nil {
            Button("Show Saved File in Finder") { pad.revealLastSaved() }
        }
        Divider()
        Button("Clear") { pad.clear() }
            .disabled(pad.text.isEmpty)
        Divider()
    }
}
