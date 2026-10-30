// BrowserModel — one window's browsing: the page showing, back and forward, searches and
// saving. Bookmarks and History are shared by every window, and Inbox hands gopher:// links
// opened elsewhere on the Mac to a new window.

import SwiftUI
import AppKit

/// What a window was opened on. The id keeps two windows on the same address apart, since
/// SwiftUI brings forward an open window rather than opening a second for the same value.
struct Opening: Codable, Hashable {
    var url: String
    var id = UUID()
}

/// A place visited or saved, by name.
struct Visit: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String
}

@MainActor
final class BrowserModel: ObservableObject {
    enum Page {
        case menu([Item])
        case text(String)
        case image(NSImage)
        case failure(String)
    }

    static let defaultHome = "gopher://sdf.org/"

    @Published private(set) var address: Address?
    @Published private(set) var title = ""
    @Published private(set) var page: Page?
    /// Changes with every new page, to start it scrolled to the top.
    @Published private(set) var pageID = 0
    @Published private(set) var loading = false
    @Published private(set) var received = 0
    @Published var hovered: Item?
    /// A passing note in the status bar, such as a file saved.
    @Published var note: String?
    /// A search waiting for its words.
    @Published var searching: Visit?
    @Published var searchWords = ""
    /// Bumped to put the cursor in the address field.
    @Published private(set) var focusAddress = 0

    /// Told of every page shown, to keep the window's restorable value up to date.
    var onVisit: (String) -> Void = { _ in }
    private var back: [Visit] = []
    private var forward: [Visit] = []
    private var raw = Data()
    private var task: Task<Void, Never>?

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var url: String? { address?.url }

    // MARK: Going places

    /// Goes to what's typed in the address field.
    func go(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let web = URL(string: text), ["http", "https"].contains(web.scheme?.lowercased()) {
            NSWorkspace.shared.open(web)
        } else if let address = Address(text) {
            visit(address, title: address.host)
        } else {
            note = "That isn't a gopher address."
        }
    }

    /// Follows a link in a menu.
    func open(_ item: Item) {
        switch item.kind {
        case .info, .error:
            break
        case .menu, .text, .image:
            visit(item.address, title: item.display.trimmingCharacters(in: .whitespaces))
        case .search:
            ask(item.address, title: item.display)
        case .web:
            if let url = item.webURL {
                NSWorkspace.shared.open(url)
            } else {
                visit(item.address, title: item.display)
            }
        case .download, .unsupported:
            download(item.address, name: item.display)
        case .telnet:
            note = "Gopher Browser doesn't do telnet. The session is at \(item.location)."
        }
    }

    private func visit(_ address: Address, title: String) {
        if address.type == "7" && address.query == nil {
            ask(address, title: title)
            return
        }
        if Kind(address.type) == .download {
            download(address, name: title)
            return
        }
        if let current = self.address {
            back.append(Visit(title: self.title, url: current.url))
            forward.removeAll()
        }
        load(address, title: title)
    }

    func goBack() {
        guard let previous = back.popLast(), let address = Address(previous.url) else { return }
        if let current = self.address { forward.append(Visit(title: title, url: current.url)) }
        load(address, title: previous.title)
    }

    func goForward() {
        guard let next = forward.popLast(), let address = Address(next.url) else { return }
        if let current = self.address { back.append(Visit(title: title, url: current.url)) }
        load(address, title: next.title)
    }

    func reload() {
        guard let address else { return }
        load(address, title: title)
    }

    func stop() {
        task?.cancel()
        task = nil
        loading = false
    }

    func goHome() {
        go(UserDefaults.standard.string(forKey: "home") ?? Self.defaultHome)
    }

    func editAddress() { focusAddress += 1 }

    private func load(_ address: Address, title: String) {
        task?.cancel()
        self.address = address
        self.title = title.isEmpty ? address.host : title
        loading = true
        received = 0
        note = nil
        onVisit(address.url)
        task = Task {
            do {
                let data = try await Gopher.fetch(address) { [weak self] count in self?.received = count }
                try Task.checkCancellation()
                show(data, as: address)
                History.shared.add(Visit(title: self.title, url: address.url))
            } catch is CancellationError {
                return
            } catch {
                page = .failure(error.localizedDescription)
                raw = Data()
                pageID += 1
            }
            loading = false
        }
    }

    private func show(_ data: Data, as address: Address) {
        raw = data
        switch Kind(address.type) {
        case .menu, .search:
            page = .menu(Gopher.menu(data))
        case .image:
            if let image = NSImage(data: data) {
                page = .image(image)
            } else {
                page = .failure("The server sent something that isn't a picture.")
            }
        default:
            page = .text(Gopher.document(data))
        }
        pageID += 1
    }

