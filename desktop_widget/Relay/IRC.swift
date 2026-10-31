// IRC — Internet Relay Chat (RFC 1459, as modern servers speak it with the IRCv3 additions):
// one long-lived connection per network, a line per message, each an optional set of tags,
// an optional prefix saying who it's from, a command, and parameters, the last of which may
// hold spaces after a colon.

import Foundation
import Network

struct IRCMessage {
    var tags: [String: String] = [:]
    var prefix: String?
    var command: String
    var params: [String] = []

    /// Reads `@tags :prefix COMMAND param param :trailing`.
    init?(_ line: String) {
        var rest = Substring(line)
        func word() -> Substring {
            let end = rest.firstIndex(of: " ") ?? rest.endIndex
            let word = rest[..<end]
            rest = rest[end...].drop { $0 == " " }
            return word
        }
        if rest.hasPrefix("@") {
            for pair in word().dropFirst().split(separator: ";") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                tags[String(parts[0])] = parts.count > 1 ? Self.unescape(parts[1]) : ""
            }
        }
        if rest.hasPrefix(":") { prefix = String(word().dropFirst()) }
        command = word().uppercased()
        guard !command.isEmpty else { return nil }
        while !rest.isEmpty {
            if rest.hasPrefix(":") {
                params.append(String(rest.dropFirst()))
                break
            }
            params.append(String(word()))
        }
    }

    /// The nick in the prefix, `nick!user@host`.
    var nick: String? { prefix.map { String($0.prefix { $0 != "!" && $0 != "@" }) } }

    /// When the server says it was sent (the server-time tag), or now.
    var time: Date {
        tags["time"].flatMap { Self.serverTime.date(from: $0) ?? Self.plainTime.date(from: $0) } ?? Date()
    }

    private static let serverTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plainTime = ISO8601DateFormatter()

    private static func unescape(_ value: Substring) -> String {
        var out = ""
        var escaping = false
        for c in value {
            if escaping {
                switch c {
                case ":": out.append(";")
                case "s": out.append(" ")
                case "r": out.append("\r")
                case "n": out.append("\n")
                default: out.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    /// A line to send: the last parameter gets a colon if it needs one.
    static func line(_ command: String, _ params: String...) -> String {
        var parts = [command]
        for (n, param) in params.enumerated() {
            let last = n == params.count - 1
            parts.append(last && (param.isEmpty || param.contains(" ") || param.hasPrefix(":")) ? ":" + param : param)
        }
        return parts.joined(separator: " ")
    }

    /// Text split into pieces that fit in one line each, at spaces where it can, never inside
    /// a character. Servers allow 512 bytes a line, less what they add when relaying it.
    static func split(_ text: String, room: Int) -> [String] {
        var pieces: [String] = []
        var rest = Substring(text)
        while rest.utf8.count > room {
            var end = rest.startIndex
            var lastSpace: Substring.Index?
            for i in rest.indices {
                if rest[rest.startIndex...i].utf8.count > room { break }
                end = rest.index(after: i)
                if rest[i] == " " { lastSpace = i }
            }
            let cut = lastSpace ?? end
            pieces.append(String(rest[..<cut]))
            rest = rest[cut...].drop { $0 == " " }
        }
        if !rest.isEmpty || pieces.isEmpty { pieces.append(String(rest)) }
        return pieces
    }
}

/// One connection to a network: lines out, lines in, and word of it opening or closing,
/// all handed to the main actor in the order they happen.
final class IRCConnection: @unchecked Sendable {
    enum Event {
        case ready
        case lines([String])
        case closed(String?)
    }

    private let queue = DispatchQueue(label: "irc.connection")
    private var connection: NWConnection?
    private var buffer: [UInt8] = []
    private var finished = false
    private let handler: @MainActor (Event) -> Void

    init(handler: @escaping @MainActor (Event) -> Void) {
        self.handler = handler
    }

    func start(host: String, port: Int, secure: Bool) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port.rawValue > 0 else {
            deliver(.closed("That isn't a port number."))
            return
        }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 20
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 120
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port,
                                      using: NWParameters(tls: secure ? NWProtocolTLS.Options() : nil, tcp: tcp))
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                deliver(.ready)
                receive()
            case .waiting(let error), .failed(let error):
                finish(Self.describe(error, host: host))
            case .cancelled:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ line: String) {
        // A line can't hold a line break; anything after one would be read as a command.
        let clean = line.prefix { $0 != "\r" && $0 != "\n" }
        connection?.send(content: Data((clean + "\r\n").utf8), completion: .contentProcessed { _ in })
    }

    func stop() {
        queue.async { [self] in
            connection?.cancel()
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                buffer.append(contentsOf: data)
                var lines: [String] = []
                var start = 0
                while let newline = buffer[start...].firstIndex(of: 10) {
                    var line = buffer[start..<newline]
                    start = newline + 1
                    if line.last == 13 { line = line.dropLast() }
                    if !line.isEmpty {
                        lines.append(String(bytes: line, encoding: .utf8) ?? String(bytes: line, encoding: .isoLatin1) ?? "")
                    }
                }
                buffer.removeFirst(start)
                if !lines.isEmpty { deliver(.lines(lines)) }
            }
            if complete {
                finish("The server closed the connection.")
            } else if let error {
                finish(error.localizedDescription)
            } else {
                receive()
            }
        }
    }

    private func finish(_ reason: String?) {
        guard !finished else { return }
        finished = true
        connection?.cancel()
        deliver(.closed(reason))
    }

    private func deliver(_ event: Event) {
        let handler = handler
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(event) } }
    }

    private static func describe(_ error: NWError, host: String) -> String {
        switch error {
        case .posix(.ECONNREFUSED): "\(host) refused the connection."
        case .posix(.ETIMEDOUT): "\(host) didn't answer."
        case .dns: "There's no server called \(host)."
        case .tls: "The secure connection to \(host) failed."
        default: error.localizedDescription
        }
    }
}
