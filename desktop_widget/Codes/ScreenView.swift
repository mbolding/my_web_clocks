// ScreenView — WordPerfect 5.1's screen: 80 columns of grey on blue, scaled to fill the
// window, with nothing on it but the text and, along the bottom, the status line
// (`Doc 1 Pg 1 Ln 1" Pos 1"`, the Pos in bold while bold is on). Alt-F3 or F11 splits it for
// Reveal Codes. The keys are WordPerfect's where the Mac lets them through (the F-keys need
// fn held), alongside the Mac's own; a template strip above the status line and the Touch
// Bar both show them, as the cardboard template around the keyboard once did.

import AppKit

enum WP {
    static let blue = NSColor(srgbRed: 0, green: 0, blue: 0.667, alpha: 1)
    static let grey = NSColor(srgbRed: 0.667, green: 0.667, blue: 0.667, alpha: 1)
    static let white = NSColor.white
    static let cyan = NSColor(srgbRed: 0.333, green: 1, blue: 1, alpha: 1)
    static let yellow = NSColor(srgbRed: 1, green: 1, blue: 0.333, alpha: 1)
    static let lightBlue = NSColor(srgbRed: 0.333, green: 0.333, blue: 1, alpha: 1)
    static let black = NSColor.black
    static let columns = 80
}

final class ScreenView: NSView, NSTextInputClient {
    let editor: MarkupEditor
    /// Told the new text after every change, for the document to save.
    var onChange: (String) -> Void = { _ in }
    weak var documentUndo: UndoManager?
    var fileName = "" { didSet { needsDisplay = true } }

    private var layout: GridLayout
    private var topRow = 0
    private var goalCol: Int?
    private var message: String?
    private var messageTimer: Timer?
    private var prompt: Prompt?
    private var showingHelp = false
    private var blinkOn = true
    private var blinkTimer: Timer?
    private var marked = ""
    private var lastEditWasTyping = false
    private var dragAnchor: Int?

    /// A question on the status line, WordPerfect-style: a menu of numbered choices, a
    /// yes/no, or a word to search for.
    private struct Prompt {
        enum Kind { case style, font, exit, search(forward: Bool) }
        var kind: Kind
        var text: String
        var answer = ""
    }

