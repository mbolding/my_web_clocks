// Session — one network's conversation: registering with a nick, logging in with SASL,
// joining the saved channels, and turning what the server sends into lines in buffers: one
// for the server itself, one for each channel, one for each person talking privately. A
// dropped connection is tried again, waiting longer each time, until it's disconnected on purpose.

import SwiftUI
import Security

struct Network: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var port = 6697
    /// TLS, as on port 6697, rather than plain text on 6667.
    var secure = true
    /// Empty to use the nick in Settings → Identity.
    var nick = ""
    /// The account for SASL, for a registered nick; empty to connect as a guest.
    var account = ""
    /// Joined on connecting, and kept up to date as channels are joined and left.
    var channels: [String] = []
    /// Connected at launch, because it was connected when the app quit.
    var autoConnect = false

    /// Fixed ids, so settings stay with the same networks every launch.
    static let starting = [
        Network(id: UUID(uuidString: "2B9C7E10-5A4D-4E3B-8F21-7C6D5E4F3A01")!,
                name: "SDF", host: "irc.sdf.org", channels: ["#sdf"]),
        Network(id: UUID(uuidString: "2B9C7E10-5A4D-4E3B-8F21-7C6D5E4F3A02")!,
                name: "tilde.chat", host: "irc.tilde.chat", channels: ["#meta"]),
        Network(id: UUID(uuidString: "2B9C7E10-5A4D-4E3B-8F21-7C6D5E4F3A03")!,
                name: "Libera.Chat", host: "irc.libera.chat", channels: ["#libera"]),
    ]
}

enum Keychain {
    private static let service = "com.mbolding.relaychat"

    static func password(for network: Network) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: network.id.uuidString, kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setPassword(_ password: String, for network: Network) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: network.id.uuidString]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrLabel as String] = "Relay Chat: \(network.host)"
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// A line in a buffer.
struct Line: Identifiable, Hashable {
    enum Kind: Hashable { case message, action, notice, event, info, error }

    var id: Int
    var time: Date
    var kind: Kind
    var nick = ""
    var text: String
    /// Someone said your nick.
    var mention = false
    /// You sent it.
    var own = false
}

struct BufferRef: Hashable, Codable {
    var network: UUID
    /// Lowercased; empty for the server's own buffer.
    var name: String
}

struct Buffer: Identifiable {
    enum Kind { case server, channel, query }

    var name: String
    var kind: Kind
    var lines: [Line] = []
    var topic = ""
    /// Nick to its mode prefix ("@", "+" or ""), for a channel.
    var users: [String: String] = [:]
    var unread = 0
    var mentions = 0
    /// In the channel now, rather than having left or been disconnected.
    var joined = false

    var id: String { name.lowercased() }
}

/// A channel from LIST, for the Join Channel sheet.
struct Listing: Identifiable, Hashable {
    var name: String
    var users: Int
    var topic: String
    var id: String { name }
}

@MainActor
final class Session: ObservableObject, Identifiable {
    enum State { case disconnected, connecting, registering, connected }

    @Published var network: Network
    @Published private(set) var state = State.disconnected
    @Published private(set) var nick = ""
    @Published private(set) var buffers: [Buffer]
    @Published private(set) var listing: [Listing]?
    @Published private(set) var listingDone = false

    /// The network's id, which never changes, so it can be read from anywhere.
    nonisolated let id: UUID
    /// Told when a line should raise a notification: a mention or a private message.
    var onAlert: (Session, Buffer, Line) -> Void = { _, _, _ in }
    /// Whether a buffer is on screen, so its lines don't count as unread.
    var isShowing: (BufferRef) -> Bool = { _ in false }
    /// Told when the network's settings change here, as when a channel is joined or left.
    var onChange: (Network) -> Void = { _ in }

