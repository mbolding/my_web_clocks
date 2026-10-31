// The Offsite app icon: a rack of three drives far away on a dusk sky, each with its light
// on, and a folder in front of them carrying the accent's up-and-down arrows, for the files
// going back and forth.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.3, blue: 0.48), Color(red: 0.07, green: 0.1, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom)

            rack
                .frame(width: 470, height: 430)
                .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
                .offset(y: -105)

            folder
                .frame(width: 560, height: 400)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
                .offset(y: 150)
        }
        .frame(width: 824, height: 824)
    }

    /// The drives: dark bays with vents and a green light.
    private var rack: some View {
        VStack(spacing: 22) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 18) {
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule().fill(Color(white: 0.12)).frame(width: 18, height: 64)
                    }
                    Spacer()
                    Circle()
                        .fill(Color(red: 0.35, green: 0.95, blue: 0.5))
                        .frame(width: 30)
                        .shadow(color: Color(red: 0.35, green: 0.95, blue: 0.5), radius: 12)
                }
                .padding(.horizontal, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 20).fill(
                    LinearGradient(colors: [Color(white: 0.42), Color(white: 0.28)], startPoint: .top, endPoint: .bottom)))
            }
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 34).fill(Color(white: 0.16)))
    }

    /// A Finder-blue folder with the arrows on its front.
    private var folder: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(red: 0.3, green: 0.6, blue: 0.92))
                .frame(width: 230, height: 90)
                .offset(x: 10, y: -42)
            RoundedRectangle(cornerRadius: 34)
                .fill(LinearGradient(colors: [Color(red: 0.5, green: 0.78, blue: 1), Color(red: 0.33, green: 0.63, blue: 0.95)],
                                     startPoint: .top, endPoint: .bottom))
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 190, weight: .heavy))
                .foregroundStyle(accent)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