    init(text: String) {
        editor = MarkupEditor(text: text)
        layout = GridLayout(editor.markup)
        super.init(frame: .zero)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.blinkOn.toggle()
                self.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { blinkTimer?.invalidate() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    // The text system's Touch Bar items would need a real text view; a template of
    // WordPerfect's function keys belongs there later.
    // The template's keys, which change with the modifier held. (No text-view items: the
    // screen isn't a text view, so there's none of Markdown Editor's Touch Bar trouble.)
    override func makeTouchBar() -> NSTouchBar? {
        let bar = TemplateTouchBar(shift: heldShift) { [weak self] action in
            MainActor.assumeIsolated { self?.perform(action) }
        }
        templateBar = bar
        return bar.makeTouchBar()
    }

    private var templateBar: TemplateTouchBar?
    /// Which set of template labels is showing: the key alone, or with Shift, Alt or Ctrl.
    private var heldShift = TemplateKey.Shift.none
    private var templateHits: [(cols: Range<Int>, action: KeyAction)] = []
    private var showsTemplate: Bool { UserDefaults.standard.object(forKey: "keyTemplate") as? Bool ?? true }

    override func flagsChanged(with event: NSEvent) {
        let shift = TemplateKey.shift(for: event.modifierFlags)
        guard shift != heldShift else { return }
        heldShift = shift
        touchBar = nil // made again for the new set
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    /// Takes in text changed from outside, as after Revert.
    func reload(_ text: String) {
        guard text != editor.text else { return }
        editor.replaceAll(with: text)
        changed(edited: false)
    }

    // MARK: - Metrics

    /// The font and line height for the window's width, worked out once per size: Menlo
    /// at whatever size makes 80 columns fill it.
    private var metrics: (width: CGFloat, font: NSFont, lineHeight: CGFloat)?

    private var font: NSFont { measured.font }

    private var measured: (width: CGFloat, font: NSFont, lineHeight: CGFloat) {
        if let metrics, metrics.width == bounds.width { return metrics }
        let probe = NSFont(name: "Menlo", size: 100) ?? NSFont.monospacedSystemFont(ofSize: 100, weight: .regular)
        let advance = probe.advancement(forGlyph: probe.glyph(withName: "M")).width / 100
        let size = max(6, bounds.width / CGFloat(WP.columns) / max(advance, 0.5))
        let font = NSFont(name: "Menlo", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let made = (bounds.width, font, ceil(font.ascender - font.descender + font.leading))
        metrics = made
        return made
    }

    private var cellWidth: CGFloat { bounds.width / CGFloat(WP.columns) }
    private var lineHeight: CGFloat { measured.lineHeight }
    private var screenRows: Int { max(4, Int(bounds.height / lineHeight)) }
    private var revealing: Bool { editor.revealed }
    /// The rows along the bottom: the status line, and the key template above it.
    private var bottomRows: Int { showsTemplate ? 2 : 1 }
    /// Rows for the document: all but the bottom ones, or the top half in Reveal Codes.
    private var textRows: Int { revealing ? (screenRows - bottomRows) / 2 : screenRows - bottomRows }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scrollToCursor()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        WP.blue.setFill()
        bounds.fill()
        let font = self.font
        if showingHelp {
            drawHelp(font)
            return
        }
        let cursorAt = layout.locate(editor.stop(atOrAfter: editor.cursor))
        let selection = editor.selection
        for screenRow in 0..<textRows {
            let index = topRow + screenRow
            guard index < layout.rows.count else { break }
            let row = layout.rows[index]
            drawRow(row.cells, row: screenRow, font: font, selected: { cell in
                cell.offset.map { selection?.contains($0) ?? false } ?? false
            })
            // A block running through the line end shows across the row's end too.
            if let selection, let end = row.end, selection.contains(end) {
                fillCell(col: row.cells.count, row: screenRow, color: WP.grey)
            }
        }
        // WordPerfect's cursor: a blinking underline.
        if blinkOn, !revealing || true {
            let screenRow = cursorAt.row - topRow
            if screenRow >= 0, screenRow < textRows {
                let rect = cellRect(col: cursorAt.col, row: screenRow)
                WP.white.setFill()
                NSRect(x: rect.minX, y: rect.maxY - max(2, lineHeight / 8), width: rect.width, height: max(2, lineHeight / 8)).fill()
            }
        }
        if !marked.isEmpty {
            let screenRow = cursorAt.row - topRow
            for (n, char) in marked.enumerated() {
                draw(Cell(char: char, style: [.italic]), col: cursorAt.col + n, row: screenRow, font: font, selected: false)
            }
        }
        if revealing { drawReveal(font) }
        if showsTemplate { drawTemplate(font) }
        drawStatus(font)
    }

    private func cellRect(col: Int, row: Int) -> NSRect {
        NSRect(x: CGFloat(col) * cellWidth, y: CGFloat(row) * lineHeight, width: cellWidth, height: lineHeight)
    }

    private func fillCell(col: Int, row: Int, color: NSColor) {
        color.setFill()
        cellRect(col: col, row: row).fill()
    }

    private func colors(for cell: Cell) -> (NSColor, NSColor?) {
        switch cell.role {
        case .decoration:
            return (cell.style.contains(.quote) ? WP.lightBlue : WP.lightBlue, nil)
        case .code:
            return (WP.yellow, nil)
        case .terminator:
            return (WP.yellow, nil)
        case .text:
            break
        }
        let style = cell.style
        if style.contains(.block) || style.contains(.code) { return (WP.cyan, nil) }
        if style.contains(.link) { return (WP.yellow, nil) }
        if style.contains(.bold) || style.contains(.heading) { return (WP.white, nil) }
        return (WP.grey, nil)
    }

    /// Draws a row of cells: backgrounds and lines cell by cell, and the characters in runs
    /// of one colour, which is many times quicker than a character at a time. Characters
    /// that may be wider than a cell (emoji, Chinese) are drawn on their own.
    private func drawRow(_ cells: [Cell], row: Int, font: NSFont, selected: (Cell) -> Bool = { _ in false },
                         highlight: (Cell) -> Bool = { _ in false }) {
        var run = ""
        var runStart = 0
        var runColor = WP.grey
        let baseline = (lineHeight - (font.ascender - font.descender)) / 2
        func flush() {
            guard !run.isEmpty else { return }
            NSAttributedString(string: run, attributes: [.font: font, .foregroundColor: runColor])
                .draw(at: NSPoint(x: CGFloat(runStart) * cellWidth, y: CGFloat(row) * lineHeight + baseline))
            run = ""
        }
        let thickness = max(1, lineHeight / 14)
        for (col, cell) in cells.enumerated() where col < WP.columns {
            var (fore, back) = colors(for: cell)
            if selected(cell) { back = WP.grey; fore = WP.blue }
            if highlight(cell) { back = WP.cyan; fore = WP.black }
            let rect = cellRect(col: col, row: row)
            if let back {
                back.setFill()
                rect.fill()
            }
            if cell.role == .text, cell.style.contains(.italic) || cell.style.contains(.link) {
                fore.setFill()
                NSRect(x: rect.minX, y: rect.maxY - thickness * 2.5, width: rect.width, height: thickness).fill()
            }
            if cell.role == .text, cell.style.contains(.strike) {
                fore.setFill()
                NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: thickness).fill()
            }
            let narrow = cell.char.unicodeScalars.allSatisfy { $0.value < 0x1100 || (0x2000...0x2BFF).contains($0.value) }
            if !narrow || fore != runColor || col != runStart + run.count {
                flush()
                runStart = col
                runColor = fore
            }
            if narrow {
                run.append(cell.char)
            } else {
                NSAttributedString(string: String(cell.char), attributes: [.font: font, .foregroundColor: fore])
                    .draw(at: NSPoint(x: rect.minX, y: rect.minY + baseline))
                runStart = col + 1
            }
        }
        flush()
    }

    private func draw(_ cell: Cell, col: Int, row: Int, font: NSFont, selected: Bool, highlight: Bool = false) {
        guard col < WP.columns else { return }
        var (fore, back) = colors(for: cell)
        if selected { back = WP.grey; fore = WP.blue }
        if highlight { back = WP.cyan; fore = WP.black }
        let rect = cellRect(col: col, row: row)
        if let back {
            back.setFill()
            rect.fill()
        }
        // Underlining and striking out are drawn as lines across the whole cell, so they run
        // on unbroken through spaces, as on a text screen.
        let thickness = max(1, lineHeight / 14)
        if cell.role == .text, cell.style.contains(.italic) || cell.style.contains(.link) {
            fore.setFill()
            NSRect(x: rect.minX, y: rect.maxY - thickness * 2.5, width: rect.width, height: thickness).fill()
        }
        if cell.role == .text, cell.style.contains(.strike) {
            fore.setFill()
            NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: thickness).fill()
        }
        guard cell.char != " " else { return }
        NSAttributedString(string: String(cell.char), attributes: [.font: font, .foregroundColor: fore])
            .draw(at: NSPoint(x: rect.minX, y: rect.minY + (lineHeight - (font.ascender - font.descender)) / 2))
    }

    private func drawText(_ text: String, col: Int, row: Int, font: NSFont, color: NSColor = WP.grey, style: Style = []) {
        for (n, char) in text.enumerated() {
            var cell = Cell(char: char, style: style)
            cell.role = .text
            var (fore, _) = colors(for: cell)
            if style.isEmpty { fore = color }
            guard col + n < WP.columns else { return }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fore]
            if style.contains(.italic) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            let rect = cellRect(col: col + n, row: row)
            NSAttributedString(string: String(char), attributes: attributes)
                .draw(at: NSPoint(x: rect.minX, y: rect.minY + (lineHeight - (font.ascender - font.descender)) / 2))
        }
    }

