// The Panorama app icon: a wide strip of mountains under an accent-coloured sun, bowed as
// a stitched panorama is, with the outlines of the three photos it was made from.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.2), Color(red: 0.22, green: 0.24, blue: 0.3)],
                           startPoint: .top, endPoint: .bottom)

            Canvas { context, size in
                let strip = Strip(left: 52, right: 772, top: 262, bottom: 562, bow: 26)
                var inside = context
                inside.clip(to: strip.path)

                // Sky, sun, two ranges of mountains and a lake.
                inside.fill(strip.path, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.35, green: 0.6, blue: 0.95), Color(red: 0.8, green: 0.9, blue: 1)]),
                    startPoint: CGPoint(x: 0, y: 236), endPoint: CGPoint(x: 0, y: 470)))
                inside.fill(Path(ellipseIn: CGRect(x: 520, y: 300, width: 92, height: 92)), with: .color(accent))
                inside.fill(ridge(base: 600, points: [(40, 470), (150, 360), (240, 430), (330, 330), (450, 440),
                                                      (560, 380), (680, 445), (790, 400)]),
                            with: .color(Color(red: 0.45, green: 0.47, blue: 0.62)))
                inside.fill(ridge(base: 600, points: [(40, 500), (120, 440), (220, 495), (360, 420), (470, 492),
                                                      (600, 450), (700, 498), (790, 470)]),
                            with: .color(Color(red: 0.2, green: 0.38, blue: 0.3)))
                inside.fill(Path(CGRect(x: 0, y: 505, width: size.width, height: 120)),
                            with: .linearGradient(Gradient(colors: [Color(red: 0.25, green: 0.45, blue: 0.7),
                                                                    Color(red: 0.15, green: 0.3, blue: 0.5)]),
                                                  startPoint: CGPoint(x: 0, y: 505), endPoint: CGPoint(x: 0, y: 600)))

                // The photos' outlines, overlapping.
                for (n, x) in [92.0, 322, 552].enumerated() {
                    let frame = CGRect(x: x, y: 236 + Double(n % 2) * 10, width: 180, height: 352)
                    context.stroke(Path(roundedRect: frame, cornerRadius: 10), with: .color(.white.opacity(0.75)),
                                   style: StrokeStyle(lineWidth: 7, dash: [22, 12]))
                }
                context.stroke(strip.path, with: .color(.white), lineWidth: 8)
            }
        }
    }

    /// A range of mountains through the given peaks and dips, filled down to `base`.
    private func ridge(base: CGFloat, points: [(CGFloat, CGFloat)]) -> Path {
        Path { p in
            p.move(to: CGPoint(x: points[0].0, y: base))
            for (x, y) in points { p.addLine(to: CGPoint(x: x, y: y)) }
            p.addLine(to: CGPoint(x: points.last!.0, y: base))
            p.closeSubpath()
        }
    }

    /// A wide strip whose top and bottom bow outward, as a panorama's edges do.
    private struct Strip {
        var left, right, top, bottom, bow: CGFloat

        var path: Path {
            Path { p in
                let middle = (left + right) / 2
                p.move(to: CGPoint(x: left, y: top))
                p.addQuadCurve(to: CGPoint(x: right, y: top), control: CGPoint(x: middle, y: top - bow * 2))
                p.addLine(to: CGPoint(x: right, y: bottom))
                p.addQuadCurve(to: CGPoint(x: left, y: bottom), control: CGPoint(x: middle, y: bottom + bow * 2))
                p.closeSubpath()
            }
        }
    }
}
