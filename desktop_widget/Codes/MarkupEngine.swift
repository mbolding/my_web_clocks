// MarkupEngine — Markdown read the way an old word processor kept its formatting: as codes
// hidden in the text. Each source line is one paragraph (a hard return ends it, as in
// WordPerfect), and every piece of markup becomes a code: a block code at the start of the
// line (`# `, `- `, `1. `, `> `, a fence) and paired inline codes around the text they
// format (`**` for bold, `*` for italic, `~~`, backticks, a link's `[` and `](address)`).
// What's left is the visible text, each character with its style.
//
// This file knows nothing about how it's drawn: the WordPerfect screen lays it out in a
// character grid, and a proportional, Word-style screen could lay out the same pieces.
// Offsets are indexes into the document's array of Characters.

import Foundation

enum CodeKind: Equatable {
    // Inline, in pairs.
    case bold, italic, strike, code
    /// A link: `[` opens it and `](address)` closes it, so the closing code carries the address.
    case link(String)
    case image(String)
    /// A backslash keeping the next character from being read as markup.
    case escape
    // Block codes, at the start of a line.
    case heading(Int)
    case bullet(Int)
    case number(String, Int)
    case quote
    case rule
    case fence(String)

    var isBlock: Bool {
        switch self {
        case .heading, .bullet, .number, .quote, .rule, .fence: true
        default: false
        }
    }

    /// The markup a pair of these codes is written with, for adding new ones.
    var delimiter: String? {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .strike: "~~"
        case .code: "`"
        default: nil
        }
    }

    /// Bold and bold, italic and italic: the same kind of formatting, whatever it carries.
    func sameFormat(as other: CodeKind) -> Bool {
        switch (self, other) {
        case (.bold, .bold), (.italic, .italic), (.strike, .strike), (.code, .code),
             (.link, .link), (.image, .image), (.fence, .fence): true
        default: false
        }
    }
}

struct Code: Equatable {
    var kind: CodeKind
    /// The markup characters it stands for.
    var range: Range<Int>
    /// For a pair, whether this is the one that starts it.
    var opens: Bool
    /// The other code of a pair, as an index into `Markup.codes`.
    var partner: Int?
}

struct Style: OptionSet, Hashable {
    let rawValue: Int
    static let bold = Style(rawValue: 1)
    static let italic = Style(rawValue: 2)
    static let strike = Style(rawValue: 4)
    static let code = Style(rawValue: 8)
    static let link = Style(rawValue: 16)
    static let heading = Style(rawValue: 32)
    static let quote = Style(rawValue: 64)
    /// Inside a fenced code block.
    static let block = Style(rawValue: 128)
}

enum Piece: Equatable {
    /// A visible character: its offset and how it's formatted.
    case char(Int, Style)
    /// A hidden code, as an index into `Markup.codes`.
    case code(Int)
}

enum BlockKind: Equatable {
    case paragraph
    case heading(Int)
    case bullet(Int)
    case number(String, Int)
    case quote
    case rule
    /// A fence line, opening or closing a code block.
    case fence
    /// A line inside a code block.
    case fenced
}

struct Line {
    /// The line's characters, not counting its hard return.
    var range: Range<Int>
    /// The hard return's offset, or nil for the last line.
    var newline: Int?
    var block: BlockKind = .paragraph
    /// The block code at its start, as an index into `Markup.codes`.
    var blockCode: Int?
    var pieces: [Piece] = []

    /// Where the cursor sits at the end of the line: on its hard return, or the end of the
    /// document.
    var end: Int { newline ?? range.upperBound }

    /// The offset of the first visible character, if it has any.
    var firstVisible: Int? {
        for case let .char(offset, _) in pieces { return offset }
        return nil
    }
}

struct Markup {
    let chars: [Character]
    private(set) var lines: [Line] = []
    private(set) var codes: [Code] = []

    init(_ chars: [Character]) {
        self.chars = chars
        parse()
    }

    /// The line holding an offset; an offset on a hard return belongs to the line it ends.
    func lineIndex(at offset: Int) -> Int {
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].range.lowerBound <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Where the cursor can stop: on every visible character and at the end of every line,
    /// and with the codes revealed, on every code as well.
    func stops(revealed: Bool) -> [Int] {
        var stops: [Int] = []
        for line in lines {
            for piece in line.pieces {
                switch piece {
                case .char(let offset, _): stops.append(offset)
                case .code(let index): if revealed { stops.append(codes[index].range.lowerBound) }
                }
            }
            stops.append(line.end)
        }
        return stops
    }

