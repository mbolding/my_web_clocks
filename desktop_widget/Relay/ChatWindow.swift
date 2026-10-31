// ChatWindow — networks and their buffers down the side, with unread counts and mentions in
// the accent; the open buffer's topic, its log and a line to type in; and the people in a
// channel in the inspector. The log is a text view, so it can be selected and searched, and
// it follows new lines only while it's scrolled to the bottom.

import SwiftUI
import AppKit

struct ChatWindow: View {
    @ObservedObject private var chat = Chat.shared
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    @Environment(\.controlActiveState) private var active

    var body: some View {
        NavigationSplitView {
            List(selection: $chat.selection) {
                ForEach(chat.sessions) { session in
                    NetworkSection(session: session)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let ref = chat.selection, let session = chat.session(ref.network) {
                BufferView(session: session, ref: ref)
                    .id(ref)
            } else {
                ContentUnavailableView("No Conversation Open", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Choose a network or channel in the sidebar."))
            }
        }
        .tint(accent.color)
        .environment(\.accent, accent.color)
        .sheet(item: $chat.joining) { session in
            JoinSheet(session: session)
        }
        .onAppear { chat.windowAppeared(true) }
        .onDisappear { chat.windowAppeared(false) }
        .onChange(of: active) { if active == .key { chat.appBecameActive() } }
    }
}

// MARK: - Sidebar

struct NetworkSection: View {
    @ObservedObject var session: Session
    @Environment(\.accent) private var accent

    var body: some View {
        Section {
            ForEach(session.buffers) { buffer in
                row(buffer)
                    .tag(BufferRef(network: session.id, name: buffer.kind == .server ? "" : buffer.id))
            }
        }
    }

    @ViewBuilder private func row(_ buffer: Buffer) -> some View {
        HStack(spacing: 6) {
            switch buffer.kind {
            case .server:
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .help(statusText)
                Text(session.network.name).fontWeight(.semibold)
            case .channel:
                Text(buffer.name)
                    .foregroundStyle(buffer.joined || session.state != .connected ? .primary : .secondary)
            case .query:
                Image(systemName: "person").foregroundStyle(.secondary)
                Text(buffer.name)
            }
            Spacer(minLength: 4)
            if buffer.mentions > 0 {
                Text("\(buffer.mentions)")
                    .font(.caption.bold())
                    .foregroundStyle(accent.readableText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(accent, in: Capsule())
            } else if buffer.unread > 0 {
                Text("\(buffer.unread)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .contextMenu { menu(buffer) }
    }

    @ViewBuilder private func menu(_ buffer: Buffer) -> some View {
        switch buffer.kind {
        case .server:
            if session.state == .disconnected {
                Button("Connect") { Chat.shared.connect(session) }
            } else {
                Button("Disconnect") { session.disconnect() }
            }
            Button("Join Channel…") { Chat.shared.joining = session }
                .disabled(session.state != .connected)
        case .channel:
            if buffer.joined {
                Button("Leave \(buffer.name)") { session.leave(buffer.name) }
            } else {
                Button("Join \(buffer.name)") { session.send("JOIN \(buffer.name)") }
                    .disabled(session.state != .connected)
            }
            Button("Close") { session.close(BufferRef(network: session.id, name: buffer.id)) }
        case .query:
            Button("Close") { session.close(BufferRef(network: session.id, name: buffer.id)) }
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .connected: .green
        case .connecting, .registering: .yellow
        case .disconnected: .secondary.opacity(0.5)
        }
    }

    private var statusText: String {
        switch session.state {
        case .connected: "Connected as \(session.nick)"
        case .connecting, .registering: "Connecting…"
        case .disconnected: "Not connected"
        }
    }
}

// MARK: - A buffer

struct BufferView: View {
    @ObservedObject var session: Session
    let ref: BufferRef
    @ObservedObject private var chat = Chat.shared
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("showEvents") private var showEvents = true
    @Environment(\.accent) private var accent

    var body: some View {
        if let buffer = session.buffer(ref.name) {
            VStack(spacing: 0) {
                if buffer.kind == .server && session.state == .disconnected {
                    connectBar
                    Divider()
                } else if !buffer.topic.isEmpty {
                    Text(AttributedString(Formatting.attributed(buffer.topic, attributes: [.font: NSFont.systemFont(ofSize: 12)])))
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .help(Formatting.strip(buffer.topic))
                    Divider()
                }
                ChatLog(buffer: buffer, lines: showEvents ? buffer.lines : buffer.lines.filter { $0.kind != .event },
                        nick: session.nick, fontSize: fontSize, accent: NSColor(accent), events: showEvents)
                Divider()
                InputLine(session: session, ref: ref, buffer: buffer)
            }
            .navigationTitle(buffer.kind == .server ? session.network.name : buffer.name)
            .navigationSubtitle(subtitle(buffer))
            .toolbar { toolbar(buffer) }
            .inspector(isPresented: Binding(get: { chat.showUsers && buffer.kind == .channel }, set: { chat.showUsers = $0 })) {
                PeopleList(session: session, buffer: buffer)
                    .inspectorColumnWidth(min: 140, ideal: 170, max: 260)
            }
        } else {
            ContentUnavailableView("Conversation Closed", systemImage: "bubble.left.and.bubble.right")
        }
    }

    private var connectBar: some View {
        HStack {
            Text(UserDefaults.standard.string(forKey: "nick")?.isEmpty == false || !session.network.nick.isEmpty
                 ? "Not connected to \(session.network.name)."
                 : "Choose a nick in Settings → Identity, then connect.")
                .foregroundStyle(.secondary)
            Spacer()
            SettingsLink { Text("Settings…") }
            Button("Connect") { Chat.shared.connect(session) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(10)
    }

    private func subtitle(_ buffer: Buffer) -> String {
        switch buffer.kind {
        case .server: session.state == .connected ? "\(session.network.host) as \(session.nick)" : session.network.host
        case .channel: buffer.joined ? "\(buffer.users.count) people · \(session.network.name)" : "not joined · \(session.network.name)"
        case .query: session.network.name
        }
    }

    @ToolbarContentBuilder private func toolbar(_ buffer: Buffer) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { chat.joining = session } label: { Label("Join Channel", systemImage: "number") }
                .help("Join a channel on \(session.network.name)")
                .disabled(session.state != .connected)
            Button { chat.showUsers.toggle() } label: { Label("People", systemImage: "person.2") }
                .help("Show or hide who's here")
                .disabled(buffer.kind != .channel)
        }
    }
}

/// The text box at the bottom: Return sends, Tab finishes a nick, and Up and Down step
/// through what was sent before.
struct InputLine: View {
    @ObservedObject var session: Session
    let ref: BufferRef
    let buffer: Buffer
    @State private var text = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @State private var completion: (prefix: String, matches: [String], index: Int)?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .focused($focused)
            .onSubmit(send)
            .onKeyPress(.tab) { complete(); return .handled }
            .onKeyPress(.upArrow) { step(-1); return .handled }
            .onKeyPress(.downArrow) { step(1); return .handled }
            .onChange(of: text) { if completion != nil && !text.hasSuffix(" ") && !text.hasSuffix(": ") { completion = nil } }
            .onAppear { focused = true }
            .disabled(session.state != .connected && buffer.kind != .server)
    }

    private var placeholder: String {
        switch buffer.kind {
        case .server: "Commands for \(session.network.name), such as /join #channel"
        case .channel: "Message \(buffer.name)"
        case .query: "Message \(buffer.name)"
        }
    }

    private func send() {
        let line = text
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        history.append(line)
        if history.count > 100 { history.removeFirst() }
        historyIndex = nil
        completion = nil
        text = ""
        session.say(line, in: ref)
        focused = true
    }

    private func step(_ by: Int) {
        guard !history.isEmpty else { return }
        let next = (historyIndex ?? history.count) + by
        if next >= history.count {
            historyIndex = nil
            text = ""
        } else {
            historyIndex = max(0, next)
            text = history[historyIndex!]
        }
    }

    /// Finishes the nick being typed from the people in the channel, cycling with each Tab.
    private func complete() {
        if var current = completion, !current.matches.isEmpty {
            current.index = (current.index + 1) % current.matches.count
            completion = current
            text = replace(current.prefix, with: current.matches[current.index])
            return
        }
        let word = String(text.split(separator: " ", omittingEmptySubsequences: false).last ?? "")
        guard !word.isEmpty else { return }
        let names = buffer.kind == .query ? [buffer.name] : Array(buffer.users.keys)
        let matches = names.filter { $0.lowercased().hasPrefix(word.lowercased()) }.sorted { $0.lowercased() < $1.lowercased() }
        guard let first = matches.first else { return }
        let prefix = String(text.dropLast(word.count))
        completion = (prefix, matches, 0)
        text = replace(prefix, with: first)
    }

    private func replace(_ prefix: String, with nick: String) -> String {
        prefix + nick + (prefix.isEmpty ? ": " : " ")
    }
}

/// Who's in a channel, operators first. Double-click someone to talk to them privately.
struct PeopleList: View {
    @ObservedObject var session: Session
    let buffer: Buffer
    @State private var selected: String?

    private func say(_ command: String) {
        session.say(command, in: BufferRef(network: session.id, name: buffer.id))
    }

    var body: some View {
        let people = buffer.users.sorted { a, b in
            let ra = session.rank(a.value), rb = session.rank(b.value)
            return ra != rb ? ra < rb : a.key.lowercased() < b.key.lowercased()
        }
        List(people, id: \.key, selection: $selected) { person in
            HStack(spacing: 2) {
                Text(person.value).foregroundStyle(.secondary).frame(width: 10)
                Text(person.key).foregroundStyle(Color(nsColor: Formatting.color(for: person.key)))
            }
            .lineLimit(1)
        }
        .contextMenu(forSelectionType: String.self) { nicks in
            if let nick = nicks.first {
                Button("Message \(nick)") { say("/query \(nick)") }
                Button("Who Is \(nick)?") { say("/whois \(nick)") }
            }
        } primaryAction: { nicks in
            if let nick = nicks.first { say("/query \(nick)") }
        }
        .overlay {
            if people.isEmpty {
                Text(buffer.joined ? "Getting the list…" : "Not in the channel").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - The log

struct ChatLog: NSViewRepresentable {
    let buffer: Buffer
    let lines: [Line]
    let nick: String
    let fontSize: Double
    let accent: NSColor
    /// Whether joins, parts and the like are shown, since turning them on adds older lines.
    let events: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor
        return scroll
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var buffer = ""
        var lastID = -1
        var style = ""
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
        let c = context.coordinator
        let style = "\(fontSize)/\(accent)/\(events)"
        let rebuild = c.buffer != buffer.id || c.style != style || (lines.first.map { $0.id > c.lastID + 1 && c.lastID >= 0 } ?? false)
            || (lines.last.map { $0.id < c.lastID } ?? (c.lastID >= 0))
        let atBottom = scroll.documentVisibleRect.maxY >= view.bounds.height - 30
        let fresh = rebuild ? lines[...] : lines.drop { $0.id <= c.lastID }
        guard rebuild || !fresh.isEmpty else { return }

        let text = NSMutableAttributedString()
        for line in fresh {
            if storage.length > 0 || text.length > 0 { text.append(NSAttributedString(string: "\n")) }
            text.append(render(line))
        }
        if rebuild { storage.setAttributedString(text) } else { storage.append(text) }
        c.buffer = buffer.id
        c.style = style
        c.lastID = lines.last?.id ?? -1
        if rebuild || atBottom { view.scrollToEndOfDocument(nil) }
    }

    private func render(_ line: Line) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: fontSize)
        let small = NSFont.monospacedDigitSystemFont(ofSize: fontSize * 0.85, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        // Wrapped lines hang under the text, past the time.
        let indent = ("00:00  " as NSString).size(withAttributes: [.font: small]).width
        paragraph.headIndent = indent
        paragraph.paragraphSpacing = fontSize * 0.25
        var base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        if line.mention { base[.backgroundColor] = accent.withAlphaComponent(0.14) }

        let out = NSMutableAttributedString(string: Self.time.string(from: line.time) + "  ",
                                            attributes: base.merging([.font: small, .foregroundColor: NSColor.tertiaryLabelColor]) { $1 })
        let bold = NSFont.boldSystemFont(ofSize: fontSize)
        let nickColor = line.own ? NSColor.secondaryLabelColor : Formatting.color(for: line.nick)
        switch line.kind {
        case .message:
            out.append(NSAttributedString(string: line.nick + "  ", attributes: base.merging([.font: bold, .foregroundColor: nickColor]) { $1 }))
            out.append(Formatting.attributed(line.text, attributes: base))
        case .action:
            let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            out.append(NSAttributedString(string: "• " + line.nick + " ", attributes: base.merging([.font: bold, .foregroundColor: nickColor]) { $1 }))
            out.append(Formatting.attributed(line.text, attributes: base.merging([.font: italic]) { $1 }))
        case .notice:
            out.append(NSAttributedString(string: "-\(line.nick.isEmpty ? "server" : line.nick)-  ",
                                          attributes: base.merging([.font: bold, .foregroundColor: NSColor.systemBrown]) { $1 }))
            out.append(Formatting.attributed(line.text, attributes: base))
        case .event:
            out.append(NSAttributedString(string: "→ " + Formatting.strip(line.text),
                                          attributes: base.merging([.foregroundColor: NSColor.secondaryLabelColor,
                                                                    .font: NSFont.systemFont(ofSize: fontSize * 0.92)]) { $1 }))
        case .info:
            out.append(Formatting.attributed(line.text, attributes: base.merging([.foregroundColor: NSColor.secondaryLabelColor]) { $1 }))
        case .error:
            out.append(NSAttributedString(string: line.text, attributes: base.merging([.foregroundColor: NSColor.systemRed]) { $1 }))
        }
        if let detector = Self.links {
            for match in detector.matches(in: out.string, range: NSRange(location: 0, length: out.length)) {
                if let url = match.url { out.addAttribute(.link, value: url, range: match.range) }
            }
        }
        return out
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}

// MARK: - Joining

/// Join a channel by name, or pick one from the network's list, busiest first.
struct JoinSheet: View {
    @ObservedObject var session: Session
    @State private var name = ""
    @State private var search = ""
    @State private var asked = false
    @State private var selected: String?
    /// No list has come back after a while.
    @State private var slow = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("#channel", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(join)
                Button("Join", action: join)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            Divider()
            if let listing = session.listing {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(listing.count) channels by name or topic", text: $search).textFieldStyle(.plain)
                    if !session.listingDone { ProgressView().controlSize(.small) }
                }
                .padding(10)
                Divider()
                List(shown(listing), selection: $selected) { channel in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.name).fontWeight(.medium)
                            if !channel.topic.isEmpty {
                                Text(channel.topic).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Text("\(channel.users)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { names in
                    if let channel = names.first {
                        name = channel
                        join()
                    }
                }
                .onChange(of: selected) { if let selected { name = selected } }
            } else {
                VStack(spacing: 12) {
                    if asked && slow {
                        Text("Nothing has come back yet. Some networks, SDF and tilde.chat among them, only list "
                             + "their channels a minute after you connect; \(session.network.name)'s own buffer says why.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                        Button("Try Again") {
                            slow = false
                            session.requestList()
                        }
                    } else if asked {
                        ProgressView("Getting the channel list from \(session.network.name)…")
                    } else {
                        Text("Type a channel's name, or see every channel on \(session.network.name).")
                            .foregroundStyle(.secondary)
                        Button("List Channels") {
                            asked = true
                            session.requestList()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: "\(asked)\(slow)") {
                    guard asked, !slow else { return }
                    try? await Task.sleep(for: .seconds(12))
                    if session.listing == nil { slow = true }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 440, idealHeight: 560)
    }

    private func shown(_ listing: [Listing]) -> [Listing] {
        let words = search.lowercased().split(separator: " ")
        let matches = words.isEmpty ? listing : listing.filter { channel in
            let text = (channel.name + " " + channel.topic).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        return Array(matches.prefix(2000))
    }

    private func join() {
        let channel = name.trimmingCharacters(in: .whitespaces)
        guard !channel.isEmpty else { return }
        session.say("/join \(channel)", in: BufferRef(network: session.id, name: ""))
        dismiss()
    }
}
