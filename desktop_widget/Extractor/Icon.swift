// The Text Extractor app icon: a laid-out document, with a picture and coloured headings,
// behind the plain text taken out of it, set in a fixed-width face on a clean card, with an
// arrow in the accent curving from one to the other.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.52), Color(red: 0.16, green: 0.19, blue: 0.25)],
                           startPoint: .top, endPoint: .bottom)

            document
                .frame(width: 420, height: 540)
                .rotationEffect(.degrees(-7))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
                .offset(x: -125, y: -60)

            plainText
                .frame(width: 400, height: 460)
                .shadow(color: .black.opacity(0.4), radius: 22, y: 14)
                .offset(x: 140, y: 110)

            Arc()
                .stroke(accent, style: StrokeStyle(lineWidth: 34, lineCap: .round))
                .frame(width: 230, height: 170)
                .offset(x: 115, y: -215)
            Head()
                .fill(accent)
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(100))
                .offset(x: 228, y: -118)
        }
        .frame(width: 824, height: 824)
    }

    /// The source: a heading, a picture, and columns of text in colour.
    private var document: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule().fill(Color(red: 0.75, green: 0.2, blue: 0.22)).frame(width: 250, height: 34)
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.68, blue: 0.9), Color(red: 0.32, green: 0.6, blue: 0.4)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 150)
                .overlay(alignment: .bottomLeading) {
                    Circle().fill(Color(red: 1, green: 0.85, blue: 0.4)).frame(width: 46).offset(x: 230, y: -90)
                }
            ForEach([340.0, 300, 330, 220], id: \.self) { width in
                Capsule().fill(Color(white: 0.75)).frame(width: width, height: 18)
            }
        }
        .padding(38)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22).fill(.white))
    }

    /// The result: plain fixed-width lines and nothing else.
    private var plainText: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Aa")
                .font(.system(size: 96, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.18))
            ForEach([300.0, 260, 320, 180, 280], id: \.self) { width in
                Capsule().fill(Color(white: 0.35)).frame(width: width, height: 20)
            }
        }
        .padding(44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color(white: 0.97)))
    }

    /// The arrow's sweep, over the top from the document to the text.
    private struct Arc: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.75))
                p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX * 1.2, y: rect.minY - 40))
            }
        }
    }

    private struct Head: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.closeSubpath()
            }
        }
    }
}
