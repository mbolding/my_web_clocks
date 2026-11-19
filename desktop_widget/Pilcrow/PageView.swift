// PageView — Pilcrow's page: Word 5.1's Normal view, proportional type on white with the
// Markdown hidden, by the same rules as Reveal Codes. The text view holds the whole Markdown
// source, and the markup's characters are kept from being drawn (their glyphs made null)
// rather than taken out, so nothing has to be mapped back. Every edit goes to MarkupEditor,
// which knows the codes, and the text view is brought into line after it. Show ¶ draws the
// markup in grey where it is, with ¶ at each return and a dot in each space, as Word's did.
// A table is the one place the text view's text differs from the file: each `|` becomes a
// paragraph break (the same length, so offsets still match), so that every cell can be a
// cell of a real text table, wrapping inside its column as Word's did.

import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// Markup kept from being drawn while Show ¶ is off.
    static let markupHidden = NSAttributedString.Key("PilcrowMarkupHidden")
    /// A list item's `-`, drawn as a bullet.
    static let bulletMark = NSAttributedString.Key("PilcrowBulletMark")
    /// A horizontal rule's line, drawn across the page.
    static let pageRule = NSAttributedString.Key("PilcrowPageRule")
    /// A quote's line, with a bar down its left side.
    static let quoteBar = NSAttributedString.Key("PilcrowQuoteBar")
    /// Which table cell a paragraph is in. The text system merges runs whose attributes
    /// compare equal, and takes cells of one row for equal; this keeps them apart, so each
    /// paragraph keeps its own cell's block.
    static let tableCell = NSAttributedString.Key("PilcrowTableCell")
}

/// What the chrome needs to know about the page: the formatting at the insertion point for
/// the Ribbon, the paragraph's indents for the Ruler, and the page for the page box.
final class PageState: ObservableObject {
    @Published var style = Style()
    @Published var block = BlockKind.paragraph
    @Published var page = 1
    @Published var showMarks = false
    weak var view: PageTextView?
}

enum Page {
    /// Word 5.1's view at 100% drew 72 points to the inch; on today's screens 150% reads
    /// about the same.
    static let zoom: CGFloat = 1.5
    static let inch: CGFloat = 72 * zoom
    static let textWidth = 6.5 * inch
    static let textHeight = 9 * inch
    static let margin = 1 * inch
    static let bodySize: CGFloat = 12 * zoom
}

// MARK: - Styling

/// The text-table objects for a document's tables, kept from one restyling to the next. The
/// text system remembers the blocks it laid a table out with, and finding new ones in their
/// place on the next pass it gives up on the table; so each cell keeps its block for as
/// long as the table keeps its shape.
final class TableCache {
    var tables: [Int: NSTextTable] = [:]
    var blocks: [String: NSTextTableBlock] = [:]

    func table(_ index: Int, columns: Int) -> NSTextTable {
        if let table = tables[index], table.numberOfColumns == columns { return table }
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.setContentWidth(100, type: .percentageValueType)
        tables[index] = table
        blocks = blocks.filter { !$0.key.hasPrefix("\(index),") }
        return table
    }

    func block(_ table: NSTextTable, index: Int, row: Int, column: Int) -> NSTextTableBlock {
        let key = "\(index),\(row),\(column)"
        if let block = blocks[key], block.table === table { return block }
        let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(.black)
        block.setWidth(3 * Page.zoom, type: .absoluteValueType, for: .padding)
        blocks[key] = block
        return block
    }
}

enum Styler {
    static let body = NSFont(name: "Times", size: Page.bodySize) ?? .systemFont(ofSize: Page.bodySize)
    static let code = NSFont(name: "Monaco", size: 10 * Page.zoom) ?? .monospacedSystemFont(ofSize: 10 * Page.zoom, weight: .regular)
    static let markColor = NSColor(white: 0.55, alpha: 1)

    static func heading(_ level: Int) -> NSFont {
        let size = [18, 14, 12, 12, 12, 12][min(level, 6) - 1] * Page.zoom
        return NSFont(name: "Helvetica-Bold", size: size) ?? .boldSystemFont(ofSize: size)
    }

