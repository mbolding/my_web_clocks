// Chat — what the whole app shares: a session for each network, which buffer is on screen,
// and the ways a quiet window asks for attention: a count on the Dock icon of mentions and
// private messages waiting, a bounce, and a notification.

import SwiftUI
import AppKit
import UserNotifications
import Combine

@MainActor
final class Chat: ObservableObject {
    static let shared = Chat()

    @Published private(set) var sessions: [Session] = []
    @Published var selection: BufferRef? {
        didSet {
            guard let selection else { return }
            session(selection.network)?.markRead(selection)
            session(selection.network)?.activeBuffer = selection.name
            UserDefaults.standard.set(try? JSONEncoder().encode(selection), forKey: "selection")
            updateBadge()
        }
    }
    /// The network whose channel list is open, for the Join Channel sheet.
    @Published var joining: Session?
    /// The network whose Log In or Register sheet is open.
    @Published var accountFor: Session?
    @Published var showUsers = true

    /// Set by the menu commands, so the Dock icon can bring the window back.
    var openWindow: OpenWindowAction?
    private var windowShowing = false
    private var watching: [UUID: AnyCancellable] = [:]

    private init() {
        let saved = UserDefaults.standard.data(forKey: "networks").flatMap { try? JSONDecoder().decode([Network].self, from: $0) }
        sessions = (saved ?? Network.starting).map(makeSession)
        selection = UserDefaults.standard.data(forKey: "selection").flatMap { try? JSONDecoder().decode(BufferRef.self, from: $0) }
            ?? sessions.first.map { BufferRef(network: $0.id, name: "") }
    }

    private func makeSession(_ network: Network) -> Session {
        let session = Session(network: network)
        session.onChange = { [weak self] _ in self?.save() }
        session.onAlert = { [weak self] session, buffer, line in self?.alert(session, buffer, line) }
        session.isShowing = { [weak self] ref in
            guard let self else { return false }
            return self.windowShowing && NSApp.isActive && self.selection == ref
        }
        session.onShow = { [weak self] ref in self?.selection = ref }
        session.onReconnectRequest = { [weak self, weak session] in
            if let session { self?.connect(session) }
        }
        // Counts change with every line; the badge follows once each change has landed.
        watching[network.id] = session.$buffers.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateBadge() }
        return session
    }

    func session(_ id: UUID) -> Session? { sessions.first { $0.id == id } }

    var networks: [Network] { sessions.map(\.network) }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(networks), forKey: "networks")
        objectWillChange.send()
        updateBadge()
    }

    // MARK: Connecting

    /// Connects the networks that were connected when the app last quit.
    func start() {
        for session in sessions where session.network.autoConnect { connect(session) }
    }

    func connect(_ session: Session) {
        let defaults = UserDefaults.standard
        session.connect(nick: defaults.string(forKey: "nick") ?? "", realName: defaults.string(forKey: "realName") ?? "")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func quitAll() -> Bool {
        let connected = sessions.filter { $0.state == .connected }
        connected.forEach { $0.quit() }
        return !connected.isEmpty
    }

    // MARK: Networks, from Settings

    func addNetwork() -> Network {
        let network = Network(name: "New Network", host: "")
        sessions.append(makeSession(network))
        save()
        return network
    }

    func update(_ network: Network) {
        guard let session = session(network.id) else { return }
        // Connection settings apply the next time it connects; channels and the rest at once.
        session.network = network
        save()
    }

    func remove(_ network: Network) {
        guard let session = session(network.id) else { return }
        session.disconnect()
        sessions.removeAll { $0.id == network.id }
        Keychain.setPassword("", for: network)
        if selection?.network == network.id { selection = sessions.first.map { BufferRef(network: $0.id, name: "") } }
        save()
    }

    // MARK: Attention

    func windowAppeared(_ showing: Bool) {
        windowShowing = showing
        if showing, let selection { session(selection.network)?.markRead(selection) }
        updateBadge()
    }

    func appBecameActive() {
        if let selection { session(selection.network)?.markRead(selection) }
        updateBadge()
    }

    private func alert(_ session: Session, _ buffer: Buffer, _ line: Line) {
        updateBadge()
        let ref = BufferRef(network: session.id, name: buffer.kind == .server ? "" : buffer.id)
        guard !(NSApp.isActive && windowShowing && selection == ref) else { return }
        NSApp.requestUserAttention(.informationalRequest)
        let content = UNMutableNotificationContent()
        content.title = buffer.kind == .query ? line.nick : "\(line.nick) in \(buffer.name)"
        content.subtitle = session.network.name
        content.body = (line.kind == .action ? "\(line.nick) " : "") + Formatting.strip(line.text)
        content.sound = .default
        content.userInfo = ["network": session.id.uuidString, "buffer": ref.name]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// The Dock shows how many mentions and private messages are waiting.
    func updateBadge() {
        let waiting = sessions.reduce(0) { total, session in total + session.buffers.reduce(0) { $0 + $1.mentions } }
        NSApp.dockTile.badgeLabel = waiting > 0 ? "\(waiting)" : nil
    }

    /// Shows the buffer a notification came from.
    func show(network: String, buffer: String) {
        guard let id = UUID(uuidString: network), session(id) != nil else { return }
        selection = BufferRef(network: id, name: buffer)
        if !windowShowing { openWindow?(id: "main") }
        NSApp.activate()
    }
}
