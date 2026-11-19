// The Reveal Codes icon: WordPerfect's blue screen, a few lines of grey text with one word
// bright for bold, the Reveal Codes ruler, and a code in brackets below it.

import SwiftUI

struct IconFace: View {
    private let blue = Color(red: 0, green: 0, blue: 0.667)
    private let grey = Color(red: 0.667, green: 0.667, blue: 0.667)
    private let yellow = Color(red: 1, green: 1, blue: 0.333)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 150, style: .continuous).fill(Color(white: 0.16))
            RoundedRectangle(cornerRadius: 70, style: .continuous).fill(blue)
                .padding(70)
            VStack(alignment: .leading, spacing: 30) {
                bar([150, 260, 120], bright: 1)
                bar([220, 90, 230], bright: nil)
                bar([300, 160], bright: nil)
                // The Reveal Codes ruler: brackets at the margins, triangles at the tabs.
                Text("[▲▲▲▲▲]")
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.top, 10)
                Text("[BOLD]")
                    .font(.system(size: 92, weight: .heavy, design: .monospaced))
                    .foregroundStyle(yellow)
            }
            .frame(width: 560, alignment: .leading)
            .offset(y: 10)
        }
        .frame(width: 824, height: 824)
    }

    /// A line of text as grey bars, one of them white for a bold word.
    private func bar(_ widths: [CGFloat], bright: Int?) -> some View {
        HStack(spacing: 22) {
            ForEach(widths.indices, id: \.self) { n in
                Rectangle().fill(n == bright ? Color.white : grey).frame(width: widths[n], height: 34)
            }
        }
    }
}
