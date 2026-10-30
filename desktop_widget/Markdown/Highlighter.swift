// Highlighter — light Markdown colouring, applied as text attributes as you type.
// Only the paragraphs an edit touched are redone, unless it opened or closed a fenced
// code block, which changes every line after it. The markup itself stays visible, dimmed.

import AppKit

/// The fonts and colours the highlighter draws with, from the app's settings.
struct MarkdownTheme: Equatable {
    var fontSize: CGFloat
    var monospaced: Bool
    var accent: NSColor

    func font(scale: CGFloat = 1, bold: Bool = false) -> NSFont {
        let size = (fontSize * scale).rounded()
        let weight: NSFont.Weight = bold ? .bold : .regular
        return monospaced ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    }

    var codeFont: NSFont { .monospacedSystemFont(ofSize: (fontSize * (monospaced ? 1 : 0.94)).rounded(), weight: .regular) }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.15
        return style
    }

    /// What plain text looks like, and what new typing starts as.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: NSColor.textColor, .paragraphStyle: paragraphStyle]
    }

    static let markup = NSColor.tertiaryLabelColor
    static let secondary = NSColor.secondaryLabelColor
    static let codeBackground = NSColor.quaternarySystemFill
}

final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    var theme = MarkdownTheme(fontSize: 13, monospaced: true, accent: .systemOrange)
    /// The fence lines as they last were, to tell when an edit changed which lines are code.
    private var fenceShape: [Int] = []

    func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let fences = Fences(storage.string)
        let string = storage.string as NSString
        if fences.shape != fenceShape {
            fenceShape = fences.shape
            highlight(storage, in: NSRange(location: 0, length: string.length), fences: fences)
        } else {
            highlight(storage, in: string.paragraphRange(for: editedRange), fences: fences)
        }
    }

    /// Redoes the whole text, as when the font or accent changes.
    func highlightAll(_ storage: NSTextStorage) {
        let fences = Fences(storage.string)
        fenceShape = fences.shape
        storage.beginEditing()
        highlight(storage, in: NSRange(location: 0, length: storage.length), fences: fences)
        storage.endEditing()
    }

    private func highlight(_ storage: NSTextStorage, in range: NSRange, fences: Fences) {
        guard range.length > 0 else { return }
        storage.setAttributes(theme.baseAttributes, range: range)

        // Code blocks first; whatever falls between them gets the Markdown rules.
        var cursor = range.location
        for block in fences.blocks where NSIntersectionRange(block.range, range).length > 0 {
            let inside = NSIntersectionRange(block.range, range)
            if inside.location > cursor { highlightText(storage, in: NSRange(location: cursor, length: inside.location - cursor)) }
            storage.addAttributes([.font: theme.codeFont, .backgroundColor: MarkdownTheme.codeBackground], range: inside)
            for fence in block.fences {
                let line = NSIntersectionRange(fence, range)
                if line.length > 0 { storage.addAttribute(.foregroundColor, value: MarkdownTheme.markup, range: line) }
            }
            cursor = NSMaxRange(inside)
        }
        if NSMaxRange(range) > cursor { highlightText(storage, in: NSRange(location: cursor, length: NSMaxRange(range) - cursor)) }
    }

    /// Markdown outside fenced code: whole-line rules first, then the inline spans.
    private func highlightText(_ storage: NSTextStorage, in range: NSRange) {
        let string = storage.string
        let accent = theme.accent

        Rules.quote.enumerateMatches(in: string, range: range) { m, _, _ in
            guard let m else { return }
            let line = (string as NSString).lineRange(for: m.range)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: line)
            storage.addAttribute(.foregroundColor, value: accent, range: m.range)
        }
        Rules.list.enumerateMatches(in: string, range: range) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: accent, range: m.range(at: 1))
            if m.range(at: 2).location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: accent, range: m.range(at: 2))
            }
        }
        Rules.rule.enumerateMatches(in: string, range: range) { m, _, _ in
            guard let m else { return }
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.markup, range: m.range)
        }
        Rules.heading.enumerateMatches(in: string, range: range) { m, _, _ in
            guard let m else { return }
            let level = m.range(at: 1).length
            let scale: CGFloat = [1.6, 1.35, 1.18, 1.08, 1, 1][level - 1]
            storage.addAttribute(.font, value: theme.font(scale: scale, bold: true), range: m.range)
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: m.range)
            storage.addAttribute(.foregroundColor, value: accent, range: m.range(at: 1))
        }

        // Code spans and link addresses are taken as they are, so a `*` or `_` inside one
        // isn't read as emphasis.
        var literal = IndexSet()
        func isFree(_ r: NSRange) -> Bool { !literal.intersects(integersIn: Range(r)!) }

        Rules.code.enumerateMatches(in: string, range: range) { m, _, _ in
            guard let m else { return }
            literal.insert(integersIn: Range(m.range)!)
            storage.addAttributes([.font: theme.codeFont, .backgroundColor: MarkdownTheme.codeBackground], range: m.range)
            let ticks = m.range(at: 1).length
            dim(storage, NSRange(location: m.range.location, length: ticks))
            dim(storage, NSRange(location: NSMaxRange(m.range) - ticks, length: ticks))
        }
        Rules.link.enumerateMatches(in: string, range: range) { m, _, _ in
            guard let m, isFree(m.range) else { return }
            dim(storage, m.range)
            storage.addAttribute(.foregroundColor, value: accent, range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: m.range(at: 2))
            literal.insert(integersIn: Range(m.range(at: 2))!)
        }
        Rules.autolink.enumerateMatches(in: string, range: range) { m, _, _ in
            guard let m, isFree(m.range) else { return }
            dim(storage, m.range)
            storage.addAttribute(.foregroundColor, value: accent, range: m.range(at: 1))
            literal.insert(integersIn: Range(m.range)!)
        }

        for (rule, marker, trait) in [(Rules.strongEmphasis, 3, NSFontTraitMask([.boldFontMask, .italicFontMask])),
                                      (Rules.strongStar, 2, .boldFontMask), (Rules.strongUnderscore, 2, .boldFontMask),
                                      (Rules.emphasisStar, 1, .italicFontMask), (Rules.emphasisUnderscore, 1, .italicFontMask)] {
            rule.enumerateMatches(in: string, range: range) { m, _, _ in
                guard let m, isFree(m.range) else { return }
                add(trait, to: storage, in: m.range)
                dim(storage, NSRange(location: m.range.location, length: marker))
                dim(storage, NSRange(location: NSMaxRange(m.range) - marker, length: marker))
            }
        }
        Rules.strike.enumerateMatches(in: string, range: range) { m, _, _ in
            guard let m, isFree(m.range) else { return }
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range)
            dim(storage, NSRange(location: m.range.location, length: 2))
            dim(storage, NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
    }

    private func dim(_ storage: NSTextStorage, _ range: NSRange) {
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.markup, range: range)
    }

    /// Makes the text bold or italic on top of whatever size and weight it has, so emphasis
    /// inside a heading keeps the heading's size.
    private func add(_ trait: NSFontTraitMask, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: run)
        }
    }
}

