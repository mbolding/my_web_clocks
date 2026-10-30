// Gopher — the protocol (RFC 1436): open a TCP connection, send a selector and a CRLF,
// read until the server closes. Addresses are gopher:// URLs as RFC 4266 writes them, and a
// menu is lines of a type character, then tab-separated display text, selector, host and port.

import Foundation
import Network

/// Where a page lives: a server, a selector on it, and the type of what's there, which
/// says how to show it, since the server sends no headers.
struct Address: Hashable, Codable {
    var host: String
    var port = 70
    var type: Character = "1"
    var selector = ""
    /// The words for a search (type 7), sent after a tab.
    var query: String?

    enum CodingKeys: CodingKey { case url }

    init(host: String, port: Int = 70, type: Character = "1", selector: String = "", query: String? = nil) {
        self.host = host
        self.port = port
        self.type = type
        self.selector = selector
        self.query = query
    }

    /// Reads `gopher://host[:port]/[type[selector]]`, the scheme optional, with `%09`
    /// before a search's words.
    init?(_ text: String) {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = rest.range(of: "://") {
            guard rest[..<scheme.lowerBound].lowercased() == "gopher" else { return nil }
            rest = String(rest[scheme.upperBound...])
        }
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        var server = String(rest[..<slash])
        let path = rest[slash...].dropFirst()

        if let colon = server.lastIndex(of: ":"), !server.hasSuffix("]"),
           let port = Int(server[server.index(after: colon)...]) {
            self.port = port
            server = String(server[..<colon])
        }
        guard !server.isEmpty, !server.contains(" ") else { return nil }
        host = server.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if let type = path.first {
            self.type = type
            let selector = String(path.dropFirst()).removingPercentEncoding ?? String(path.dropFirst())
            if let tab = selector.firstIndex(of: "\t") {
                self.selector = String(selector[..<tab])
                query = String(selector[selector.index(after: tab)...])
            } else {
                self.selector = selector
            }
        }
    }

    var url: String {
        let server = host.contains(":") ? "[\(host)]" : host
        var url = "gopher://\(server)\(port == 70 ? "" : ":\(port)")/"
        if type == "1" && selector.isEmpty && query == nil { return url }
        url.append(type)
        url += Self.escape(selector)
        if let query { url += "%09" + Self.escape(query) }
        return url
    }

    private static let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "%"))
    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    init(from decoder: Decoder) throws {
        let url = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .url)
        guard let address = Address(url) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.url], debugDescription: url))
        }
        self = address
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
    }
}

/// How each item type is shown and opened. Types past RFC 1436's own (`g`, `I`, `h`, `i`
/// and the rest) are the ones gopher servers settled on since.
enum Kind {
    case menu, text, search, image, web, download, telnet, error, info, unsupported

    init(_ type: Character) {
        switch type {
        case "1", "+": self = .menu
        case "0": self = .text
        case "7": self = .search
        case "g", "I", "p": self = .image
        case "h": self = .web
        case "4", "5", "6", "9", "d", "P", "s", ";", "r", "x", "c", "M": self = .download
        case "8", "T": self = .telnet
        case "3": self = .error
        case "i": self = .info
        default: self = .unsupported
        }
    }

    var symbol: String {
        switch self {
        case .menu: "folder"
        case .text: "doc.text"
        case .search: "magnifyingglass"
        case .image: "photo"
        case .web: "globe"
        case .download: "arrow.down.circle"
        case .telnet: "terminal"
        case .error: "exclamationmark.triangle"
        case .info: ""
        case .unsupported: "questionmark.square"
        }
    }

    var name: String {
        switch self {
        case .menu: "Menu"
        case .text: "Text"
        case .search: "Search"
        case .image: "Picture"
        case .web: "Web page"
        case .download: "File to save"
        case .telnet: "Telnet session"
        case .error: "Error"
        case .info: ""
        case .unsupported: "Unknown type"
        }
    }
}

/// One line of a menu.
struct Item: Identifiable {
    let id: Int
    var type: Character
    var display: String
    var selector: String
    var host: String
    var port: Int

    var kind: Kind { Kind(type) }
    var address: Address { Address(host: host, port: port, type: type, selector: selector) }

    /// For a web link, the page it points to, from the `URL:` selector servers use for them.
    var webURL: URL? {
        guard kind == .web, selector.hasPrefix("URL:") || selector.hasPrefix("/URL:") else { return nil }
        let link = selector.drop { $0 == "/" }.dropFirst(4)
        return URL(string: String(link))
    }

    /// What the status bar shows while the pointer is over it.
    var location: String {
        if let webURL { return webURL.absoluteString }
        if kind == .telnet { return "telnet://\(host)\(port == 23 ? "" : ":\(port)")" }
        return address.url
    }
}

