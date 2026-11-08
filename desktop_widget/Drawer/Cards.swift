// Cards — what's been dropped on Text Drawer: the text, when, and from which app, newest
// first. Twenty are kept, plus any you pin; the list is saved in Application Support and
// comes back after a restart. Only drops are taken, never the clipboard, so a password
// copied elsewhere never lands here.

import AppKit
import UniformTypeIdentifiers

struct Card: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
    var app: String?
    var pinned = false
}

@MainActor
final class Cards: ObservableObject {
    static let shared = Cards()
    static let limit = 20
    static let dropTypes: [UTType] = [.plainText, .rtf, .url]

    @Published private(set) var all: [Card] = []
    /// The card under the pointer, for ⌫ and ⌘C.
    @Published var hovered: Card.ID?
    /// The card just copied, which says so for a moment.
    @Published private(set) var copied: Card.ID?

    private let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.mbolding.textdrawer/Cards.json")

    private init() {
        if let data = try? Data(contentsOf: file), let cards = try? JSONDecoder().decode([Card].self, from: data) {
            all = cards
        }
    }

    func add(_ raw: String, from app: String?) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // The same text again moves up to the top, keeping its pin.
        var card = Card(text: text, date: .now, app: app)
        if let i = all.firstIndex(where: { $0.text == text }) {
            card.pinned = all[i].pinned
            card.app = app ?? all[i].app
            all.remove(at: i)
        }
        all.insert(card, at: 0)
        // Past the limit, the oldest unpinned cards go.
        var unpinned = 0
        all = all.filter { c in
            if c.pinned { return true }
            unpinned += 1
            return unpinned <= Self.limit
        }
        save()
    }

    func remove(_ id: Card.ID) {
        all.removeAll { $0.id == id }
        if hovered == id { hovered = nil }
        save()
    }

    func togglePin(_ id: Card.ID) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].pinned.toggle()
        save()
    }

    func copy(_ id: Card.ID) {
        guard let card = all.first(where: { $0.id == id }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.text, forType: .string)
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copied == id { self?.copied = nil }
        }
    }

    func clearUnpinned() {
        all.removeAll { !$0.pinned }
        save()
    }

    /// Takes a drop: plain text as it is, rich text as its plain text, a link as its
    /// address and a file as its path. The app is whichever was in front, which during a
    /// drag is the one it came from.
    func take(_ providers: [NSItemProvider]) -> Bool {
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front?.localizedName
        var took = false
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self), !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                took = true
                _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                    guard let text = text as? String else { return }
                    Task { @MainActor in Cards.shared.add(text, from: app) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier) {
                took = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.rtf.identifier) { data, _ in
                    guard let data, let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string else { return }
                    Task { @MainActor in Cards.shared.add(text, from: app) }
                }
            } else if provider.canLoadObject(ofClass: NSURL.self) {
                took = true
                _ = provider.loadObject(ofClass: NSURL.self) { url, _ in
                    guard let url = url as? URL else { return }
                    let text = url.isFileURL ? url.path : url.absoluteString
                    Task { @MainActor in Cards.shared.add(text, from: app) }
                }
            }
        }
        return took
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: file, options: .atomic)
    }
}
