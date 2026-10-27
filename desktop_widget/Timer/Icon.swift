// The dial timer app icon: the dial with twenty minutes set, on a dark tile.

import SwiftUI

struct IconFace: View {
    var body: some View {
        DialFace(minutes: 20)
            .padding(36)
            .background(Circle().fill(Color(white: 0.2)).padding(36))
            .background(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.1)],
                                       startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .dark)
    }
}
