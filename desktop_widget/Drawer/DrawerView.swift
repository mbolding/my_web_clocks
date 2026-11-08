// DrawerView — Text Drawer's panel: the dropped and pasted text as cards, newest first, each with its
// first few lines, when it came and from which app. Click a card to copy it, drag it out
// into any app, hover and press ⌫ to delete it, or pin it to keep it past the limit.

import SwiftUI

struct DrawerView: View {
    @ObservedObject private var cards = Cards.shared
    @Environment(\.accent) private var accent
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Text Drawer").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(cards.all.isEmpty ? "" : "\(cards.all.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Button { cards.paste() } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Paste what you've copied as a card (⌘V)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 8)
            Divider()
            if cards.all.isEmpty {
                Text("Drop text here from any app, or onto the tab at the edge of the screen, or paste it in with ⌘V.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(cards.all) { CardView(card: $0) }
                    }
                    .padding(10)
                }
            }
        }
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(accent, lineWidth: 2).padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: Cards.dropTypes, isTargeted: $targeted) { cards.take($0) }
    }
}

private struct CardView: View {
    var card: Card
    @ObservedObject private var cards = Cards.shared
    @Environment(\.accent) private var accent

    private var hovered: Bool { cards.hovered == card.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(card.text)
                .font(.system(size: 12))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(caption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(cards.copied == card.id ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovered ? 0.08 : 0.045)))
        .overlay(alignment: .topTrailing) {
            if hovered || card.pinned {
                HStack(spacing: 2) {
                    button(card.pinned ? "pin.fill" : "pin", tint: card.pinned ? accent : .secondary,
                           help: card.pinned ? "Unpin" : "Pin, to keep it past the last \(Cards.limit)") {
                        cards.togglePin(card.id)
                    }
                    if hovered {
                        button("xmark", tint: .secondary, help: "Delete (⌫)") { cards.remove(card.id) }
                    }
                }
                .padding(4)
                .background(.regularMaterial, in: Capsule())
                .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { cards.hovered = card.id } else if hovered { cards.hovered = nil }
        }
        .onTapGesture { cards.copy(card.id) }
        .onDrag { NSItemProvider(object: card.text as NSString) }
        .help("Click to copy, or drag it out")
    }

    private var caption: String {
        if cards.copied == card.id { return "Copied" }
        let when = card.date.timeIntervalSinceNow > -45 ? "Just now"
            : card.date.formatted(.relative(presentation: .named)).capitalizedFirst
        return [when, card.app].compactMap { $0 }.joined(separator: " · ")
    }

    private func button(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
