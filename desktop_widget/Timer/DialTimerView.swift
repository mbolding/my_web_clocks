// DialTimerView — the dial timer's window. Drag around the face to set up to an hour;
// letting go starts it. Tap the middle to pause, resume, or dismiss when it's done.
// The outer rim, where the ticks are, moves the window. While idle the middle shows
// the time of day.

import SwiftUI

struct DialTimerView: View {
    @ObservedObject var timer = DialTimer.shared
    @State private var dragMinutes: Int?

    private var isRunning: Bool {
        if case .running = timer.state { true } else { false }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: isRunning || timer.state == .finished ? 0.1 : 1)) { timeline in
            GeometryReader { geo in
                let r = min(geo.size.width, geo.size.height) / 2
                let now = timeline.date
                ZStack {
                    // The rim and anything not covered below moves the window.
                    Circle().fill(Color.clear).contentShape(Circle()).modifier(MovesWindow())

                    DialFace(minutes: dragMinutes.map(Double.init) ?? timer.remaining(at: now) / 60,
                             finished: timer.state == .finished,
                             pulse: (sin(now.timeIntervalSinceReferenceDate * 4) + 1) / 2)
                        .allowsHitTesting(false)

                    Circle().fill(Color.clear)
                        .frame(width: r * 1.56, height: r * 1.56)
                        .contentShape(Circle())
                        .gesture(setting(radius: r * 0.78))

                    readout(now: now, r: r)
                        .frame(width: r * 0.72, height: r * 0.72)
                        .contentShape(Circle())
                        .onTapGesture { timer.toggle() }

                    FloatPin().offset(y: r * 0.5) // between the readout and the 30
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// Dragging round the face sets whole minutes, 0 at the top, clockwise. It doesn't
    /// wrap: sweeping past the top pins it at 0 or 60.
    private func setting(radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { drag in
                let dx = drag.location.x - radius, dy = drag.location.y - radius
                var angle = atan2(dx, -dy)
                if angle < 0 { angle += 2 * .pi }
                var minutes = Int((angle / (2 * .pi) * 60).rounded())
                let previous = dragMinutes ?? Int((timer.remaining() / 60).rounded())
                if previous >= 45 && minutes <= 15 { minutes = 60 }
                if previous <= 15 && minutes >= 45 { minutes = 0 }
                dragMinutes = min(minutes, DialTimer.maxMinutes)
            }
            .onEnded { _ in
                if let minutes = dragMinutes { timer.start(minutes: minutes) }
                dragMinutes = nil
            }
    }

    private func readout(now: Date, r: CGFloat) -> some View {
        let (main, caption): (String, String) = {
            if let dragMinutes { return ("\(dragMinutes) min", dragMinutes > 0 ? "let go to start" : "let go to clear") }
            switch timer.state {
            case .idle: return (now.formatted(date: .omitted, time: .shortened), "drag to set")
            case .running: return (Self.clock(timer.remaining(at: now)), "tap to pause")
            case .paused: return (Self.clock(timer.remaining(at: now)), "paused")
            case .finished: return ("Done", "tap to dismiss")
            }
        }()
        return VStack(spacing: r * 0.02) {
            Text(main)
                .font(.system(size: r * (main.count > 6 ? 0.15 : 0.2), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.system(size: r * 0.075, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// m:ss, rounding up, so a fresh 5-minute timer reads 5:00 rather than 4:59.
    private static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
