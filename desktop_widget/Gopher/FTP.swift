// FTP — the File Transfer Protocol (RFC 959), the way the great archives were reached before
// the web: anonymous and read-only. A control connection to port 21 carries commands and
// numbered replies; each listing or file comes over a second connection the server opens
// for it, in passive mode (EPSV, or PASV on older servers). Listings come as MLSD's facts
// where the server has it, and otherwise as LIST's `ls -l` (or DOS) lines, read as best
// they can be. Only anonymous logins: FTP sends passwords unencrypted.

import Foundation
import Network

enum FTP {
    struct Entry: Identifiable, Hashable {
        enum Kind { case directory, file, link }
        var id: String { name }
        var name: String
        var kind: Kind
        var size: Int?
        var modified: Date?
        /// Where a symbolic link points, if the listing says.
        var target: String?
    }

    struct Listing {
        /// The folder, from the server's root, ending in a slash.
        var path: String
        var entries: [Entry]
        /// What the server says on arriving: its welcome at the top, a folder's note below.
        var message: String
        /// Lines of the listing that couldn't be read, shown as they came.
        var unread: [String]
    }

    enum Result {
        case listing(Listing, raw: Data)
        case file(Data)
        /// A file too big to show, by the size the server gave; it's saved instead.
        case large(Int)
    }

    /// Files bigger than this are saved rather than shown.
    static let showLimit = 32 << 20

    struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    // MARK: Fetching

