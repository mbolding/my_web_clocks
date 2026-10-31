// The Relay Chat app icon: two speech bubbles passing a message between them, the newer in
// the accent, with a hash for a channel.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.27), Color(red: 0.06, green: 0.08, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)

            bubble(fill: Color(white: 0.92), tailLeft: true)
                .frame(width: 430, height: 300)
                .position(x: 340, y: 330)
            Text("#")
                .font(.system(size: 190, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.27))
                .position(x: 340, y: 320)

            bubble(fill: accent, tailLeft: false)
                .frame(width: 400, height: 260)
                .position(x: 490, y: 560)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            HStack(spacing: 34) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.white).frame(width: 44, height: 44)
                }
            }
            .position(x: 490, y: 550)
        }
        .frame(width: 824, height: 824)
    }

    private func bubble(fill: Color, tailLeft: Bool) -> some View {
        ZStack(alignment: tailLeft ? .bottomLeading : .bottomTrailing) {
            RoundedRectangle(cornerRadius: 90).fill(fill)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 90, y: 0))
                p.addLine(to: CGPoint(x: tailLeft ? -10 : 100, y: 90))
                p.closeSubpath()
            }
            .fill(fill)
            .frame(width: 90, height: 90)
            .offset(x: tailLeft ? 60 : -60, y: 60)
        }
    }
}
