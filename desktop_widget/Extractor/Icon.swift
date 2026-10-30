// The Text Extractor app icon: a page of text with two lines selected in the accent colour
// and the text cursor at the end of them.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent

    // Line widths down the page; the selected ones are picked out.
    private let lines: [CGFloat] = [380, 420, 340, 410, 400, 260, 0, 390, 410, 300]
    private let selected = 3...4

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.52), Color(red: 0.2, green: 0.24, blue: 0.31)],
                           startPoint: .top, endPoint: .bottom)

            ZStack(alignment: .topLeading) {
                Page()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
                Page.fold
                    .fill(Color(white: 0.84))

                VStack(alignment: .leading, spacing: 22) {
                    ForEach(lines.indices, id: \.self) { i in
                        Capsule()
                            .fill(selected.contains(i) ? accent : Color(white: 0.72))
                            .frame(width: lines[i], height: 20)
                            .opacity(lines[i] == 0 ? 0 : 1)
                            .background(alignment: .leading) {
                                if selected.contains(i) {
                                    Rectangle()
                                        .fill(accent.opacity(0.25))
                                        .frame(width: 470, height: 42)
                                        .offset(x: -12)
                                }
                            }
                    }
                }
                .padding(.leading, 70)
                .padding(.top, 150)
            }
            .frame(width: 560, height: 680)

            ZStack {
                IBeam().stroke(.white, style: StrokeStyle(lineWidth: 46, lineCap: .round, lineJoin: .round))
                IBeam().stroke(accent, style: StrokeStyle(lineWidth: 26, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 120, height: 300)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 6)
            .offset(x: 200, y: -30)
        }
    }

    /// The text cursor: a bar with a short crossbar at each end.
    private struct IBeam: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.midX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                for y in [rect.minY, rect.maxY] {
                    p.move(to: CGPoint(x: rect.minX, y: y))
                    p.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
            }
        }
    }

    /// A sheet of paper with its top right corner folded down.
    private struct Page: Shape {
        static let corner: CGFloat = 110

        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX - Self.corner, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + Self.corner))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.closeSubpath()
            }
        }

        static var fold: some Shape {
            Fold()
        }

        private struct Fold: Shape {
            func path(in rect: CGRect) -> Path {
                Path { p in
                    p.move(to: CGPoint(x: rect.maxX - Page.corner, y: rect.minY))
                    p.addLine(to: CGPoint(x: rect.maxX - Page.corner, y: rect.minY + Page.corner))
                    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + Page.corner))
                    p.closeSubpath()
                }
            }
        }
    }
}
