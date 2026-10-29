// Dial Timer — a round, up-to-an-hour timer that floats on the desktop, and a stopwatch.

import SwiftUI

@main
enum DialTimerApp {
    @MainActor static func main() {
        // Round, and its face takes drags for setting the time, so only the rim moves it.
        // Starts below the Soma player.
        DesktopClock.run(size: CGSize(width: 200, height: 200),
                         defaultTop: 24 + 170 + 20 + 250 + 20 + 260 + 20 + 108 + 20,
                         round: true, movableByBackground: false) {
            DialTimerView()
        } options: {
            TimerOptions()
        }
    }
}

struct TimerOptions: View {
    @ObservedObject var timer = DialTimer.shared
    @ObservedObject var stopwatch = Stopwatch.shared

    var body: some View {
        Picker("Mode", selection: $timer.mode) {
            Text("Timer").tag(DialTimer.Mode.timer)
            Text("Stopwatch").tag(DialTimer.Mode.stopwatch)
        }
        .pickerStyle(.inline)
        Divider()
        if timer.mode == .stopwatch {
            stopwatchOptions
        } else {
            timerOptions
        }
        Divider()
    }

    @ViewBuilder private var stopwatchOptions: some View {
        switch stopwatch.state {
        case .idle: Button("Start") { stopwatch.toggle() }
        case .running: Button("Pause") { stopwatch.toggle() }
        case .paused: Button("Resume") { stopwatch.toggle() }
        }
        if stopwatch.state != .idle {
            Button("Reset") { stopwatch.reset() }
        }
    }

    @ViewBuilder private var timerOptions: some View {
        Menu("Start") {
            ForEach([1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60], id: \.self) { minutes in
                Button(minutes == 1 ? "1 minute" : "\(minutes) minutes") { timer.start(minutes: minutes) }
            }
        }
        switch timer.state {
        case .running: Button("Pause") { timer.pause() }
        case .paused: Button("Resume") { timer.toggle() }
        default: EmptyView()
        }
        if timer.state != .idle {
            Button("Reset") { timer.reset() }
        }
        Toggle("Chime When Done", isOn: $timer.sound)
    }
}
