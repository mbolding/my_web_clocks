// Word Clock — the time in words as a floating desktop clock.

import SwiftUI

@main
enum WordClockApp {
    @MainActor static func main() {
        // Starts below the analog clock rather than on top of it.
        DesktopClock.run(size: CGSize(width: 250, height: 250), defaultTop: 24 + 170 + 20) {
            TimelineView(.everyMinute) { timeline in
                WordFace(date: timeline.date)
                    .padding(16)
            }
        }
    }
}