    /// The code starting at an offset, if one does.
    func code(startingAt offset: Int) -> Int? {
        codes.firstIndex { $0.range.lowerBound == offset }
    }

    /// The style a character typed at this offset would have.
    func style(at offset: Int) -> Style {
        let line = lines[lineIndex(at: offset)]
        var style = Style()
        var counts: [Int: Int] = [:]
        if case .heading = line.block { style.insert(.heading) }
        if line.block == .quote { style.insert(.quote) }
        if line.block == .fenced { return [.block] }
        for piece in line.pieces {
            guard case .code(let index) = piece else { continue }
            let code = codes[index]
            guard code.range.upperBound <= offset, code.partner != nil, let flag = Self.flag(code.kind) else { continue }
            counts[flag.rawValue, default: 0] += code.opens ? 1 : -1
        }
        for (raw, count) in counts where count > 0 { style.insert(Style(rawValue: raw)) }
        return style
    }

    /// The inline pairs that are open at an offset, outermost first.
    func openPairs(at offset: Int) -> [Int] {
        let line = lines[lineIndex(at: offset)]
        var open: [Int] = []
        for piece in line.pieces {
            guard case .code(let index) = piece else { continue }
            let code = codes[index]
            guard code.partner != nil, !code.kind.isBlock else { continue }
            if code.opens {
                if code.range.upperBound <= offset { open.append(index) }
            } else if code.range.upperBound <= offset {
                open.removeAll { $0 == code.partner }
            }
        }
        return open
    }

    static func flag(_ kind: CodeKind) -> Style? {
        switch kind {
        case .bold: .bold
        case .italic: .italic
        case .strike: .strike
        case .code: .code
        case .link, .image: .link
        default: nil
        }
    }

    // MARK: - Blocks

    private mutating func parse() {
        var start = 0
        var fence: (char: Character, length: Int, code: Int)?
        while true {
            var end = start
            while end < chars.count, !chars[end].isNewline { end += 1 }
            var line = Line(range: start..<end, newline: end < chars.count ? end : nil)
            if let open = fence {
                if let closing = fenceRun(start, end), closing.char == open.char, closing.length >= open.length,
                   chars[(start + closing.indent + closing.length)..<end].allSatisfy(\.isWhitespace) {
                    line.block = .fence
                    let index = addCode(Code(kind: .fence(""), range: start..<end, opens: false, partner: open.code))
                    codes[open.code].partner = index
                    line.blockCode = index
                    line.pieces = [.code(index)]
                    fence = nil
                } else {
                    line.block = .fenced
                    line.pieces = (start..<end).map { .char($0, [.block]) }
                }
            } else if let run = fenceRun(start, end) {
                line.block = .fence
                let info = String(chars[(start + run.indent + run.length)..<end]).trimmingCharacters(in: .whitespaces)
                let index = addCode(Code(kind: .fence(info), range: start..<end, opens: true, partner: nil))
                line.blockCode = index
                line.pieces = [.code(index)]
                fence = (run.char, run.length, index)
            } else {
                parseBlock(&line)
            }
            lines.append(line)
            guard end < chars.count else { break }
            start = end + 1
        }
        // A fence never closed runs to the end of the document, as Markdown has it.
    }

    private func fenceRun(_ start: Int, _ end: Int) -> (char: Character, length: Int, indent: Int)? {
        var i = start
        while i < end, chars[i] == " ", i - start < 3 { i += 1 }
        guard i < end, chars[i] == "`" || chars[i] == "~" else { return nil }
        let char = chars[i]
        var j = i
        while j < end, chars[j] == char { j += 1 }
        guard j - i >= 3 else { return nil }
        if char == "`", chars[j..<end].contains("`") { return nil }
        return (char, j - i, i - start)
    }