    static func font(for style: Style, block: BlockKind) -> NSFont {
        if style.contains(.code) || style.contains(.block) { return code }
        var font = body
        if case .heading(let level) = block { font = heading(level) }
        let manager = NSFontManager.shared
        if style.contains(.bold) { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if style.contains(.italic) { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    static func paragraph(for line: Line) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.05
        switch line.block {
        case .heading(let level):
            paragraph.paragraphSpacingBefore = (level == 1 ? 12 : 8) * Page.zoom
            paragraph.paragraphSpacing = 3 * Page.zoom
        case .bullet(let depth), .number(_, let depth):
            let indent = CGFloat(depth + 1) * 0.25 * Page.inch
            paragraph.headIndent = indent
            paragraph.firstLineHeadIndent = indent - 0.25 * Page.inch
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
        case .quote:
            paragraph.headIndent = 0.5 * Page.inch
            paragraph.firstLineHeadIndent = 0.5 * Page.inch
            paragraph.tailIndent = -0.5 * Page.inch
        case .fenced, .fence:
            paragraph.headIndent = 0.25 * Page.inch
            paragraph.firstLineHeadIndent = 0.25 * Page.inch
            paragraph.lineHeightMultiple = 1
        default:
            break
        }
        return paragraph
    }

    /// What the text view shows: the file's text, but with each `|` between a table's cells
    /// made a paragraph break, so each cell can be a paragraph of its own (Show ¶ shows the
    /// table as it's written).
    static func displayText(_ markup: Markup, showMarks: Bool) -> String {
        guard !showMarks, !markup.tables.isEmpty else { return String(markup.chars) }
        var chars = markup.chars
        for line in markup.lines {
            guard case .tableRow = line.block else { continue }
            for case .code(let index) in line.pieces where markup.codes[index].kind == .cell {
                chars[markup.codes[index].range.lowerBound] = "\u{2029}"
            }
        }
        return String(chars)
    }

    /// Lays a table's rows out as text-table cells. Each row's text from line start to its
    /// return is cut at its pipes (paragraph breaks on screen) into the paragraphs of its
    /// cells; the bits outside a leading or trailing pipe go, squashed flat, into the first
    /// and last cells. The rule under the header goes, squashed flat, into the header's last
    /// cell (a row of its own would break the table's grid), and the header cells get a
    /// thicker line along their foot for it.
    private static func applyTable(_ table: Table, at tableIndex: Int, _ markup: Markup, to storage: NSTextStorage,
                                   cache: TableCache, range: (Range<Int>) -> NSRange) {
        let text = cache.table(tableIndex, columns: max(1, table.columns))
        var row = 0
        var lastBlock: NSTextTableBlock?
        for index in table.lines {
            let line = markup.lines[index]
            let whole = line.range.lowerBound..<(line.newline.map { $0 + 1 } ?? line.range.upperBound)
            if case .tableRule = line.block {
                guard let block = lastBlock else { continue }
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [block]
                paragraph.maximumLineHeight = 0.5
                storage.addAttributes([.paragraphStyle: paragraph, .tableCell: (row - 1) * 1000 + 999], range: range(whole))
                storage.addAttributes(vanish, range: range(whole))
                continue
            }
            let header: Bool = { if case .tableRow(_, true) = line.block { true } else { false } }()
            let bars = line.pieces.compactMap { piece -> Int? in
                if case .code(let i) = piece, markup.codes[i].kind == .cell { return markup.codes[i].range.lowerBound }
                return nil
            }
            // The paragraphs: from the line's start to each pipe (taking the pipe, its
            // break), and from the last pipe to the return.
            var paragraphs: [Range<Int>] = []
            var at = whole.lowerBound
            for bar in bars { paragraphs.append(at..<(bar + 1)); at = bar + 1 }
            paragraphs.append(at..<whole.upperBound)
            let leading = bars.first.map { chars(markup, line.range.lowerBound..<$0).allSatisfy(\.isWhitespace) } ?? false
            let trailing = bars.last.map { chars(markup, ($0 + 1)..<line.range.upperBound).allSatisfy(\.isWhitespace) } ?? false
            // One block for each cell, shared by every paragraph in it, as the text system
            // insists.
            var blocks: [Int: NSTextTableBlock] = [:]
            for (n, paragraphRange) in paragraphs.enumerated() {
                let isLeading = leading && n == 0
                let isTrailing = trailing && n == paragraphs.count - 1 && !(leading && paragraphs.count == 1)
                var column = n - (leading ? 1 : 0)
                if isLeading { column = 0 }
                column = min(max(column, 0), text.numberOfColumns - 1)
                let paragraph = NSMutableParagraphStyle()
                let block = blocks[column] ?? cache.block(text, index: tableIndex, row: row, column: column)
                block.setWidth(header ? 2.5 * Page.zoom : 1, type: .absoluteValueType, for: .border, edge: .maxY)
                blocks[column] = block
                lastBlock = block
                paragraph.textBlocks = [block]
                if table.aligns.indices.contains(column) {
                    paragraph.alignment = [.left: .left, .center: .center, .right: .right][table.aligns[column]] ?? .left
                }
                let r = range(paragraphRange)
                if isLeading || isTrailing {
                    // Nothing to show: squash it flat.
                    paragraph.maximumLineHeight = 0.5
                    storage.addAttributes(vanish, range: r)
                }
                storage.addAttributes([.paragraphStyle: paragraph, .tableCell: row * 1000 + column], range: r)
                // The spaces padding a cell are hidden, so the padding is the cell's own.
                for edge in [paragraphRange.lowerBound, paragraphRange.upperBound - 2] where edge >= paragraphRange.lowerBound {
                    if edge < markup.chars.count, markup.chars[edge] == " " {
                        storage.addAttributes(vanish, range: range(edge..<(edge + 1)))
                    }
                }
            }
            row += 1
        }
    }

    private static func chars(_ markup: Markup, _ r: Range<Int>) -> ArraySlice<Character> { markup.chars[r] }

    /// Markup inside a table is hidden by being set tiny and clear rather than by null
    /// glyphs, which leave the text system stepping each cell of a row down a line.
    static let vanish: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 0.5), .foregroundColor: NSColor.clear]

