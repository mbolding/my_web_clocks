// The analog app icon: the real dial on a light tile.

import SwiftUI

struct IconFace: View {
    var body: some View {
        ClockFace(date: iconDate, showSeconds: true)
            .padding(70)
            .background(LinearGradient(colors: [Color(white: 0.99), Color(white: 0.86)],
                                       startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .light)
    }
}
