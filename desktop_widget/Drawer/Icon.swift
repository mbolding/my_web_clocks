// The Text Drawer app icon: a wooden drawer pulled half open, with a few paper cards of
// text standing in it and an accent tab on its front.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent
    private let wood = Color(red: 0.62, green: 0.42, blue: 0.26)
    private let woodDark = Color(red: 0.40, green: 0.26, blue: 0.16)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.86, green: 0.89, blue: 0.93), Color(red: 0.66, green: 0.71, blue: 0.78)],
                           startPoint: .top, endPoint: .bottom)

            // The cabinet's dark opening, the cards standing up in it, then the drawer front.
            RoundedRectangle(cornerRadius: 30).fill(woodDark)
                .frame(width: 640, height: 300)
                .offset(y: 30)
            ForEach(0..<3, id: \.self) { i in
                card(lines: [3, 2, 3][i])
                    .frame(width: 400, height: 300)
                    .rotationEffect(.degrees([-6.0, 2, 7][i]))
                    .offset(x: CGFloat([-70, 10, 80][i]), y: CGFloat([-90, -120, -80][i]))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
            }
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [wood, woodDark.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .frame(width: 700, height: 290)
                .overlay {
                    // The handle.
                    Capsule().fill(Color(white: 0.85)).frame(width: 200, height: 40)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 4)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
                .offset(y: 170)
            // The accent tab on the drawer's side, as on the screen edge.
            UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22)
                .fill(accent)
                .frame(width: 44, height: 200)
                .offset(x: 390, y: 170)
        }
        .frame(width: 824, height: 824)
    }

    private func card(lines: Int) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18).fill(.white)
            VStack(alignment: .leading, spacing: 34) {
                ForEach(0..<lines, id: \.self) { i in
                    Capsule().fill(Color(white: 0.55)).frame(width: i == lines - 1 ? 180 : 300, height: 18)
                }
            }
            .padding(.leading, 44)
            .padding(.top, 50)
        }
    }
}
