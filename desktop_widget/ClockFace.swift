// ClockFace — the analog dial shared by the desktop app and the WidgetKit widget.

import SwiftUI

struct ClockFace: View {
    var date: Date
    var showSeconds: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ink: Color = scheme == .dark ? .white : .black
            let accent = Color.orange

            func point(_ turns: Double, _ len: Double) -> CGPoint {
                let a = turns * 2 * .pi
                return CGPoint(x: c.x + sin(a) * len, y: c.y - cos(a) * len)
            }

            // Minute and hour ticks
            for i in 0..<60 {
                let major = i % 5 == 0
                var p = Path()
                p.move(to: point(Double(i) / 60, r * (major ? 0.78 : 0.85)))
                p.addLine(to: point(Double(i) / 60, r * 0.90))
                ctx.stroke(p, with: .color(ink.opacity(major ? 0.85 : 0.25)),
                           style: StrokeStyle(lineWidth: major ? r * 0.03 : r * 0.012, lineCap: .round))
            }

            // Weekday + day of month
            let weekday = date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
            let day = date.formatted(.dateTime.day())
            let label = Text("\(Text(weekday).foregroundStyle(accent)) \(Text(day).foregroundStyle(ink.opacity(0.7)))")
            ctx.draw(label.font(.system(size: r * 0.15, weight: .semibold, design: .rounded)),
                     at: CGPoint(x: c.x, y: c.y + r * 0.42))

            // Hands
            let cal = Calendar.current
            let t = cal.dateComponents([.hour, .minute, .second], from: date)
            let sec = Double(t.second ?? 0)
            let minute = Double(t.minute ?? 0) + sec / 60
            let hour = Double((t.hour ?? 0) % 12) + minute / 60

            func hand(_ turns: Double, _ len: Double, _ width: Double, _ color: Color, tail: Double = 0) {
                var p = Path()
                p.move(to: point(turns + 0.5, tail))
                p.addLine(to: point(turns, len))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            hand(hour / 12, r * 0.48, r * 0.065, ink)
            hand(minute / 60, r * 0.72, r * 0.045, ink)
            if showSeconds {
                hand(sec / 60, r * 0.80, r * 0.018, accent, tail: r * 0.16)
            }
            let hub = r * (showSeconds ? 0.045 : 0.06)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - hub, y: c.y - hub, width: hub * 2, height: hub * 2)),
                     with: .color(showSeconds ? accent : ink))
        }
    }
}