enum Gopher {
    struct Failure: LocalizedError {
        var errorDescription: String?
    }

    /// Text as servers send it: UTF-8 these days, Latin-1 on older servers.
    static func text(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func lines(_ data: Data) -> [Substring] {
        let lines = text(data).split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
            .map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
        // A lone full stop ends the listing; anything after it is padding.
        if let end = lines.firstIndex(of: ".") { return Array(lines[..<end]) }
        return lines
    }

    static func menu(_ data: Data) -> [Item] {
        lines(data).enumerated().compactMap { n, line in
            guard let type = line.first else { return nil }
            let fields = line.dropFirst().split(separator: "\t", omittingEmptySubsequences: false)
            // A line without the fields is read as plain text, as most clients do.
            guard fields.count >= 4 else {
                return Item(id: n, type: "i", display: String(line), selector: "", host: "", port: 70)
            }
            return Item(id: n, type: type, display: String(fields[0]), selector: String(fields[1]),
                        host: String(fields[2]), port: Int(fields[3].trimmingCharacters(in: .whitespaces)) ?? 70)
        }
    }

    /// A text file, with the full stop that ends it taken off and doubled leading stops undone.
    static func document(_ data: Data) -> String {
        lines(data).map { $0.hasPrefix("..") ? $0.dropFirst() : $0 }.joined(separator: "\n")
    }

    /// Fetches what's at an address. `progress` hears the bytes so far, on the main actor.
    static func fetch(_ address: Address, limit: Int = 256 << 20,
                      progress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> Data {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: address.port)) else {
            throw Failure(errorDescription: "\(address.port) isn't a port number.")
        }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        let connection = NWConnection(host: NWEndpoint.Host(address.host), port: port,
                                      using: NWParameters(tls: nil, tcp: tcp))
        let request = address.selector + (address.query.map { "\t" + $0 } ?? "") + "\r\n"
        let fetch = Fetch(connection, request: Data(request.utf8), limit: limit, progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { fetch.start($0) }
        } onCancel: {
            fetch.cancel()
        }
    }

    /// One request's state, touched only on its own serial queue.
    private final class Fetch: @unchecked Sendable {
        private let connection: NWConnection
        private let request: Data
        private let limit: Int
        private let progress: @MainActor (Int) -> Void
        private let queue = DispatchQueue(label: "gopher.fetch")
        private var continuation: CheckedContinuation<Data, Error>?
        private var data = Data()
        private var lastByte = Date()

        init(_ connection: NWConnection, request: Data, limit: Int, progress: @escaping @MainActor (Int) -> Void) {
            self.connection = connection
            self.request = request
            self.limit = limit
            self.progress = progress
        }

        func start(_ continuation: CheckedContinuation<Data, Error>) {
            queue.async { [self] in
                self.continuation = continuation
                connection.stateUpdateHandler = { [self] state in
                    switch state {
                    case .ready:
                        connection.send(content: request, completion: .contentProcessed { [self] error in
                            if let error { finish(.failure(error)) }
                        })
                        receive()
                    case .waiting(let error), .failed(let error):
                        finish(.failure(Self.describe(error)))
                    case .cancelled:
                        finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                watch()
            }
        }

        func cancel() {
            queue.async { [self] in finish(.failure(CancellationError())) }
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] content, _, complete, error in
                if let content {
                    data.append(content)
                    lastByte = Date()
                    let count = data.count
                    Task { @MainActor [progress] in progress(count) }
                }
                if data.count > limit {
                    finish(.failure(Failure(errorDescription: "It's larger than \(limit >> 20) MB, so it was stopped.")))
                } else if complete {
                    finish(.success(data))
                } else if let error {
                    // A server that resets instead of closing has usually sent it all.
                    data.isEmpty ? finish(.failure(Self.describe(error))) : finish(.success(data))
                } else {
                    receive()
                }
            }
        }

        /// Gives up on a server that stops sending for half a minute.
        private func watch() {
            queue.asyncAfter(deadline: .now() + 5) { [self] in
                guard continuation != nil else { return }
                if Date().timeIntervalSince(lastByte) > 30 {
                    finish(.failure(Failure(errorDescription: "The server stopped answering.")))
                } else {
                    watch()
                }
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation.resume(with: result)
        }

        private static func describe(_ error: NWError) -> Error {
            switch error {
            case .posix(.ECONNREFUSED): Failure(errorDescription: "The server refused the connection.")
            case .posix(.ETIMEDOUT): Failure(errorDescription: "The server didn't answer.")
            case .dns: Failure(errorDescription: "There's no server by that name.")
            default: Failure(errorDescription: error.localizedDescription)
            }
        }
    }
}
