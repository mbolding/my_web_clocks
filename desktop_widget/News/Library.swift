// Library — what every window shares: the servers, the groups subscribed on each, which
// articles have been read, and one NNTP session per server. Read marks are kept as ranges
// of article numbers per group, the way a .newsrc file keeps them, so a group of thousands
// read in order takes one range. Passwords are kept in the Keychain, never in preferences.

import SwiftUI
import Security

struct Server: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int
    /// TLS, as on port 563, rather than plain text on 119.
    var secure: Bool
    /// Empty for servers that let anyone read.
    var username = ""

    /// Fixed ids, so the starting subscriptions point at the same servers every launch.
    static let starting = [
        Server(id: UUID(uuidString: "6E3A1C52-0B7D-4F6A-9C1E-1D2B3A4C5D01")!,
               name: "tilde.club", host: "news.tilde.club", port: 563, secure: true),
        Server(id: UUID(uuidString: "6E3A1C52-0B7D-4F6A-9C1E-1D2B3A4C5D02")!,
               name: "Gmane", host: "news.gmane.io", port: 119, secure: false),
        Server(id: UUID(uuidString: "6E3A1C52-0B7D-4F6A-9C1E-1D2B3A4C5D03")!,
               name: "Eternal September", host: "news.eternal-september.org", port: 563, secure: true),
    ]
}

/// A group on a server: what the sidebar selects.
struct GroupRef: Codable, Hashable {
    var server: UUID
    var name: String

    var key: String { "\(server.uuidString)/\(name)" }
}

enum Keychain {
    private static let service = "com.mbolding.newsreader"

    static func password(for server: Server) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: server.id.uuidString, kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setPassword(_ password: String, for server: Server) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: server.id.uuidString]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrLabel as String] = "News Reader: \(server.host)"
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// Article numbers as sorted, separate ranges.
struct Marks: Codable, Hashable {
    var ranges: [ClosedRange<Int>] = []

    func contains(_ n: Int) -> Bool {
        var low = 0, high = ranges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if ranges[mid].contains(n) { return true }
            if n < ranges[mid].lowerBound { high = mid - 1 } else { low = mid + 1 }
        }
        return false
    }

    mutating func insert(_ range: ClosedRange<Int>) {
        var merged = range
        var kept: [ClosedRange<Int>] = []
        for existing in ranges {
            if existing.upperBound + 1 < merged.lowerBound || merged.upperBound + 1 < existing.lowerBound {
                kept.append(existing)
            } else {
                merged = min(existing.lowerBound, merged.lowerBound)...max(existing.upperBound, merged.upperBound)
            }
        }
        kept.append(merged)
        ranges = kept.sorted { $0.lowerBound < $1.lowerBound }
    }

    mutating func remove(_ n: Int) {
        ranges = ranges.flatMap { range -> [ClosedRange<Int>] in
            guard range.contains(n) else { return [range] }
            var pieces: [ClosedRange<Int>] = []
            if range.lowerBound < n { pieces.append(range.lowerBound...(n - 1)) }
            if n < range.upperBound { pieces.append((n + 1)...range.upperBound) }
            return pieces
        }
    }

    /// How many numbers in `bounds` are marked.
    func count(in bounds: ClosedRange<Int>) -> Int {
        ranges.reduce(0) { total, range in
            let low = max(range.lowerBound, bounds.lowerBound), high = min(range.upperBound, bounds.upperBound)
            return total + max(0, high - low + 1)
        }
    }
}

