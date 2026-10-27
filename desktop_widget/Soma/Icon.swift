// The Soma Player app icon: radio waves on a deep blue tile.

import SwiftUI

struct IconFace: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.42), Color(red: 0.05, green: 0.07, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 420, weight: .medium))
                .foregroundStyle(.orange)
                .shadow(color: .orange.opacity(0.45), radius: 36)
        }
    }
}
