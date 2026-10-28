// Accent — the highlight colour all the widgets share.

import SwiftUI
import AppKit

/// The highlight colour every widget draws with, picked from any widget's right-click
/// menu. It's kept in a preferences domain they all share, and each one watches it, so
/// changing it in one recolours them all. Views read it as the `accent` environment
/// value, which is orange where nothing sets it, as in the app icons.
enum Accent: String, CaseIterable, Identifiable {
    case orange, red, pink, purple, blue, teal, green, yellow, system

    static let defaults = UserDefaults(suiteName: "com.mbolding.desktopwidgets")!

    var id: Self { self }
    var name: String { self == .system ? "Match System" : rawValue.capitalized }
    var color: Color { Color(nsColor: nsColor) }

    private var nsColor: NSColor {
        switch self {
        case .orange: .systemOrange
        case .red: .systemRed
        case .pink: .systemPink
        case .purple: .systemPurple
        case .blue: .systemBlue
        case .teal: .systemTeal
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .system: .controlAccentColor
        }
    }

    /// A dot of the colour for the menu; not a template, so the menu keeps its colour.
    var swatch: NSImage {
        let color = nsColor
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

extension EnvironmentValues {
    @Entry var accent: Color = .orange
}
