// Month Calendar — this month's calendar as a floating desktop widget.

import SwiftUI

@main
enum MonthCalendarApp {
    @MainActor static func main() {
        // The same size as the analog clock, and starts just to its left.
        DesktopClock.run(size: CGSize(width: 170, height: 170), defaultRight: 24 + 170 + 20,
                         canSitBehindIcons: true) {
            TimelineView(.everyMinute) { timeline in
                CalendarFace(date: timeline.date)
                    .padding(EdgeInsets(top: 12, leading: 10, bottom: 10, trailing: 10))
            }
        }
    }
}