    private var connection: IRCConnection?
    private var wanted = false
    private var retries = 0
    private var nextLine = 0
    private var offered: Set<String> = []
    private var capsDone = false
    private var prefixes: [(mode: Character, symbol: Character)] = [("o", "@"), ("v", "+")]
    private var channelTypes: Set<Character> = ["#", "&"]
    private var pendingNames: [String: [String: String]] = [:]
    private var pendingListing: [Listing] = []
    /// A channel the person asked to join here, to show once it's joined.
    var showOnJoin: String?
    var onShow: (BufferRef) -> Void = { _ in }

    init(network: Network) {
        id = network.id
        self.network = network
        buffers = [Buffer(name: network.name, kind: .server)]
    }

    // MARK: Connecting

    func connect(nick wantedNick: String, realName: String) {
        guard state == .disconnected else { return }
        let nick = (network.nick.isEmpty ? wantedNick : network.nick).trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty, !nick.contains(" ") else {
            add(Line(id: 0, time: Date(), kind: .error, text: "Choose a nick in Settings → Identity before connecting."), to: "")
            return
        }
        self.nick = nick
        wanted = true
        network.autoConnect = true
        onChange(network)
        open(realName: realName)
    }

    private func open(realName: String) {
        state = .connecting
        capsDone = false
        offered = []
        add(Line(id: 0, time: Date(), kind: .info, text: "Connecting to \(network.host), port \(network.port)\(network.secure ? " over TLS" : "")…"), to: "")
        let connection = IRCConnection { [weak self] event in self?.handle(event, realName: realName) }
        self.connection = connection
        connection.start(host: network.host, port: network.port, secure: network.secure)
    }

    func disconnect(_ message: String = "Relay Chat") {
        wanted = false
        network.autoConnect = false
        onChange(network)
        guard state != .disconnected else { return }
        if state == .connected { send(IRCMessage.line("QUIT", message)) }
        let connection = connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { connection?.stop() }
        dropped(reason: nil)
    }

    /// Says goodbye on quitting, leaving autoConnect as it is so the next launch reconnects.
    func quit() {
        guard state == .connected else { return }
        wanted = false
        send(IRCMessage.line("QUIT", "Relay Chat"))
    }

