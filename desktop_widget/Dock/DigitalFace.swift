// DigitalFace — the time in figures, for Dock Clock's Digital choice. Sized off the
// square it's given, so it reads at Dock icon sizes: the weekday and date over large
// hours and minutes, and the seconds as an accent bar filling across the minute.

import SwiftUI

struct DigitalFace: View {
    var date: Date
    var showSeconds: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let ink: Color = scheme == .dark ? .white : .black
            // Hours follow the system's 12- or 24-hour setting, without AM/PM.
            let time = date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
            let weekday = date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
            let day = date.formatted(.dateTime.day())
            let second = Double(Calendar.current.component(.second, from: date))

            VStack(spacing: s * 0.05) {
                Text("\(Text(weekday).foregroundStyle(accent)) \(Text(day).foregroundStyle(ink.opacity(0.7)))")
                    .font(.system(size: s * 0.17, weight: .semibold, design: .rounded))
                Text(time)
                    .font(.system(size: s * 0.36, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: s)
                // The seconds bar keeps its place without seconds, so the time doesn't
                // jump when they're turned on and off.
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.12))
                    Capsule().fill(accent)
                        .frame(width: max(s * 0.06, s * 0.8 * (second + 1) / 60))
                }
                .frame(width: s * 0.8, height: s * 0.06)
                .opacity(showSeconds ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
