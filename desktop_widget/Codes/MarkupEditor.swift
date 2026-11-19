// MarkupEditor — editing a Markdown document as a word processor edits text with hidden
// codes, after WordPerfect's rules. The cursor is an offset in the source. With the codes
// hidden it stops only on visible characters and at line ends, and it sits just before the
// character it's on, after any codes in front of that character; so a bold word's first
// letter is inside the bold, and the space after it is outside. Formatting keys work like
// WordPerfect's F6: press it to turn bold on, type, and press it again to step past the
// closing code. (The codes go in with the first character typed, since an empty pair isn't
// Markdown at all.) Pressed inside bold text, it turns bold off for what's typed next. With
// the codes revealed the cursor stops on codes too, and deleting one takes its partner.
//
// Like MarkupEngine, it knows nothing of how the text is drawn; moving up and down a row
// is left to the screen, which knows where the rows break.

import Foundation

final class MarkupEditor {
    private(set) var chars: [Character]
    private(set) var markup: Markup
    /// Where the cursor is, as a source offset.
    var cursor: Int {
        didSet {
            cursor = min(max(cursor, 0), chars.count)
            if cursor != pendingAt { pending = [] }
        }
    }
    /// Formatting turned on (true) or off (false) by F6 and the rest for what's typed next
    /// at the cursor, which only becomes codes once something is typed.
    private(set) var pending: [(kind: CodeKind, on: Bool)] = []
    private var pendingAt = -1
    /// The other end of a block (WordPerfect's word for a selection), if one is on.
    var anchor: Int?
    /// Whether the cursor stops on codes, as it does in Reveal Codes.
    var revealed = false

    init(text: String) {
        chars = Array(text)
        markup = Markup(chars)
        cursor = 0
    }

    var text: String { String(chars) }

    var selection: Range<Int>? {
        guard let anchor, anchor != cursor else { return nil }
        return min(anchor, cursor)..<max(anchor, cursor)
    }

    var stops: [Int] { markup.stops(revealed: revealed) }

    // MARK: - Moving

    /// The first stop at or after an offset: where the cursor is shown.
    func stop(atOrAfter offset: Int) -> Int {
        let stops = self.stops
        return stops.first { $0 >= offset } ?? chars.count
    }

    func moveLeft() {
        let stops = self.stops
        if let previous = stops.last(where: { $0 < cursor }) { cursor = previous }
    }

    func moveRight() {
        let here = stop(atOrAfter: cursor)
        if here > cursor { cursor = here; return }
        if let next = stops.first(where: { $0 > cursor }) { cursor = next }
    }

    func moveWord(forward: Bool) {
        let stops = self.stops
        func isSpace(_ offset: Int) -> Bool { offset >= chars.count || chars[offset].isWhitespace || chars[offset].isNewline }
        if forward {
            var i = stops.firstIndex { $0 > cursor } ?? stops.count
            while i < stops.count, !isSpace(stops[i]) { i += 1 }
            while i < stops.count, isSpace(stops[i]), stops[i] < chars.count, !chars[stops[i]].isNewline { i += 1 }
            cursor = i < stops.count ? stops[i] : chars.count
        } else {
            var i = (stops.lastIndex { $0 < cursor } ?? -1)
            while i > 0, isSpace(stops[i]) { i -= 1 }
            while i > 0, !isSpace(stops[i - 1]) { i -= 1 }
            if i >= 0 { cursor = stops[i] }
        }
    }

    // MARK: - Typing

    func insert(_ text: String) {
        if selection != nil { deleteSelection() }
        anchor = nil
        guard !pending.isEmpty, !text.isEmpty else {
            replace(cursor..<cursor, with: Array(text))
            cursor += text.count
            tidy()
            return
        }
        // Formatting waiting at the cursor: closing codes for what's turned off (and any
        // formatting inside it, to keep the pairs nested), opening codes for what's turned
        // on, the text, then the closing codes after the cursor and the turned-off
        // formatting opened again.
        let open = markup.openPairs(at: cursor)
        var inner: [Int] = []
        for off in pending where !off.on {
            if let at = open.firstIndex(where: { markup.codes[$0].kind.sameFormat(as: off.kind) }) {
                for index in open[at...] where !inner.contains(index) { inner.append(index) }
            }
        }
        inner.sort { markup.codes[$0].range.lowerBound < markup.codes[$1].range.lowerBound }
        let closers = inner.reversed().compactMap { markup.codes[$0].kind.delimiter }.joined()
        let reopen = inner.compactMap { markup.codes[$0].kind.delimiter }.joined()
        let ons = pending.filter(\.on).compactMap { $0.kind.delimiter }
        let before = closers + ons.joined() + text
        let after = ons.reversed().joined() + reopen
        pending = []
        replace(cursor..<cursor, with: Array(before + after))
        cursor += before.count
        tidy()
    }