    private func drawStatus(_ font: NSFont) {
        let row = screenRows - 1
        if let prompt {
            drawText(prompt.text + prompt.answer, col: 0, row: row, font: font, color: WP.white)
            if blinkOn {
                let rect = cellRect(col: prompt.text.count + prompt.answer.count, row: row)
                WP.white.setFill()
                NSRect(x: rect.minX, y: rect.maxY - max(2, lineHeight / 8), width: rect.width, height: max(2, lineHeight / 8)).fill()
            }
            return
        }
        var left = editor.anchor != nil ? (blinkOn ? "Block on" : "") : (message ?? fileName)
        // A long path keeps its end, where the file's name is.
        if left.count > 44 { left = "…" + left.suffix(43) }
        drawText(left, col: 0, row: row, font: font)
        let at = layout.locate(editor.stop(atOrAfter: editor.cursor))
        let docRow = layout.rows.indices.contains(at.row) ? layout.rows[at.row].docRow : 0
        let page = docRow / GridLayout.pageLength + 1
        let ln = 1 + Double(docRow % GridLayout.pageLength) / 6
        let pos = 1 + Double(at.col) / 10
        let head = "Doc 1 Pg \(page) Ln \(Self.inches(ln)) Pos "
        let value = Self.inches(pos)
        let start = WP.columns - head.count - value.count
        drawText(head, col: start, row: row, font: font)
        // WordPerfect showed the Pos number in the formatting that's on at the cursor.
        let style = editor.cursorStyle.intersection([.bold, .italic, .strike, .code])
        drawText(value, col: start + head.count, row: row, font: font, color: style.contains(.bold) ? WP.white : WP.grey,
                 style: style.subtracting(.bold))
    }

