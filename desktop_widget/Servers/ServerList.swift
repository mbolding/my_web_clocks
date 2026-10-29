// ServerList — the saved servers, kept as a list of URLs under "servers" in this app's
// preferences, and the alert that adds one. Opening a server hands its URL to macOS, so
// vnc:// opens Screen Sharing, ssh:// opens Terminal, and smb:// or afp:// mounts the
// share in Finder.

import AppKit

struct Server: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }

    /// A URL with a scheme and a host, such as vnc://hostname or ssh://user@hostname.
    init?(string: String) {
        guard string.contains("://"), let url = URL(string: string),
              url.scheme != nil, !(url.host() ?? "").isEmpty else { return nil }
        self.url = url
    }

    /// The host, or user@host, with the port if it names one.
    var label: String {
        var host = url.host(percentEncoded: false) ?? id
        if let port = url.port { host += ":\(port)" }
        if let user = url.user(percentEncoded: false) { return "\(user)@\(host)" }
        return host
    }

    var symbol: String {
        switch url.scheme?.lowercased() {
        case "vnc": "display"
        case "ssh": "terminal"
        case "smb", "afp", "nfs", "cifs": "externaldrive.connected.to.line.below"
        default: "globe"
        }
    }
}

@MainActor
final class ServerList: NSObject, ObservableObject {
    static let shared = ServerList()
    private static let key = "servers"

    @Published private(set) var servers: [Server] = []

    private override init() {
        super.init()
        load()
        // Also hears changes written from outside the app, as by `defaults write`.
        UserDefaults.standard.addObserver(self, forKeyPath: Self.key, context: nil)
    }

    override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.load() } }
    }

    private func load() {
        let saved = (UserDefaults.standard.stringArray(forKey: Self.key) ?? []).compactMap(Server.init(string:))
        if saved != servers { servers = saved }
    }

    private func save(_ servers: [Server]) {
        self.servers = servers
        UserDefaults.standard.set(servers.map(\.id), forKey: Self.key)
    }

    func open(_ server: Server) {
        NSWorkspace.shared.open(server.url)
    }

    func remove(_ server: Server) {
        save(servers.filter { $0 != server })
    }

    /// Asks for an address and adds it to the end of the list. Waits for the menu that
    /// chose it to close, then brings the app forward so the alert's field takes typing.
    func promptToAdd() {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.runAddAlert() } }
    }

    private func runAddAlert(text: String = "", problem: String? = nil) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Add Server"
        alert.informativeText = problem ?? "Enter an address such as vnc://hostname to open Screen Sharing, or ssh://user@hostname to open Terminal."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = text
        field.placeholderString = "vnc://hostname"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let address = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        guard let server = Server(string: address) else {
            runAddAlert(text: address, problem: "“\(address)” isn't a server address. Start it with the kind of connection, as in vnc://hostname or ssh://user@hostname.")
            return
        }
        if !servers.contains(server) { save(servers + [server]) }
    }
}
