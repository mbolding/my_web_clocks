// CalendarFace — the month at a glance: its name, the weekday initials, and the days in
// a grid, with weekends greyed and today on a circle of the accent colour. The week
// starts on the system's first weekday, and the rows stretch to fill the window, so a
// four-, five- or six-week month all fill it.

import SwiftUI

struct CalendarFace: View {
    var date: Date
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent

    var body: some View {
        let cal = Calendar.current
        let first = cal.dateInterval(of: .month, for: date)!.start
        let days = cal.range(of: .day, in: .month, for: date)!.count
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7 // blanks before the 1st
        let weeks = (lead + days + 6) / 7
        let today = cal.component(.day, from: date)
        let ink: Color = scheme == .dark ? .white : .black

        // Columns by the date they hold in the first week (which may fall in the month
        // before), so the weekend comes from the calendar rather than being assumed.
        let columns = (0..<7).map { cal.date(byAdding: .day, value: $0 - lead, to: first)! }
        let weekend = columns.map(cal.isDateInWeekend)
        let dayColor = { (column: Int) in ink.opacity(weekend[column] ? 0.45 : 0.85) }

        GeometryReader { geo in
            let w = geo.size.width / 7, h = geo.size.height / CGFloat(weeks + 2)
            let font = min(w, h) * 0.62

            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.month(.wide)).uppercased())
                    .font(.system(size: font, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, maxHeight: h, alignment: .leading)
                    .padding(.leading, w * 0.12)

                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let weekday = cal.component(.weekday, from: columns[column]) - 1
                        Text(cal.veryShortStandaloneWeekdaySymbols[weekday])
                            .foregroundStyle(dayColor(column))
                            .frame(width: w, height: h)
                    }
                }
                .font(.system(size: font * 0.9, weight: .semibold))

                ForEach(0..<weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let day = week * 7 + column - lead + 1
                            ZStack {
                                if day == today {
                                    Circle().fill(accent).frame(width: min(w, h) * 0.98, height: min(w, h) * 0.98)
                                }
                                if (1...days).contains(day) {
                                    Text("\(day)")
                                        .fontWeight(day == today ? .bold : .semibold)
                                        .foregroundStyle(day == today ? accent.readableText : dayColor(column))
                                }
                            }
                            .frame(width: w, height: h)
                        }
                    }
                }
                .font(.system(size: font))
            }
        }
    }
}
