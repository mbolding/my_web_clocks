// BrowserModel — one window's browsing: the page showing, back and forward, input for
// searches and saving. Bookmarks and History are shared by every window, and Inbox hands
// gopher://, gemini://, spartan:// and finger:// links opened elsewhere on the Mac to a new window.

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

/// A page in any of the protocols.
enum Location: Hashable {
    case gopher(Address)
    case gemini(URL)
    case spartan(URL)
    case finger(URL)

    /// The schemes whose pages open here rather than in another app.
    static let schemes: Set = ["gopher", "gemini", "spartan", "finger"]

    /// Reads a gemini://, spartan:// or finger:// URL, or a gopher address with or without its scheme.
    init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = text.range(of: "://").map { text[..<$0.lowerBound].lowercased() }
        if let scheme, ["gemini", "spartan", "finger"].contains(scheme) {
            let escaped = text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(["#", "%"])) ?? text
            guard var url = URL(string: text) ?? URL(string: escaped), let host = url.host, !host.isEmpty else { return nil }
            // A bare server is asked for its root, as servers expect. Finger has no root: a
            // bare server lists who's on.
            if scheme != "finger", url.path.isEmpty, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                parts.path = "/"
                url = parts.url ?? url
            }
            switch scheme {
            case "gemini": self = .gemini(url)
            case "spartan": self = .spartan(url)
            default: self = .finger(url)
            }
        } else if let address = Address(text) {
            self = .gopher(address)
        } else {
            return nil
        }
    }

    var url: String {
        switch self {
        case .gopher(let address): address.url
        case .gemini(let url), .spartan(let url), .finger(let url): url.absoluteString
        }
    }

    var host: String {
        switch self {
        case .gopher(let address): address.host
        case .gemini(let url), .spartan(let url), .finger(let url): url.host ?? ""
        }
    }

    /// What to call the page until it says otherwise: its server, or for finger, who's asked about.
    var name: String {
        if case .finger(let url) = self, case let user = Finger.user(url), !user.isEmpty { return "\(user)@\(host)" }
        return host
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    enum Page {
        case menu([Item])
        case gemtext([GemLine])
        case text(String)
        case image(NSImage)
        /// A search or other question, waiting for words to send.
        case input(prompt: String, sensitive: Bool)
        /// Something to save rather than show.
        case file(type: String, size: Int)
        case failure(String)
        case certificateChanged(Gemini.CertificateChanged)
    }

    static let defaultHome = "gopher://sdf.org/"

    @Published private(set) var location: Location?
    @Published private(set) var title = ""
    @Published private(set) var page: Page?
    /// Changes with every new page, to start it scrolled to the top.
    @Published private(set) var pageID = 0
    @Published private(set) var loading = false
    @Published private(set) var received = 0
    /// Where the link under the pointer goes, for the status bar.
    @Published var hovered: String?
    /// A passing note in the status bar, such as a file saved.
    @Published var note: String?
    @Published var inputWords = ""
    /// Bumped to put the cursor in the address field.
    @Published private(set) var focusAddress = 0

    /// Told of every page shown, to keep the window's restorable value up to date.
    var onVisit: (String) -> Void = { _ in }
    private var back: [Visit] = []
    private var forward: [Visit] = []
    private var raw = Data()
    private var task: Task<Void, Never>?
    /// Spartan addresses reached by a "=:" link, which ask for words before they're fetched.
    private var prompts: Set<URL> = []

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var url: String? { location?.url }

    // MARK: Going places

    /// Goes to what's typed in the address field.
    func go(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        follow(text, title: "")
    }

    /// Goes to a gopher, Gemini, Spartan or finger address here, opens telnet in Terminal, and
    /// hands anything else (the web, mail) to the app that opens it. `prompt` is for a Spartan
    /// "=:" link, which asks for words to send first.
    func follow(_ text: String, title: String, prompt: Bool = false) {
        if let location = Location(text) {
            if prompt, case .spartan(let url) = location { prompts.insert(url) }
            visit(location, title: title.isEmpty ? location.name : title)
        } else if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["telnet", "tn3270"].contains(scheme) {
            telnet(host: url.host ?? "", port: url.port ?? 23, user: url.user(percentEncoded: false) ?? "")
        } else if let url = URL(string: text), let scheme = url.scheme, !Location.schemes.contains(scheme.lowercased()) {
            NSWorkspace.shared.open(url)
        } else {
            note = "That isn't an address Gopher Browser can open."
        }
    }

    /// Follows a link in a gopher menu.
    func open(_ item: Item) {
        let title = item.display.trimmingCharacters(in: .whitespaces)
        switch item.kind {
        case .info, .error:
            break
        case .menu, .text, .image, .search:
            visit(.gopher(item.address), title: title)
        case .web:
            if let url = item.webURL {
                follow(url.absoluteString, title: title)
            } else {
                visit(.gopher(item.address), title: title)
            }
        case .download, .unsupported:
            download(item.address, name: title)
        case .telnet:
            telnet(host: item.host, port: item.port, user: item.selector)
        }
    }

    private func telnet(host: String, port: Int, user: String) {
        do {
            try Telnet.open(host: host, port: port, user: user)
            note = "Opened a session with \(host) in Terminal."
        } catch {
            note = error.localizedDescription
        }
    }

    private func visit(_ location: Location, title: String) {
        if case .gopher(let address) = location, Kind(address.type) == .download {
            download(address, name: title)
            return
        }
        if let current = self.location {
            back.append(Visit(title: self.title, url: current.url))
            forward.removeAll()
        }
        load(location, title: title)
    }

    func goBack() {
        guard let previous = back.popLast(), let location = Location(previous.url) else { return }
        if let current = self.location { forward.append(Visit(title: title, url: current.url)) }
        load(location, title: previous.title)
    }

    func goForward() {
        guard let next = forward.popLast(), let location = Location(next.url) else { return }
        if let current = self.location { back.append(Visit(title: title, url: current.url)) }
        load(location, title: next.title)
    }

    func reload() {
        guard let location else { return }
        load(location, title: title)
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

    private func load(_ location: Location, title: String) {
        task?.cancel()
        arrive(at: location, title: title)
        loading = true
        received = 0
        note = nil
        task = Task {
            do {
                switch location {
                case .gopher(let address):
                    try await loadGopher(address)
                case .gemini(let url):
                    try await loadGemini(url)
                case .spartan(let url):
                    try await loadSpartan(url)
                case .finger(let url):
                    try await loadFinger(url)
                }
            } catch is CancellationError {
                return
            } catch let changed as Gemini.CertificateChanged {
                show(.certificateChanged(changed))
            } catch {
                show(.failure(error.localizedDescription))
            }
            loading = false
        }
    }

    private func arrive(at location: Location, title: String) {
        self.location = location
        self.title = title.isEmpty ? location.name : title
        onVisit(location.url)
    }

    private func show(_ page: Page, raw: Data = Data()) {
        self.page = page
        self.raw = raw
        pageID += 1
        if let location {
            switch page {
            case .failure, .certificateChanged, .input: break
            default: History.shared.add(Visit(title: title, url: location.url))
            }
        }
    }

    private func loadGopher(_ address: Address) async throws {
        // A search with no words yet asks for them before going to the server.
        if address.type == "7" && address.query == nil {
            inputWords = ""
            show(.input(prompt: "Search \(title)", sensitive: false))
            return
        }
        let data = try await Gopher.fetch(address) { [weak self] count in self?.received = count }
        try Task.checkCancellation()
        switch Kind(address.type) {
        case .menu, .search:
            show(.menu(Gopher.menu(data)), raw: data)
        case .image:
            if let image = NSImage(data: data) {
                show(.image(image), raw: data)
            } else {
                show(.failure("The server sent something that isn't a picture."))
            }
        default:
            show(.text(Gopher.document(data)), raw: data)
        }
    }

    private func loadGemini(_ start: URL) async throws {
        var url = start
        for _ in 0..<5 {
            let response = try await Gemini.fetch(url) { [weak self] count in self?.received = count }
            try Task.checkCancellation()
            switch response.status / 10 {
            case 1:
                inputWords = ""
                show(.input(prompt: response.meta.isEmpty ? "The page asks for some words." : response.meta,
                            sensitive: response.status == 11))
            case 2:
                showDocument(response, from: url)
            case 3:
                guard let next = Gemini.resolve(response.meta, against: url) else {
                    show(.failure("The server sent a redirect that doesn't say where to."))
                    return
                }
                if next.scheme?.lowercased() == "gemini" {
                    url = next
                    arrive(at: .gemini(next), title: title)
                    continue
                }
                show(.failure("The server sent this on to \(next.absoluteString)."))
            case 4, 5:
                let reason = response.meta.isEmpty ? Gemini.describe(response.status) : response.meta
                show(.failure("\(reason) (\(response.status))"))
            case 6:
                show(.failure("The page asks for a client certificate, which Gopher Browser doesn't have."))
            default:
                show(.failure("The server sent a status Gemini doesn't have (\(response.status))."))
            }
            return
        }
        show(.failure("The server redirected too many times."))
    }

    /// Spartan's answers are like Gemini's: a type, then the page, gemtext unless it says otherwise.
    private func loadSpartan(_ start: URL) async throws {
        if prompts.contains(start) && start.query == nil {
            inputWords = ""
            show(.input(prompt: title, sensitive: false))
            return
        }
        var url = start
        for _ in 0..<5 {
            let reply = try await Spartan.fetch(url) { [weak self] count in self?.received = count }
            try Task.checkCancellation()
            switch reply.status {
            case 2:
                showDocument(reply, from: url)
            case 3:
                // Redirects stay on the same server; the spec gives them only a path.
                guard let next = Gemini.resolve(reply.meta, against: url),
                      next.scheme?.lowercased() == "spartan", next.host == url.host, next.port == url.port else {
                    show(.failure("The server sent a redirect that doesn't stay on the server."))
                    return
                }
                url = next
                arrive(at: .spartan(next), title: title)
                continue
            default:
                let reason = reply.meta.isEmpty
                    ? (reply.status == 4 ? "The server couldn't find or wouldn't send that." : "The server failed.")
                    : reply.meta
                show(.failure("\(reason) (\(reply.status))"))
            }
            return
        }
        show(.failure("The server redirected too many times."))
    }

    private func loadFinger(_ url: URL) async throws {
        let data = try await Finger.fetch(url) { [weak self] count in self?.received = count }
        try Task.checkCancellation()
        let text = Gopher.text(data).replacingOccurrences(of: "\r\n", with: "\n")
        show(.text(text.isEmpty ? "The server had nothing to say about \(title)." : text), raw: data)
    }

    private func showDocument(_ response: Reply, from url: URL) {
        let mime = response.meta.split(separator: ";").first.map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        } ?? "text/gemini"
        let type = mime.isEmpty ? "text/gemini" : mime
        if type == "text/gemini" {
            let lines = Gemini.gemtext(Gopher.text(response.body), base: url)
            if let heading = Gemini.title(lines) { title = heading }
            show(.gemtext(lines), raw: response.body)
        } else if type.hasPrefix("text/") || (type == "application/octet-stream" && Self.isPlainText(response.body)) {
            // Servers that don't know a type call it octet-stream, as Spartan's echo does; if
            // it's plain text, it's shown.
            show(.text(Gopher.text(response.body)), raw: response.body)
        } else if type.hasPrefix("image/"), let image = NSImage(data: response.body) {
            show(.image(image), raw: response.body)
        } else {
            show(.file(type: type, size: response.body.count), raw: response.body)
        }
    }

    // MARK: Input

    /// Sends the words typed on an input page: after a tab to a gopher server, or as the
    /// URL's query to a Gemini or Spartan one, which Spartan sends as the request's data.
    func submit() {
        let words = inputWords.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty, let location else { return }
        switch location {
        case .gopher(var address):
            address.query = words
            visit(.gopher(address), title: "\(title): \(words)")
        case .gemini(let url):
            guard let next = Self.adding(words, to: url) else { return }
            visit(.gemini(next), title: title)
        case .spartan(let url):
            guard let next = Self.adding(words, to: url) else { return }
            visit(.spartan(next), title: title)
        case .finger:
            return
        }
        inputWords = ""
    }

    private static func adding(_ words: String, to url: URL) -> URL? {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.percentEncodedQuery = words.addingPercentEncoding(withAllowedCharacters: queryAllowed)
        return parts?.url
    }

    private static let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#"))

    /// Trusts a Gemini server's new certificate, then tries the page again.
    func trust(_ changed: Gemini.CertificateChanged) {
        KnownServers.remember(changed.fingerprint, for: changed.server)
        reload()
    }

    // MARK: Saving and copying

    /// Asks where to save a gopher file, then fetches it there.
    private func download(_ address: Address, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(for: address.selector, fallback: name.isEmpty ? address.host : name)
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
        guard let location, canSave else { return }
        let panel = NSSavePanel()
        var name: String
        switch location {
        case .gopher(let address):
            name = Self.fileName(for: address.selector, fallback: title)
            if Kind(address.type) == .menu, !name.hasSuffix(".txt") { name += ".txt" }
        case .gemini(let url), .spartan(let url):
            name = Self.fileName(for: url.path, fallback: title)
            if case .gemtext = page, !name.hasSuffix(".gmi") { name += ".gmi" }
        case .finger:
            name = location.name + ".txt"
        }
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

    private static func fileName(for path: String, fallback: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? ""
        let name = last.isEmpty ? fallback : (last.removingPercentEncoding ?? last)
        return name.replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
    }

    /// Short UTF-8 with no control characters but tabs and line breaks.
    private static func isPlainText(_ data: Data) -> Bool {
        guard data.count < 1 << 20, let text = String(data: data, encoding: .utf8) else { return false }
        return !text.unicodeScalars.contains { $0.value < 32 && ![9, 10, 13].contains($0.value) }
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Shared lists

/// Saved places, kept between launches, starting with SDF's gopherspace and Floodgap's, a few
/// Gemini capsules, Spartan's home and SDF's finger server.
@MainActor
final class Bookmarks: ObservableObject {
    static let shared = Bookmarks()

    static let starting = [
        Visit(title: "SDF Public Access UNIX System", url: "gopher://sdf.org/"),
        Visit(title: "SDF Gopherspace, by member", url: "gopher://sdf.org/1/maps/"),
        Visit(title: "SDF Phlogosphere", url: "gopher://gopher.club/1/phlogs/"),
        Visit(title: "Floodgap Systems", url: "gopher://gopher.floodgap.com/"),
        Visit(title: "Veronica-2 Search", url: "gopher://gopher.floodgap.com/7/v2/vs"),
        Visit(title: "SDF Gemini", url: "gemini://sdf.org/"),
        Visit(title: "Project Gemini", url: "gemini://geminiprotocol.net/"),
        Visit(title: "Kennedy, a Gemini search", url: "gemini://kennedy.gemi.dev/search"),
        Visit(title: "Spartan, and the servers that speak it", url: "spartan://mozz.us/"),
        Visit(title: "SDF, by finger", url: "finger://sdf.org"),
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

/// Opens gopher://, gemini://, spartan:// and finger:// links from other apps, each in a new window. Links that come in before
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
