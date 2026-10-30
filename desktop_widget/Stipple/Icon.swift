// The Stipple app icon: a ball lit from the top left, drawn in ink dots on paper, with its
// shadow, and a pen in the accent colour still at work on the shadow's edge.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.96, blue: 0.91)

            Canvas { context, size in
                for dot in Self.dots {
                    let r = dot.size / 2
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: dot.size, height: dot.size)),
                                 with: .color(Color(white: 0.12)))
                }
            }

            Pen(accent: accent)
                .frame(width: 92, height: 470)
                .rotationEffect(.degrees(38))
                .offset(x: 230, y: 120)
                .shadow(color: .black.opacity(0.3), radius: 10, x: -6, y: 10)
        }
    }

    private struct Dot { var x, y, size: CGFloat }

    /// Dots placed along a Halton sequence and kept by how dark the scene is there, so the
    /// icon comes out the same on every build.
    private static let dots: [Dot] = {
        let centre = CGPoint(x: 360, y: 350), radius: CGFloat = 230
        let light = normalize(x: -0.55, y: -0.6, z: 0.6)

        func darkness(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let dx = (x - centre.x) / radius, dy = (y - centre.y) / radius
            let r2 = dx * dx + dy * dy
            if r2 < 1 {
                let nz = (1 - r2).squareRoot()
                let lit = max(0, dx * light.x + dy * light.y + nz * light.z)
                return 0.08 + 0.85 * pow(1 - lit, 1.6)
            }
            // The shadow on the floor, an ellipse falling to the lower right.
            let sx = (x - 470) / 300, sy = (y - 620) / 95
            let s = sx * sx + sy * sy
            return s < 1 ? 0.7 * (1 - s) : 0
        }

        var dots: [Dot] = []
        var i = 1
        while dots.count < 2600 && i < 60_000 {
            let x = halton(i, 2) * 824, y = halton(i, 3) * 824, keep = halton(i, 5)
            let d = darkness(x, y)
            if keep < d { dots.append(Dot(x: x, y: y, size: 5 + 5 * d)) }
            i += 1
        }
        return dots
    }()

    private static func halton(_ index: Int, _ base: Int) -> CGFloat {
        var f: CGFloat = 1, r: CGFloat = 0, i = index
        while i > 0 {
            f /= CGFloat(base)
            r += f * CGFloat(i % base)
            i /= base
        }
        return r
    }

    private static func normalize(x: CGFloat, y: CGFloat, z: CGFloat) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
        let l = (x * x + y * y + z * z).squareRoot()
        return (x / l, y / l, z / l)
    }

    /// A technical pen, nib down: accent barrel, dark grip and a fine steel tip.
    private struct Pen: View {
        var accent: Color

        var body: some View {
            VStack(spacing: 0) {
                Capsule().fill(accent).frame(height: 300)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.35)).frame(width: 16).padding(.vertical, 24).padding(.leading, 14)
                    }
                Rectangle().fill(Color(white: 0.18)).frame(width: 78, height: 90)
                Cone().fill(Color(white: 0.55)).frame(width: 78, height: 54)
                Rectangle().fill(Color(white: 0.3)).frame(width: 10, height: 26)
            }
        }
    }

    private struct Cone: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX + 6, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.midX - 6, y: rect.maxY))
                p.closeSubpath()
            }
        }
    }
}
