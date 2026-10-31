// Spartan — a smaller cousin of Gemini (spartan.mozz.us): gemtext pages over plain TCP on
// port 300. The request is the host, the path and the length of any data sent after it, and
// the answer starts with one digit: 2 for the page, 3 for a redirect on the same server, 4 and
// 5 for errors. A URL's query is sent as that data, and a "=:" line in a page is a link that
// asks for it first, which is how Spartan does searches and forms.

import Foundation
import Network

enum Spartan {
    static func fetch(_ url: URL, progress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> Reply {
        guard let host = url.host(percentEncoded: true), !host.isEmpty else {
            throw Net.Failure(errorDescription: "That address has no server in it.")
        }
        let path = url.path(percentEncoded: true)
        let data = Data((url.query(percentEncoded: false) ?? "").utf8)
        var request = Data("\(host) \(path.isEmpty ? "/" : path) \(data.count)\r\n".utf8)
        request.append(data)

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        let answer = try await Net.fetch(host: host, port: url.port ?? 300, parameters: NWParameters(tls: nil, tcp: tcp),
                                         request: request, progress: progress)

        guard let newline = answer.firstIndex(of: 10) else {
            throw Net.Failure(errorDescription: "The server's answer had no status line.")
        }
        var header = String(decoding: answer[..<newline], as: UTF8.self)
        if header.hasSuffix("\r") { header.removeLast() }
        guard let first = header.first, let status = first.wholeNumberValue, (2...5).contains(status) else {
            throw Net.Failure(errorDescription: "The server didn't answer in Spartan.")
        }
        let meta = header.dropFirst().trimmingCharacters(in: .whitespaces)
        return Reply(status: status, meta: meta, body: answer[answer.index(after: newline)...])
    }
}
