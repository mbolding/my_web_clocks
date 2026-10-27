// ClockWidgetExtension — the same dial as a WidgetKit widget (desktop / Notification Center).
// WidgetKit only redraws on a timeline, so this version has no second hand:
// we hand the system one entry per minute for the next hour, then it asks again.

import SwiftUI
import WidgetKit

struct MinuteEntry: TimelineEntry {
    let date: Date
}

struct MinuteProvider: TimelineProvider {
    func placeholder(in context: Context) -> MinuteEntry { MinuteEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (MinuteEntry) -> Void) {
        completion(MinuteEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MinuteEntry>) -> Void) {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .minute, for: .now)!.start
        let entries = (0..<60).map { MinuteEntry(date: cal.date(byAdding: .minute, value: $0, to: start)!) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct AnalogClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnalogClock", provider: MinuteProvider()) { entry in
            ClockFace(date: entry.date, showSeconds: false)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Analog Clock")
        .description("A simple analog clock with the day and date.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ClockWidgetBundle: WidgetBundle {
    var body: some Widget { AnalogClockWidget() }
}
