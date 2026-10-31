// Remote — the account, reached with the Mac's own sftp and ssh and the key they already
// use, never a password. Everything goes through sftp's batch mode rather than commands
// run on the far side, so a path is only ever an escaped argument to sftp and never reaches
// a remote shell. Every window shares one connection (ssh's ControlMaster), so after the
// first each listing or transfer starts at once.

import Foundation

struct RemoteFile: Identifiable, Hashable {
    var name: String
    var isFolder: Bool
    var isLink: Bool
    var size: Int64
    var modified: Date?
    /// Whether the listing gave the time of day; it gives only the date past six months.
    var hasTime = true

    var id: String { name }
    var sortDate: Date { modified ?? .distantPast }
    var sortSize: Int64 { isFolder ? -1 : size }
}

struct RemoteError: LocalizedError {
    var errorDescription: String?
    /// The account turned the key away, which the window explains how to fix.
    var keyRefused = false

    init(_ message: String, keyRefused: Bool = false) {
        errorDescription = message
        self.keyRefused = keyRefused
    }
}

enum Remote {
    /// user@host, or a Host alias from ~/.ssh/config, set in Settings.
    static var login: String {
        (UserDefaults.standard.string(forKey: "login") ?? "").trimmingCharacters(in: .whitespaces)
    }

    static let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.mbolding.offsite")

    /// Where the shared connection's socket lives. Not in the caches folder, whose path is
    /// too long for a socket's once ssh adds its own; a folder of our own in /tmp, which
    /// another user could have made first, so it's used only if it's ours and private.
    private static let sockets: String? = {
        let path = "/tmp/offsite-\(getuid())"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o777 == 0o700,
              (info.st_mode & S_IFMT) == S_IFDIR else { return nil }
        return path
    }()

    private static var options: [String] {
        var options = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=20", "-o", "ServerAliveInterval=30"]
        if let sockets {
            options += ["-o", "ControlMaster=auto", "-o", "ControlPath=\(sockets)/%C", "-o", "ControlPersist=120"]
        }
        return options
    }

    // MARK: Commands

