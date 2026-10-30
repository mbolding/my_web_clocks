// Clock Widget — the analog dial as a floating desktop clock.

import SwiftUI

@main
enum AnalogClockApp {
    @MainActor static func main() {
        DesktopClock.run(size: CGSize(width: 170, height: 170), canSitBehindIcons: true) {
            AnalogClockView()
        } options: {
            SecondsOption()
        }
    }
}

struct AnalogClockView: View {
    @AppStorage("showSeconds") private var showSeconds = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: showSeconds ? 1 : 15)) { timeline in
            ClockFace(date: timeline.date, showSeconds: showSeconds)
                .padding(14)
        }
    }
}

struct SecondsOption: View {
    @AppStorage("showSeconds") private var showSeconds = true

    var body: some View {
        Toggle("Show Seconds", isOn: $showSeconds)
    }
}
