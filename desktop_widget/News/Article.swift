// Article — what a news article is made of (RFC 5536, which leans on email's RFC 5322 and
// MIME): headers, a blank line, and a body. Headers may carry encoded words for anything
// past ASCII (RFC 2047), bodies may be quoted-printable or base64, in any charset, sometimes
// in parts, and sometimes "flowed" so paragraphs can be rewrapped (RFC 3676).

import Foundation

/// One line of a group's overview: enough to list an article without fetching it.
struct Overview: Identifiable, Hashable {
    var number: Int
    var subject: String
    var from: String
    var date: Date?
    var messageID: String
    var references: [String]
    var lines: Int

    var id: Int { number }

    /// Reads a tab-separated OVER line, in the order RFC 3977 fixes.
    init?(line: String) {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 8, let number = Int(fields[0]) else { return nil }
        self.number = number
        subject = Headers.decode(fields[1])
        from = Headers.decode(fields[2])
        date = Headers.date(fields[3])
        messageID = fields[4].trimmingCharacters(in: .whitespaces)
        references = Headers.messageIDs(fields[5])
        lines = Int(fields[7].trimmingCharacters(in: .whitespaces)) ?? 0
    }

    var author: String { Headers.name(from) }
}

struct Article {
    /// Headers in order, decoded, with continuation lines joined.
    var headers: [(name: String, value: String)] = []
    var body: String = ""
    /// Whether the body arrived as format=flowed, so its paragraphs were joined.
    var flowed = false

    func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var subject: String { header("Subject") ?? "" }
    var from: String { header("From") ?? "" }
    var date: Date? { header("Date").flatMap(Headers.date) }
    var messageID: String { header("Message-ID")?.trimmingCharacters(in: .whitespaces) ?? "" }
    var references: [String] { Headers.messageIDs(header("References") ?? "") }
    var newsgroups: String { header("Newsgroups") ?? "" }