    /// Runs sftp commands in order, stopping at the first that fails. Returns what they
    /// printed, without sftp's echo of each command.
    @discardableResult
    static func sftp(_ commands: [String]) async throws -> String {
        // One command a line, so a name with a line break would end its command and start
        // another, and sftp runs lines starting with ! in a shell on the Mac.
        guard !commands.contains(where: { $0.contains(where: \.isNewline) }) else {
            throw RemoteError("A name with a line break in it can't be sent.")
        }
        let output = try await run("/usr/bin/sftp", ["-b", "-"] + options + [try checkedLogin()],
                                   input: commands.joined(separator: "\n") + "\n")
        try check(output, tool: "sftp")
        return output.out.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("sftp> ") }
            .joined(separator: "\n")
    }

    /// One command run on the account, with no arguments from the user in it.
    static func ssh(_ command: String) async throws -> String {
        let output = try await run("/usr/bin/ssh", options + [try checkedLogin(), command])
        try check(output, tool: "ssh")
        return output.out
    }

    /// The files in a folder, not counting . and ..
    static func list(_ path: String) async throws -> [RemoteFile] {
        parse(try await sftp(["ls -lna \(quote(path))"]))
    }

    /// A path as one sftp argument: every space, quote, backslash and wildcard character
    /// escaped with a backslash. That's the form sftp reads the same way in every command,
    /// whether or not it expands wildcards there; inside double quotes it would take a
    /// backslash literally.
    static func quote(_ path: String) -> String {
        let special: Set<Character> = [" ", "\t", "\\", "\"", "'", "*", "?", "[", "]", "#"]
        var quoted = ""
        for c in path {
            if special.contains(c) { quoted.append("\\") }
            quoted.append(c)
        }
        return quoted.isEmpty ? "." : quoted
    }

    /// Joins a folder and a name; the home folder is "".
    static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : folder + "/" + name
    }

    /// sftp commands that delete a file, or a folder and everything in it, from the
    /// deepest up, since sftp can only remove a folder once it's empty.
    static func deletion(of path: String, isFolder: Bool) async throws -> [String] {
        guard isFolder else { return ["rm \(quote(path))"] }
        var commands: [String] = []
        for file in try await list(path) {
            commands += try await deletion(of: join(path, file.name), isFolder: file.isFolder && !file.isLink)
        }
        return commands + ["rmdir \(quote(path))"]
    }

    // MARK: Listing

    /// sftp's `ls -ln` lines, which it writes itself in one fixed form whatever the server:
    /// mode, links (or "?", as rsync.net sends), owner, group, size, then the time as "Oct 30 14:05" for the last six months
    /// or "Oct 30  2024" before, and the name after one space.
    private static let line = #/^([dlbcps-][^ ]*) +\S+ +\S+ +\S+ +(\d+) +([A-Z][a-z]{2}) +(\d{1,2}) +(\d{1,2}:\d{2}|\d{4}) (.*)$/#

    static func parse(_ output: String, now: Date = Date()) -> [RemoteFile] {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        return output.split(separator: "\n").compactMap { text in
            guard let match = String(text).wholeMatch(of: line) else { return nil }
            let mode = match.1, name = String(match.6)
            // sftp prints the folder's own path as the start of each name when it's given one.
            let shortName = name.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? name
            guard shortName != ".", shortName != "..", !shortName.isEmpty else { return nil }

            var parts = DateComponents()
            parts.month = (months.firstIndex(of: String(match.3)) ?? 0) + 1
            parts.day = Int(match.4)
            if match.5.contains(":") {
                let clock = match.5.split(separator: ":")
                parts.hour = Int(clock[0])
                parts.minute = Int(clock[1])
                parts.year = year
                // A time means the last six months, so a date ahead of today was last year.
                if let date = calendar.date(from: parts), date > now.addingTimeInterval(86_400) {
                    parts.year = year - 1
                }
            } else {
                parts.year = Int(match.5)
            }
            return RemoteFile(name: shortName, isFolder: mode.hasPrefix("d"), isLink: mode.hasPrefix("l"),
                              size: Int64(match.2) ?? 0, modified: calendar.date(from: parts),
                              hasTime: match.5.contains(":"))
        }
    }

    // MARK: Running

    private static func checkedLogin() throws -> String {
        let login = self.login
        // Taken as one argument, but a leading dash would still read as an option.
        guard !login.isEmpty, !login.hasPrefix("-"), !login.contains(where: \.isWhitespace) else {
            throw RemoteError("Set the account in Settings (⌘,), as user@host or a Host from ~/.ssh/config.")
        }
        return login
    }

    private static func check(_ output: Output, tool: String) throws {
        guard output.status != 0 else { return }
        let message = output.err.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("sftp> ") }
            .joined(separator: "\n")
        if message.contains("Permission denied (publickey") || message.contains("Too many authentication failures") {
            throw RemoteError("\(login) didn't accept this Mac's SSH key.", keyRefused: true)
        }
        throw RemoteError(message.isEmpty ? "\(tool) to \(login) failed (\(output.status))." : String(message.suffix(400)))
    }

    struct Output {
        var out: String
        var err: String
        var status: Int32
    }

    /// Lets a cancelled task stop the process it started, whether or not it's begun yet.
    private final class Running: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var cancelled = false

        /// Starts the process unless it's been cancelled already.
        func start() throws -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if cancelled { return false }
            try process.run()
            return true
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            if process.isRunning { process.terminate() }
        }

        var wasCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    static func run(_ tool: String, _ arguments: [String], input: String? = nil) async throws -> Output {
        let running = Running()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    let process = running.process
                    process.executableURL = URL(fileURLWithPath: tool)
                    process.arguments = arguments
                    // Names as UTF-8, and sftp's dates in English whatever the Mac's language,
                    // so they can be read back.
                    var environment = ProcessInfo.processInfo.environment
                    environment["LC_ALL"] = nil
                    environment["LC_CTYPE"] = "en_US.UTF-8"
                    environment["LC_TIME"] = "C"
                    process.environment = environment
                    let out = Pipe(), err = Pipe(), inp = Pipe()
                    process.standardOutput = out
                    process.standardError = err
                    process.standardInput = input == nil ? FileHandle.nullDevice : inp
                    do {
                        guard try running.start() else { return continuation.resume(throwing: CancellationError()) }
                    } catch {
                        return continuation.resume(throwing: error)
                    }
                    if let input {
                        DispatchQueue.global().async {
                            inp.fileHandleForWriting.write(Data(input.utf8))
                            try? inp.fileHandleForWriting.close()
                        }
                    }
                    // Read both while it runs, so a full pipe can't stall it.
                    var errData = Data()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        errData = err.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    let outData = out.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()
                    if running.wasCancelled { return continuation.resume(throwing: CancellationError()) }
                    continuation.resume(returning: Output(out: String(decoding: outData, as: UTF8.self),
                                                          err: String(decoding: errData, as: UTF8.self),
                                                          status: process.terminationStatus))
                }
            }
        } onCancel: {
            running.cancel()
        }
    }
}