    private mutating func parseBlock(_ line: inout Line) {
        let start = line.range.lowerBound, end = line.range.upperBound
        var i = start
        while i < end, chars[i] == " " { i += 1 }
        let indent = i - start
        var blockEnd: Int?
        var kind: CodeKind?

        func spaces(after j: Int) -> Int? {
            guard j == end || chars[j] == " " || chars[j] == "\t" else { return nil }
            var k = j
            while k < end, chars[k] == " " || chars[k] == "\t" { k += 1 }
            return k
        }

        if indent <= 3, i < end, chars[i] == "#" {
            var j = i
            while j < end, chars[j] == "#" { j += 1 }
            if j - i <= 6, let after = spaces(after: j) {
                kind = .heading(j - i)
                blockEnd = after
            }
        }
        if kind == nil, indent <= 3, isRule(i, end) {
            kind = .rule
            blockEnd = end
        }
        if kind == nil, indent <= 3, i < end, chars[i] == ">" {
            kind = .quote
            blockEnd = i + 1 < end && chars[i + 1] == " " ? i + 2 : i + 1
        }
        if kind == nil, i < end, "-*+".contains(chars[i]), let after = spaces(after: i + 1), after > i + 1 || i + 1 == end {
            kind = .bullet(indent / 2)
            blockEnd = after
        }
        if kind == nil, i < end, chars[i].isASCII, chars[i].isNumber {
            var j = i
            while j < end, chars[j].isASCII, chars[j].isNumber, j - i < 9 { j += 1 }
            if j < end, chars[j] == "." || chars[j] == ")", let after = spaces(after: j + 1), after > j + 1 || j + 1 == end {
                kind = .number(String(chars[i...j]), indent / 2)
                blockEnd = after
            }
        }

        var textStart = start
        if let kind, let blockEnd {
            let index = addCode(Code(kind: kind, range: start..<blockEnd, opens: true, partner: nil))
            line.blockCode = index
            line.pieces.append(.code(index))
            switch kind {
            case .heading(let level): line.block = .heading(level)
            case .bullet(let depth): line.block = .bullet(depth)
            case .number(let text, let depth): line.block = .number(text, depth)
            case .quote: line.block = .quote
            default: line.block = .rule
            }
            textStart = blockEnd
        }
        guard line.block != .rule else { return }
        var base = Style()
        if case .heading = line.block { base.insert(.heading) }
        if line.block == .quote { base.insert(.quote) }
        line.pieces += inline(textStart..<end, base: base)
    }

    private func isRule(_ start: Int, _ end: Int) -> Bool {
        var char: Character?
        var count = 0
        for c in chars[start..<end] where c != " " && c != "\t" {
            guard "-*_".contains(c), char == nil || char == c else { return false }
            char = c
            count += 1
        }
        return count >= 3
    }

    // MARK: - Inline

    /// One step of a line's text before emphasis is matched.
    private indirect enum Atom {
        case char(Int)
        /// A run of `*`, `_` or `~` that might open or close emphasis.
        case run(char: Character, start: Int, length: Int, canOpen: Bool, canClose: Bool)
        /// Codes already decided (code spans, escapes), with what's between them.
        case fixed([Piece])
        /// A link: its codes and the text inside, already parsed.
        case group(open: Int, inner: [Atom], close: Int)
    }

    private mutating func inline(_ range: Range<Int>, base: Style) -> [Piece] {
        let atoms = atomize(range)
        var matched = match(atoms)
        return flatten(&matched, base: base)
    }

    private func isPunctuation(_ c: Character) -> Bool { c.isPunctuation || c.isSymbol }