    /// How text typed at the cursor will be formatted, counting F6 and the rest pressed
    /// but not yet typed after.
    var cursorStyle: Style {
        var style = markup.style(at: cursor)
        for change in pending {
            guard let flag = Markup.flag(change.kind) else { continue }
            if change.on { style.insert(flag) } else { style.remove(flag) }
        }
        return style
    }

    /// Enter: a hard return. A list item or quote carries on onto the next line, and Enter
    /// on an empty one ends the list instead. Formatting open at the cursor is closed
    /// before the return and opened again after it, so both halves keep it.
    func newline() {
        if selection != nil { deleteSelection() }
        anchor = nil
        let line = markup.lines[markup.lineIndex(at: cursor)]
        if let index = line.blockCode, line.firstVisible == nil, [.quote].contains(line.block) || isList(line.block) {
            removeBlockCode(index)
            tidy()
            return
        }
        var prefix = ""
        switch line.block {
        case .bullet:
            if let index = line.blockCode { prefix = String(chars[markup.codes[index].range]) }
        case .number(let text, _):
            if let index = line.blockCode {
                let written = String(chars[markup.codes[index].range])
                let number = Int(text.dropLast()) ?? 0
                prefix = written.replacingOccurrences(of: text, with: "\(number + 1)\(text.last!)")
            }
        case .quote:
            prefix = "> "
        default:
            break
        }
        let open = line.block == .fenced ? [] : markup.openPairs(at: cursor).filter { cursor > line.range.lowerBound && markup.codes[$0].kind.delimiter != nil }
        let closers = open.reversed().compactMap { markup.codes[$0].kind.delimiter }.joined()
        let openers = open.compactMap { markup.codes[$0].kind.delimiter }.joined()
        let inserted = closers + "\n" + prefix + openers
        replace(cursor..<cursor, with: Array(inserted))
        cursor += inserted.count
        tidy()
    }

    private func isList(_ block: BlockKind) -> Bool {
        if case .bullet = block { return true }
        if case .number = block { return true }
        return false
    }

    // MARK: - Deleting

    /// Backspace: the character before the cursor, or with the codes revealed, the code
    /// before it. At the start of a list item, heading or quote it takes off that
    /// formatting first; at the start of a plain line it joins the line to the one above.
    func deleteBackward() {
        if selection != nil { deleteSelection(); return }
        anchor = nil
        let lineIndex = markup.lineIndex(at: cursor)
        let line = markup.lines[lineIndex]
        let previousStops = stops.filter { $0 < cursor }
        // At the start of a line with a block code (nothing visible of it before the cursor).
        if let index = line.blockCode, line.block != .fence, cursor <= (line.firstVisible ?? line.end),
           cursor >= markup.codes[index].range.upperBound || !revealed {
            removeBlockCode(index)
            tidy()
            return
        }
        guard let previous = previousStops.last else { return }
        if revealed, let code = markup.code(startingAt: previous), !isNewline(previous) {
            deleteCode(code)
        } else if isNewline(previous) {
            remove(previous..<(previous + 1))
            cursor = previous
        } else {
            cursor -= removeChar(at: previous) - (cursor > previous ? 0 : 0)
        }
        tidy()
    }

    /// Takes out one visible character, and with it any pair of codes it was all that was
    /// left inside. Returns how many characters went before the cursor.
    @discardableResult
    private func removeChar(at offset: Int) -> Int {
        var range = offset..<(offset + 1)
        // Widen to each pair that holds nothing else.
        var widened = true
        while widened {
            widened = false
            for code in markup.codes where code.opens && code.kind.delimiter != nil {
                guard let partner = code.partner else { continue }
                let close = markup.codes[partner]
                if code.range.upperBound == range.lowerBound && close.range.lowerBound == range.upperBound {
                    range = code.range.lowerBound..<close.range.upperBound
                    widened = true
                }
            }
        }
        let before = cursor > range.lowerBound ? min(cursor, range.upperBound) - range.lowerBound : 0
        remove(range)
        return before
    }

