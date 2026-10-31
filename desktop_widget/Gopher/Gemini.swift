// Gemini — gopher's successor (geminiprotocol.net): the same one request and one answer,
// but over TLS on port 1965, with a full URL as the request and a status line before the
// body. Its pages are gemtext, a line-based format of text, links, headings, lists, quotes
// and preformatted blocks.
//
// Most servers sign their own certificates, so they're trusted the way SSH trusts hosts: the
// first one seen for a server is remembered, and a different one later stops the request,
// unless the Mac itself trusts the new one, as it does a renewed Let's Encrypt certificate.

import Foundation
import Network
import CryptoKit
import Security

struct GeminiResponse {
    var status: Int
    /// The prompt for input, the type of a page, where a redirect goes, or why it failed.
    var meta: String
    var body: Data
}

/// One line of a gemtext page, or a whole preformatted block.
struct GemLine: Identifiable {
    enum Kind {
        case text(String)
        case link(url: URL?, label: String)
        case heading(level: Int, text: String)
        case item(String)
        case quote(String)
        case preformatted(alt: String, text: String)
    }

    let id: Int
    let kind: Kind
}

enum Gemini {
    struct CertificateChanged: LocalizedError {
        var server: String
        var fingerprint: String
        var errorDescription: String? { "\(server)'s certificate isn't the one it had before." }
    }

    static func fetch(_ url: URL, progress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> GeminiResponse {
        guard let host = url.host, !host.isEmpty else {
            throw Net.Failure(errorDescription: "That address has no server in it.")
        }
        let port = url.port ?? 1965
        let trust = Trust(server: "\(host.lowercased()):\(port)")

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv12)
        sec_protocol_options_set_tls_server_name(security, host)
        sec_protocol_options_set_verify_block(security, { _, secTrust, complete in
            complete(trust.check(secTrust))
        }, trust.queue)

        let data: Data
        do {
            data = try await Net.fetch(host: host, port: port, parameters: NWParameters(tls: tls, tcp: tcp),
                                       request: Data((url.absoluteString + "\r\n").utf8), progress: progress)
        } catch {
            if let fingerprint = trust.changed {
                throw CertificateChanged(server: trust.server, fingerprint: fingerprint)
            }
            throw error
        }

        guard let newline = data.firstIndex(of: 10) else {
            throw Net.Failure(errorDescription: "The server's answer had no status line.")
        }
        var header = String(decoding: data[..<newline], as: UTF8.self)
        if header.hasSuffix("\r") { header.removeLast() }
        guard header.count >= 2, let status = Int(header.prefix(2)) else {
            throw Net.Failure(errorDescription: "The server didn't answer in Gemini.")
        }
        let meta = header.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return GeminiResponse(status: status, meta: meta, body: data[data.index(after: newline)...])
    }

    /// What a failure's status means, for servers that don't say.
    static func describe(_ status: Int) -> String {
        switch status {
        case 41: "The server is unavailable."
        case 42: "The server's script failed."
        case 43: "A proxy in the way failed."
        case 44: "The server asks you to slow down and try again later."
        case 51: "There's nothing at that address."
        case 52: "What was here is gone for good."
        case 53: "The server won't fetch pages for other servers."
        case 59: "The server didn't understand the request."
        case 40..<50: "The server couldn't answer just now."
        default: "The server couldn't answer."
        }
    }

    // MARK: Gemtext

    static func gemtext(_ text: String, base: URL) -> [GemLine] {
        var lines: [GemLine] = []
        var block: (alt: String, lines: [Substring])?
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            if line.hasPrefix("```") {
                if let open = block {
                    lines.append(GemLine(id: lines.count, kind: .preformatted(alt: open.alt, text: open.lines.joined(separator: "\n"))))
                    block = nil
                } else {
                    block = (String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
                }
                continue
            }
            if block != nil {
                block?.lines.append(line)
                continue
            }
            lines.append(GemLine(id: lines.count, kind: kind(of: line, base: base)))
        }
        if let open = block {
            lines.append(GemLine(id: lines.count, kind: .preformatted(alt: open.alt, text: open.lines.joined(separator: "\n"))))
        }
        // Trailing blank lines are only the end of the file.
        while case .text(let t)? = lines.last?.kind, t.isEmpty { lines.removeLast() }
        return lines
    }

    private static func kind(of line: Substring, base: URL) -> GemLine.Kind {
        if line.hasPrefix("=>") {
            let rest = line.dropFirst(2).drop { $0 == " " || $0 == "\t" }
            let end = rest.firstIndex { $0 == " " || $0 == "\t" } ?? rest.endIndex
            let link = String(rest[..<end])
            let label = rest[end...].trimmingCharacters(in: .whitespaces)
            return .link(url: resolve(link, against: base), label: label.isEmpty ? link : label)
        }
        for level in (1...3).reversed() where line.hasPrefix(String(repeating: "#", count: level)) {
            return .heading(level: level, text: line.dropFirst(level).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("* ") { return .item(line.dropFirst(2).trimmingCharacters(in: .whitespaces)) }
        if line.hasPrefix(">") { return .quote(line.dropFirst().trimmingCharacters(in: .whitespaces)) }
        return .text(String(line))
    }

    /// A link as written, made absolute, with any spaces or other loose characters escaped.
    static func resolve(_ link: String, against base: URL) -> URL? {
        if let url = URL(string: link, relativeTo: base) { return url.absoluteURL }
        let escaped = link.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(["#"])) ?? link
        return URL(string: escaped, relativeTo: base)?.absoluteURL
    }

    /// The title of a page: its first top-level heading.
    static func title(_ lines: [GemLine]) -> String? {
        for line in lines {
            if case .heading(1, let text) = line.kind, !text.isEmpty { return text }
        }
        return nil
    }

    // MARK: Trust on first use

    /// Checks one connection's certificate against the one remembered for its server.
    private final class Trust: @unchecked Sendable {
        let server: String
        let queue = DispatchQueue(label: "gemini.trust")
        /// The new certificate's fingerprint, when it didn't match.
        private(set) var changed: String?

        init(server: String) { self.server = server }

        func check(_ trust: sec_trust_t) -> Bool {
            let ref = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(ref) as? [SecCertificate], let leaf = chain.first else {
                return false
            }
            let fingerprint = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
                .map { String(format: "%02x", $0) }.joined()
            let known = KnownServers.fingerprint(for: server)
            if known == nil || known == fingerprint || SecTrustEvaluateWithError(ref, nil) {
                if known != fingerprint { KnownServers.remember(fingerprint, for: server) }
                return true
            }
            changed = fingerprint
            return false
        }
    }
}

/// The certificate each Gemini server showed last, by "host:port".
enum KnownServers {
    private static let key = "geminiServers"

    static func fingerprint(for server: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[server]
    }

    static func remember(_ fingerprint: String, for server: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        all[server] = fingerprint
        UserDefaults.standard.set(all, forKey: key)
    }
}