    /// Sets the whole text's attributes from the markup.
    static func apply(_ markup: Markup, to storage: NSTextStorage, utf16: [Int], showMarks: Bool, tables cache: TableCache) {
        func range(_ r: Range<Int>) -> NSRange { NSRange(location: utf16[r.lowerBound], length: utf16[r.upperBound] - utf16[r.lowerBound]) }
        storage.beginEditing()
        storage.setAttributes([.font: body, .foregroundColor: NSColor.black], range: NSRange(location: 0, length: storage.length))
        for line in markup.lines {
            let whole = range(line.range.lowerBound..<(line.newline.map { $0 + 1 } ?? line.range.upperBound))
            storage.addAttribute(.paragraphStyle, value: paragraph(for: line), range: whole)
            if line.block == .quote { storage.addAttribute(.quoteBar, value: true, range: whole) }
            if line.block == .rule {
                storage.addAttribute(.pageRule, value: true, range: whole)
            }
            if case .heading(let level) = line.block { storage.addAttribute(.font, value: heading(level), range: whole) }
            if line.block == .fenced || line.block == .fence {
                storage.addAttribute(.backgroundColor, value: NSColor(white: 0.93, alpha: 1), range: range(line.range))
                storage.addAttribute(.font, value: code, range: whole)
            }
            if case .tableRule = line.block, !showMarks { continue }
            for piece in line.pieces {
                switch piece {
                case .char(let offset, let style):
                    var attributes: [NSAttributedString.Key: Any] = [.font: font(for: style, block: line.block)]
                    if style.contains(.link) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    if style.contains(.strike) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    storage.addAttributes(attributes, range: range(offset..<(offset + 1)))
                case .code(let index):
                    let code = markup.codes[index]
                    let r = range(code.range)
                    if case .bullet = code.kind, !showMarks {
                        // The `-` (or `*`, `+`) drawn as a bullet, the space after it as a tab.
                        if let dash = markup.chars[code.range].firstIndex(where: { "-*+".contains($0) }) {
                            storage.addAttribute(.bulletMark, value: true, range: range(dash..<(dash + 1)))
                        }
                        continue
                    }
                    if case .number = code.kind, !showMarks { continue }
                    if showMarks {
                        storage.addAttribute(.foregroundColor, value: markColor, range: r)
                    } else if case .tableRow = line.block {
                        storage.addAttributes(vanish, range: r)
                    } else {
                        storage.addAttribute(.markupHidden, value: true, range: r)
                    }
                }
            }
        }
        if !showMarks {
            for (index, table) in markup.tables.enumerated() {
                applyTable(table, at: index, markup, to: storage, cache: cache, range: range)
            }
        }
        storage.endEditing()
    }
}

// MARK: - Layout

