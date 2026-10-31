// Formatting — IRC's in-line codes: ^B bold, ^] italic, ^_ underline, ^^ strikethrough, ^C
// with up to two numbers for mIRC's sixteen colours, ^D with hex colours, ^V reverse and ^O
// to reset. They're drawn where they can be and taken out where they can't.

import AppKit

enum Formatting {
    /// mIRC's palette, 0 to 15.
    static let palette: [NSColor] = [
        .white, .black, NSColor(red: 0, green: 0, blue: 0.5, alpha: 1), NSColor(red: 0, green: 0.58, blue: 0, alpha: 1),
        .systemRed, NSColor(red: 0.5, green: 0, blue: 0, alpha: 1), NSColor(red: 0.61, green: 0, blue: 0.61, alpha: 1), .systemOrange,
        .systemYellow, NSColor(red: 0, green: 0.85, blue: 0, alpha: 1), NSColor(red: 0, green: 0.58, blue: 0.58, alpha: 1), .systemTeal,
        .systemBlue, NSColor(red: 1, green: 0, blue: 1, alpha: 1), .systemGray, .lightGray,
    ]

    /// The colour a nick is always drawn in, picked from its letters.
    static func color(for nick: String) -> NSColor {
        let colors: [NSColor] = [.systemRed, .systemOrange, .systemGreen, .systemTeal, .systemBlue, .systemPurple,
                                 .systemPink, .systemBrown, .systemIndigo, .systemMint, .systemCyan]
        var hash: UInt32 = 5381
        for byte in nick.lowercased().utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return colors[Int(hash % UInt32(colors.count))]
    }

    static func strip(_ text: String) -> String {
        var out = ""
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            switch c {
            case "\u{2}", "\u{1D}", "\u{1F}", "\u{1E}", "\u{11}", "\u{16}", "\u{F}": continue
            case "\u{3}": _ = colorCode(&chars)
            case "\u{4}": skipHex(&chars)
            default: out.append(c)
            }
        }
        return out
    }

    /// `text` drawn with its codes, starting from `attributes`.
    static func attributed(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let baseFont = attributes[.font] as? NSFont ?? .systemFont(ofSize: 13)
        var bold = false, italic = false, underline = false, strike = false
        var foreground: NSColor?, background: NSColor?
        var run = ""

        func flush() {
            guard !run.isEmpty else { return }
            var attrs = attributes
            var traits: NSFontDescriptor.SymbolicTraits = baseFont.fontDescriptor.symbolicTraits
            if bold { traits.insert(.bold) }
            if italic { traits.insert(.italic) }
            if bold || italic {
                attrs[.font] = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(traits), size: baseFont.pointSize) ?? baseFont
            }
            if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let foreground { attrs[.foregroundColor] = foreground }
            if let background { attrs[.backgroundColor] = background }
            out.append(NSAttributedString(string: run, attributes: attrs))
            run = ""
        }

        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            switch c {
            case "\u{2}": flush(); bold.toggle()
            case "\u{1D}": flush(); italic.toggle()
            case "\u{1F}": flush(); underline.toggle()
            case "\u{1E}": flush(); strike.toggle()
            case "\u{11}", "\u{16}": continue
            case "\u{F}":
                flush()
                bold = false; italic = false; underline = false; strike = false
                foreground = nil; background = nil
            case "\u{3}":
                flush()
                if let (fg, bg) = colorCode(&chars) {
                    foreground = palette[fg % 16]
                    if let bg { background = palette[bg % 16].withAlphaComponent(0.35) }
                } else {
                    foreground = nil; background = nil
                }
            case "\u{4}":
                flush()
                skipHex(&chars)
            default:
                run.append(c)
            }
        }
        flush()
        return out
    }

    /// Reads the numbers after ^C: a foreground of one or two digits, then perhaps a comma
    /// and a background. Nil when there are none, which resets the colours.
    private static func colorCode(_ chars: inout ArraySlice<Character>) -> (Int, Int?)? {
        func number() -> Int? {
            var digits = ""
            while digits.count < 2, let c = chars.first, c.isASCII, c.isNumber {
                digits.append(c)
                chars.removeFirst()
            }
            return Int(digits)
        }
        guard let fg = number() else { return nil }
        if chars.first == ",", chars.dropFirst().first?.isNumber == true {
            chars.removeFirst()
            return (fg, number())
        }
        return (fg, nil)
    }

    private static func skipHex(_ chars: inout ArraySlice<Character>) {
        func hex() { for _ in 0..<6 where chars.first?.isHexDigit == true { chars.removeFirst() } }
        hex()
        if chars.first == ",", chars.dropFirst().first?.isHexDigit == true {
            chars.removeFirst()
            hex()
        }
    }
}
