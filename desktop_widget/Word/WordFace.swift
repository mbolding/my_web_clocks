// WordFace — the time spelled out on an 11×11 letter grid, to the nearest five minutes.
// Same grid and rules as clocks/art/word_clock.html: "IT IS A QUARTER PAST THREE PM",
// with the hour picked out in the accent colour.

import SwiftUI

enum WordGrid {
    static let rows = [
        "ITLISASAMPM",
        "ACQUARTERDC",
        "TWENTYFIVEX",
        "HALFBTENFTO",
        "PASTERUNINE",
        "ONESIXTHREE",
        "FOURFIVETWO",
        "EIGHTELEVEN",
        "SEVENTWELVE",
        "TLOTENSDOCL",
        "OCKAMPMTIME",
    ].map(Array.init)

    // Word positions as (row, columns); OCLOCK wraps from the end of one row onto the next.
    static let words: [String: [(row: Int, cols: ClosedRange<Int>)]] = [
        "IT": [(0, 0...1)], "IS": [(0, 3...4)], "A": [(0, 5...5)],
        "AM": [(10, 3...4)], "PM": [(10, 5...6)],
        "QUARTER": [(1, 2...8)], "TWENTY": [(2, 0...5)], "FIVE_MIN": [(2, 6...9)],
        "HALF": [(3, 0...3)], "TEN_MIN": [(3, 5...7)], "TO": [(3, 9...10)], "PAST": [(4, 0...3)],
        "ONE": [(5, 0...2)], "TWO": [(6, 8...10)], "THREE": [(5, 6...10)], "FOUR": [(6, 0...3)],
        "FIVE": [(6, 4...7)], "SIX": [(5, 3...5)], "SEVEN": [(8, 0...4)], "EIGHT": [(7, 0...4)],
        "NINE": [(4, 7...10)], "TEN": [(9, 3...5)], "ELEVEN": [(7, 5...10)], "TWELVE": [(8, 5...10)],
        "OCLOCK": [(9, 8...10), (10, 0...2)],
    ]

    static let hourWords = ["TWELVE", "ONE", "TWO", "THREE", "FOUR", "FIVE",
                            "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN"]

    /// The words to light for `date`, and which one is the hour.
    static func phrase(at date: Date) -> (words: [String], hour: String) {
        let t = Calendar.current.dateComponents([.hour, .minute], from: date)
        let rounded = Int((Double(t.minute ?? 0) / 5).rounded()) * 5
        // Past the half hour we count down to the next hour.
        let hour = ((t.hour ?? 0) + (rounded > 30 ? 1 : 0)) % 24

        var words = ["IT", "IS"]
        switch rounded {
        case 0, 60: words += ["OCLOCK"]
        case 5, 55: words += ["FIVE_MIN"]
        case 10, 50: words += ["TEN_MIN"]
        case 15, 45: words += ["A", "QUARTER"]
        case 20, 40: words += ["TWENTY"]
        case 25, 35: words += ["TWENTY", "FIVE_MIN"]
        default: words += ["HALF"]
        }
        if rounded != 0 && rounded != 60 {
            words += [rounded > 30 ? "TO" : "PAST"]
        }
        words += [hour >= 12 ? "PM" : "AM"]
        return (words, hourWords[hour % 12])
    }

    /// Lit cells (row * 11 + column), split into plain and accent.
    static func cells(at date: Date) -> (lit: Set<Int>, accent: Set<Int>) {
        func cells(_ word: String) -> [Int] {
            words[word, default: []].flatMap { run in run.cols.map { run.row * 11 + $0 } }
        }
        let (lit, hour) = phrase(at: date)
        return (Set(lit.flatMap(cells)), Set(cells(hour)))
    }
}

struct WordFace: View {
    var date: Date
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accentColor

    var body: some View {
        let (lit, accent) = WordGrid.cells(at: date)
        let ink: Color = scheme == .dark ? .white : .black

        GeometryReader { geo in
            let cell = min(geo.size.width, geo.size.height) / 11
            VStack(spacing: 0) {
                ForEach(0..<11, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<11, id: \.self) { col in
                            let i = row * 11 + col
                            let letter = Text(String(WordGrid.rows[row][col]))
                            let color = accent.contains(i) ? accentColor : ink
                            ZStack {
                                letter.foregroundStyle(ink.opacity(scheme == .dark ? 0.16 : 0.12))
                                letter.foregroundStyle(color)
                                    .shadow(color: scheme == .dark ? color.opacity(0.6) : .clear, radius: cell * 0.25)
                                    .opacity(lit.contains(i) || accent.contains(i) ? 1 : 0)
                            }
                            .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .font(.system(size: cell * 0.6, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.4), value: [lit, accent])
        }
    }
}
