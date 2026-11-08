// Text Drawer — a drawer at the edge of the screen for text you drop on it. A thin tab
// peeks in from the edge; drag selected text onto it from any app and it keeps a card.
// Hover or click the tab to slide out the last twenty, click one to copy it or drag it
// back out into any app.

import SwiftUI

@main
enum TextDrawerApp {
    @MainActor static func main() {
        EdgeDrawer.run(panelSize: CGSize(width: 280, height: 440), position: 0.3,
                       dropTypes: Cards.dropTypes,
                       onDrop: { Cards.shared.take($0) },
                       keyDown: { event in
                           let cards = Cards.shared
                           guard let id = cards.hovered else { return false }
                           switch event.keyCode {
                           case 51, 117: // ⌫, ⌦
                               cards.remove(id)
                               return true
                           case 8 where event.modifierFlags.contains(.command): // ⌘C
                               cards.copy(id)
                               return true
                           default:
                               return false
                           }
                       }) {
            DrawerView()
        } options: {
            DrawerOptions()
        }
    }
}

struct DrawerOptions: View {
    @ObservedObject private var cards = Cards.shared

    var body: some View {
        Button("Clear Unpinned Cards") { cards.clearUnpinned() }
            .disabled(!cards.all.contains { !$0.pinned })
        Divider()
    }
}
