// Chrome — Word 5.1's window around the page, in System 7's black and white: the Ribbon
// (the paragraph's style, the font and size, buttons for bold, italic, strikethrough and
// code, and ¶ for Show ¶), the Ruler (inches from the left margin, with the paragraph's
// indents as triangles), and the page box at the bottom left. Geneva, the Mac's small
// interface face since 1984, still ships with macOS; Chicago, its menu face, doesn't.

import SwiftUI

enum Chrome {
    static let font = Font.custom("Geneva", size: 11)
    static let small = Font.custom("Geneva", size: 9)
}

struct Ribbon: View {
    @ObservedObject var state: PageState

    var body: some View {
        HStack(spacing: 6) {
            styleMenu
            box("Times", width: 92)
            box("\(Int(Page.bodySize / Page.zoom))", width: 34)
            Rectangle().fill(.black).frame(width: 1, height: 18)
            toggle("B", on: state.style.contains(.bold), help: "Bold (⌘B)", font: .custom("Times-Bold", size: 14)) { $0.toggleBold(nil) }
            toggle("I", on: state.style.contains(.italic), help: "Italic (⌘I)", font: .custom("Times-Italic", size: 14)) { $0.toggleItalic(nil) }
            toggle("S", on: state.style.contains(.strike), help: "Strikethrough (⇧⌘X)", font: .custom("Times-Roman", size: 14), strike: true) { $0.toggleStrikeout(nil) }
            toggle("{ }", on: state.style.contains(.code), help: "Code (⇧⌘K)", font: .custom("Monaco", size: 10)) { $0.toggleCode(nil) }
            Rectangle().fill(.black).frame(width: 1, height: 18)
            toggle("¶", on: state.showMarks, help: "Show ¶ (⌘J): the Markdown, the returns and the spaces", font: .custom("Times-Roman", size: 15)) { $0.toggleShowMarks(nil) }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Color.white)
    }

    private var styleMenu: some View {
        Menu {
            ForEach(Self.styles, id: \.name) { style in
                Button(style.name) { act { $0.setBlock(style.block) } }
            }
        } label: {
            Text(Self.name(of: state.block)).font(Chrome.font).foregroundStyle(.black)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .frame(width: 110)
        .padding(.horizontal, 4)
        .frame(height: 20)
        .overlay(Rectangle().stroke(.black, lineWidth: 1))
        .help("The paragraph's style")
    }

    static let styles: [(name: String, block: BlockKind)] = [
        ("Normal", .paragraph), ("heading 1", .heading(1)), ("heading 2", .heading(2)), ("heading 3", .heading(3)),
        ("List Bullet", .bullet(0)), ("List Number", .number("1.", 0)), ("Quote", .quote), ("Code", .fence),
    ]

    static func name(of block: BlockKind) -> String {
        switch block {
        case .heading(let level): "heading \(level)"
        case .bullet: "List Bullet"
        case .number: "List Number"
        case .quote: "Quote"
        case .fence, .fenced: "Code"
        case .rule: "Rule"
        case .paragraph: "Normal"
        case .tableRow, .tableRule: "Table"
        }
    }

    private func box(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(Chrome.font)
            .foregroundStyle(.black)
            .frame(width: width, height: 20, alignment: .leading)
            .padding(.leading, 4)
            .overlay(Rectangle().stroke(.black, lineWidth: 1))
            .help("Markdown has no fonts or sizes: the page is set in Times, as Word's Normal style was")
    }

    private func toggle(_ label: String, on: Bool, help: String, font: Font, strike: Bool = false,
                        action: @escaping (PageTextView) -> Void) -> some View {
        Button { act(action) } label: {
            Text(label)
                .font(font)
                .strikethrough(strike)
                .foregroundStyle(on ? .white : .black)
                .frame(width: 24, height: 20)
                .background(on ? Color.black : Color.white)
                .overlay(Rectangle().stroke(.black, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func act(_ action: (PageTextView) -> Void) {
        guard let view = state.view else { return }
        action(view)
        view.window?.makeFirstResponder(view)
    }
}

struct Ruler: View {
    @ObservedObject var state: PageState

    var body: some View {
        Canvas { context, size in
            let left = Page.margin
            let line = Path { p in
                p.move(to: CGPoint(x: left, y: 18.5))
                p.addLine(to: CGPoint(x: left + Page.textWidth, y: 18.5))
            }
            context.stroke(line, with: .color(.black), lineWidth: 1)
            // Ticks every eighth of an inch, longer at the half and whole inches.
            for eighth in 0...Int(6.5 * 8) {
                let x = left + CGFloat(eighth) * Page.inch / 8 + 0.5
                let length: CGFloat = eighth % 8 == 0 ? 7 : eighth % 4 == 0 ? 5 : 3
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: 18))
                    p.addLine(to: CGPoint(x: x, y: 18 - length))
                }, with: .color(.black), lineWidth: 1)
                if eighth % 8 == 0, eighth > 0 {
                    context.draw(Text("\(eighth / 8)").font(Chrome.small).foregroundStyle(.black),
                                 at: CGPoint(x: x + 5, y: 6), anchor: .center)
                }
            }
            // The paragraph's indents: first line and left as triangles below the line,
            // the right indent at its end.
            let (first, head, tail) = indents
            func triangle(at x: CGFloat, up: Bool) {
                let y: CGFloat = up ? 26 : 20
                context.fill(Path { p in
                    p.move(to: CGPoint(x: x - 4, y: up ? y : y))
                    p.addLine(to: CGPoint(x: x + 4, y: y))
                    p.addLine(to: CGPoint(x: x, y: up ? y - 5 : y + 5))
                    p.closeSubpath()
                }, with: .color(.black))
            }
            triangle(at: left + first, up: false)
            triangle(at: left + head, up: true)
            triangle(at: left + Page.textWidth - tail, up: true)
            _ = size
        }
        .frame(height: 30)
        .background(Color.white)
        .help("The Ruler: inches from the left margin, and the paragraph's indents")
    }

    private var indents: (CGFloat, CGFloat, CGFloat) {
        switch state.block {
        case .bullet(let depth), .number(_, let depth):
            let indent = CGFloat(depth + 1) * 0.25 * Page.inch
            return (indent - 0.25 * Page.inch, indent, 0)
        case .quote: return (0.5 * Page.inch, 0.5 * Page.inch, 0.5 * Page.inch)
        case .fence, .fenced: return (0.25 * Page.inch, 0.25 * Page.inch, 0)
        default: return (0, 0, 0)
        }
    }
}

/// The bottom left of Word's window: the page the insertion point is on, and the style.
struct PageBox: View {
    @ObservedObject var state: PageState

    var body: some View {
        HStack(spacing: 0) {
            Text("Page \(state.page)")
                .font(Chrome.font)
                .foregroundStyle(.black)
                .frame(width: 70, height: 18)
                .overlay(Rectangle().stroke(.black, lineWidth: 1))
            Text(Ribbon.name(of: state.block))
                .font(Chrome.font)
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .overlay(Rectangle().stroke(.black, lineWidth: 1))
            Spacer()
            if state.showMarks {
                Text("Show ¶").font(Chrome.font).foregroundStyle(.black).padding(.trailing, 8)
            }
        }
        .frame(height: 18)
        .background(Color.white)
    }
}
