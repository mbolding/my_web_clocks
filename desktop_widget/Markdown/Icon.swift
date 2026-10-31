// The Markdown Editor app icon: the Markdown mark, an M and a down arrow in a rounded frame,
// on a white card over deep ink, with the arrow in the accent.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent
    private let ink = Color(red: 0.12, green: 0.14, blue: 0.20)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.23, blue: 0.32), Color(red: 0.07, green: 0.08, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)

            RoundedRectangle(cornerRadius: 70, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.92)], startPoint: .top, endPoint: .bottom))
                .frame(width: 640, height: 420)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)

            // The frame of the mark.
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .stroke(ink, lineWidth: 34)
                .frame(width: 540, height: 320)

            MLetter()
                .stroke(ink, style: StrokeStyle(lineWidth: 48, lineCap: .square, lineJoin: .miter))
                .frame(width: 190, height: 170)
                .offset(x: -95, y: 0)

            DownArrow()
                .fill(accent)
                .frame(width: 140, height: 170)
                .offset(x: 130, y: 0)
        }
        .frame(width: 824, height: 824)
    }

    private struct MLetter: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.08))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
        }
    }

    /// A stem with a wide head pointing down.
    private struct DownArrow: Shape {
        func path(in rect: CGRect) -> Path {
            let stem = rect.width * 0.36
            let head = rect.height * 0.46
            return Path { p in
                p.move(to: CGPoint(x: rect.midX - stem / 2, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX + stem / 2, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX + stem / 2, y: rect.maxY - head))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - head))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - head))
                p.addLine(to: CGPoint(x: rect.midX - stem / 2, y: rect.maxY - head))
                p.closeSubpath()
            }
        }
    }
}