    init(lines: [[UInt8]]) {
        let split = lines.firstIndex(where: \.isEmpty) ?? lines.endIndex
        var raw: [(String, String)] = []
        for line in lines[..<split] {
            let text = NNTPSession.text(line)
            if let first = text.first, first == " " || first == "\t", !raw.isEmpty {
                raw[raw.count - 1].1 += " " + text.trimmingCharacters(in: .whitespaces)
            } else if let colon = text.firstIndex(of: ":") {
                raw.append((String(text[..<colon]), text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
            }
        }
        headers = raw.map { ($0.0, Headers.decode($0.1)) }

        let rawHeaders = Dictionary(raw.map { ($0.0.lowercased(), $0.1) }, uniquingKeysWith: { first, _ in first })
        var bodyBytes: [UInt8] = []
        for (n, line) in lines[min(split + 1, lines.endIndex)...].enumerated() {
            if n > 0 { bodyBytes += [10] }
            bodyBytes += line
        }
        (body, flowed) = MIME.text(of: bodyBytes, contentType: rawHeaders["content-type"] ?? "text/plain",
                                   encoding: rawHeaders["content-transfer-encoding"] ?? "8bit")
    }
}

// MARK: - Headers

enum Headers {
    /// Undoes RFC 2047 encoded words, `=?charset?Q|B?text?=`, joining ones only whitespace apart.
    static func decode(_ value: String) -> String {
        guard value.contains("=?") else { return value }
        let pattern = #/=\?([^?\s]+)\?([QqBb])\?([^?\s]*)\?=/#
        var out = ""
        var rest = value[...]
        var lastWasWord = false
        while let match = rest.firstMatch(of: pattern) {
            let between = rest[..<match.range.lowerBound]
            if !(lastWasWord && between.allSatisfy(\.isWhitespace)) { out += between }
            let charset = String(match.output.1)
            let bytes: [UInt8]
            if match.output.2.uppercased() == "B" {
                bytes = Array(Data(base64Encoded: padded(String(match.output.3))) ?? Data())
            } else {
                bytes = MIME.quotedPrintable(Array(match.output.3.replacingOccurrences(of: "_", with: " ").utf8))
            }
            out += MIME.string(bytes, charset: charset)
            rest = rest[match.range.upperBound...]
            lastWasWord = true
        }
        return out + rest
    }

    private static func padded(_ base64: String) -> String {
        base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
    }

    /// Message ids in a References header, oldest first.
    static func messageIDs(_ value: String) -> [String] {
        value.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.hasPrefix("<") && $0.hasSuffix(">") }
    }

    /// The name in a From header, or the address where there's no name.
    static func name(_ from: String) -> String {
        if let open = from.firstIndex(of: "<") {
            let name = from[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !name.isEmpty { return name }
            return from[from.index(after: open)...].trimmingCharacters(in: CharacterSet(charactersIn: "> "))
        }
        // The old style: address (Name)
        if let open = from.firstIndex(of: "("), let close = from.lastIndex(of: ")"), open < close {
            return String(from[from.index(after: open)..<close])
        }
        return from
    }

    private static let dateFormats: [DateFormatter] = [
        "EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm Z",
        "EEE, d MMM yy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss zzz",
    ].map {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = $0
        return formatter
    }

    /// An RFC 5322 date, with any comment such as "(UTC)" taken off.
    static func date(_ value: String) -> Date? {
        var text = value
        if let open = text.firstIndex(of: "(") { text = String(text[..<open]) }
        text = text.trimmingCharacters(in: .whitespaces)
        for formatter in dateFormats {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    // MARK: Writing

    /// A header value as an encoded word if it isn't plain ASCII.
    static func encode(_ value: String) -> String {
        guard !value.allSatisfy({ $0.isASCII }) else { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

    /// "Name <address>", with the name encoded if it needs to be.
    static func from(name: String, address: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return address }
        let plain = name.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "." || $0 == "-" } && name.allSatisfy(\.isASCII)
        return "\(plain ? name : encode(name)) <\(address)>"
    }

    static func rfc5322(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}

// MARK: - Bodies

enum MIME {
    /// The readable text of a body: the first text/plain part of a multipart one, decoded
    /// from its transfer encoding and charset, with flowed paragraphs joined.
    static func text(of body: [UInt8], contentType: String, encoding: String) -> (String, Bool) {
        let type = parameters(contentType)
        if type.value.hasPrefix("multipart/"), let boundary = type.params["boundary"] {
            for part in parts(body, boundary: boundary) {
                let split = part.firstIndex(of: [])
                let headerLines = part[..<(split ?? part.endIndex)].map { NNTPSession.text($0) }
                var headers: [String: String] = [:]
                var last: String?
                for line in headerLines {
                    if let first = line.first, first == " " || first == "\t", let key = last {
                        headers[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
                    } else if let colon = line.firstIndex(of: ":") {
                        let key = line[..<colon].lowercased()
                        headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                        last = key
                    }
                }
                let partType = headers["content-type"] ?? "text/plain"
                guard parameters(partType).value == "text/plain" || parameters(partType).value.hasPrefix("multipart/") else { continue }
                let bodyLines = split.map { Array(part[($0 + 1)...]) } ?? []
                return text(of: Array(bodyLines.joined(separator: [10])), contentType: partType,
                            encoding: headers["content-transfer-encoding"] ?? "7bit")
            }
            return ("(This article has no plain text part to show.)", false)
        }

        var bytes = body
        switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
        case "quoted-printable": bytes = quotedPrintable(bytes)
        case "base64":
            let compact = bytes.filter { !$0.isWhitespace }
            bytes = Array(Data(base64Encoded: Data(compact), options: .ignoreUnknownCharacters) ?? Data(bytes))
        default: break
        }
        var text = string(bytes, charset: type.params["charset"] ?? "utf-8")
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        let flowed = type.params["format"]?.lowercased() == "flowed"
        if flowed { text = unflow(text, delsp: type.params["delsp"]?.lowercased() == "yes") }
        return (text, flowed)
    }

    /// A Content-Type value and its parameters, names lowercased and quotes taken off.
    static func parameters(_ header: String) -> (value: String, params: [String: String]) {
        let pieces = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var params: [String: String] = [:]
        for piece in pieces.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            let name = piece[..<equals].lowercased().trimmingCharacters(in: .whitespaces)
            params[name] = piece[piece.index(after: equals)...].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        }
        return ((pieces.first ?? "").lowercased(), params)
    }

    private static func parts(_ body: [UInt8], boundary: String) -> [[[UInt8]]] {
        let lines = body.split(separator: 10, omittingEmptySubsequences: false).map { line -> [UInt8] in
            line.last == 13 ? Array(line.dropLast()) : Array(line)
        }
        let open = Array("--\(boundary)".utf8), close = Array("--\(boundary)--".utf8)
        var parts: [[[UInt8]]] = []
        var current: [[UInt8]]?
        for line in lines {
            let trimmed = Array(line.reversed().drop { $0 == 32 || $0 == 9 }.reversed())
            if trimmed == close { break }
            if trimmed == open {
                if let part = current { parts.append(part) }
                current = []
            } else {
                current?.append(line)
            }
        }
        if let part = current { parts.append(part) }
        return parts
    }

    static func quotedPrintable(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte == 61 {                                // "="
                if i + 1 < bytes.count, bytes[i + 1] == 10 { i += 2; continue }     // soft line break
                if i + 2 < bytes.count, bytes[i + 1] == 13, bytes[i + 2] == 10 { i += 3; continue }
                if i + 2 < bytes.count, let value = UInt8(String(bytes: bytes[(i + 1)...(i + 2)], encoding: .ascii) ?? "", radix: 16) {
                    out.append(value)
                    i += 3
                    continue
                }
            }
            out.append(byte)
            i += 1
        }
        return out
    }

    /// Text in a named charset, falling back to UTF-8 and then Latin-1.
    static func string(_ bytes: [UInt8], charset: String) -> String {
        let name = charset.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) as CFString
        let cf = CFStringConvertIANACharSetNameToEncoding(name)
        if cf != kCFStringEncodingInvalidId {
            let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            if let text = String(bytes: bytes, encoding: encoding) { return text }
        }
        return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }

    /// Joins format=flowed lines: one ending in a space carries on into the next, unless
    /// it's the signature line or the quote depth changes.
    static func unflow(_ text: String, delsp: Bool) -> String {
        var out: [String] = []
        var carry: (depth: Int, text: String)?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            let depth = line.prefix { $0 == ">" }.count
            line.removeFirst(depth)
            if line.hasPrefix(" ") { line.removeFirst() }    // space-stuffing
            let soft = line.hasSuffix(" ") && line != "-- "
            if delsp && soft { line.removeLast() }
            if let pending = carry, pending.depth == depth {
                carry = (depth, pending.text + line)
            } else {
                if let pending = carry { out.append(quoted(pending.text, depth: pending.depth)) }
                carry = (depth, line)
            }
            if !soft, let pending = carry {
                out.append(quoted(pending.text, depth: pending.depth))
                carry = nil
            }
        }
        if let pending = carry { out.append(quoted(pending.text, depth: pending.depth)) }
        return out.joined(separator: "\n")
    }

    private static func quoted(_ text: String, depth: Int) -> String {
        depth == 0 ? text : String(repeating: ">", count: depth) + " " + text
    }

    /// Wraps typed text for posting as format=flowed: long lines are broken at spaces near
    /// 72 columns, each broken line ending in a space so readers can join them again.
    /// Quoted lines are left as they are.
    static func flow(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            // Trailing spaces would read as soft breaks, so a typed line loses them, save the signature line.
            var line = raw == "-- " ? String(raw) : String(raw.reversed().drop { $0 == " " }.reversed())
            if line.hasPrefix(" ") || line.hasPrefix("From ") { line = " " + line }   // space-stuffing
            guard !line.hasPrefix(">"), line.count > 78 else {
                out.append(line)
                continue
            }
            var rest = Substring(line)
            while rest.count > 78 {
                let window = rest.prefix(72)
                guard let space = window.lastIndex(of: " "), space > rest.startIndex else {
                    // One long word: break after it instead.
                    guard let next = rest.dropFirst(72).firstIndex(of: " ") else { break }
                    out.append(String(rest[...next]))
                    rest = rest[rest.index(after: next)...]
                    continue
                }
                out.append(String(rest[...space]))
                rest = rest[rest.index(after: space)...]
            }
            out.append(String(rest))
        }
        return out
    }
}

