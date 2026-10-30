// The Gopher Browser app icon: a burrow under the grass, its tunnels branching like a gopher
// menu, with a folder, a page and a search in the chambers, the page lit in the accent.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent
    private let soil = Color(red: 0.16, green: 0.10, blue: 0.06)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.58, green: 0.40, blue: 0.25), Color(red: 0.33, green: 0.21, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                Color(red: 0.55, green: 0.78, blue: 0.95).frame(height: 110)
                Color(red: 0.40, green: 0.66, blue: 0.29).frame(height: 56)
                Spacer()
            }

            // The mound at the way in.
            Ellipse()
                .fill(Color(red: 0.50, green: 0.33, blue: 0.20))
                .frame(width: 210, height: 90)
                .position(x: 210, y: 150)

            Path { p in
                p.move(to: CGPoint(x: 210, y: 140))
                p.addLine(to: CGPoint(x: 210, y: 660))
                for y in [300.0, 480, 660] {
                    p.move(to: CGPoint(x: 210, y: y))
                    p.addLine(to: CGPoint(x: 540, y: y))
                }
            }
            .stroke(soil, style: StrokeStyle(lineWidth: 66, lineCap: .round, lineJoin: .round))

            chamber("folder.fill", at: CGPoint(x: 570, y: 300), fill: soil, ink: Color(white: 0.92))
            chamber("doc.text.fill", at: CGPoint(x: 570, y: 480), fill: accent, ink: .white)
            chamber("magnifyingglass", at: CGPoint(x: 570, y: 660), fill: soil, ink: Color(white: 0.92))
        }
        .frame(width: 824, height: 824)
    }

    private func chamber(_ symbol: String, at point: CGPoint, fill: Color, ink: Color) -> some View {
        ZStack {
            Circle().fill(fill)
            Image(systemName: symbol)
                .font(.system(size: 76, weight: .semibold))
                .foregroundStyle(ink)
        }
        .frame(width: 158, height: 158)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
        .position(point)
    }
}