    static func inches(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "\""
    }

    private func drawReveal(_ font: NSFont) {
        let rulerRow = textRows
        // The ruler between the two halves: the margins as brackets, the tab stops as triangles.
        var ruler = Array(repeating: Character("─"), count: WP.columns)
        for col in stride(from: GridLayout.tab, to: GridLayout.width, by: GridLayout.tab) { ruler[col] = "▲" }
        ruler[0] = "["
        ruler[GridLayout.width] = "]"
        drawText(String(ruler), col: 0, row: rulerRow, font: font, color: WP.white)

        let paneRows = screenRows - bottomRows - rulerRow - 1
        guard paneRows > 0 else { return }
        let cursorLine = editor.markup.lineIndex(at: editor.cursor)
        let lines = max(0, cursorLine - paneRows)...min(editor.markup.lines.count - 1, cursorLine + paneRows)
        let rows = layout.revealRows(editor.markup, lines: lines)
        // The row the cursor's on, kept in the middle of the pane.
        let target = editor.revealed && editor.markup.code(startingAt: editor.cursor) != nil ? editor.cursor : editor.stop(atOrAfter: editor.cursor)
        let cursorRow = rows.firstIndex { $0.contains { $0.offset == target } } ?? 0
        let first = max(0, min(cursorRow - paneRows / 2, rows.count - paneRows))
        let onCode = editor.markup.code(startingAt: target) != nil
        for n in 0..<paneRows {
            let index = first + n
            guard index < rows.count else { break }
            drawRow(rows[index], row: rulerRow + 1 + n, font: font, highlight: { cell in
                guard cell.offset == target else { return false }
                if case .code = cell.role { return onCode }
                return !onCode
            })
        }
    }

    /// The key template: each key in reverse, then what it does, for the set of labels the
    /// held modifier calls for, in that set's colour on the template.
    private func drawTemplate(_ font: NSFont) {
        let row = screenRows - 2
        templateHits = []
        var col = 0
        let heading = TemplateKey.heading(heldShift)
        if !heading.isEmpty {
            drawText(heading, col: 0, row: row, font: font, color: WP.white)
            col = heading.count
        }
        let keyColor = heldShift == .none ? WP.grey : TemplateKey.color(heldShift).blended(withFraction: 0.35, of: .white) ?? WP.grey
        for key in TemplateKey.keys(for: heldShift) {
            let tag = "F\(key.number)"
            guard col + tag.count + key.label.count < WP.columns else { break }
            let start = col
            for (n, char) in tag.enumerated() {
                fillCell(col: col + n, row: row, color: keyColor)
                drawText(String(char), col: col + n, row: row, font: font, color: WP.blue)
            }
            col += tag.count
            drawText(key.label, col: col, row: row, font: font)
            col += key.label.count
            templateHits.append((start..<col, key.action))
            col += heldShift == .none ? 1 : 2
        }
    }

    private func drawHelp(_ font: NSFont) {
        let lines = Self.help
        for (n, line) in lines.enumerated() where n < screenRows {
            drawText(line, col: 0, row: n, font: font, color: n == 0 ? WP.white : WP.grey)
        }
    }

    /// The help screen, laid out to fit 80 columns: keys in two columns of 40.
    static let help: [String] = {
        let keys = [("F6", "Bold on/off"), ("F8", "Italic (underlined)"),
                    ("Ctrl-F8", "Font menu"), ("Alt-F8", "Style menu"),
                    ("Alt-F3, F11", "Reveal Codes"), ("Alt-F4, F12", "Block on/off"),
                    ("F2, Shift-F2", "Search fwd/back"), ("F10", "Save"),
                    ("Shift-F10", "Retrieve (open)"), ("F7", "Exit"),
                    ("F1, Esc", "Cancel"), ("F3", "Help"),
                    ("Alt-F7", "Table"), ("Tab", "Next cell")]
        func column(_ pair: (String, String)) -> String {
            ("  " + pair.0.padding(toLength: 14, withPad: " ", startingAt: 0) + pair.1).padding(toLength: 40, withPad: " ", startingAt: 0)
        }
        var lines = ["Help" + String(repeating: " ", count: 51) + "Reveal Codes for Markdown", "",
                     "  Each line is a paragraph, and Enter ends it. The file is plain Markdown,",
                     "  so its formatting is kept as codes: **bold**, *italic*, `code`, # heads.", ""]
        for n in stride(from: 0, to: keys.count, by: 2) { lines.append(column(keys[n]) + column(keys[n + 1])) }
        lines += ["",
                  "  Style (Alt-F8) makes the line a heading, a list item, a quote or code.",
                  "  Font (Ctrl-F8) has bold, italic, strikeout and code.",
                  "",
                  "  In Reveal Codes the cursor stops on codes too. Backspace or Delete on",
                  "  one takes it out, and its partner with it: [BOLD] goes with [bold].",
                  "",
                  "  The template above the status line and the Touch Bar show the keys; hold",
                  "  Shift, Alt or Ctrl to see theirs, and click or tap one to use it. The",
                  "  Mac's keys work too: ⌘B, ⌘I, ⌥⌘R, ⌘C ⌘X ⌘V, ⌘Z. F-keys need fn.",
                  "",
                  String(repeating: " ", count: 56) + "Press any key to go back"]
        return lines.map { String($0.prefix(80)) }
    }()

