// The month calendar app icon: October 2026 with the 26th picked out, on a light tile.

import SwiftUI

struct IconFace: View {
    var body: some View {
        CalendarFace(date: iconDate)
            .padding(70)
            .background(LinearGradient(colors: [Color(white: 0.99), Color(white: 0.86)],
                                       startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .light)
    }
}