/// Draws what Word's Normal view drew beside the text: a rule's line, a quote's bar, the
/// dotted line of each page break, and with Show ¶ on, ¶ at returns and dots in spaces. As
/// its own delegate it also keeps hidden markup from being drawn, and draws a list item's
/// dash as a bullet.
final class PageLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var showMarks = false

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let storage = textStorage else { return 0 }
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: range.length))
        var newProps = Array(UnsafeBufferPointer(start: properties, count: range.length))
        var changed = false
        for i in 0..<range.length {
            let index = characterIndexes[i]
            guard index < storage.length else { continue }
            if storage.attribute(.markupHidden, at: index, effectiveRange: nil) != nil {
                // Never a line or paragraph break: the text system needs those to find where
                // paragraphs, and a table's cells, end. (Hidden ones are set tiny instead.)
                let unit = (storage.string as NSString).character(at: index)
                if unit == 0x0A || unit == 0x0D || unit == 0x2029 || unit == 0x2028 { continue }
                newProps[i] = .null
                changed = true
            } else if storage.attribute(.bulletMark, at: index, effectiveRange: nil) != nil {
                var bullet = CGGlyph(0)
                var char = UniChar(0x2022)
                if CTFontGetGlyphsForCharacters(font as CTFont, &char, &bullet, 1) {
                    newGlyphs[i] = bullet
                    changed = true
                }
            }
        }
        guard changed else { return 0 }
        newGlyphs.withUnsafeBufferPointer { g in
            newProps.withUnsafeBufferPointer { p in
                setGlyphs(g.baseAddress!, properties: p.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
            }
        }
        return range.length
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        NSColor.black.setFill()
        storage.enumerateAttribute(.pageRule, in: characters) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            NSRect(x: origin.x + container.lineFragmentPadding, y: origin.y + rect.midY,
                   width: container.size.width - 2 * container.lineFragmentPadding, height: 1).fill()
        }
        storage.enumerateAttribute(.quoteBar, in: characters) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                NSRect(x: origin.x + 0.3 * Page.inch, y: origin.y + rect.minY, width: 2, height: rect.height).fill()
            }
        }
        guard showMarks else { return }
        // Show ¶: a dot in each space, ¶ at each return.
        let string = storage.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: Styler.body, .foregroundColor: Styler.markColor]
        for i in characters.location..<NSMaxRange(characters) {
            let char = string.character(at: i)
            guard char == 0x20 || char == 0x0A else { continue }
            let glyph = glyphIndexForCharacter(at: i)
            let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location = self.location(forGlyphAt: glyph)
            let mark = char == 0x20 ? "·" : "¶"
            // On the line's baseline, whatever the size of the type on it.
            let point = NSPoint(x: origin.x + fragment.minX + location.x,
                                y: origin.y + fragment.minY + location.y - defaultBaselineOffset(for: Styler.body))
            if char == 0x20 {
                let width = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).width
                (mark as NSString).draw(at: NSPoint(x: point.x + width / 2 - 2, y: point.y), withAttributes: attributes)
            } else {
                (mark as NSString).draw(at: point, withAttributes: attributes)
            }
        }
    }
}

// MARK: - The text view

final class PageTextView: NSTextView {
    let editor: MarkupEditor
    var onChange: (String) -> Void = { _ in }
    weak var documentUndo: UndoManager?
    let state: PageState
    /// The UTF-16 offset of each character, and one past the last: the text view counts in
    /// UTF-16, the editor in characters.
    private var utf16: [Int] = [0]
    private var syncing = false
    private let tableCache = TableCache()
    private var lastEditWasTyping = false