    // MARK: - Changes

    private func changed(edited: Bool = true) {
        layout = GridLayout(editor.markup)
        if edited { onChange(editor.text) }
        scrollToCursor()
        blinkOn = true
        needsDisplay = true
    }

    private func scrollToCursor() {
        let row = layout.locate(editor.stop(atOrAfter: editor.cursor)).row
        if row < topRow { topRow = row }
        if row >= topRow + textRows { topRow = row - textRows + 1 }
        topRow = max(0, min(topRow, max(0, layout.rows.count - 1)))
    }

    /// Runs an edit, keeping it undoable. A run of typing undoes as one.
    private func edit(typing: Bool = false, _ body: () -> Void) {
        let before = editor.snapshot
        body()
        goalCol = nil
        if editor.chars != before.chars {
            if !(typing && lastEditWasTyping) { registerUndo(before) }
            lastEditWasTyping = typing
        }
        changed()
    }

    private func registerUndo(_ snapshot: MarkupEditor.Snapshot) {
        guard let undo = documentUndo else { return }
        undo.registerUndo(withTarget: self) { view in
            let current = view.editor.snapshot
            view.editor.restore(snapshot)
            view.registerUndo(current)
            view.lastEditWasTyping = false
            view.changed()
        }
    }

    private func moved() {
        lastEditWasTyping = false
        changed(edited: false)
    }

    private func move(extending: Bool, _ body: () -> Void) {
        if extending {
            if editor.anchor == nil { editor.anchor = editor.cursor }
        } else if !blockKeyOn {
            editor.anchor = nil
        }
        body()
        moved()
    }

    /// Alt-F4 or F12 turned a block on, which every move then stretches, as in WordPerfect.
    private var blockKeyOn = false

