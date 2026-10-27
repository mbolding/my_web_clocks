// The Widget Bar app icon: a row of small widget tiles on a bar, on a dark tile.

import SwiftUI

struct IconFace: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.3), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 70, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(width: 680, height: 220)
            HStack(spacing: 34) {
                ForEach(0..<4) { i in
                    VStack(spacing: 18) {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(i == 0 ? Color.orange : Color.white.opacity(0.75))
                            .frame(width: 118, height: 118)
                        Circle()
                            .fill(Color.white.opacity(i < 2 ? 0.7 : 0))
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .offset(y: 17)
        }
    }
}
