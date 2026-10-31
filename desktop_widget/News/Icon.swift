// The News Reader app icon: a page of threads, each reply indented under the one before
// with the lines of the tree joining them, and the unread one marked in the accent.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent
    private let ink = Color(red: 0.20, green: 0.24, blue: 0.32)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.22, green: 0.30, blue: 0.44), Color(red: 0.10, green: 0.13, blue: 0.21)],
                           startPoint: .top, endPoint: .bottom)

            RoundedRectangle(cornerRadius: 46)
                .fill(Color(white: 0.97))
                .frame(width: 560, height: 640)
                .shadow(color: .black.opacity(0.4), radius: 22, y: 12)

            // The tree: a stem down the left, a branch to each reply.
            Path { p in
                p.move(to: CGPoint(x: 252, y: 262))
                p.addLine(to: CGPoint(x: 252, y: 548))
                for y in [372.0, 548] {
                    p.move(to: CGPoint(x: 252, y: y))
                    p.addLine(to: CGPoint(x: 300, y: y))
                }
                p.move(to: CGPoint(x: 332, y: 400))
                p.addLine(to: CGPoint(x: 332, y: 460))
                p.addLine(to: CGPoint(x: 376, y: 460))
            }
            .stroke(ink.opacity(0.45), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))

            row(x: 232, y: 230, width: 360, unread: false)
            row(x: 312, y: 372, width: 290, unread: true)
            row(x: 392, y: 460, width: 220, unread: false)
            row(x: 312, y: 548, width: 290, unread: false)
        }
        .frame(width: 824, height: 824)
    }

    /// A line of the list: a dot, then a bar standing for the subject.
    private func row(x: CGFloat, y: CGFloat, width: CGFloat, unread: Bool) -> some View {
        HStack(spacing: 20) {
            Circle()
                .fill(unread ? accent : ink.opacity(0.25))
                .frame(width: 40, height: 40)
            Capsule()
                .fill(unread ? ink : ink.opacity(0.35))
                .frame(width: width - 60, height: 30)
        }
        .frame(width: width, alignment: .leading)
        .position(x: x + width / 2, y: y)
    }
}
