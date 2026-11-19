// GridLayout — the document as WordPerfect 5.1 put it on an 80-column text screen. Lines
// wrap at 65 columns (6.5" between 1" margins, at ten characters an inch), a page is 54
// lines (9" at six lines an inch), and formatting the screen can't show as a font it shows
// as a decoration: a bullet, a number, a bar down a quote, a line across for a rule, and a
// table in box-drawing lines, as WordPerfect 5.1's tables were. Also the rows of the Reveal
// Codes window, where the codes are written out in brackets.

import Foundation

struct Cell {
    enum Role: Equatable {
        case text
        /// Drawn for a code the screen otherwise hides: a bullet, a rule.
        case decoration
        /// A code written out in Reveal Codes; every cell of it carries the code's index.
        case code(Int)
        /// A return written out in Reveal Codes.
        case terminator
    }

    var char: Character
    var style: Style = []
    /// The source offset of the character, where the cursor can be on it.
    var offset: Int?
    var role: Role = .text
}

struct Row {
    var cells: [Cell] = []
    var line: Int
    /// Where the cursor sits after the row's last character, if it can: on the last row of
    /// a line, its hard return.
    var end: Int?
    var isPageBreak = false
    /// One of a table's lines, drawn between its rows.
    var isBorder = false
    /// Where the row's end shows, when it isn't after its last cell (a table row's end is
    /// inside its last cell).
    var endCol: Int?
    /// The row's number counting only rows of text, for the page and line in the status.
    var docRow = 0
}

struct GridLayout {
    static let width = 65
    static let pageLength = 54
    static let tab = 5

    private(set) var rows: [Row] = []
    /// Every place the cursor can be shown, in source order: (offset, row, column).
    private(set) var positions: [(offset: Int, row: Int, col: Int)] = []

    init(_ markup: Markup) {
        var docRow = 0
        for (index, line) in markup.lines.enumerated() {
            var lineRows: [Row]
            switch line.block {
            case .tableRow(let table, _), .tableRule(let table):
                // A table is laid out whole, at its first line.
                guard markup.tables[table].lines.lowerBound == index else { continue }
                lineRows = Self.tableRows(markup.tables[table], in: markup)
            default:
                lineRows = Self.rows(for: line, at: index, in: markup)
            }
            for var row in lineRows {
                if docRow > 0, docRow % Self.pageLength == 0 {
                    rows.append(Row(cells: Array(repeating: Cell(char: "─", role: .decoration), count: 80), line: index,
                                    isPageBreak: true, docRow: docRow))
                }
                row.docRow = docRow
                docRow += 1
                let n = rows.count
                for (col, cell) in row.cells.enumerated() where cell.role == .text {
                    if let offset = cell.offset { positions.append((offset, n, col)) }
                }
                if let end = row.end { positions.append((end, n, row.endCol ?? row.cells.count)) }
                rows.append(row)
            }
        }
        positions.sort { $0.offset < $1.offset }
    }

    /// Where an offset is shown: at the first place the cursor can be at or after it.
    func locate(_ offset: Int) -> (row: Int, col: Int) {
        var low = 0, high = positions.count - 1
        guard high >= 0 else { return (0, 0) }
        while low < high {
            let mid = (low + high) / 2
            if positions[mid].offset < offset { low = mid + 1 } else { high = mid }
        }
        let found = positions[low]
        return (found.row, found.col)
    }

    /// The cursor's offset for a row and column: the place on that row nearest the column,
    /// not past it.
    func offset(row: Int, col: Int) -> Int? {
        let places = positions.filter { $0.row == row }
        guard !places.isEmpty else { return nil }
        return (places.last { $0.col <= col } ?? places.first!).offset
    }

    func firstOffset(row: Int) -> Int? { positions.first { $0.row == row }?.offset }
    func lastOffset(row: Int) -> Int? { positions.last { $0.row == row }?.offset }

    // MARK: - Wrapping