private extension UInt8 {
    var isWhitespace: Bool { self == 32 || self == 9 || self == 10 || self == 13 }
}

// MARK: - Threads

/// A row of the thread list: an article and how deep it sits under the one that started it.
struct ThreadRow: Identifiable, Hashable {
    var article: Overview
    var depth: Int
    /// Whether this starts a thread, so the list can space threads apart.
    var root: Bool
    /// Whether its subject says something new, rather than "Re:" its parent's.
    var newSubject: Bool

    var id: Int { article.number }
}

enum Threads {
    /// Arranges articles into threads by their References, newest activity first, each
    /// thread's replies in the order they were written.
    static func rows(_ articles: [Overview]) -> [ThreadRow] {
        let byID = Dictionary(articles.map { ($0.messageID, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [String: [Overview]] = [:]
        var roots: [Overview] = []
        for article in articles {
            // The nearest ancestor that's here, since older ones may have expired.
            if let parent = article.references.last(where: { byID[$0] != nil && $0 != article.messageID }) {
                children[parent, default: []].append(article)
            } else {
                roots.append(article)
            }
        }
        func order(_ list: [Overview]) -> [Overview] {
            list.sorted { ($0.date ?? .distantPast, $0.number) < ($1.date ?? .distantPast, $1.number) }
        }
        func latest(_ article: Overview) -> Date {
            (children[article.messageID] ?? []).map(latest).max().map { max($0, article.date ?? .distantPast) }
                ?? article.date ?? .distantPast
        }
        var rows: [ThreadRow] = []
        var seen = Set<String>()
        func add(_ article: Overview, depth: Int, parentSubject: String?) {
            guard seen.insert(article.messageID).inserted else { return }
            let subject = bare(article.subject)
            rows.append(ThreadRow(article: article, depth: depth, root: depth == 0, newSubject: subject != parentSubject))
            for child in order(children[article.messageID] ?? []) { add(child, depth: depth + 1, parentSubject: subject) }
        }
        let latestByRoot = Dictionary(roots.map { ($0.number, latest($0)) }, uniquingKeysWith: { first, _ in first })
        for root in roots.sorted(by: { latestByRoot[$0.number]! > latestByRoot[$1.number]! }) {
            add(root, depth: 0, parentSubject: nil)
        }
        return rows
    }

    /// A subject without its "Re:"s, to compare with another.
    static func bare(_ subject: String) -> String {
        var text = subject.trimmingCharacters(in: .whitespaces)
        while let colon = text.firstIndex(of: ":"), ["re", "aw", "sv", "antw"].contains(text[..<colon].lowercased()) {
            text = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}
