// The Dock Load app icon: the live gauge at a fixed moment, as the Dock shows it while
// the app isn't running.

import SwiftUI

struct IconFace: View {
    var body: some View {
        LoadFace(cpu: 0.62, memory: 0.45, pressure: .normal)
    }
}