    private static func rows(for line: Line, at index: Int, in markup: Markup) -> [Row] {
        let chars = markup.chars
        let dim = Style.quote
        var prefix: [Cell] = []
        switch line.block {
        case .bullet(let depth):
            prefix = spaces(depth * tab) + [Cell(char: "•", role: .decoration), Cell(char: " ", role: .decoration)]
        case .number(let text, let depth):
            let label = Array(text + " ").map { Cell(char: $0, role: .decoration) }
            prefix = spaces(depth * tab) + label + spaces(max(0, 4 - label.count))
        case .quote:
            prefix = [Cell(char: "│", style: dim, role: .decoration), Cell(char: " ", role: .decoration)]
        case .rule:
            return [Row(cells: Array(repeating: Cell(char: "─", role: .decoration), count: width), line: index, end: line.end)]
        case .fence:
            var label = "───"
            if let code = line.blockCode, case .fence(let info) = markup.codes[code].kind, markup.codes[code].opens {
                label += info.isEmpty ? " code " : " \(info) "
            }
            let cells = Array(label.padding(toLength: width, withPad: "─", startingAt: 0)).map { Cell(char: $0, role: .decoration) }
            return [Row(cells: cells, line: index, end: line.end)]
        default:
            break
        }

        // The text, with tabs spread to the next stop.
        var text: [Cell] = []
        for piece in line.pieces {
            guard case .char(let offset, let style) = piece else { continue }
            var char = chars[offset]
            if char == "\t" {
                text.append(Cell(char: " ", style: style, offset: offset))
                while (prefix.count + text.count) % tab != 0 { text.append(Cell(char: " ", style: style, role: .decoration)) }
                continue
            }
            if case .heading(1) = line.block, let upper = String(char).uppercased().first, String(char).uppercased().count == 1 {
                char = upper
            }
            text.append(Cell(char: char, style: style, offset: offset))
        }

        var rows: [Row] = []
        var current = prefix
        let hanging = spaces(prefix.count)
        var i = 0
        while i < text.count {
            current.append(text[i])
            i += 1
            // A space that lands on the margin stays at the end of the row, as in WordPerfect.
            while current.count >= width, i < text.count, text[i].char == " " {
                current.append(text[i])
                i += 1
            }
            if current.count >= width && i < text.count {
                // Break after the last space on the row, or mid-word if there isn't one.
                let start = rows.isEmpty ? prefix.count : hanging.count
                var cut = current.count
                if let space = current[start...].lastIndex(where: { $0.char == " " && $0.role == .text }), space + 1 > start {
                    cut = space + 1
                }
                let carried = Array(current[cut...])
                rows.append(Row(cells: Array(current[..<cut]), line: index))
                current = hanging + carried
            }
        }
        rows.append(Row(cells: current, line: index, end: line.end))
        return rows
    }

    // MARK: - Tables

    /// A table in box-drawing lines: a line above and below, a double line under the header,
    /// single lines between the rows, each column as wide as its widest cell, narrowed
    /// (widest first) to fit the page, with longer cells wrapping inside their column.
    private static func tableRows(_ table: Table, in markup: Markup) -> [Row] {
        let columns = max(1, table.columns)
        struct Content { var line: Int; var cells: [[Cell]]; var header: Bool }
        var contents: [Content] = []
        var ruleLine = table.lines.lowerBound + 1
        for index in table.lines {
            let line = markup.lines[index]
            if case .tableRule = line.block { ruleLine = index; continue }
            guard case .tableRow(_, let header) = line.block else { continue }
            var cells: [[Cell]] = [[]]
            var sawText = false
            for piece in line.pieces {
                switch piece {
                case .code(let code) where markup.codes[code].kind == .cell:
                    if sawText || cells.count > 1 || !cells[0].isEmpty { cells.append([]) }
                    sawText = true
                case .char(let offset, let style):
                    var char = markup.chars[offset]
                    if char == "\t" { char = " " }
                    cells[cells.count - 1].append(Cell(char: char, style: style, offset: offset))
                default:
                    break
                }
            }
            // A leading pipe leaves an empty first cell, a trailing one an empty last.
            if cells.count > 1, cells[0].allSatisfy({ $0.char == " " }), cells[0].isEmpty { cells.removeFirst() }
            if cells.count > columns, cells.last?.allSatisfy({ $0.char == " " }) == true, cells.last!.isEmpty { cells.removeLast() }
            // More cells than columns go in the last; fewer are left empty.
            while cells.count > columns { let extra = cells.removeLast(); cells[cells.count - 1] += extra }
            while cells.count < columns { cells.append([]) }
            contents.append(Content(line: index, cells: cells, header: header))
        }
        var widths = (0..<columns).map { c in max(3, contents.map { $0.cells[c].count }.max() ?? 3) }
        while widths.reduce(0, +) + columns + 1 > width, let widest = widths.indices.max(by: { widths[$0] < widths[$1] }), widths[widest] > 3 {
            widths[widest] -= 1
        }

        func border(_ left: Character, _ fill: Character, _ middle: Character, _ right: Character, line: Int) -> Row {
            var cells = [Cell(char: left, role: .decoration)]
            for (c, w) in widths.enumerated() {
                cells += Array(repeating: Cell(char: fill, role: .decoration), count: w)
                cells.append(Cell(char: c == columns - 1 ? right : middle, role: .decoration))
            }
            return Row(cells: cells, line: line, isBorder: true)
        }

        var rows = [border("┌", "─", "┬", "┐", line: table.lines.lowerBound)]
        for (r, content) in contents.enumerated() {
            // Each cell wrapped to its column, then the row as tall as its tallest cell.
            let wrapped = content.cells.enumerated().map { c, cells in wrap(cells, to: widths[c]) }
            let height = wrapped.map(\.count).max() ?? 1
            for h in 0..<height {
                var cells = [Cell(char: "│", role: .decoration)]
                var lastText = 1
                for c in 0..<columns {
                    let text = h < wrapped[c].count ? wrapped[c][h] : []
                    let room = widths[c] - text.count
                    let left = table.aligns.indices.contains(c) ? (table.aligns[c] == .right ? room : table.aligns[c] == .center ? room / 2 : 0) : 0
                    cells += spaces(left) + text + spaces(room - left)
                    if !text.isEmpty || c == 0 { lastText = cells.count }
                    cells.append(Cell(char: "│", role: .decoration))
                }
                var row = Row(cells: cells, line: content.line)
                if h == height - 1 {
                    row.end = markup.lines[content.line].end
                    row.endCol = lastText
                }
                rows.append(row)
            }
            if r < contents.count - 1 {
                rows.append(content.header ? border("╞", "═", "╪", "╡", line: ruleLine) : border("├", "─", "┼", "┤", line: content.line))
            }
        }
        rows.append(border("└", "─", "┴", "┘", line: table.lines.upperBound))
        return rows
    }