    /// Delete: the character the cursor is on, or with the codes revealed, the code it's
    /// on. At the end of a line it joins the next line on, dropping that line's own list or
    /// heading code.
    func deleteForward() {
        if selection != nil { deleteSelection(); return }
        anchor = nil
        if revealed, let code = markup.code(startingAt: cursor) {
            deleteCode(code)
            tidy()
            return
        }
        let here = stop(atOrAfter: cursor)
        guard here < chars.count else { return }
        if isNewline(here) {
            let next = markup.lines[markup.lineIndex(at: here) + 1]
            if let index = next.blockCode, next.block != .fence {
                remove(markup.codes[index].range)
            }
            remove(here..<(here + 1))
        } else {
            let removedBefore = removeChar(at: here)
            cursor -= removedBefore
            cursor = min(cursor, chars.count)
            tidy()
            return
        }
        cursor = min(cursor, here)
        tidy()
    }

    func deleteSelection() {
        guard let range = selection else { anchor = nil; return }
        remove(range)
        cursor = range.lowerBound
        anchor = nil
        tidy()
    }

    /// Deletes a code, and its partner with it.
    func deleteCode(_ index: Int) {
        let code = markup.codes[index]
        var ranges = [code.range]
        if let partner = code.partner { ranges.append(markup.codes[partner].range) }
        if code.kind.isBlock && code.partner == nil {
            removeBlockCode(index)
            return
        }
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            remove(range)
            if cursor >= range.upperBound { cursor -= range.count } else if cursor > range.lowerBound { cursor = range.lowerBound }
        }
    }

    private func removeBlockCode(_ index: Int) {
        let range = markup.codes[index].range
        remove(range)
        if cursor >= range.upperBound { cursor -= range.count } else if cursor > range.lowerBound { cursor = range.lowerBound }
    }

    private func isNewline(_ offset: Int) -> Bool { offset < chars.count && chars[offset].isNewline }

    // MARK: - Formatting

    /// WordPerfect's F6 (bold), F8 (here italic, which it showed underlined) and the rest.
    /// With a block on, the block is formatted, line by line. With none, the cursor either
    /// steps past the closing code it's just before, or splits the formatting it's inside,
    /// or puts in a new pair of codes with itself between them.
    func toggle(_ kind: CodeKind) {
        guard let delimiter = kind.delimiter else { return }
        let mark = Array(delimiter)
        if let range = selection {
            var segments: [Range<Int>] = []
            for line in markup.lines where line.range.overlaps(range) || (line.range.isEmpty && range.contains(line.range.lowerBound)) {
                guard line.block != .fence, line.block != .rule else { continue }
                let textStart = line.blockCode.map { markup.codes[$0].range.upperBound } ?? line.range.lowerBound
                var a = max(range.lowerBound, textStart), b = min(range.upperBound, line.range.upperBound)
                while a < b, chars[a].isWhitespace { a += 1 }
                while b > a, chars[b - 1].isWhitespace { b -= 1 }
                if a < b { segments.append(a..<b) }
            }
            var end = range.upperBound
            for segment in segments.reversed() {
                replace(segment.upperBound..<segment.upperBound, with: mark)
                replace(segment.lowerBound..<segment.lowerBound, with: mark)
                if segment == segments.last { end = segment.upperBound + 2 * mark.count }
            }
            anchor = nil
            cursor = end
            tidy()
            return
        }
        anchor = nil
        let line = markup.lines[markup.lineIndex(at: cursor)]
        guard line.block != .fenced, line.block != .rule else { return }
        // Pressed again before typing anything: never mind.
        if let waiting = pending.firstIndex(where: { $0.kind.sameFormat(as: kind) }) {
            pending.remove(at: waiting)
            return
        }
        let open = markup.openPairs(at: cursor).filter { markup.codes[$0].kind.sameFormat(as: kind) }
        if let opener = open.last, let partner = markup.codes[opener].partner {
            let closer = markup.codes[partner]
            if cursor == closer.range.lowerBound {
                // Just before the closing code: step past it.
                cursor = closer.range.upperBound
                return
            }
            pending.append((kind, false))
        } else {
            pending.append((kind, true))
        }
        pendingAt = cursor
    }

    /// Makes the cursor's line (or every line of the block) a heading, a list item, a quote,
    /// a code block or a plain paragraph.
    func setBlock(_ block: BlockKind) {
        let range = selection ?? cursor..<cursor
        var lineIndexes = Array(markup.lineIndex(at: range.lowerBound)...markup.lineIndex(at: max(range.lowerBound, range.upperBound - (range.isEmpty ? 0 : 1))))
        lineIndexes = lineIndexes.filter { ![.fence].contains(markup.lines[$0].block) }
        anchor = nil
        if block == .fence {
            guard let first = lineIndexes.first, let last = lineIndexes.last else { return }
            let start = markup.lines[first].range.lowerBound, end = markup.lines[last].range.upperBound
            replace(end..<end, with: Array("\n```"))
            replace(start..<start, with: Array("```\n"))
            cursor += 4
            tidy()
            return
        }
        var number = 1
        for index in lineIndexes.reversed() {
            let line = markup.lines[index]
            let start = line.range.lowerBound
            var removed = 0
            if let code = line.blockCode, line.block != .fence {
                let codeRange = markup.codes[code].range
                remove(codeRange)
                removed = codeRange.count
            }
            let prefix: String
            switch block {
            case .heading(let level): prefix = String(repeating: "#", count: level) + " "
            case .bullet(let depth): prefix = String(repeating: "  ", count: depth) + "- "
            case .number(_, let depth): prefix = String(repeating: "  ", count: depth) + "\(lineIndexes.count - number + 1). "
            case .quote: prefix = "> "
            default: prefix = ""
            }
            number += 1
            replace(start..<start, with: Array(prefix))
            if cursor >= start { cursor += prefix.count - min(removed, cursor - start) }
        }
        tidy()
    }

    // MARK: - Undo

    struct Snapshot {
        var chars: [Character]
        var cursor: Int
    }

    var snapshot: Snapshot { Snapshot(chars: chars, cursor: cursor) }

    func restore(_ snapshot: Snapshot) {
        chars = snapshot.chars
        markup = Markup(chars)
        cursor = snapshot.cursor
        anchor = nil
    }

    func replaceAll(with text: String) {
        chars = Array(text)
        markup = Markup(chars)
        cursor = min(cursor, chars.count)
        anchor = nil
    }

    // MARK: - Underneath

    private func replace(_ range: Range<Int>, with new: [Character]) {
        chars.replaceSubrange(range, with: new)
        markup = Markup(chars)
    }

    private func remove(_ range: Range<Int>) {
        replace(range, with: [])
    }

    /// Joins formatting split in two: a pair's closing code followed straight away by an
    /// opening one of the same kind, as when the space between two bold words is deleted.
    /// (A pair with nothing between isn't Markdown, so it's read as plain asterisks and
    /// never gets here; removeChar keeps them from being left behind.)
    func tidy() {
        var changed = true
        while changed {
            changed = false
            for (index, code) in markup.codes.enumerated() where code.opens && code.kind.delimiter != nil {
                guard let partner = code.partner else { continue }
                let close = markup.codes[partner]
                if code.range.upperBound == close.range.lowerBound && cursor != code.range.upperBound {
                    let whole = code.range.lowerBound..<close.range.upperBound
                    remove(whole)
                    if cursor >= whole.upperBound { cursor -= whole.count } else if cursor > whole.lowerBound { cursor = whole.lowerBound }
                    changed = true
                    break
                }
                _ = index
            }
            if changed { continue }
            for code in markup.codes where !code.opens && code.kind.delimiter != nil {
                guard let next = markup.codes.first(where: { $0.opens && $0.range.lowerBound == code.range.upperBound && $0.kind == code.kind })
                else { continue }
                let whole = code.range.lowerBound..<next.range.upperBound
                remove(whole)
                if cursor >= whole.upperBound { cursor -= whole.count } else if cursor > whole.lowerBound { cursor = whole.lowerBound }
                changed = true
                break
            }
        }
    }
}
