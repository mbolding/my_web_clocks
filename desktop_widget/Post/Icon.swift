// The SDF Post app icon: a page of text lifting off on an arrow in the accent, over the
// tilde that stands for a Unix home.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.17, blue: 0.24), Color(red: 0.05, green: 0.06, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)

            Text("~")
                .font(.system(size: 330, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.10))
                .position(x: 412, y: 640)

            RoundedRectangle(cornerRadius: 34)
                .fill(Color(white: 0.96))
                .frame(width: 380, height: 470)
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                .position(x: 360, y: 430)
            VStack(alignment: .leading, spacing: 30) {
                ForEach([250.0, 300, 270, 300, 180], id: \.self) { width in
                    Capsule().fill(Color(white: 0.62)).frame(width: width, height: 22)
                }
            }
            .frame(width: 300, alignment: .leading)
            .position(x: 360, y: 440)

            Circle()
                .fill(accent)
                .frame(width: 250, height: 250)
                .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                .position(x: 580, y: 590)
            Image(systemName: "arrow.up")
                .font(.system(size: 140, weight: .bold))
                .foregroundStyle(.white)
                .position(x: 580, y: 590)
        }
        .frame(width: 824, height: 824)
    }
}