    private mutating func atomize(_ range: Range<Int>) -> [Atom] {
        var atoms: [Atom] = []
        var i = range.lowerBound
        let end = range.upperBound
        while i < end {
            let c = chars[i]
            if c == "\\", i + 1 < end, chars[i + 1].isASCII, isPunctuation(chars[i + 1]) {
                let index = addCode(Code(kind: .escape, range: i..<(i + 1), opens: true, partner: nil))
                atoms.append(.fixed([.code(index), .char(i + 1, [])]))
                i += 2
            } else if c == "`" {
                var j = i
                while j < end, chars[j] == "`" { j += 1 }
                let length = j - i
                if let close = closingTicks(from: j, end: end, length: length) {
                    let open = addCode(Code(kind: .code, range: i..<j, opens: true, partner: nil))
                    let shut = addCode(Code(kind: .code, range: close..<(close + length), opens: false, partner: open))
                    codes[open].partner = shut
                    atoms.append(.fixed([.code(open)] + (j..<close).map { .char($0, [.code]) } + [.code(shut)]))
                    i = close + length
                } else {
                    atoms += (i..<j).map { .char($0) }
                    i = j
                }
            } else if c == "[" || (c == "!" && i + 1 < end && chars[i + 1] == "["), let link = linkEnd(from: c == "!" ? i + 1 : i, end: end) {
                let openEnd = c == "!" ? i + 2 : i + 1
                let address = String(chars[(link.bracket + 2)..<link.paren]).trimmingCharacters(in: .whitespaces)
                let kindOpen: CodeKind = c == "!" ? .image(address) : .link(address)
                let open = addCode(Code(kind: kindOpen, range: i..<openEnd, opens: true, partner: nil))
                let inner = atomize(openEnd..<link.bracket)
                let shut = addCode(Code(kind: kindOpen, range: link.bracket..<(link.paren + 1), opens: false, partner: open))
                codes[open].partner = shut
                atoms.append(.group(open: open, inner: inner, close: shut))
                i = link.paren + 1
            } else if c == "*" || c == "_" || c == "~" {
                var j = i
                while j < end, chars[j] == c { j += 1 }
                let before: Character? = i > range.lowerBound ? chars[i - 1] : nil
                let after: Character? = j < end ? chars[j] : nil
                let beforeSpace = before.map(\.isWhitespace) ?? true, afterSpace = after.map(\.isWhitespace) ?? true
                let beforePunct = before.map(isPunctuation) ?? false, afterPunct = after.map(isPunctuation) ?? false
                let left = !afterSpace && (!afterPunct || beforeSpace || beforePunct)
                let right = !beforeSpace && (!beforePunct || afterSpace || afterPunct)
                var canOpen = left, canClose = right
                if c == "_" {
                    canOpen = left && (!right || beforePunct)
                    canClose = right && (!left || afterPunct)
                }
                if c == "~" && j - i != 2 {
                    atoms += (i..<j).map { .char($0) }
                } else {
                    atoms.append(.run(char: c, start: i, length: j - i, canOpen: canOpen, canClose: canClose))
                }
                i = j
            } else {
                atoms.append(.char(i))
                i += 1
            }
        }
        return atoms
    }

    private func closingTicks(from start: Int, end: Int, length: Int) -> Int? {
        var i = start
        while i < end {
            if chars[i] == "`" {
                var j = i
                while j < end, chars[j] == "`" { j += 1 }
                if j - i == length { return i }
                i = j
            } else {
                i += 1
            }
        }
        return nil
    }

    /// The `]` and the `)` of a link starting at `[`, if it is one.
    private func linkEnd(from start: Int, end: Int) -> (bracket: Int, paren: Int)? {
        var depth = 0
        var i = start
        while i < end {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "[" { depth += 1 }
            if chars[i] == "]" {
                depth -= 1
                if depth == 0 { break }
            }
            i += 1
        }
        guard i < end, i + 1 < end, chars[i + 1] == "(" else { return nil }
        var parens = 0
        var j = i + 1
        while j < end {
            if chars[j] == "(" { parens += 1 }
            if chars[j] == ")" {
                parens -= 1
                if parens == 0 { return (i, j) }
            }
            j += 1
        }
        return nil
    }

    /// What became of each delimiter run: the codes cut from it, and how many of its
    /// characters are left as text.
    private struct RunResult {
        var opening: [(range: Range<Int>, code: Int)] = [] // cut from its end, innermost first
        var closing: [(range: Range<Int>, code: Int)] = [] // cut from its start, innermost first
    }

    private enum Matched {
        case atom(Atom)
        case run(char: Character, start: Int, length: Int, result: RunResult)
        case group(open: Int, inner: [Matched], close: Int)
    }