@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    @Published var servers: [Server] { didSet { save(servers, "servers"); dropStaleSessions() } }
    /// Group names by server id.
    @Published private(set) var subscriptions: [UUID: [String]] { didSet { save(subscriptions, "subscriptions") } }
    @Published private(set) var read: [String: Marks] { didSet { save(read, "read") } }
    /// The latest GROUP answer for each subscribed group, for the sidebar's unread counts.
    @Published private(set) var info: [GroupRef: GroupInfo] = [:]
    /// Why a server or group couldn't be reached, for the sidebar.
    @Published private(set) var problems: [String: String] = [:]

    private var sessions: [UUID: NNTPSession] = [:]
    private var sessionServers: [UUID: Server] = [:]

    private init() {
        servers = Self.load("servers") ?? Server.starting
        read = Self.load("read") ?? [:]
        if let saved: [UUID: [String]] = Self.load("subscriptions") {
            subscriptions = saved
        } else {
            // A few of the tildeverse's busier groups, so there's something to read at once.
            let tilde = Server.starting[0].id
            subscriptions = [tilde: ["tilde.meta", "tilde.club", "tilde.art.ascii", "tilde.text", "tilde.gopher"]]
        }
    }

    func server(_ id: UUID) -> Server? { servers.first { $0.id == id } }

    /// The one session for a server, made anew if its settings have changed.
    func session(_ server: Server) -> NNTPSession {
        if let session = sessions[server.id], sessionServers[server.id] == server { return session }
        if let old = sessions[server.id] { Task { await old.close() } }
        let session = NNTPSession(server: server)
        sessions[server.id] = session
        sessionServers[server.id] = server
        return session
    }

    private func dropStaleSessions() {
        for (id, session) in sessions where sessionServers[id] != server(id) {
            Task { await session.close() }
            sessions[id] = nil
            sessionServers[id] = nil
        }
    }

    // MARK: Subscriptions

    func groups(on server: Server) -> [String] { subscriptions[server.id] ?? [] }

    func isSubscribed(_ ref: GroupRef) -> Bool { subscriptions[ref.server]?.contains(ref.name) ?? false }

    func subscribe(_ ref: GroupRef) {
        guard !isSubscribed(ref) else { return }
        subscriptions[ref.server, default: []].append(ref.name)
        subscriptions[ref.server]?.sort()
        Task { await refresh(ref) }
    }

    func unsubscribe(_ ref: GroupRef) {
        subscriptions[ref.server]?.removeAll { $0 == ref.name }
        info[ref] = nil
    }

    func removeServer(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        subscriptions[server.id] = nil
        read = read.filter { !$0.key.hasPrefix(server.id.uuidString) }
        Keychain.setPassword("", for: server)
    }

    // MARK: Read marks

    func isRead(_ ref: GroupRef, _ number: Int) -> Bool { read[ref.key]?.contains(number) ?? false }

    func markRead(_ ref: GroupRef, _ range: ClosedRange<Int>) {
        read[ref.key, default: Marks()].insert(range)
    }

    func markUnread(_ ref: GroupRef, _ number: Int) {
        read[ref.key]?.remove(number)
    }

    func unread(_ ref: GroupRef) -> Int? {
        guard let group = info[ref] else { return nil }
        guard group.high >= group.low, group.count > 0 else { return 0 }
        let readHere = read[ref.key]?.count(in: group.low...group.high) ?? 0
        return max(0, min(group.count, group.high - group.low + 1) - readHere)
    }

    // MARK: Refreshing

    /// Asks every server about its subscribed groups, servers side by side.
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { tasks in
            for server in servers {
                let names = groups(on: server)
                guard !names.isEmpty else { continue }
                tasks.addTask { @MainActor in
                    for name in names { await self.refresh(GroupRef(server: server.id, name: name)) }
                }
            }
        }
    }

    func refresh(_ ref: GroupRef) async {
        guard let server = server(ref.server) else { return }
        do {
            let group = try await session(server).group(ref.name)
            note(group, for: ref)
            problems[ref.key] = nil
            problems[server.id.uuidString] = nil
        } catch {
            problems[ref.key] = error.localizedDescription
        }
    }

    func note(_ group: GroupInfo, for ref: GroupRef) {
        info[ref] = group
    }

    func problem(_ ref: GroupRef) -> String? { problems[ref.key] }

    // MARK: Keeping

    private func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
