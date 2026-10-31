// NNTP — Usenet's protocol (RFC 3977): one long-lived connection to a news server, lines of
// commands and status codes, and listings and articles that end with a lone full stop. Each
// server gets one connection, opened on first use, logged in if the server has a user name,
// and opened again if the server has dropped it for idling. Commands wait their turn, since
// the answers come back in order on the one connection.

import Foundation
import Network

struct NNTPError: LocalizedError {
    var errorDescription: String?
    /// The connection failed, rather than the server answering no, so it's worth trying again.
    var dropped = false
}

/// A group as the server lists it.
struct GroupInfo: Hashable {
    var name: String
    var low: Int
    var high: Int
    /// The server's estimate of how many articles it holds.
    var count: Int
    var postingAllowed = true
}

actor NNTPSession {
    let server: Server
    private var connection: NWConnection?
    private var buffer: [UInt8] = []
    private var start = 0
    private var selected: String?
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(server: Server) { self.server = server }

    deinit { connection?.cancel() }

    // MARK: What the app asks for

    func groups() async throws -> [GroupInfo] {
        try await exclusive {
            try await expect(command("LIST ACTIVE"), 215)
            return try await listing().compactMap { line in
                let fields = Self.text(line).split(separator: " ")
                guard fields.count >= 4, let high = Int(fields[1]), let low = Int(fields[2]) else { return nil }
                let count = high >= low ? high - low + 1 : 0
                return GroupInfo(name: String(fields[0]), low: low, high: high, count: count,
                                 postingAllowed: fields[3] != "n")
            }
        }
    }

    func group(_ name: String) async throws -> GroupInfo {
        try await exclusive { try await select(name) }
    }

    /// The overview of each article numbered in `range`: subject, author, date, ids and size.
    func overview(_ name: String, _ range: ClosedRange<Int>) async throws -> [Overview] {
        try await exclusive {
            _ = try await select(name)
            var reply = try await command("OVER \(range.lowerBound)-\(range.upperBound)")
            if reply.code == 500 { reply = try await command("XOVER \(range.lowerBound)-\(range.upperBound)") }
            if reply.code == 423 { return [] }             // none left in that range
            try expect(reply, 224)
            return try await listing().compactMap { Overview(line: Self.text($0)) }
        }
    }

    /// An article, by its number in a group or by its message id.
    func article(_ name: String, number: Int) async throws -> Article {
        try await exclusive {
            _ = try await select(name)
            try await expect(command("ARTICLE \(number)"), 220)
            return Article(lines: try await listing())
        }
    }

    func article(id: String) async throws -> Article {
        try await exclusive {
            try await expect(command("ARTICLE \(id)"), 220)
            return Article(lines: try await listing())
        }
    }

    /// Posts an article given as its lines, headers and body.
    func post(_ lines: [String]) async throws {
        try await exclusive {
            let reply = try await command("POST")
            if reply.code == 440 { throw NNTPError(errorDescription: "\(server.name) doesn't take posts.") }
            try expect(reply, 340)
            var data = Data()
            for line in lines {
                // A line starting with a full stop gets another, so it can't end the article.
                data.append(contentsOf: Array(((line.hasPrefix(".") ? "." : "") + line + "\r\n").utf8))
            }
            data.append(contentsOf: Array(".\r\n".utf8))
            try await send(data)
            let done = try await status()
            guard done.code == 240 else {
                throw NNTPError(errorDescription: "\(server.name) turned the post down: \(done.text)")
            }
        }
    }

    func close() {
        connection?.cancel()
        connection = nil
    }

    // MARK: One at a time

    /// Runs `body` with the connection to itself, trying once more on a fresh connection if
    /// the old one had been dropped.
    private func exclusive<T>(_ body: () async throws -> T) async throws -> T {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
        defer {
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        }
        if connection == nil {
            // A connection that failed to open or log in is no use to the next try.
            do { try await open() } catch { close(); throw error }
        }
        do {
            return try await body()
        } catch let error as NNTPError where error.dropped {
            close()
            do { try await open() } catch { close(); throw error }
            return try await body()
        } catch {
            if !(error is NNTPError) { close() }
            throw error
        }
    }

    private func select(_ name: String) async throws -> GroupInfo {
        let reply = try await command("GROUP \(name)")
        if reply.code == 411 { throw NNTPError(errorDescription: "\(server.name) has no group called \(name).") }
        try expect(reply, 211)
        let fields = reply.text.split(separator: " ")
        guard fields.count >= 3, let count = Int(fields[0]), let low = Int(fields[1]), let high = Int(fields[2]) else {
            throw NNTPError(errorDescription: "\(server.name) answered GROUP oddly: \(reply.text)")
        }
        selected = name
        return GroupInfo(name: name, low: low, high: high, count: count)
    }

    // MARK: Connecting

    private func open() async throws {
        buffer = []
        start = 0
        selected = nil
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        let parameters = NWParameters(tls: server.secure ? NWProtocolTLS.Options() : nil, tcp: tcp)
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: server.port)), server.port > 0 else {
            throw NNTPError(errorDescription: "\(server.port) isn't a port number.")
        }
        let connection = NWConnection(host: NWEndpoint.Host(server.host), port: port, using: parameters)
        let server = server
        let queue = DispatchQueue(label: "nntp.\(server.host)")
        self.connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // The handler only runs on `queue`, one call at a time.
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            connection.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready:
                    once.done = true
                    continuation.resume()
                case .waiting(let error), .failed(let error):
                    once.done = true
                    connection.cancel()
                    continuation.resume(throwing: Self.describe(error, server: server))
                case .cancelled:
                    once.done = true
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        let greeting = try await status()
        guard greeting.code == 200 || greeting.code == 201 else {
            throw NNTPError(errorDescription: "\(server.name) isn't taking readers: \(greeting.text)")
        }
        // Servers that do both feeding and reading need telling which this is; the rest say
        // they don't know the command, which is fine.
        _ = try await command("MODE READER")
        if !server.username.isEmpty { try await logIn() }
    }

    private func logIn() async throws {
        let user = try await command("AUTHINFO USER \(server.username)")
        if user.code == 281 { return }
        guard user.code == 381 else { throw NNTPError(errorDescription: "\(server.name) won't take a login: \(user.text)") }
        guard let password = Keychain.password(for: server), !password.isEmpty else {
            throw NNTPError(errorDescription: "There's no password for \(server.username) on \(server.name). Add it in Settings.")
        }
        let pass = try await command("AUTHINFO PASS \(password)")
        guard pass.code == 281 else {
            throw NNTPError(errorDescription: "\(server.name) didn't accept the user name and password: \(pass.text)")
        }
    }

    private static func describe(_ error: NWError, server: Server) -> NNTPError {
        switch error {
        case .posix(.ECONNREFUSED): NNTPError(errorDescription: "\(server.host) refused the connection on port \(server.port).")
        case .posix(.ETIMEDOUT): NNTPError(errorDescription: "\(server.host) didn't answer.")
        case .dns: NNTPError(errorDescription: "There's no server called \(server.host).")
        case .tls: NNTPError(errorDescription: "The secure connection to \(server.host) failed.")
        default: NNTPError(errorDescription: error.localizedDescription)
        }
    }

    // MARK: Lines

    struct Status {
        var code: Int
        var text: String
    }

    /// Sends a command and reads its status line. Errors never repeat the command, so a
    /// password never shows in one.
    private func command(_ line: String) async throws -> Status {
        try await send(Data((line + "\r\n").utf8))
        let reply = try await status()
        if reply.code == 480 {
            throw NNTPError(errorDescription: server.username.isEmpty
                ? "\(server.name) needs a login to read. Add a user name and password in Settings."
                : "\(server.name) didn't accept the login.")
        }
        if reply.code == 400 || reply.code == 503 {
            // The server is closing the connection, often for idling too long.
            throw NNTPError(errorDescription: reply.text, dropped: true)
        }
        return reply
    }

    private func expect(_ reply: Status, _ code: Int) throws {
        guard reply.code == code else {
            throw NNTPError(errorDescription: "\(server.name) said: \(reply.code) \(reply.text)")
        }
    }

    private func status() async throws -> Status {
        let line = Self.text(try await readLine())
        guard line.count >= 3, let code = Int(line.prefix(3)) else {
            throw NNTPError(errorDescription: "\(server.name) didn't answer in NNTP.", dropped: true)
        }
        return Status(code: code, text: line.dropFirst(3).trimmingCharacters(in: .whitespaces))
    }

    /// The lines of a listing or article, up to the lone full stop, with doubled leading stops undone.
    private func listing() async throws -> [[UInt8]] {
        var lines: [[UInt8]] = []
        while true {
            let line = try await readLine()
            if line == [46] { return lines }
            lines.append(line.first == 46 ? Array(line.dropFirst()) : line)
        }
    }

    private func readLine() async throws -> [UInt8] {
        var scan = start
        while true {
            while scan + 1 < buffer.count {
                if buffer[scan] == 13 && buffer[scan + 1] == 10 {
                    let line = Array(buffer[start..<scan])
                    start = scan + 2
                    if start > 1 << 20 {
                        buffer.removeFirst(start)
                        start = 0
                    }
                    return line
                }
                scan += 1
            }
            let before = buffer.count - start
            try await receive()
            scan = start + max(0, before - 1)
        }
    }

    private func receive() async throws {
        guard let connection else { throw NNTPError(errorDescription: "Not connected.", dropped: true) }
        // A server that goes quiet for a minute is given up on.
        let watchdog = DispatchWorkItem { connection.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)
        defer { watchdog.cancel() }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, complete, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if let error {
                    continuation.resume(throwing: NNTPError(errorDescription: error.localizedDescription, dropped: true))
                } else if complete {
                    continuation.resume(throwing: NNTPError(errorDescription: "The server closed the connection.", dropped: true))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
        buffer.append(contentsOf: data)
    }

    private func send(_ data: Data) async throws {
        guard let connection else { throw NNTPError(errorDescription: "Not connected.", dropped: true) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: NNTPError(errorDescription: error.localizedDescription, dropped: true))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// A line as text: UTF-8 if it is, Latin-1 if not, as older servers send.
    static func text(_ bytes: [UInt8]) -> String {
        String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }
}