    /// Pairs up emphasis runs the way CommonMark does, more or less: each closer takes the
    /// nearest opener of the same character before it, two at a time where both have two.
    private mutating func match(_ atoms: [Atom]) -> [Matched] {
        var items: [Matched] = atoms.map { atom in
            switch atom {
            case .run(let char, let start, let length, _, _): .run(char: char, start: start, length: length, result: RunResult())
            case .group(let open, let inner, let close): .group(open: open, inner: match(inner), close: close)
            default: .atom(atom)
            }
        }
        struct Delim { var item: Int; var char: Character; var start: Int; var length: Int; var remaining: Int; var used = 0; var opened = 0; var canOpen: Bool; var canClose: Bool; var alive = true }
        var delims: [Delim] = []
        for (n, atom) in atoms.enumerated() {
            if case .run(let char, let start, let length, let canOpen, let canClose) = atom {
                delims.append(Delim(item: n, char: char, start: start, length: length, remaining: length, canOpen: canOpen, canClose: canClose))
            }
        }
        var closer = 0
        while closer < delims.count {
            guard delims[closer].canClose, delims[closer].remaining > 0 else { closer += 1; continue }
            var opener = closer - 1
            while opener >= 0 && !(delims[opener].alive && delims[opener].char == delims[closer].char
                                   && delims[opener].canOpen && delims[opener].remaining > 0) {
                opener -= 1
            }
            guard opener >= 0 else { closer += 1; continue }
            let both = min(delims[opener].remaining, delims[closer].remaining)
            let char = delims[closer].char
            if char == "~" && both < 2 { closer += 1; continue }
            let use = both >= 2 ? 2 : 1
            let kind: CodeKind = char == "~" ? .strike : use == 2 ? .bold : .italic
            // Cut from the inside of each run: an opener from its end, a closer from its start
            // (a run can be both, closing one span and opening the next).
            let openEnd = delims[opener].start + delims[opener].length - delims[opener].opened
            let closeStart = delims[closer].start + delims[closer].used
            let open = addCode(Code(kind: kind, range: (openEnd - use)..<openEnd, opens: true, partner: nil))
            let shut = addCode(Code(kind: kind, range: closeStart..<(closeStart + use), opens: false, partner: open))
            codes[open].partner = shut
            if case .run(let c, let s, let l, var result) = items[delims[opener].item] {
                result.opening.append(((openEnd - use)..<openEnd, open))
                items[delims[opener].item] = .run(char: c, start: s, length: l, result: result)
            }
            if case .run(let c, let s, let l, var result) = items[delims[closer].item] {
                result.closing.append((closeStart..<(closeStart + use), shut))
                items[delims[closer].item] = .run(char: c, start: s, length: l, result: result)
            }
            delims[opener].remaining -= use
            delims[opener].opened += use
            delims[closer].remaining -= use
            delims[closer].used += use
            // Openers between the two can't be used any more.
            for k in (opener + 1)..<closer { delims[k].alive = false }
            if delims[closer].remaining == 0 { closer += 1 }
        }
        return items
    }

    private func flatten(_ items: inout [Matched], base: Style) -> [Piece] {
        var pieces: [Piece] = []
        func walk(_ items: [Matched]) {
            for item in items {
                switch item {
                case .atom(.char(let offset)):
                    pieces.append(.char(offset, []))
                case .atom(.fixed(let fixed)):
                    pieces += fixed
                case .atom:
                    break
                case .group(let open, let inner, let close):
                    pieces.append(.code(open))
                    walk(inner)
                    pieces.append(.code(close))
                case .run(_, let start, let length, let result):
                    let closingLength = result.closing.reduce(0) { $0 + $1.range.count }
                    let openingLength = result.opening.reduce(0) { $0 + $1.range.count }
                    // Closing codes come first in the run, innermost first; then the
                    // characters left as text; then the opening codes, outermost first.
                    for cut in result.closing { pieces.append(.code(cut.code)) }
                    for offset in (start + closingLength)..<(start + length - openingLength) {
                        pieces.append(.char(offset, []))
                    }
                    for cut in result.opening.reversed() { pieces.append(.code(cut.code)) }
                }
            }
        }
        walk(items)
        // Give each character the style of the pairs open around it.
        var counts: [Int: Int] = [:]
        return pieces.map { piece in
            switch piece {
            case .code(let index):
                if let flag = Self.flag(codes[index].kind), codes[index].partner != nil {
                    counts[flag.rawValue, default: 0] += codes[index].opens ? 1 : -1
                }
                return piece
            case .char(let offset, let own):
                var style = base.union(own)
                for (raw, count) in counts where count > 0 { style.insert(Style(rawValue: raw)) }
                return .char(offset, style)
            }
        }
    }

    private mutating func addCode(_ code: Code) -> Int {
        codes.append(code)
        return codes.count - 1
    }
}