    /// A cell's text in lines no wider than its column, broken after spaces where it can be.
    private static func wrap(_ cells: [Cell], to width: Int) -> [[Cell]] {
        var lines: [[Cell]] = []
        var current: [Cell] = []
        for cell in cells {
            current.append(cell)
            if current.count > width {
                let cut = (current.lastIndex { $0.char == " " }).map { $0 + 1 } ?? width
                let usable = cut > 0 && cut <= width ? cut : width
                lines.append(Array(current[..<usable]))
                current = Array(current[usable...])
            }
        }
        lines.append(current)
        return lines
    }

    private static func spaces(_ count: Int) -> [Cell] {
        Array(repeating: Cell(char: " ", role: .decoration), count: max(0, count))
    }

    // MARK: - Reveal Codes

    /// What a code looks like written out, after WordPerfect's own: on in capitals, off in
    /// small letters.
    static func name(of code: Code) -> String {
        switch code.kind {
        case .bold: code.opens ? "[BOLD]" : "[bold]"
        case .italic: code.opens ? "[ITALC]" : "[italc]"
        case .strike: code.opens ? "[STKOUT]" : "[stkout]"
        case .code: code.opens ? "[CODE]" : "[code]"
        case .link(let address): code.opens ? "[LINK]" : "[link:\(short(address))]"
        case .image(let address): code.opens ? "[IMAGE]" : "[image:\(short(address))]"
        case .escape: "[\\]"
        case .heading(let level): "[Head \(level)]"
        case .bullet: "[Bullet]"
        case .number(let text, _): "[Num \(text)]"
        case .quote: "[Quote]"
        case .rule: "[HLine]"
        case .fence(let info): code.opens ? (info.isEmpty ? "[CODE BLOCK]" : "[CODE BLOCK:\(info)]") : "[code block]"
        case .cell: "[Cell]"
        case .tableRule(let aligns): "[Tbl Def:\(aligns.count) col\(aligns.count == 1 ? "" : "s")]"
        }
    }

    private static func short(_ address: String) -> String {
        address.count > 30 ? String(address.prefix(29)) + "…" : address
    }

    /// The Reveal Codes rows for the lines from `first` to `last`: each screen row's text
    /// with its codes written out, ending in [SRt] where the row wraps and [HRt] at a hard
    /// return, broken to fit 80 columns.
    func revealRows(_ markup: Markup, lines: ClosedRange<Int>) -> [[Cell]] {
        var out: [[Cell]] = []
        let rowIndexes = rows.indices.filter { !rows[$0].isPageBreak && !rows[$0].isBorder && lines.contains(rows[$0].line) }
        var cellsByRow: [Int: [Cell]] = [:]
        for lineIndex in lines {
            let line = markup.lines[lineIndex]
            for piece in line.pieces {
                switch piece {
                case .char(let offset, let style):
                    var char = markup.chars[offset]
                    if char == "\t" { char = "→" }
                    cellsByRow[locate(offset).row, default: []].append(Cell(char: char, style: style, offset: offset))
                case .code(let index):
                    let code = markup.codes[index]
                    let name = Self.name(of: code)
                    let row = locate(code.range.lowerBound).row
                    cellsByRow[row, default: []] += name.map { Cell(char: $0, offset: code.range.lowerBound, role: .code(index)) }
                }
            }
        }
        for n in rowIndexes {
            var cells = cellsByRow[n] ?? []
            let row = rows[n]
            if let end = row.end {
                if markup.lines[row.line].newline != nil {
                    cells += "[HRt]".map { Cell(char: $0, offset: end, role: .terminator) }
                }
            } else {
                cells += "[SRt]".map { Cell(char: $0, role: .terminator) }
            }
            if cells.isEmpty { cells = [] }
            while cells.count > 80 {
                out.append(Array(cells[..<80]))
                cells = Array(cells[80...])
            }
            out.append(cells)
        }
        return out
    }
}
