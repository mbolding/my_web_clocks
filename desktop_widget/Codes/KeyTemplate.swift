// KeyTemplate — WordPerfect's function keys in one table, after the cardboard template that
// sat around the keyboard's F-keys with four colours of label: black for the key alone,
// green with Shift, blue with Alt and red with Ctrl. The keys, the template strip drawn
// above the status line and the Touch Bar all work from it, the last two changing with
// whichever of Shift, Alt and Ctrl is held.

import AppKit

enum KeyAction {
    case cancel, search, searchBack, help, reveal, block, bold, exit, print, italic, font, style, save, open
}

struct TemplateKey {
    enum Shift: CaseIterable { case none, shift, alt, ctrl }
    var number: Int
    var shift: Shift
    var action: KeyAction
    /// Short, for the strip and the Touch Bar.
    var label: String

    var name: String {
        switch shift {
        case .none: "F\(number)"
        case .shift: "Shift-F\(number)"
        case .alt: "Alt-F\(number)"
        case .ctrl: "Ctrl-F\(number)"
        }
    }

    static let all: [TemplateKey] = [
        TemplateKey(number: 1, shift: .none, action: .cancel, label: "Cancel"),
        TemplateKey(number: 2, shift: .none, action: .search, label: "Search"),
        TemplateKey(number: 3, shift: .none, action: .help, label: "Help"),
        TemplateKey(number: 6, shift: .none, action: .bold, label: "Bold"),
        TemplateKey(number: 7, shift: .none, action: .exit, label: "Exit"),
        TemplateKey(number: 8, shift: .none, action: .italic, label: "Italic"),
        TemplateKey(number: 10, shift: .none, action: .save, label: "Save"),
        TemplateKey(number: 11, shift: .none, action: .reveal, label: "Codes"),
        TemplateKey(number: 12, shift: .none, action: .block, label: "Block"),
        TemplateKey(number: 2, shift: .shift, action: .searchBack, label: "Search back"),
        TemplateKey(number: 7, shift: .shift, action: .print, label: "Print"),
        TemplateKey(number: 10, shift: .shift, action: .open, label: "Retrieve"),
        TemplateKey(number: 3, shift: .alt, action: .reveal, label: "Reveal Codes"),
        TemplateKey(number: 4, shift: .alt, action: .block, label: "Block"),
        TemplateKey(number: 8, shift: .alt, action: .style, label: "Style"),
        TemplateKey(number: 8, shift: .ctrl, action: .font, label: "Font"),
    ]

    static func keys(for shift: Shift) -> [TemplateKey] { all.filter { $0.shift == shift } }

    static func action(number: Int, shift: Shift) -> KeyAction? {
        all.first { $0.number == number && $0.shift == shift }?.action
    }

    /// Which set of labels the held modifier keys call for.
    static func shift(for flags: NSEvent.ModifierFlags) -> Shift {
        if flags.contains(.control) { return .ctrl }
        if flags.contains(.option) { return .alt }
        if flags.contains(.shift) { return .shift }
        return .none
    }

    /// The template's colour for each set of labels.
    static func color(_ shift: Shift) -> NSColor {
        switch shift {
        case .none: NSColor(white: 0.3, alpha: 1)
        case .shift: NSColor(srgbRed: 0.1, green: 0.55, blue: 0.2, alpha: 1)
        case .alt: NSColor(srgbRed: 0.15, green: 0.3, blue: 0.85, alpha: 1)
        case .ctrl: NSColor(srgbRed: 0.8, green: 0.15, blue: 0.15, alpha: 1)
        }
    }

    static func heading(_ shift: Shift) -> String {
        switch shift {
        case .none: ""
        case .shift: "Shift "
        case .alt: "Alt "
        case .ctrl: "Ctrl "
        }
    }
}

// MARK: - The Touch Bar

extension NSTouchBarItem.Identifier {
    static func templateKey(_ key: TemplateKey) -> NSTouchBarItem.Identifier {
        NSTouchBarItem.Identifier("com.mbolding.revealcodes.\(key.shift)-\(key.number)")
    }
}

/// Buttons for the keys of the set held down, in the template's colour, each doing its key's
/// job when tapped, so the F-keys (and fn) aren't needed at all.
final class TemplateTouchBar: NSObject, NSTouchBarDelegate {
    let shift: TemplateKey.Shift
    let perform: (KeyAction) -> Void
    private let keys: [TemplateKey]

    init(shift: TemplateKey.Shift, perform: @escaping (KeyAction) -> Void) {
        self.shift = shift
        self.perform = perform
        keys = TemplateKey.keys(for: shift)
    }

    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = keys.map { .templateKey($0) }
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let index = keys.firstIndex(where: { .templateKey($0) == identifier }) else { return nil }
        let key = keys[index]
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: "\(TemplateKey.heading(shift))F\(key.number) \(key.label)", target: self, action: #selector(tapped(_:)))
        button.tag = index
        button.bezelColor = TemplateKey.color(shift)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        item.view = button
        return item
    }

    @objc private func tapped(_ sender: NSButton) {
        perform(keys[sender.tag].action)
    }
}