    // MARK: Searching

    private func ask(_ address: Address, title: String) {
        searchWords = ""
        searching = Visit(title: title.trimmingCharacters(in: .whitespaces), url: address.url)
    }

    func search() {
        guard let searching, var address = Address(searching.url) else { return }
        let words = searchWords.trimmingCharacters(in: .whitespaces)
        self.searching = nil
        guard !words.isEmpty else { return }
        address.query = words
        visit(address, title: "\(searching.title): \(words)")
    }

    // MARK: Saving and copying

    /// Asks where to save a file, then fetches it there.
    private func download(_ address: Address, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(for: address, fallback: name)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        note = "Saving \(destination.lastPathComponent)…"
        Task {
            do {
                let data = try await Gopher.fetch(address) { [weak self] count in
                    self?.note = "Saving \(destination.lastPathComponent)… \(Self.size(count))"
                }
                try data.write(to: destination)
                note = "Saved \(destination.lastPathComponent), \(Self.size(data.count))."
            } catch {
                note = "Couldn't save \(destination.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    var canSave: Bool { !raw.isEmpty }

    /// Saves the page as the server sent it.
    func save() {
        guard let address, canSave else { return }
        let panel = NSSavePanel()
        var name = Self.fileName(for: address, fallback: title)
        if Kind(address.type) == .menu, !name.hasSuffix(".txt") { name += ".txt" }
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try raw.write(to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func copyLink(_ url: String? = nil) {
        guard let url = url ?? self.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    private static func fileName(for address: Address, fallback: String) -> String {
        let last = address.selector.split(separator: "/").last.map(String.init) ?? ""
        let name = last.isEmpty ? (fallback.isEmpty ? address.host : fallback) : last
        return name.replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Shared lists

/// Saved places, kept between launches, starting with SDF's gopherspace and Floodgap's.
@MainActor
final class Bookmarks: ObservableObject {
    static let shared = Bookmarks()

    static let starting = [
        Visit(title: "SDF Public Access UNIX System", url: "gopher://sdf.org/"),
        Visit(title: "SDF Gopherspace, by member", url: "gopher://sdf.org/1/maps/"),
        Visit(title: "SDF Phlogosphere", url: "gopher://gopher.club/1/phlogs/"),
        Visit(title: "Floodgap Systems", url: "gopher://gopher.floodgap.com/"),
        Visit(title: "Veronica-2 Search", url: "gopher://gopher.floodgap.com/7/v2/vs"),
    ]

    @Published var all: [Visit] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: "bookmarks") }
    }

    private init() {
        all = UserDefaults.standard.data(forKey: "bookmarks")
            .flatMap { try? JSONDecoder().decode([Visit].self, from: $0) } ?? Self.starting
    }

    func contains(_ url: String?) -> Bool { all.contains { $0.url == url } }

    func toggle(_ url: String?, title: String) {
        guard let url else { return }
        if contains(url) {
            all.removeAll { $0.url == url }
        } else {
            all.append(Visit(title: title, url: url))
        }
    }
}

/// The pages shown lately in any window, newest first.
@MainActor
final class History: ObservableObject {
    static let shared = History()

    @Published private(set) var recent: [Visit] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(recent), forKey: "history") }
    }

    private init() {
        recent = UserDefaults.standard.data(forKey: "history")
            .flatMap { try? JSONDecoder().decode([Visit].self, from: $0) } ?? []
    }

    func add(_ visit: Visit) {
        recent.removeAll { $0.url == visit.url }
        recent.insert(visit, at: 0)
        if recent.count > 100 { recent.removeLast(recent.count - 100) }
    }

    func clear() { recent = [] }
}

/// Opens gopher:// links from other apps, each in a new window. Links that come in before
/// SwiftUI can open windows wait for it.
@MainActor
final class Inbox {
    static let shared = Inbox()

    /// SwiftUI's action for opening a window. The menu commands hand it over, as SwiftUI
    /// sets them up at launch, before any window.
    var openWindow: OpenWindowAction?
    private var pending: [String] = []
    private var launched = false

    func open(_ url: String) {
        pending.append(url)
        if launched { flush() }
    }

    /// Waits a moment after launch, so the empty window SwiftUI opens by itself can take
    /// the first link rather than showing the home page beside a second window.
    func finishLaunching() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            launched = true
            flush()
        }
    }

    func takeFirst() -> String? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    private func flush() {
        guard let openWindow else { return }
        let urls = pending
        pending = []
        urls.forEach { openWindow(value: Opening(url: $0)) }
    }
}
