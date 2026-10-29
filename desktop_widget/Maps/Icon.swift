// The Map Browser app icon: a scrap of street map in OpenStreetMap's colours, with a
// park, a river and a pin.

import SwiftUI

struct IconFace: View {
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.94, blue: 0.91)

            RoundedRectangle(cornerRadius: 40)
                .fill(Color(red: 0.68, green: 0.82, blue: 0.62))
                .frame(width: 300, height: 230)
                .offset(x: -190, y: -210)

            Path { p in
                p.move(to: CGPoint(x: -20, y: 600))
                p.addCurve(to: CGPoint(x: 844, y: 700), control1: CGPoint(x: 260, y: 470), control2: CGPoint(x: 560, y: 820))
            }
            .stroke(Color(red: 0.67, green: 0.83, blue: 0.87), lineWidth: 90)

            road([CGPoint(x: -20, y: 420), CGPoint(x: 844, y: 330)], width: 44, fill: .white)
            road([CGPoint(x: 560, y: -20), CGPoint(x: 470, y: 844)], width: 44, fill: .white)
            road([CGPoint(x: -20, y: 160), CGPoint(x: 844, y: 520)], width: 62,
                 fill: Color(red: 0.99, green: 0.84, blue: 0.64))

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 250, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .orange)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
                .offset(x: 120, y: -40)
        }
    }

    /// A road with a darker casing, as OpenStreetMap draws them.
    private func road(_ points: [CGPoint], width: CGFloat, fill: Color) -> some View {
        let path = Path { p in p.addLines(points) }
        return ZStack {
            path.stroke(Color(white: 0.75), lineWidth: width + 10)
            path.stroke(fill, lineWidth: width)
        }
    }
}
