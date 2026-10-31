// Finger — the oldest of them (RFC 1288): a name and a CRLF to port 79, and the server sends
// back what it says about that user, or about who's on if the name is left out. Addresses are
// finger://host/user, or finger://user@host as some write them.

import Foundation
import Network

enum Finger {
    /// The user a finger:// URL asks about, which may be none.
    static func user(_ url: URL) -> String {
        if let user = url.user(percentEncoded: false), !user.isEmpty { return user }
        return String(url.path(percentEncoded: false).drop { $0 == "/" })
    }

    static func fetch(_ url: URL, progress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> Data {
        guard let host = url.host, !host.isEmpty else {
            throw Net.Failure(errorDescription: "That address has no server in it.")
        }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        return try await Net.fetch(host: host, port: url.port ?? 79, parameters: NWParameters(tls: nil, tcp: tcp),
                                   request: Data((user(url) + "\r\n").utf8), progress: progress)
    }
}