/// The fenced code blocks (``` or ~~~) in the text. A block runs from its opening fence to
/// a closing one of the same character and at least the same length, or to the end.
struct Fences {
    struct Block {
        var range: NSRange
        var fences: [NSRange]
    }

    var blocks: [Block] = []
    /// Each opening and closing fence's character and length, which is all that decides
    /// which lines are code; it doesn't change when text elsewhere moves the fences along.
    var shape: [Int] = []

    init(_ string: String) {
        let ns = string as NSString
        var open: (range: NSRange, char: unichar, length: Int)?
        Rules.fence.enumerateMatches(in: string, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let line = ns.lineRange(for: m.range)
            let marker = m.range(at: 1)
            let char = ns.character(at: marker.location)
            let info = ns.substring(with: m.range(at: 2))
            if let o = open {
                guard char == o.char, marker.length >= o.length,
                      info.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                blocks.append(Block(range: NSUnionRange(o.range, line), fences: [o.range, line]))
                shape.append(-marker.length)
                open = nil
            } else {
                // ```code``` on one line is a code span, not a fence.
                if char == 0x60, info.contains("`") { return }
                open = (line, char, marker.length)
                shape.append(Int(char) << 16 | marker.length)
            }
        }
        if let o = open {
            blocks.append(Block(range: NSRange(location: o.range.location, length: ns.length - o.range.location), fences: [o.range]))
        }
    }
}

/// The patterns, compiled once. Each runs over a stretch of whole lines.
enum Rules {
    private static func make(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
    }

    static let fence = make("^ {0,3}(`{3,}|~{3,})([^\\n]*)$")
    static let heading = make("^ {0,3}(#{1,6})(?=[ \\t]|$)[^\\n]*")
    static let rule = make("^ {0,3}([-*_])(?:[ \\t]*\\1){2,}[ \\t]*$|^ {0,3}=+[ \\t]*$")
    static let quote = make("^ {0,3}(?:>[ \\t]?)+")
    // A bullet or number after any quote markers, and a task box after it.
    static let list = make("^(?:[ \\t]*>)*[ \\t]*([-*+]|\\d{1,9}[.)])[ \\t]+(\\[[ xX]\\](?=[ \\t]))?")
    // A run of backticks, then anything up to a run of exactly the same length.
    static let code = make("(?<!`)(`+)(?=[^`\\n])[^\\n]*?(?<=[^`])\\1(?!`)")
    static let link = make("!?\\[([^\\]\\n]*)\\]\\(([^)\\n]*)\\)")
    static let autolink = make("<((?:https?|mailto):[^>\\s]+)>")
    static let strongEmphasis = make("(?<![\\\\*])\\*\\*\\*(?=[^\\s*])[^\\n]*?(?<=[^\\s*\\\\])\\*\\*\\*(?!\\*)")
    static let strongStar = make("(?<!\\\\)\\*\\*(?=[^\\s*])[^\\n]*?(?<=[^\\s\\\\])\\*\\*")
    static let strongUnderscore = make("(?<![\\\\\\w])__(?=[^\\s_])[^\\n]*?(?<=[^\\s\\\\])__(?!\\w)")
    static let emphasisStar = make("(?<![\\\\*])\\*(?=[^\\s*])[^\\n]*?(?<=[^\\s*\\\\])\\*(?!\\*)")
    static let emphasisUnderscore = make("(?<![\\\\\\w])_(?=[^\\s_])[^\\n]*?(?<=[^\\s_\\\\])_(?!\\w)")
    static let strike = make("(?<!~)~~(?=\\S)[^\\n]*?(?<=\\S)~~(?!~)")
}