    private func say(_ text: String) {
        message = text
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.message = nil
                self?.needsDisplay = true
            }
        }
        needsDisplay = true
    }

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        blinkOn = true
        if showingHelp {
            showingHelp = false
            needsDisplay = true
            return
        }
        if prompt != nil {
            answer(event)
            return
        }
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if let key = event.charactersIgnoringModifiers?.unicodeScalars.first?.value, (0xF704...0xF70F).contains(key) {
            functionKey(Int(key - 0xF704) + 1, mods)
            return
        }
        switch event.keyCode {
        case 115: // Home
            move(extending: mods.contains(.shift)) { mods.contains(.control) || mods.contains(.command) ? (editor.cursor = 0) : rowEdge(start: true) }
            return
        case 119: // End
            move(extending: mods.contains(.shift)) { mods.contains(.control) || mods.contains(.command) ? (editor.cursor = editor.chars.count) : rowEdge(start: false) }
            return
        case 116: // Page Up
            move(extending: mods.contains(.shift)) { vertical(-max(1, textRows - 1)) }
            return
        case 121: // Page Down
            move(extending: mods.contains(.shift)) { vertical(max(1, textRows - 1)) }
            return
        case 53: // Esc
            cancel()
            return
        default:
            break
        }
        interpretKeyEvents([event])
    }

    private func functionKey(_ number: Int, _ mods: NSEvent.ModifierFlags) {
        let shift: TemplateKey.Shift = mods == .shift ? .shift : mods == .option ? .alt : mods == .control ? .ctrl
            : mods.isEmpty ? .none : .shift
        guard mods.isEmpty || [.shift, .option, .control].contains(mods),
              let action = TemplateKey.action(number: number, shift: shift) else {
            NSSound.beep()
            return
        }
        perform(action)
    }

    /// What a key does, whether pressed, tapped on the Touch Bar or clicked on the template.
    func perform(_ action: KeyAction) {
        blinkOn = true
        if showingHelp, action != .help { showingHelp = false }
        switch action {
        case .cancel: cancel()
        case .search: ask(.search(forward: true), "-> Srch: ")
        case .searchBack: ask(.search(forward: false), "<- Srch: ")
        case .help: showingHelp.toggle(); needsDisplay = true
        case .reveal: toggleRevealCodes(nil)
        case .block: toggleBlock(nil)
        case .bold: toggleBold(nil)
        case .italic: toggleItalic(nil)
        case .exit: ask(.exit, "Exit document? No (Yes) ")
        case .print: say("Print isn't built yet")
        case .font: ask(.font, "1 Bold; 2 Italic; 3 Strikeout; 4 Code: 0")
        case .style: ask(.style, "1 Head 1; 2 Head 2; 3 Head 3; 4 Bullet; 5 Numbered; 6 Quote; 7 Code Block; 8 Normal: 0")
        case .save:
            NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: self)
            say("Saving \(fileName)")
        case .open:
            NSDocumentController.shared.openDocument(nil)
        case .table:
            insertTable(nil)
        }
    }

    private func ask(_ kind: Prompt.Kind, _ text: String) {
        prompt = Prompt(kind: kind, text: text)
        needsDisplay = true
    }

    private func answer(_ event: NSEvent) {
        guard var prompt else { return }
        let key = event.charactersIgnoringModifiers ?? ""
        func done() { self.prompt = nil; needsDisplay = true }
        if event.keyCode == 53 || key.unicodeScalars.first?.value == 0xF704 { done(); return } // Esc, F1
        switch prompt.kind {
        case .style:
            done()
            let blocks: [String: BlockKind] = ["1": .heading(1), "2": .heading(2), "3": .heading(3), "4": .bullet(0),
                                               "5": .number("1.", 0), "6": .quote, "7": .fence, "8": .paragraph]
            if let block = blocks[key] { edit { editor.setBlock(block) } }
        case .font:
            done()
            let kinds: [String: CodeKind] = ["1": .bold, "2": .italic, "3": .strike, "4": .code]
            if let kind = kinds[key] { format(kind) }
        case .exit:
            done()
            if key.lowercased() == "y" { window?.performClose(nil) }
        case .search(let forward):
            if event.keyCode == 36 || event.keyCode == 76 || key.unicodeScalars.first?.value == 0xF705 { // Return, F2
                done()
                search(prompt.answer, forward: forward)
            } else if event.keyCode == 51 {
                if !prompt.answer.isEmpty { prompt.answer.removeLast() }
                self.prompt = prompt
            } else if let typed = event.characters, !typed.isEmpty, typed.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) {
                prompt.answer += typed
                self.prompt = prompt
            }
            needsDisplay = true
        }
    }

    private var lastSearch = ""

    private func search(_ words: String, forward: Bool) {
        let needle = words.isEmpty ? lastSearch : words
        guard !needle.isEmpty else { return }
        lastSearch = needle
        let text = editor.chars
        let target = Array(needle.lowercased())
        func matches(at i: Int) -> Bool {
            guard i + target.count <= text.count else { return false }
            for k in 0..<target.count where String(text[i + k]).lowercased() != String(target[k]) { return false }
            return true
        }
        let from = editor.cursor
        let order = forward ? Array((from + 1)..<max(from + 1, text.count)) : Array((0..<from).reversed())
        if let hit = order.first(where: matches) {
            editor.anchor = nil
            editor.cursor = forward ? hit + target.count : hit
            moved()
        } else {
            say("* Not found *")
        }
    }

    private func cancel() {
        editor.anchor = nil
        blockKeyOn = false
        prompt = nil
        marked = ""
        changed(edited: false)
    }

    private func rowEdge(start: Bool) {
        let row = layout.locate(editor.stop(atOrAfter: editor.cursor)).row
        if let offset = start ? layout.firstOffset(row: row) : layout.lastOffset(row: row) { editor.cursor = offset }
    }

    private func vertical(_ delta: Int) {
        let here = layout.locate(editor.stop(atOrAfter: editor.cursor))
        let goal = goalCol ?? here.col
        var row = here.row + delta
        row = max(0, min(row, layout.rows.count - 1))
        while layout.rows.indices.contains(row), layout.rows[row].isPageBreak { row += delta > 0 ? 1 : -1 }
        guard layout.rows.indices.contains(row), let offset = layout.offset(row: row, col: goal) else { return }
        editor.cursor = offset
        goalCol = goal
        if abs(delta) > 1 { topRow = max(0, topRow + delta) }
    }

    private func keepGoal(_ body: () -> Void) {
        let goal = goalCol
        body()
        goalCol = goal
    }

    // MARK: - Text input

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(moveLeft(_:)): move(extending: false) { editor.moveLeft() }
        case #selector(moveRight(_:)): move(extending: false) { editor.moveRight() }
        case #selector(moveUp(_:)): move(extending: false) { keepGoal { vertical(-1) } }
        case #selector(moveDown(_:)): move(extending: false) { keepGoal { vertical(1) } }
        case #selector(moveLeftAndModifySelection(_:)): move(extending: true) { editor.moveLeft() }
        case #selector(moveRightAndModifySelection(_:)): move(extending: true) { editor.moveRight() }
        case #selector(moveUpAndModifySelection(_:)): move(extending: true) { keepGoal { vertical(-1) } }
        case #selector(moveDownAndModifySelection(_:)): move(extending: true) { keepGoal { vertical(1) } }
        case #selector(moveWordLeft(_:)), #selector(moveWordBackward(_:)): move(extending: false) { editor.moveWord(forward: false) }
        case #selector(moveWordRight(_:)), #selector(moveWordForward(_:)): move(extending: false) { editor.moveWord(forward: true) }
        case #selector(moveWordLeftAndModifySelection(_:)): move(extending: true) { editor.moveWord(forward: false) }
        case #selector(moveWordRightAndModifySelection(_:)): move(extending: true) { editor.moveWord(forward: true) }
        case #selector(moveToBeginningOfLine(_:)), #selector(moveToLeftEndOfLine(_:)): move(extending: false) { rowEdge(start: true) }
        case #selector(moveToEndOfLine(_:)), #selector(moveToRightEndOfLine(_:)): move(extending: false) { rowEdge(start: false) }
        case #selector(moveToLeftEndOfLineAndModifySelection(_:)): move(extending: true) { rowEdge(start: true) }
        case #selector(moveToRightEndOfLineAndModifySelection(_:)): move(extending: true) { rowEdge(start: false) }
        case #selector(moveToBeginningOfDocument(_:)): move(extending: false) { editor.cursor = 0 }
        case #selector(moveToEndOfDocument(_:)): move(extending: false) { editor.cursor = editor.chars.count }
        case #selector(moveToBeginningOfDocumentAndModifySelection(_:)): move(extending: true) { editor.cursor = 0 }
        case #selector(moveToEndOfDocumentAndModifySelection(_:)): move(extending: true) { editor.cursor = editor.chars.count }
        case #selector(scrollPageUp(_:)), #selector(pageUp(_:)): move(extending: false) { vertical(-max(1, textRows - 1)) }
        case #selector(scrollPageDown(_:)), #selector(pageDown(_:)): move(extending: false) { vertical(max(1, textRows - 1)) }
        case #selector(deleteBackward(_:)): edit { editor.deleteBackward() }; blockKeyOn = false
        case #selector(deleteForward(_:)): edit { editor.deleteForward() }; blockKeyOn = false
        case #selector(deleteWordBackward(_:)):
            edit {
                let end = editor.cursor
                editor.moveWord(forward: false)
                editor.anchor = end
                editor.deleteSelection()
            }
        case #selector(insertNewline(_:)): edit { editor.newline() }; blockKeyOn = false
        case #selector(insertTab(_:)):
            // In a table Tab goes to the next cell, adding a row after the last.
            edit { if !editor.moveCell(forward: true) { editor.insert("\t") } }
        case #selector(insertBacktab(_:)): edit { editor.moveCell(forward: false) }
        case #selector(cancelOperation(_:)): cancel()
        default: break
        }
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        marked = ""
        guard !text.isEmpty else { return }
        blockKeyOn = false
        edit(typing: true) { editor.insert(text) }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        needsDisplay = true
    }

    func unmarkText() { marked = "" }
    func selectedRange() -> NSRange { NSRange(location: editor.cursor, length: 0) }
    func markedRange() -> NSRange { marked.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: editor.cursor, length: marked.count) }
    func hasMarkedText() -> Bool { !marked.isEmpty }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { editor.cursor }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let at = layout.locate(editor.stop(atOrAfter: editor.cursor))
        let rect = cellRect(col: at.col, row: at.row - topRow)
        guard let window else { return .zero }
        return window.convertToScreen(convert(rect, to: nil))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if showingHelp { showingHelp = false; needsDisplay = true; return }
        // A click on a key of the template does that key's job.
        let point = convert(event.locationInWindow, from: nil)
        if showsTemplate, Int(point.y / lineHeight) == screenRows - 2 {
            let col = Int(point.x / cellWidth)
            if let hit = templateHits.first(where: { $0.cols.contains(col) }) { perform(hit.action) }
            return
        }
        guard let offset = offset(at: convert(event.locationInWindow, from: nil)) else { return }
        if event.modifierFlags.contains(.shift) {
            if editor.anchor == nil { editor.anchor = editor.cursor }
        } else {
            editor.anchor = nil
            blockKeyOn = false
        }
        editor.cursor = offset
        dragAnchor = editor.anchor ?? offset
        goalCol = nil
        moved()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchor, let offset = offset(at: convert(event.locationInWindow, from: nil)) else { return }
        editor.anchor = anchor
        editor.cursor = offset
        moved()
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchor = nil
        if editor.anchor == editor.cursor { editor.anchor = nil; needsDisplay = true }
    }

    override func scrollWheel(with event: NSEvent) {
        let rows = Int((-event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? lineHeight : 1)).rounded())
        guard rows != 0 else { return }
        topRow = max(0, min(topRow + rows, max(0, layout.rows.count - textRows)))
        needsDisplay = true
    }

    private func offset(at point: NSPoint) -> Int? {
        let screenRow = Int(point.y / lineHeight)
        guard screenRow < textRows else { return nil }
        let row = min(topRow + screenRow, layout.rows.count - 1)
        guard row >= 0 else { return nil }
        return layout.offset(row: row, col: Int(point.x / cellWidth))
    }

    // MARK: - Menu actions

    @objc func toggleBold(_ sender: Any?) { format(.bold) }
    @objc func toggleItalic(_ sender: Any?) { format(.italic) }
    @objc func toggleStrikeout(_ sender: Any?) { format(.strike) }
    @objc func toggleCode(_ sender: Any?) { format(.code) }

    private func format(_ kind: CodeKind) {
        blockKeyOn = false
        edit { editor.toggle(kind) }
    }

    @objc func toggleRevealCodes(_ sender: Any?) {
        editor.revealed.toggle()
        changed(edited: false)
    }

    @objc func toggleBlock(_ sender: Any?) {
        if editor.anchor == nil {
            editor.anchor = editor.cursor
            blockKeyOn = true
        } else {
            editor.anchor = nil
            blockKeyOn = false
        }
        needsDisplay = true
    }

    /// Alt-F7, Columns/Table in WordPerfect: a new table, two columns by two rows.
    @objc func insertTable(_ sender: Any?) {
        blockKeyOn = false
        edit { editor.insertTable() }
        say("Table: Tab moves to the next cell; Enter adds a row")
    }

    @objc func toggleKeyTemplate(_ sender: Any?) {
        UserDefaults.standard.set(!showsTemplate, forKey: "keyTemplate")
        scrollToCursor()
        needsDisplay = true
    }

    @objc func showHelp(_ sender: Any?) {
        showingHelp = true
        needsDisplay = true
    }

    @objc func styleHeading1(_ sender: Any?) { edit { editor.setBlock(.heading(1)) } }
    @objc func styleHeading2(_ sender: Any?) { edit { editor.setBlock(.heading(2)) } }
    @objc func styleHeading3(_ sender: Any?) { edit { editor.setBlock(.heading(3)) } }
    @objc func styleBullet(_ sender: Any?) { edit { editor.setBlock(.bullet(0)) } }
    @objc func styleNumbered(_ sender: Any?) { edit { editor.setBlock(.number("1.", 0)) } }
    @objc func styleQuote(_ sender: Any?) { edit { editor.setBlock(.quote) } }
    @objc func styleCodeBlock(_ sender: Any?) { edit { editor.setBlock(.fence) } }
    @objc func styleNormal(_ sender: Any?) { edit { editor.setBlock(.paragraph) } }

    @objc func copy(_ sender: Any?) {
        guard let range = editor.selection else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(editor.chars[range]), forType: .string)
    }

    @objc func cut(_ sender: Any?) {
        guard editor.selection != nil else { NSSound.beep(); return }
        copy(sender)
        blockKeyOn = false
        edit { editor.deleteSelection() }
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        blockKeyOn = false
        edit { editor.insert(text) }
    }

    @objc override func selectAll(_ sender: Any?) {
        editor.anchor = 0
        editor.cursor = editor.chars.count
        moved()
    }
}