    /// A folder's listing or a file, whichever the address turns out to be: the server is
    /// asked to change to it first, and if it can't, it's fetched as a file.
    static func fetch(_ url: URL, progress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> Result {
        let session = try await Session.open(url)
        defer { session.close() }
        let path = Self.path(url)

        let cwd = try await session.command("CWD \(path)")
        if cwd.code / 100 == 2 {
            var message = cwd.note
            if path == "/" { message = [session.welcome, message].filter { !$0.isEmpty }.joined(separator: "\n\n") }
            var raw = Data()
            var machine = true
            do {
                try await session.transfer("MLSD", into: { raw.append($0); Task { @MainActor [n = raw.count] in progress(n) } })
            } catch let rejected as Session.Rejected where rejected.code / 100 == 5 {
                machine = false
                raw = Data()
                try await session.transfer("LIST", into: { raw.append($0); Task { @MainActor [n = raw.count] in progress(n) } })
            }
            var listing = machine ? Self.machineListing(raw) : Self.listing(raw)
            listing.path = path.hasSuffix("/") ? path : path + "/"
            listing.message = message
            return .listing(listing, raw: raw)
        }

        // Not a folder, so a file. A server that knows its size says so before it's sent.
        let size = try await session.size(path)
        if let size, size > showLimit { return .large(size) }
        var data = Data()
        do {
            try await session.transfer("RETR \(path)", into: { chunk in
                data.append(chunk)
                if data.count > showLimit { throw Failure("It's larger than \(showLimit >> 20) MB, too big to show. Save it instead.") }
                Task { @MainActor [n = data.count] in progress(n) }
            })
        } catch let rejected as Session.Rejected {
            throw Failure(cwd.code == 550 && rejected.code == 550 ? "There's nothing at that address." : rejected.message)
        }
        return .file(data)
    }

    /// Saves a file straight to disk as it comes, however large. `progress` hears the bytes
    /// so far and the size the server gave, if any.
    static func download(_ url: URL, to destination: URL,
                         progress: @escaping @MainActor (Int, Int?) -> Void = { _, _ in }) async throws -> Int {
        let session = try await Session.open(url)
        defer { session.close() }
        let path = Self.path(url)
        let size = try await session.size(path)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let file = try FileHandle(forWritingTo: destination)
        var count = 0
        do {
            try await session.transfer("RETR \(path)", into: { chunk in
                try file.write(contentsOf: chunk)
                count += chunk.count
                Task { @MainActor [count] in progress(count, size) }
            })
            try file.close()
        } catch {
            try? file.close()
            try? FileManager.default.removeItem(at: destination)
            if let rejected = error as? Session.Rejected { throw Failure(rejected.message) }
            throw error
        }
        return count
    }

    /// The path on the server an ftp:// URL names, from the root.
    static func path(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.isEmpty ? "/" : path
    }

    /// The address of something in a listing.
    static func url(for entry: Entry, in folder: URL) -> URL {
        var parts = URLComponents(url: folder, resolvingAgainstBaseURL: false)
        var path = folder.path(percentEncoded: false)
        if !path.hasSuffix("/") { path += "/" }
        path += entry.name + (entry.kind == .directory ? "/" : "")
        parts?.path = path
        return parts?.url ?? folder
    }

    /// The folder above, or nil at the root.
    static func parent(of url: URL) -> URL? {
        var path = url.path(percentEncoded: false)
        while path.hasSuffix("/") { path.removeLast() }
        guard !path.isEmpty else { return nil }
        path = String(path[...(path.lastIndex(of: "/") ?? path.startIndex)])
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.path = path.isEmpty ? "/" : path
        return parts?.url
    }

    private static let textExtensions: Set = [
        "txt", "text", "md", "me", "1st", "nfo", "diz", "asc", "readme", "msg", "lsm", "faq", "log", "lst",
        "c", "h", "cc", "cpp", "py", "pl", "sh", "rb", "s", "asm", "bas", "pas", "f", "lisp", "el", "tcl",
        "ini", "cfg", "conf", "csv", "tsv", "json", "xml", "htm", "html", "gmi", "tex", "bib", "diff", "patch",
        "md5", "sha1", "sha256", "sha512", "sum", "sums", "sig", "rfc", "man", "1", "2", "3", "4", "5", "6", "7", "8",
    ]
    private static let imageExtensions: Set = ["gif", "jpg", "jpeg", "png", "bmp", "tif", "tiff", "webp", "heic", "ico"]

    /// Whether to open it here: text and pictures not too big to show, and files with no
    /// extension at all, as READMEs and INDEXes often are.
    static func isViewable(_ entry: Entry) -> Bool {
        if let size = entry.size, size > showLimit { return false }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        if ext.isEmpty || entry.name.hasPrefix(".") { return (entry.size ?? 0) < 4 << 20 }
        return textExtensions.contains(ext) || imageExtensions.contains(ext)
    }

    /// Mostly printable, with no NULs: plain text, whatever its encoding.
    static func looksLikeText(_ data: Data) -> Bool {
        let sample = data.prefix(8192)
        guard !sample.contains(0) else { return false }
        let controls = sample.filter { $0 < 32 && ![9, 10, 12, 13, 27].contains($0) }.count
        return controls * 50 < max(sample.count, 1)
    }

    // MARK: Listings

    /// MLSD: `fact=value;fact=value; name`, with the type, size and time as facts.
    static func machineListing(_ data: Data) -> Listing {
        var entries: [Entry] = [], unread: [String] = []
        for line in lines(data) {
            guard let space = line.firstIndex(of: " ") else { unread.append(line); continue }
            let name = String(line[line.index(after: space)...])
            var facts: [String: String] = [:]
            for fact in line[..<space].split(separator: ";") {
                let pair = fact.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { facts[pair[0].lowercased()] = pair[1] }
            }
            let type = facts["type"]?.lowercased() ?? ""
            if type == "cdir" || type == "pdir" || name == "." || name == ".." { continue }
            let kind: Entry.Kind = type == "dir" ? .directory : type.contains("slink") ? .link : .file
            entries.append(Entry(name: name, kind: kind, size: (facts["size"] ?? facts["sizd"]).flatMap { Int($0) },
                                 modified: facts["modify"].flatMap(machineTime)))
        }
        return Listing(path: "/", entries: sorted(entries), message: "", unread: unread)
    }

    /// LIST: no standard at all, but nearly every server sends `ls -l` lines, and a few DOS ones.
    static func listing(_ data: Data) -> Listing {
        var entries: [Entry] = [], unread: [String] = []
        for line in lines(data) {
            if line.hasPrefix("total ") { continue }
            if let entry = unixEntry(line) ?? dosEntry(line) {
                if entry.name != "." && entry.name != ".." { entries.append(entry) }
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                unread.append(line)
            }
        }
        return Listing(path: "/", entries: sorted(entries), message: "", unread: unread)
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private static let unixLine = try! NSRegularExpression(pattern:
        #"^([-dlbcpsD])\S*\s+(?:\d+\s+)?(?:\S+\s+){0,2}?(\d+)\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{1,2}:\d{2}|\d{4})\s+(.*)$"#)

    private static func unixEntry(_ line: String) -> Entry? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = unixLine.firstMatch(in: line, range: range),
              let month = months.firstIndex(of: group(match, 3, line).lowercased()) else { return nil }
        var name = group(match, 6, line)
        var target: String?
        let type = group(match, 1, line)
        if type == "l", let arrow = name.range(of: " -> ") {
            target = String(name[arrow.upperBound...])
            name = String(name[..<arrow.lowerBound])
        }
        guard !name.isEmpty else { return nil }
        // A time instead of a year means within the last six months or so.
        let day = Int(group(match, 4, line)) ?? 1, yearOrTime = group(match, 5, line)
        var parts = DateComponents(month: month + 1, day: day)
        let calendar = Calendar(identifier: .gregorian)
        if yearOrTime.contains(":") {
            let hm = yearOrTime.split(separator: ":").compactMap { Int($0) }
            parts.hour = hm.first
            parts.minute = hm.last
            let now = Date()
            parts.year = calendar.component(.year, from: now)
            if let date = calendar.date(from: parts), date > now.addingTimeInterval(86400 * 2) { parts.year! -= 1 }
        } else {
            parts.year = Int(yearOrTime)
        }
        return Entry(name: name, kind: type == "d" || type == "D" ? .directory : type == "l" ? .link : .file,
                     size: Int(group(match, 2, line)), modified: calendar.date(from: parts), target: target)
    }

    private static let dosLine = try! NSRegularExpression(pattern:
        #"^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})\s*([AaPp][Mm])?\s+(<DIR>|\d+)\s+(.*)$"#)

    private static func dosEntry(_ line: String) -> Entry? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = dosLine.firstMatch(in: line, range: range) else { return nil }
        var year = Int(group(match, 3, line)) ?? 1970
        if year < 100 { year += year < 70 ? 2000 : 1900 }
        var hour = Int(group(match, 4, line)) ?? 0
        let half = group(match, 6, line).lowercased()
        if half == "pm" && hour < 12 { hour += 12 } else if half == "am" && hour == 12 { hour = 0 }
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(
            year: year, month: Int(group(match, 1, line)), day: Int(group(match, 2, line)),
            hour: hour, minute: Int(group(match, 5, line))))
        let size = group(match, 7, line)
        return Entry(name: group(match, 8, line), kind: size == "<DIR>" ? .directory : .file,
                     size: Int(size), modified: date)
    }

    private static func group(_ match: NSTextCheckingResult, _ n: Int, _ line: String) -> String {
        Range(match.range(at: n), in: line).map { String(line[$0]) } ?? ""
    }

    /// MLSD's YYYYMMDDHHMMSS, in UTC.
    private static func machineTime(_ s: String) -> Date? {
        let digits = s.prefix(14)
        guard digits.count == 14, let n = Int(digits) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: n / 10_000_000_000, month: n / 100_000_000 % 100,
                                                  day: n / 1_000_000 % 100, hour: n / 10_000 % 100,
                                                  minute: n / 100 % 100, second: n % 100))
    }

    private static func lines(_ data: Data) -> [String] {
        Gopher.text(data).split(omittingEmptySubsequences: true) { $0 == "\n" || $0 == "\r\n" }
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : String($0) }
    }

    /// Folders (and links) first, then by name as Finder sorts them, so rfc2 comes before rfc10.
    private static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted { a, b in
            // Links go with the folders, which on the archives they nearly always are.
            let folders = (a.kind != .file, b.kind != .file)
            if folders.0 != folders.1 { return folders.0 }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: The connections

    /// One conversation with a server: logged in anonymously, in binary mode.
    final class Session: @unchecked Sendable {
        struct Reply {
            var code: Int
            var lines: [String]
            /// The reply's text without its numbers.
            var text: String { lines.map(FTP.Session.strip).joined(separator: "\n") }
            /// The lines before the last, which servers fill with a folder's .message or a welcome.
            var note: String {
                lines.count > 1 ? lines.dropLast().map(FTP.Session.strip).joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }
        }

        struct Rejected: LocalizedError {
            var code: Int
            var message: String
            var errorDescription: String? { message }
        }

        private let control: Channel
        private let host: String
        private var buffer = Data()
        /// The server's greeting and login messages, its welcome.
        private(set) var welcome = ""

        private init(control: Channel, host: String) {
            self.control = control
            self.host = host
        }

        static func open(_ url: URL) async throws -> Session {
            guard let host = url.host(percentEncoded: false), !host.isEmpty else {
                throw Failure("That address has no server in it.")
            }
            if let user = url.user(percentEncoded: false), !["anonymous", "ftp"].contains(user.lowercased()) {
                throw Failure("Gopher Browser only logs in to FTP anonymously, since FTP sends passwords unencrypted.")
            }
            let session = Session(control: try await Channel.open(host: host, port: url.port ?? 21), host: host)
            do {
                try await session.login()
            } catch {
                session.close()
                throw error
            }
            return session
        }

        private func login() async throws {
            var hello = try await reply()
            while hello.code / 100 == 1 { hello = try await reply() } // 120: ready in a moment
            guard hello.code == 220 else { throw Failure("The server isn't taking connections: \(hello.text)") }
            var greeting = hello.text
            if hello.lines.count == 1 { greeting = "" } // a lone "220 (vsFTPd 3.0.3)" says nothing
            var login = try await command("USER anonymous")
            // The password for anonymous FTP was once your email address; a few servers still
            // want one that looks like it, so a placeholder goes, never the user's own.
            if login.code == 331 { login = try await command("PASS anonymous@example.com") }
            guard login.code / 100 == 2 else {
                throw Failure(login.code == 530 ? "The server doesn't let anyone in anonymously." : login.text)
            }
            welcome = [greeting, login.note].filter { !$0.isEmpty }.joined(separator: "\n\n")
            let binary = try await command("TYPE I")
            guard binary.code / 100 == 2 else { throw Failure(binary.text) }
        }

        func close() {
            control.send("QUIT\r\n")
            control.close()
        }

        func command(_ line: String) async throws -> Reply {
            control.send(line + "\r\n")
            return try await reply()
        }

        /// The server's size for a file, if it says.
        func size(_ path: String) async throws -> Int? {
            let answer = try await command("SIZE \(path)")
            guard answer.code == 213 else { return nil }
            return Int(Self.strip(answer.lines.last ?? "").trimmingCharacters(in: .whitespaces))
        }

        /// Runs a command whose answer comes over a data connection, handing it on as it
        /// arrives, then waits for the server to say it's all sent.
        @discardableResult
        func transfer(_ line: String, into sink: (Data) throws -> Void) async throws -> Int {
            let data = try await passive()
            defer { data.close() }
            let start = try await command(line)
            guard start.code == 125 || start.code == 150 else {
                throw Rejected(code: start.code, message: start.text)
            }
            var count = 0
            while let chunk = try await data.receive() {
                try sink(chunk)
                count += chunk.count
            }
            // Some servers (ProFTPD) wait for this side to close before saying it's done.
            data.close()
            let done = try await reply()
            guard done.code / 100 == 2 else { throw Rejected(code: done.code, message: done.text) }
            return count
        }

        /// A data connection, to the port the server opens for it.
        private func passive() async throws -> Channel {
            let extended = try await command("EPSV")
            if extended.code == 229, let port = Self.epsvPort(extended.text) {
                return try await Channel.open(host: host, port: port)
            }
            let plain = try await command("PASV")
            guard plain.code == 227, let port = Self.pasvPort(plain.text) else {
                throw Failure("The server wouldn't open a connection for the data: \(plain.text)")
            }
            // The address in the reply is often a private one behind the server's router, so
            // the data goes to the same server as the commands, as most clients do now.
            return try await Channel.open(host: host, port: port)
        }

        /// "229 Entering Extended Passive Mode (|||6446|)"
        private static func epsvPort(_ text: String) -> Int? {
            guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return nil }
            let inner = text[text.index(after: open)..<close]
            guard let mark = inner.first else { return nil }
            return inner.split(separator: mark, omittingEmptySubsequences: false).dropFirst(3).first.flatMap { Int($0) }
        }

        /// "227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)"
        private static func pasvPort(_ text: String) -> Int? {
            let numbers = text.split { !$0.isNumber && $0 != "," }.last?.split(separator: ",").compactMap { Int($0) } ?? []
            guard numbers.count == 6 else { return nil }
            return numbers[4] * 256 + numbers[5]
        }

        /// One reply, of one line or several: "123-first", …, "123 last".
        private func reply() async throws -> Reply {
            var lines: [String] = []
            var code: Int?
            while true {
                let line = try await nextLine()
                let number = line.count >= 3 ? Int(line.prefix(3)) : nil
                let mark = line.count >= 4 ? line[line.index(line.startIndex, offsetBy: 3)] : " "
                if code == nil {
                    guard let number else { throw Failure("The server didn't answer in FTP.") }
                    code = number
                    lines.append(line)
                    if mark != "-" { break }
                } else {
                    lines.append(line)
                    if number == code && mark == " " { break }
                }
            }
            return Reply(code: code ?? 0, lines: lines)
        }

        private func nextLine() async throws -> String {
            while true {
                if let newline = buffer.firstIndex(of: 10) {
                    var line = buffer[..<newline]
                    if line.last == 13 { line = line.dropLast() }
                    buffer = Data(buffer[buffer.index(after: newline)...])
                    return Gopher.text(Data(line))
                }
                guard let chunk = try await control.receive() else {
                    throw Failure("The server closed the connection.")
                }
                buffer.append(chunk)
            }
        }

        fileprivate static func strip(_ line: String) -> String {
            let prefix = line.prefix(4)
            if prefix.count == 4, prefix.prefix(3).allSatisfy(\.isNumber), prefix.last == "-" || prefix.last == " " {
                return String(line.dropFirst(4))
            }
            return line.hasPrefix(" ") ? String(line.dropFirst()) : line
        }
    }

    /// A TCP connection to read and write in turn, which gives up on a server that goes
    /// quiet for half a minute.
    final class Channel: @unchecked Sendable {
        private let connection: NWConnection
        private let queue = DispatchQueue(label: "gopher.ftp")
        /// The server has closed its side, which can come with the last of the data.
        private let ended = Once()

        private init(_ connection: NWConnection) { self.connection = connection }

        static func open(host: String, port: Int) async throws -> Channel {
            guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port.rawValue > 0 else {
                throw Failure("\(port) isn't a port number.")
            }
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = 15
            let channel = Channel(NWConnection(host: NWEndpoint.Host(host), port: port, using: NWParameters(tls: nil, tcp: tcp)))
            try await channel.start()
            return channel
        }

        private func start() async throws {
            let once = Once()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready: once.run { continuation.resume() }
                        case .waiting(let error), .failed(let error): once.run { continuation.resume(throwing: Self.describe(error)) }
                        case .cancelled: once.run { continuation.resume(throwing: CancellationError()) }
                        default: break
                        }
                    }
                    connection.start(queue: queue)
                }
            } onCancel: { [connection] in connection.cancel() }
        }

        func send(_ text: String) {
            connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
        }

        /// The next bytes, or nil once the server has closed its side.
        func receive() async throws -> Data? {
            if ended.hasRun { return nil }
            let once = Once()
            let quiet = Once() // run when the server has said nothing for too long
            let timer = DispatchWorkItem { [connection] in quiet.run {}; connection.cancel() }
            queue.asyncAfter(deadline: .now() + 30, execute: timer)
            defer { timer.cancel() }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [ended] content, _, complete, error in
                        once.run {
                            if complete { ended.run {} }
                            if let content, !content.isEmpty {
                                continuation.resume(returning: content)
                            } else if complete {
                                continuation.resume(returning: nil)
                            } else if let error {
                                if quiet.hasRun {
                                    continuation.resume(throwing: Failure("The server stopped answering."))
                                } else if case .posix(let code) = error, code == .ECONNRESET || code == .ENODATA {
                                    // The server closing (which Network reports as "no data")
                                    // or resetting after the data is the end of it.
                                    continuation.resume(returning: nil)
                                } else if case .posix(.ECANCELED) = error {
                                    continuation.resume(throwing: CancellationError())
                                } else {
                                    continuation.resume(throwing: Self.describe(error))
                                }
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                    }
                }
            } onCancel: { [connection] in connection.cancel() }
        }

        func close() { connection.cancel() }

        private static func describe(_ error: NWError) -> Error {
            switch error {
            case .posix(.ECONNREFUSED): Failure("The server refused the connection.")
            case .posix(.ETIMEDOUT): Failure("The server didn't answer.")
            case .dns: Failure("There's no server by that name.")
            default: Failure(error.localizedDescription)
            }
        }
    }

    /// Runs its block the first time only, so a continuation is resumed once.
    private final class Once: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        var hasRun: Bool { lock.lock(); defer { lock.unlock() }; return done }
        func run(_ block: () -> Void) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { block() }
        }
    }
}
