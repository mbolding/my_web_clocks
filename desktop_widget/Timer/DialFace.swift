// DialFace — the timer's dial, drawn to fill a circle: minute ticks with 0–55 round the
// edge, a wedge in the accent colour from 12 o'clock clockwise for the minutes left, and
// a cap in the middle for the readout. A finished timer pulses a ring instead. As a
// stopwatch it adds a sweeping seconds hand, and the wedge, now the minutes gone, fades
// back behind it.

import SwiftUI

struct DialFace: View {
    var minutes: Double // 0...60, the wedge
    var finished = false
    var pulse = 0.0 // 0...1, for the finished ring
    var seconds: Double? // 0..<60, the stopwatch's hand
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ink: Color = scheme == .dark ? .white : .black

            func point(_ minute: Double, _ length: Double) -> CGPoint {
                let a = minute / 60 * 2 * .pi
                return CGPoint(x: c.x + sin(a) * length, y: c.y - cos(a) * length)
            }

            // Ticks and numbers
            for i in 0..<60 {
                let major = i % 5 == 0
                var tick = Path()
                tick.move(to: point(Double(i), r * (major ? 0.80 : 0.85)))
                tick.addLine(to: point(Double(i), r * 0.90))
                ctx.stroke(tick, with: .color(ink.opacity(major ? 0.7 : 0.25)),
                           style: StrokeStyle(lineWidth: major ? r * 0.022 : r * 0.01, lineCap: .round))
                if major {
                    ctx.draw(Text("\(i)").font(.system(size: r * 0.1, weight: .medium, design: .rounded))
                                .foregroundStyle(ink.opacity(0.55)),
                             at: point(Double(i), r * 0.68))
                }
            }

            // The wedge: from 12 o'clock clockwise, shrinking back as time runs out.
            if minutes > 0 {
                var wedge = Path()
                wedge.move(to: c)
                wedge.addArc(center: c, radius: r * 0.58, startAngle: .degrees(-90),
                             endAngle: .degrees(-90 + 360 * min(minutes, 60) / 60), clockwise: false)
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(accent.opacity(seconds != nil ? 0.3 : scheme == .dark ? 0.85 : 0.8)))
            }

            if let seconds {
                var hand = Path()
                hand.move(to: c)
                hand.addLine(to: point(seconds, r * 0.88))
                ctx.stroke(hand, with: .color(accent), style: StrokeStyle(lineWidth: r * 0.025, lineCap: .round))
            }

            if finished {
                let ring = Path(ellipseIn: CGRect(x: c.x - r * 0.93, y: c.y - r * 0.93, width: r * 1.86, height: r * 1.86))
                ctx.stroke(ring, with: .color(accent.opacity(0.35 + 0.6 * pulse)), lineWidth: r * 0.06)
            }

            // Cap for the readout.
            let cap = r * 0.36
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - cap, y: c.y - cap, width: cap * 2, height: cap * 2)),
                     with: .color(scheme == .dark ? Color(white: 0.13) : Color(white: 0.97)))
        }
    }
}
