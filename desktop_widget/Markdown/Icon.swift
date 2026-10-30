// The Markdown Editor app icon: a page of Markdown as the editor colours it, with a
// heading, a bulleted list and a code block.

import SwiftUI

struct IconFace: View {
    private let ink = Color(white: 0.22)
    private let faint = Color(white: 0.78)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.99), Color(white: 0.93)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 34) {
                HStack(spacing: 26) {
                    Text("#")
                        .font(.system(size: 150, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.orange)
                    bar(330, height: 64, ink)
                }
                .frame(height: 140)

                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 22) { bar(250, faint); bar(180, .orange.opacity(0.85)) }
                    bar(470, faint)
                }

                VStack(alignment: .leading, spacing: 30) {
                    ForEach([300, 380], id: \.self) { width in
                        HStack(spacing: 30) {
                            Circle().fill(.orange).frame(width: 30, height: 30)
                            bar(CGFloat(width), faint)
                        }
                    }
                }

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(white: 0.86))
                    .frame(width: 560, height: 150)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 26) {
                            bar(300, height: 28, Color(white: 0.55))
                            bar(200, height: 28, Color(white: 0.55))
                        }
                        .padding(.leading, 44)
                    }
            }
            .frame(width: 560, alignment: .leading)
        }
    }

    private func bar(_ width: CGFloat, height: CGFloat = 34, _ color: Color) -> some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}