    init(text: String, state: PageState) {
        editor = MarkupEditor(text: text)
        self.state = state
        let storage = NSTextStorage()
        let layout = PageLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: Page.textWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        // No padding, so the text starts exactly at the Ruler's zero.
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        super.init(frame: NSRect(x: 0, y: 0, width: Page.textWidth + 2 * Page.margin, height: 800), textContainer: container)
        textContainerInset = NSSize(width: Page.margin, height: 0.5 * Page.inch)
        isRichText = false
        allowsUndo = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        smartInsertDeleteEnabled = false
        backgroundColor = .white
        insertionPointColor = .black
        selectedTextAttributes = [.backgroundColor: NSColor.black, .foregroundColor: NSColor.white]
        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        state.view = self
        sync(full: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    // As Markdown Editor learned on this Touch Bar Mac: a text view's own Touch Bar items
    // walk every attribute run, which stalls on a heavily styled document.
    override func makeTouchBar() -> NSTouchBar? { nil }

    private var pageLayout: PageLayoutManager? { layoutManager as? PageLayoutManager }

    // MARK: Keeping the text view in line with the editor

    private func charIndex(_ utf16Offset: Int) -> Int {
        var low = 0, high = utf16.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if utf16[mid] <= utf16Offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Brings the text view's text, styling and selection in line with the editor's.
    func sync(full: Bool = false) {
        syncing = true
        defer { syncing = false }
        guard let storage = textStorage else { return }
        let new = Styler.displayText(editor.markup, showMarks: state.showMarks) as NSString
        let old = storage.string as NSString
        if full || old != new {
            // Replace only what changed: the part between the common start and end.
            var start = 0
            let oldLength = old.length, newLength = new.length
            while start < oldLength && start < newLength && old.character(at: start) == new.character(at: start) { start += 1 }
            var end = 0
            while end < oldLength - start && end < newLength - start
                    && old.character(at: oldLength - 1 - end) == new.character(at: newLength - 1 - end) { end += 1 }
            storage.replaceCharacters(in: NSRange(location: start, length: oldLength - start - end),
                                      with: new.substring(with: NSRange(location: start, length: newLength - start - end)))
        }
        var offsets = [0]
        offsets.reserveCapacity(editor.chars.count + 1)
        for char in editor.chars { offsets.append(offsets.last! + char.utf16.count) }
        utf16 = offsets
        pageLayout?.showMarks = state.showMarks
        Styler.apply(editor.markup, to: storage, utf16: utf16, showMarks: state.showMarks, tables: tableCache)
        let caret = utf16[min(editor.stop(atOrAfter: editor.cursor), editor.chars.count)]
        if let selection = editor.selection {
            super.setSelectedRanges([NSValue(range: NSRange(location: utf16[selection.lowerBound],
                                                             length: utf16[selection.upperBound] - utf16[selection.lowerBound]))],
                                    affinity: .downstream, stillSelecting: false)
        } else {
            super.setSelectedRanges([NSValue(range: NSRange(location: state.showMarks ? utf16[editor.cursor] : caret, length: 0))],
                                    affinity: .downstream, stillSelecting: false)
        }
        updateState()
        scrollRangeToVisible(selectedRange())
    }

    private func updateState() {
        state.style = editor.cursorStyle
        state.block = editor.markup.lines[editor.markup.lineIndex(at: editor.cursor)].block
        if let layout = layoutManager, let container = textContainer, layout.numberOfGlyphs > 0 {
            let glyph = layout.glyphIndexForCharacter(at: min(selectedRange().location, max(0, (textStorage?.length ?? 1) - 1)))
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 0), in: container)
            state.page = Int(rect.minY / Page.textHeight) + 1
        } else {
            state.page = 1
        }
    }

    /// Takes the text view's selection into the editor, before an edit.
    private func takeSelection() {
        let range = selectedRange()
        let start = charIndex(range.location), end = charIndex(NSMaxRange(range))
        if range.length == 0 {
            editor.anchor = nil
            if editor.cursor != start && !(editor.stop(atOrAfter: editor.cursor) == start && !state.showMarks) {
                editor.cursor = start
            }
        } else {
            editor.anchor = start
            editor.cursor = end
        }
    }

    /// Runs an edit through the editor, keeping it undoable; a run of typing undoes as one.
    private func edit(typing: Bool = false, _ body: () -> Void) {
        takeSelection()
        let before = editor.snapshot
        body()
        if editor.chars != before.chars {
            if !(typing && lastEditWasTyping) { registerUndo(before) }
            lastEditWasTyping = typing
            onChange(editor.text)
        }
        sync()
    }

    private func registerUndo(_ snapshot: MarkupEditor.Snapshot) {
        documentUndo?.registerUndo(withTarget: self) { view in
            let current = view.editor.snapshot
            view.editor.restore(snapshot)
            view.registerUndo(current)
            view.lastEditWasTyping = false
            view.onChange(view.editor.text)
            view.sync()
        }
    }

    func reload(_ text: String) {
        guard text != editor.text else { return }
        editor.replaceAll(with: text)
        sync(full: true)
    }

    func setShowMarks(_ on: Bool) {
        takeSelection()
        state.showMarks = on
        editor.revealed = on
        sync(full: true)
        layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0))
    }

    // MARK: Typing

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if hasMarkedText() { unmarkText() }
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        guard !text.isEmpty else { return }
        edit(typing: true) { editor.insert(text) }
    }

    override func deleteBackward(_ sender: Any?) { edit { editor.deleteBackward() } }
    override func deleteForward(_ sender: Any?) { edit { editor.deleteForward() } }
    override func insertNewline(_ sender: Any?) { edit { editor.newline() } }
    // In a table, Tab and Shift-Tab go from cell to cell, and Tab in the last adds a row,
    // as in Word.
    override func insertTab(_ sender: Any?) { edit { if !editor.moveCell(forward: true) { editor.insert("\t") } } }
    override func insertBacktab(_ sender: Any?) { edit { editor.moveCell(forward: false) } }
    @objc func insertTable(_ sender: Any?) { edit { editor.insertTable() } }

    override func deleteWordBackward(_ sender: Any?) {
        edit {
            let end = editor.cursor
            editor.moveWord(forward: false)
            editor.anchor = end
            editor.deleteSelection()
        }
    }

    // With the markup hidden, left and right step over it, as Reveal Codes' cursor does.
    override func moveLeft(_ sender: Any?) {
        guard !state.showMarks, selectedRange().length == 0 else { return super.moveLeft(sender) }
        takeSelection()
        editor.moveLeft()
        sync()
    }

    override func moveRight(_ sender: Any?) {
        guard !state.showMarks, selectedRange().length == 0 else { return super.moveRight(sender) }
        takeSelection()
        editor.moveRight()
        sync()
    }

    /// A click or an up or down arrow landing inside hidden markup moves on to the next
    /// place the cursor can be.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        guard !syncing, !state.showMarks, ranges.count == 1, ranges[0].rangeValue.length == 0, utf16.count > 1 else {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            if !syncing { updateState() }
            return
        }
        let offset = charIndex(ranges[0].rangeValue.location)
        let stop = editor.stop(atOrAfter: offset)
        editor.anchor = nil
        if editor.cursor != offset { editor.cursor = offset }
        super.setSelectedRanges([NSValue(range: NSRange(location: utf16[min(stop, utf16.count - 1)], length: 0))],
                                affinity: affinity, stillSelecting: stillSelecting)
        updateState()
    }

    // MARK: Copy and paste, as Markdown

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        // From the file's text, not the view's, whose tables have breaks for pipes.
        let start = charIndex(range.location), end = charIndex(NSMaxRange(range))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(editor.chars[start..<end]), forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        copy(sender)
        edit { editor.deleteSelection() }
    }

    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        edit { editor.insert(text) }
    }

    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }

    // MARK: Formatting

    @objc func toggleBold(_ sender: Any?) { edit { editor.toggle(.bold) } }
    @objc func toggleItalic(_ sender: Any?) { edit { editor.toggle(.italic) } }
    @objc func toggleStrikeout(_ sender: Any?) { edit { editor.toggle(.strike) } }
    @objc func toggleCode(_ sender: Any?) { edit { editor.toggle(.code) } }
    @objc func toggleShowMarks(_ sender: Any?) { setShowMarks(!state.showMarks) }

    func setBlock(_ block: BlockKind) { edit { editor.setBlock(block) } }

    @objc func styleHeading1(_ sender: Any?) { setBlock(.heading(1)) }
    @objc func styleHeading2(_ sender: Any?) { setBlock(.heading(2)) }
    @objc func styleHeading3(_ sender: Any?) { setBlock(.heading(3)) }
    @objc func styleBullet(_ sender: Any?) { setBlock(.bullet(0)) }
    @objc func styleNumbered(_ sender: Any?) { setBlock(.number("1.", 0)) }
    @objc func styleQuote(_ sender: Any?) { setBlock(.quote) }
    @objc func styleCodeBlock(_ sender: Any?) { setBlock(.fence) }
    @objc func styleNormal(_ sender: Any?) { setBlock(.paragraph) }

    // MARK: Page breaks

    /// Word's Normal view marked where each page would break with a dotted line across.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([2, 3], count: 2, phase: 0)
        var y = textContainerInset.height + Page.textHeight
        while y < bounds.height {
            if y >= rect.minY - 1 && y <= rect.maxY + 1 {
                path.move(to: NSPoint(x: 0, y: y + 0.5))
                path.line(to: NSPoint(x: bounds.width, y: y + 0.5))
            }
            y += Page.textHeight
        }
        NSColor.black.setStroke()
        path.stroke()
    }
}

/// The page in a scroll view, as a SwiftUI view.
struct PageScroll: NSViewRepresentable {
    let document: MarkdownFile
    let state: PageState
    var undoManager: UndoManager?

    func makeNSView(context: Context) -> NSScrollView {
        let view = PageTextView(text: document.text, state: state)
        view.onChange = { [document] text in document.text = text }
        view.documentUndo = undoManager
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.documentView = view
        view.autoresizingMask = [.width]
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? PageTextView else { return }
        view.documentUndo = undoManager
        view.reload(document.text)
    }
}