    private func handle(_ event: IRCConnection.Event, realName: String) {
        switch event {
        case .ready:
            state = .registering
            send("CAP LS 302")
            send(IRCMessage.line("NICK", nick))
            send(IRCMessage.line("USER", nick, "0", "*", realName.isEmpty ? nick : realName))
        case .lines(let lines):
            for line in lines {
                if let message = IRCMessage(line) { receive(message) }
            }
        case .closed(let reason):
            guard state != .disconnected else { return }
            dropped(reason: reason)
            if wanted {
                retries += 1
                let delay = [5.0, 10, 30, 60, 120][min(retries - 1, 4)]
                add(Line(id: 0, time: Date(), kind: .info, text: "Trying again in \(Int(delay)) seconds."), to: "")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.wanted, self.state == .disconnected else { return }
                    self.open(realName: realName)
                }
            }
        }
    }

    private func dropped(reason: String?) {
        connection = nil
        state = .disconnected
        for i in buffers.indices where buffers[i].kind == .channel {
            buffers[i].joined = false
            buffers[i].users = [:]
        }
        add(Line(id: 0, time: Date(), kind: reason == nil ? .info : .error, text: reason ?? "Disconnected."), to: "")
    }

    func send(_ line: String) {
        connection?.send(line)
    }

    // MARK: What the server says

    private func receive(_ m: IRCMessage) {
        let p = m.params
        let from = m.nick ?? ""
        switch m.command {
        case "PING":
            send(IRCMessage.line("PONG", p.first ?? ""))
        case "CAP":
            capability(p)
        case "AUTHENTICATE":
            if p.first == "+" { authenticate() }
        case "001":
            state = .connected
            retries = 0
            if let me = p.first { nick = me }
            server(p.last ?? "Connected.", m)
            if !network.channels.isEmpty { send("JOIN \(network.channels.joined(separator: ","))") }
        case "005":
            for token in p.dropFirst().dropLast() { support(token) }
        case "433", "432":
            if state == .registering {
                nick += "_"
                send(IRCMessage.line("NICK", nick))
            } else {
                active(.error, p.dropFirst().joined(separator: " "))
            }
        case "900":
            server(p.last ?? "Logged in.", m)
        case "903":
            server("Logged in with SASL.", m)
            endCaps()
        case "902", "904", "905", "906", "907", "908":
            if m.command != "908" {
                add(Line(id: 0, time: m.time, kind: .error, text: "SASL login failed: \(p.last ?? m.command). Check the account and password in Settings."), to: "")
                endCaps()
            }
        case "332":
            if p.count >= 3 { update(p[1]) { $0.topic = p[2] } }
        case "353":
            if p.count >= 4 {
                var names = pendingNames[p[2].lowercased()] ?? [:]
                for entry in p[3].split(separator: " ") {
                    let symbols = entry.prefix { c in prefixes.contains { $0.symbol == c } }
                    names[String(entry.dropFirst(symbols.count))] = symbols.first.map(String.init) ?? ""
                }
                pendingNames[p[2].lowercased()] = names
            }
        case "366":
            if p.count >= 2, let names = pendingNames.removeValue(forKey: p[1].lowercased()) {
                update(p[1]) { $0.users = names }
            }
        case "321":
            pendingListing = []
        case "322":
            if p.count >= 3 { pendingListing.append(Listing(name: p[1], users: Int(p[2]) ?? 0, topic: p.count > 3 ? Self.plain(p[3]) : "")) }
            if pendingListing.count % 2000 == 0 { listing = pendingListing }
        case "323":
            listing = pendingListing.sorted { $0.users > $1.users }
            listingDone = true
        case "375", "372", "376", "422", "002", "003", "004", "250", "251", "252", "253", "254", "255", "265", "266", "396":
            server(p.dropFirst().joined(separator: " "), m)
        case "JOIN":
            guard let channel = p.first else { return }
            if from.caseInsensitiveCompare(nick) == .orderedSame {
                open(channel, kind: .channel)
                update(channel) { $0.joined = true; $0.users = [:] }
                if !network.channels.contains(where: { $0.caseInsensitiveCompare(channel) == .orderedSame }) {
                    network.channels.append(channel)
                    onChange(network)
                }
                if showOnJoin?.caseInsensitiveCompare(channel) == .orderedSame {
                    showOnJoin = nil
                    onShow(BufferRef(network: id, name: channel.lowercased()))
                }
            } else {
                update(channel) { $0.users[from] = "" }
                event(channel, "\(from) joined", m)
            }
        case "PART":
            guard let channel = p.first else { return }
            let reason = p.count > 1 && !p[1].isEmpty ? " (\(Self.plain(p[1])))" : ""
            if from.caseInsensitiveCompare(nick) == .orderedSame {
                update(channel) { $0.joined = false; $0.users = [:] }
                event(channel, "You left \(channel)", m)
            } else {
                update(channel) { $0.users[from] = nil }
                event(channel, "\(from) left\(reason)", m)
            }
        case "KICK":
            guard p.count >= 2 else { return }
            let reason = p.count > 2 ? " (\(Self.plain(p[2])))" : ""
            if p[1].caseInsensitiveCompare(nick) == .orderedSame {
                update(p[0]) { $0.joined = false; $0.users = [:] }
                add(Line(id: 0, time: m.time, kind: .error, text: "\(from) removed you from \(p[0])\(reason)"), to: p[0])
            } else {
                update(p[0]) { $0.users[p[1]] = nil }
                event(p[0], "\(from) removed \(p[1])\(reason)", m)
            }
        case "QUIT":
            let reason = p.first.map { " (\(Self.plain($0)))" } ?? ""
            for buffer in buffers where buffer.users[from] != nil || (buffer.kind == .query && buffer.name.caseInsensitiveCompare(from) == .orderedSame) {
                update(buffer.name) { $0.users[from] = nil }
                event(buffer.name, "\(from) quit\(reason)", m)
            }
        case "NICK":
            guard let new = p.first else { return }
            let me = from.caseInsensitiveCompare(nick) == .orderedSame
            if me { nick = new }
            for buffer in buffers where buffer.users[from] != nil || (buffer.kind == .query && buffer.name.caseInsensitiveCompare(from) == .orderedSame) {
                update(buffer.name) { buffer in
                    if let mode = buffer.users.removeValue(forKey: from) { buffer.users[new] = mode }
                    if buffer.kind == .query { buffer.name = new }
                }
                event(buffer.kind == .query ? new : buffer.name, me ? "You're now \(new)" : "\(from) is now \(new)", m)
            }
            if me { server("You're now \(new)", m) }
        case "TOPIC":
            guard p.count >= 2 else { return }
            update(p[0]) { $0.topic = p[1] }
            event(p[0], "\(from) set the topic: \(Self.plain(p[1]))", m)
        case "MODE":
            guard p.count >= 2, isChannel(p[0]) else { return }
            event(p[0], "\(from) set mode \(p.dropFirst().joined(separator: " "))", m)
            if p.count > 2 { send("NAMES \(p[0])") }       // modes on people change their prefixes
        case "INVITE":
            if p.count >= 2 { active(.info, "\(from) invited you to \(p[1]). Type /join \(p[1]) to go.") }
        case "PRIVMSG", "NOTICE":
            message(m)
        case "ERROR":
            server(p.first ?? "The server ended the connection.", m, kind: .error)
        default:
            guard let code = Int(m.command) else { return }
            let text = p.dropFirst().joined(separator: " ")
            if code >= 400 { active(.error, text) } else { active(.info, text) }
        }
    }

    private func message(_ m: IRCMessage) {
        guard m.params.count >= 2 else { return }
        let target = m.params[0], from = m.nick ?? m.prefix ?? ""
        var text = m.params[1]
        let notice = m.command == "NOTICE"
        var kind: Line.Kind = notice ? .notice : .message

        // CTCP: \u{1}ACTION waves\u{1} is /me; a VERSION query gets an answer; the rest are ignored.
        if text.hasPrefix("\u{1}") {
            let body = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{1}"))
            if body.uppercased().hasPrefix("ACTION") {
                text = String(body.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                kind = .action
            } else {
                if !notice && body.uppercased() == "VERSION" {
                    send(IRCMessage.line("NOTICE", from, "\u{1}VERSION Relay Chat, a small Mac IRC client\u{1}"))
                }
                return
            }
        }

        let toMe = target.caseInsensitiveCompare(nick) == .orderedSame
        let fromServer = m.prefix.map { !$0.contains("!") } ?? true
        let destination: String
        if isChannel(target) {
            destination = target
        } else if notice && (fromServer || state != .connected || buffer(from) == nil) {
            // Server notices, and notices from services, go to the server's buffer.
            destination = ""
        } else if toMe {
            destination = from
            open(from, kind: .query)
        } else {
            destination = target
        }
        let mention = !toMe && kind != .notice && Self.mentions(text, nick: nick)
        let line = Line(id: 0, time: m.time, kind: kind, nick: from, text: text,
                        mention: mention || (toMe && !notice && destination != ""))
        add(line, to: destination)
    }

    // MARK: Capabilities and SASL

    private func capability(_ p: [String]) {
        guard p.count >= 3 else { return }
        switch p[1] {
        case "LS":
            for cap in p.last!.split(separator: " ") {
                offered.insert(String(cap.prefix { $0 != "=" }))
            }
            guard p[2] != "*" else { return }               // more to come
            var wanted = ["server-time", "multi-prefix"].filter(offered.contains)
            if !network.account.isEmpty {
                if offered.contains("sasl") {
                    wanted.append("sasl")
                } else {
                    add(Line(id: 0, time: Date(), kind: .error, text: "\(network.name) doesn't offer SASL, so you're on as a guest."), to: "")
                }
            }
            if wanted.isEmpty { endCaps() } else { send("CAP REQ :\(wanted.joined(separator: " "))") }
        case "ACK":
            if p.last!.split(separator: " ").contains("sasl") {
                send("AUTHENTICATE PLAIN")
            } else {
                endCaps()
            }
        case "NAK":
            endCaps()
        default:
            break
        }
    }

    private func authenticate() {
        let password = Keychain.password(for: network) ?? ""
        let token = Data("\(network.account)\0\(network.account)\0\(password)".utf8).base64EncodedString()
        // Sent in pieces of 400, with a lone "+" after a final piece of exactly 400.
        var rest = Substring(token)
        while rest.count >= 400 {
            send("AUTHENTICATE \(rest.prefix(400))")
            rest = rest.dropFirst(400)
        }
        send("AUTHENTICATE \(rest.isEmpty ? "+" : String(rest))")
    }

    private func endCaps() {
        guard !capsDone else { return }
        capsDone = true
        send("CAP END")
    }

    private func support(_ token: String) {
        if token.hasPrefix("PREFIX=("), let close = token.firstIndex(of: ")") {
            let modes = token[token.index(token.startIndex, offsetBy: 8)..<close]
            let symbols = token[token.index(after: close)...]
            prefixes = Array(zip(modes, symbols))
        } else if token.hasPrefix("CHANTYPES=") {
            channelTypes = Set(token.dropFirst(10))
        }
    }

    // MARK: What you say

    /// Sends what was typed in a buffer: a message, or a command starting with "/".
    func say(_ input: String, in ref: BufferRef) {
        guard let buffer = buffer(ref.name) else { return }
        let text = input.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return }
        if text.hasPrefix("/") && !text.hasPrefix("//") {
            command(String(text.dropFirst()), in: buffer)
        } else if buffer.kind == .server {
            add(Line(id: 0, time: Date(), kind: .error, text: "This is the server's buffer. Join a channel with /join #channel, or use /msg nick text."), to: "")
        } else {
            privmsg(buffer.name, text.hasPrefix("//") ? String(text.dropFirst()) : text)
        }
    }

    private func privmsg(_ target: String, _ text: String, action: Bool = false) {
        guard state == .connected else {
            active(.error, "You're not connected.")
            return
        }
        // Room for the server to add your nick!user@host when relaying it.
        let room = 440 - target.utf8.count - nick.utf8.count - (action ? 9 : 0)
        for piece in IRCMessage.split(text, room: room) {
            send(IRCMessage.line("PRIVMSG", target, action ? "\u{1}ACTION \(piece)\u{1}" : piece))
            add(Line(id: 0, time: Date(), kind: action ? .action : .message, nick: nick, text: piece, own: true), to: target)
        }
    }

    private func command(_ text: String, in buffer: Buffer) {
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let name = parts.first.map { $0.lowercased() } ?? ""
        let rest = parts.count > 1 ? String(parts[1]) : ""
        let words = rest.split(separator: " ").map(String.init)
        let here = buffer.kind == .server ? nil : buffer.name

        switch name {
        case "join", "j":
            guard let channel = words.first else { return active(.error, "Usage: /join #channel") }
            let name = isChannel(channel) ? channel : "#" + channel
            showOnJoin = name
            send("JOIN \(name)\(words.count > 1 ? " \(words[1])" : "")")
        case "part", "leave":
            var channel = here ?? ""
            var reason = rest
            if let first = words.first, isChannel(first) {
                channel = first
                reason = words.dropFirst().joined(separator: " ")
            }
            guard isChannel(channel) else { return active(.error, "Usage: /part #channel") }
            leave(channel, reason: reason)
        case "me":
            guard let here else { return active(.error, "/me works in a channel or private conversation.") }
            privmsg(here, rest, action: true)
        case "msg", "query", "q":
            guard let who = words.first else { return active(.error, "Usage: /\(name) nick [message]") }
            if !isChannel(who) { open(who, kind: .query) }
            onShow(BufferRef(network: id, name: who.lowercased()))
            let message = words.dropFirst().joined(separator: " ")
            if !message.isEmpty { privmsg(who, message) }
        case "notice":
            guard words.count >= 2 else { return active(.error, "Usage: /notice target text") }
            send(IRCMessage.line("NOTICE", words[0], words.dropFirst().joined(separator: " ")))
        case "nick":
            guard let new = words.first else { return active(.error, "Usage: /nick newnick") }
            send(IRCMessage.line("NICK", new))
        case "topic":
            guard let here, isChannel(here) else { return active(.error, "/topic works in a channel.") }
            if rest.isEmpty {
                active(.info, buffer.topic.isEmpty ? "No topic is set." : "Topic: \(Self.plain(buffer.topic))")
            } else {
                send(IRCMessage.line("TOPIC", here, rest))
            }
        case "whois", "wi":
            guard let who = words.first else { return active(.error, "Usage: /whois nick") }
            send("WHOIS \(who)")
        case "away":
            send(rest.isEmpty ? "AWAY" : IRCMessage.line("AWAY", rest))
        case "names":
            if let here, isChannel(here) { send("NAMES \(here)") }
        case "close":
            close(BufferRef(network: id, name: buffer.id))
        case "quit", "disconnect":
            disconnect(rest.isEmpty ? "Relay Chat" : rest)
        case "connect":
            onReconnectRequest()
        case "raw", "quote":
            send(rest)
        case "clear":
            update(buffer.name) { $0.lines = [] }
        case "help":
            active(.info, "Commands: /join #channel, /part [reason], /me action, /msg nick text, /query nick, /notice target text, /nick name, /topic [text], /whois nick, /away [message], /names, /close, /clear, /quit [message], /raw line. Any other /command is sent to the server as it is. Start a message with // to send one that begins with a slash.")
        default:
            send(text)
        }
    }

    /// Set by the app, to connect again with the current nick.
    var onReconnectRequest: () -> Void = {}

    func leave(_ channel: String, reason: String = "") {
        send(reason.isEmpty ? "PART \(channel)" : IRCMessage.line("PART", channel, reason))
        network.channels.removeAll { $0.caseInsensitiveCompare(channel) == .orderedSame }
        onChange(network)
    }

    /// Closes a buffer, leaving its channel first.
    func close(_ ref: BufferRef) {
        guard let buffer = buffer(ref.name), buffer.kind != .server else { return }
        if buffer.kind == .channel && buffer.joined { leave(buffer.name) }
        if buffer.kind == .channel {
            network.channels.removeAll { $0.caseInsensitiveCompare(buffer.name) == .orderedSame }
            onChange(network)
        }
        buffers.removeAll { $0.id == buffer.id }
    }

    func requestList() {
        listing = nil
        listingDone = false
        pendingListing = []
        send("LIST")
    }

    // MARK: Buffers

    func buffer(_ name: String) -> Buffer? {
        let key = name.lowercased()
        return buffers.first { key.isEmpty ? $0.kind == .server : $0.id == key && $0.kind != .server }
    }

    @discardableResult
    func open(_ name: String, kind: Buffer.Kind) -> Buffer {
        if let existing = buffer(name) { return existing }
        let new = Buffer(name: name, kind: kind)
        // The server first, then channels, then people, each in order of name.
        let rank: (Buffer) -> Int = { $0.kind == .server ? 0 : $0.kind == .channel ? 1 : 2 }
        let index = buffers.firstIndex { rank($0) > rank(new) || (rank($0) == rank(new) && $0.id > new.id) } ?? buffers.endIndex
        buffers.insert(new, at: index)
        return new
    }

    func markRead(_ ref: BufferRef) {
        guard let i = buffers.firstIndex(where: { ref.name.isEmpty ? $0.kind == .server : $0.id == ref.name && $0.kind != .server }),
              buffers[i].unread > 0 || buffers[i].mentions > 0 else { return }
        buffers[i].unread = 0
        buffers[i].mentions = 0
    }

    private func update(_ name: String, _ change: (inout Buffer) -> Void) {
        let key = name.lowercased()
        guard let i = buffers.firstIndex(where: { key.isEmpty ? $0.kind == .server : $0.id == key && $0.kind != .server }) else { return }
        change(&buffers[i])
    }

    /// Adds a line to a buffer (the server's for ""), opening a channel's buffer if need be.
    func add(_ line: Line, to name: String) {
        if !name.isEmpty && buffer(name) == nil { open(name, kind: isChannel(name) ? .channel : .query) }
        nextLine += 1
        var line = line
        line.id = nextLine
        let ref = BufferRef(network: id, name: name.lowercased())
        let showing = isShowing(ref)
        update(name) { buffer in
            buffer.lines.append(line)
            if buffer.lines.count > 3000 { buffer.lines.removeFirst(buffer.lines.count - 2500) }
            if !showing && !line.own && [.message, .action, .notice].contains(line.kind) {
                buffer.unread += 1
                if line.mention || buffer.kind == .query { buffer.mentions += 1 }
            }
        }
        if !line.own, [.message, .action].contains(line.kind), line.mention || buffer(name)?.kind == .query, let buffer = buffer(name) {
            onAlert(self, buffer, line)
        }
    }

    private func server(_ text: String, _ m: IRCMessage, kind: Line.Kind = .info) {
        add(Line(id: 0, time: m.time, kind: kind, text: text), to: "")
    }

    private func event(_ channel: String, _ text: String, _ m: IRCMessage) {
        add(Line(id: 0, time: m.time, kind: .event, text: text), to: channel)
    }

    /// Replies to commands go where the person is looking, if that's on this network.
    var activeBuffer: String = ""

    private func active(_ kind: Line.Kind, _ text: String) {
        add(Line(id: 0, time: Date(), kind: kind, text: text), to: buffer(activeBuffer) == nil ? "" : activeBuffer)
    }

    func isChannel(_ name: String) -> Bool {
        name.first.map(channelTypes.contains) ?? false
    }

    /// The rank of a mode prefix, highest first, for sorting people in a channel.
    func rank(_ symbol: String) -> Int {
        guard let c = symbol.first, let i = prefixes.firstIndex(where: { $0.symbol == c }) else { return prefixes.count }
        return i
    }

    // MARK: Text

    /// Text with IRC's formatting codes taken out.
    static func plain(_ text: String) -> String {
        Formatting.strip(text)
    }

    /// Whether `text` says `nick` as a word of its own.
    static func mentions(_ text: String, nick: String) -> Bool {
        guard !nick.isEmpty else { return false }
        let plain = Formatting.strip(text).lowercased()
        let target = nick.lowercased()
        var search = plain.startIndex
        while let range = plain.range(of: target, range: search..<plain.endIndex) {
            let before = range.lowerBound == plain.startIndex ? nil : plain[plain.index(before: range.lowerBound)]
            let after = range.upperBound == plain.endIndex ? nil : plain[range.upperBound]
            let isWordChar: (Character?) -> Bool = { c in c.map { $0.isLetter || $0.isNumber || "_-[]\\`^{}|".contains($0) } ?? false }
            if !isWordChar(before) && !isWordChar(after) { return true }
            search = range.upperBound
        }
        return false
    }
}
