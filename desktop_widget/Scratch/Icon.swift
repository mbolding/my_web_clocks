// The Scratch Pad app icon: a yellow legal pad, ruled in blue with a red margin, a few lines
// scribbled on it, and a pencil in the accent lying across it.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent
    private let paper = Color(red: 1.0, green: 0.93, blue: 0.55)
    private let rule = Color(red: 0.45, green: 0.62, blue: 0.85).opacity(0.55)
    private let pencilLead = Color(white: 0.2)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.45, green: 0.33, blue: 0.24), Color(red: 0.26, green: 0.18, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)

            pad
                .frame(width: 560, height: 680)
                .rotationEffect(.degrees(-4))
                .shadow(color: .black.opacity(0.45), radius: 22, y: 14)
                .offset(x: -20, y: 10)

            pencil
                .rotationEffect(.degrees(-38))
                .offset(x: 120, y: 120)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 10)
        }
        .frame(width: 824, height: 824)
    }

    private var pad: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16).fill(paper)
            // Ruled lines, and the margin.
            VStack(spacing: 52) {
                ForEach(0..<10, id: \.self) { _ in Rectangle().fill(rule).frame(height: 5) }
            }
            .padding(.top, 140)
            Rectangle()
                .fill(Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.75))
                .frame(width: 6)
                .padding(.leading, 96)
            // The binding at the top.
            Rectangle()
                .fill(Color(red: 0.62, green: 0.18, blue: 0.16))
                .frame(height: 70)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
            // A few scribbled lines.
            VStack(alignment: .leading, spacing: 30) {
                ForEach([300.0, 360, 240], id: \.self) { width in
                    Scribble().stroke(Color(red: 0.15, green: 0.2, blue: 0.4).opacity(0.85),
                                      style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                        .frame(width: width, height: 26)
                }
            }
            .padding(.leading, 130)
            .padding(.top, 156)
        }
    }

    private var pencil: some View {
        HStack(spacing: 0) {
            // Eraser and its ferrule.
            UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18)
                .fill(Color(red: 0.95, green: 0.55, blue: 0.6))
                .frame(width: 60, height: 76)
            Rectangle().fill(Color(white: 0.75)).frame(width: 40, height: 76)
            Rectangle().fill(accent).frame(width: 340, height: 76)
                .overlay { Rectangle().fill(.black.opacity(0.12)).frame(height: 22).offset(y: 22) }
            // The sharpened wood, then the lead.
            Tip().fill(Color(red: 0.93, green: 0.78, blue: 0.58)).frame(width: 110, height: 76)
                .overlay(alignment: .trailing) {
                    Tip().fill(pencilLead).frame(width: 36, height: 25)
                }
        }
    }

    /// A wavy line, as handwriting looks from a distance.
    private struct Scribble: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                let steps = Int(rect.width / 20)
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                for i in 1...steps {
                    let x = rect.minX + CGFloat(i) * rect.width / CGFloat(steps)
                    let y = rect.midY + (i % 2 == 0 ? -1 : 1) * rect.height * (0.25 + 0.2 * CGFloat((i * 7) % 3) / 2)
                    p.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    /// A point to the right.
    private struct Tip: Shape {
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
