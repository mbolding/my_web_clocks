// The word clock app icon: the grid lit at 10:09 ("IT IS TEN PAST TEN AM") on a dark tile.

import SwiftUI

struct IconFace: View {
    var body: some View {
        WordFace(date: iconDate)
            .padding(80)
            .background(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)],
                                       startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .dark)
    }
}
