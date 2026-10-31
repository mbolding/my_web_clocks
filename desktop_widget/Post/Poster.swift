// Poster — the draft, kept as it's typed, and posting it. A post goes to SDF over the Mac's
// own ssh, with the key it already uses, never a password: first to read the phlog's text
// files, which are the record of every post, then to send the new post with every page and
// index made again from that record, so the web blog, phlog and gemlog always agree.
// Everything sent rides as base64 inside the script, so nothing typed reaches the shell.

import AppKit

@MainActor
final class Poster: ObservableObject {
    static let shared = Poster()

    enum State: Equatable {
        case idle
        case working(String)
        case posted(title: String, web: String, gopher: String, gemini: String)
        case failed(String)
    }

    @Published var title = UserDefaults.standard.string(forKey: "title") ?? "" {
        didSet { UserDefaults.standard.set(title, forKey: "title") }
    }
    @Published var body = UserDefaults.standard.string(forKey: "body") ?? "" {
        didSet { UserDefaults.standard.set(body, forKey: "body") }
    }
    @Published private(set) var state = State.idle
    /// user@host for ssh.
    @Published var login = UserDefaults.standard.string(forKey: "login") ?? "\(NSUserName())@sdf.org" {
        didSet { UserDefaults.standard.set(login, forKey: "login") }
    }
    /// Add a link to the blog from the homepage, once.
    @Published var linkHomepage = UserDefaults.standard.object(forKey: "linkHomepage") as? Bool ?? true {
        didSet { UserDefaults.standard.set(linkHomepage, forKey: "linkHomepage") }
    }

    /// Where on SDF the gopher and html folders are: home, except in tests.
    var remoteHome = "$HOME"

    var isEmpty: Bool { body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var busy: Bool { if case .working = state { true } else { false } }

    var site: Site {
        let parts = login.split(separator: "@", maxSplits: 1).map(String.init)
        let user = parts.first ?? NSUserName()
        let host = parts.count > 1 ? parts[1] : "sdf.org"
        return Site(user: user, host: host, web: "https://\(user).\(host)/")
    }

    // MARK: Posting

    func post() {
        guard !isEmpty, !busy else { return }
        guard Self.validLogin(login) else {
            state = .failed("“\(login)” isn't a login. Set it from the right-click menu, as you@sdf.org.")
            return
        }
        let (title, body) = titleAndBody()
        Task {
            do {
                state = .working("Reading your posts…")
                let existing = try await existingPosts()
                state = .working("Posting…")
                let now = Date()
                let date = Self.day(now)
                let post = Post(date: date, slug: Self.uniqueSlug(Post.slug(title), date: date, among: existing),
                                title: title, body: body, posted: ISO8601DateFormatter().string(from: now))
                let all = ([post] + existing).sorted(by: Post.newestFirst)
                try await publish(post, all: all)
                let urls = site.post(post)
                state = .posted(title: title, web: urls.web, gopher: urls.gopher, gemini: urls.gemini)
                self.title = ""
                self.body = ""
                if linkHomepage { linkHomepage = false }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// The title typed, or else the body's first line (a Markdown heading's "#" taken off),
    /// which then leaves the body.
    private func titleAndBody() -> (String, String) {
        var body = self.body.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
        var title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            let first = body.prefix { $0 != "\n" }
            title = String(first.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            body = String(body.dropFirst(first.count)).trimmingCharacters(in: .newlines)
            if body.isEmpty { body = title }
        }
        return (String(title.prefix(120)), body)
    }

    private func existingPosts() async throws -> [Post] {
        let script = """
            [ -d "\(remoteHome)/gopher" ] || { echo "There's no gopher space yet. Run mkgopher on SDF and choose setup." >&2; exit 3; }
            [ -d "\(remoteHome)/html" ] || { echo "There's no web space yet. Run mkhomepg on SDF." >&2; exit 3; }
            cd "\(remoteHome)/gopher/phlog" 2>/dev/null || exit 0
            # Each post's source, where this app kept one; otherwise the phlog's own text.
            for f in *.txt; do
              [ -f "$f" ] || continue
              s="\(remoteHome)/.sdfpost/posts/$f"
              if [ -f "$s" ]; then printf '\\036%s\\tsource\\n' "$f"; cat "$s"; else printf '\\036%s\\tphlog\\n' "$f"; cat "$f"; fi
            done
            """
        let output = try await ssh(script)
        return output.split(separator: "\u{1E}").compactMap { record in
            let newline = record.firstIndex(of: "\n") ?? record.endIndex
            let header = record[..<newline].split(separator: "\t")
            guard let file = header.first.map(String.init) else { return nil }
            let text = String(record[newline...].dropFirst())
            return header.last == "source" ? Post(source: file, text: text) : Post(file: file, text: text)
        }
    }

    private func publish(_ post: Post, all: [Post]) async throws {
        let site = self.site
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("sdfpost-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        let gopher = temp.appendingPathComponent("gopher"), html = temp.appendingPathComponent("html")
        let sources = temp.appendingPathComponent("sources")

        // The new post's text, and every page made again from all of them.
        try write(Render.text(post), to: gopher.appendingPathComponent("phlog/\(post.name).txt"))
        try write(post.source, to: sources.appendingPathComponent("posts/\(post.name).txt"))
        try write(Render.phlogIndex(all), to: gopher.appendingPathComponent("phlog/gophermap"))
        for each in all {
            try write(Render.gemtext(each), to: gopher.appendingPathComponent("gemlog/\(each.name).gmi"))
            try write(Render.html(each, site: site), to: html.appendingPathComponent("blog/\(each.name).html"))
        }
        try write(Render.gemlogIndex(all, site: site), to: gopher.appendingPathComponent("gemlog/index.gmi"))
        try write(Render.blogIndex(all, site: site), to: html.appendingPathComponent("blog/index.html"))

        let gopherTar = try await tar(gopher), htmlTar = try await tar(html), sourceTar = try await tar(sources)
        var script = """
            set -e
            umask 022
            mkdir -p "\(remoteHome)/gopher/phlog" "\(remoteHome)/gopher/gemlog" "\(remoteHome)/html/blog"
            base64 -di <<'END_OF_GOPHER' | (cd "\(remoteHome)/gopher" && tar xf -)
            \(gopherTar.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]))
            END_OF_GOPHER
            base64 -di <<'END_OF_HTML' | (cd "\(remoteHome)/html" && tar xf -)
            \(htmlTar.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]))
            END_OF_HTML
            mkdir -p "\(remoteHome)/.sdfpost" && chmod 700 "\(remoteHome)/.sdfpost"
            base64 -di <<'END_OF_SOURCES' | (cd "\(remoteHome)/.sdfpost" && tar xf -)
            \(sourceTar.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]))
            END_OF_SOURCES
            chmod 755 "\(remoteHome)/gopher/phlog" "\(remoteHome)/gopher/gemlog" "\(remoteHome)/html/blog"
            # The capsule's front page links the gemlog, and the gopher hole's the phlog, once.
            f="\(remoteHome)/gopher/index.gmi"
            if [ -f "$f" ] && ! grep -q 'gemlog/' "$f"; then
              awk 'BEGIN { done = 0 } !done && /^=>/ { print "=> gemlog/ Gemlog"; done = 1 } { print } END { if (!done) print "=> gemlog/ Gemlog" }' "$f" > "$f.new" && cat "$f.new" > "$f" && rm "$f.new"
            fi
            f="\(remoteHome)/gopher/gophermap"
            if [ -f "$f" ] && ! grep -q 'phlog' "$f"; then printf '1Phlog\\tphlog\\n' >> "$f"; fi

            """
        if linkHomepage {
            // One link to the blog on the homepage: after its first heading, or before </body>.
            script += """
                f="\(remoteHome)/html/index.html"
                if [ -f "$f" ] && ! grep -q 'href="blog/"' "$f"; then
                  awk 'BEGIN { done = 0; link = "    <p><a href=\\"blog/\\">blog</a></p>" }
                       { l = tolower($0) }
                       !done && l ~ /<\\/body>/ { print link; done = 1 }
                       { print }
                       !done && l ~ /<h[12][ >]/ && l ~ /<\\/h[12]>/ { print link; done = 1 }' "$f" > "$f.new" && cat "$f.new" > "$f" && rm "$f.new"
                fi

                """
        }
        script += "echo posted\n"
        let result = try await ssh(script)
        guard result.contains("posted") else { throw Failure("SDF didn't say the post went up.") }
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Tools

    struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// A plain ustar archive of a folder's contents, with none of the Mac's extra files.
    private func tar(_ folder: URL) async throws -> Data {
        let output = try await run("/usr/bin/tar", ["--format", "ustar", "--no-mac-metadata", "-cf", "-", "-C", folder.path, "."],
                                   environment: ["COPYFILE_DISABLE": "1"])
        return output.data
    }

    /// Runs a script on SDF with `sh`, fed through ssh's input so nothing in it is a command
    /// line of its own.
    private func ssh(_ script: String) async throws -> String {
        let output = try await run("/usr/bin/ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=20", login, "/bin/sh -s"],
                                   input: Data(script.utf8))
        guard output.status == 0 else {
            let message = output.error.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.contains("Permission denied") {
                throw Failure("SDF didn't accept your SSH key for \(login). Logging in needs a key, not a password.")
            }
            throw Failure(message.isEmpty ? "ssh to \(login) failed (\(output.status))." : String(message.suffix(300)))
        }
        return String(decoding: output.data, as: UTF8.self)
    }

    private func run(_ tool: String, _ arguments: [String], input: Data? = nil,
                     environment: [String: String] = [:]) async throws -> (data: Data, error: String, status: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
                let out = Pipe(), err = Pipe(), inp = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = input == nil ? FileHandle.nullDevice : inp
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                if let input {
                    DispatchQueue.global().async {
                        inp.fileHandleForWriting.write(input)
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
                let data = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: (data, String(decoding: errData, as: UTF8.self), process.terminationStatus))
            }
        }
    }

    static func validLogin(_ login: String) -> Bool {
        let parts = login.split(separator: "@")
        return parts.count == 2 && !login.hasPrefix("-") && !login.contains(where: { $0.isWhitespace })
    }

    /// The day by SDF's clock, which keeps UTC, so a post's date matches the server's.
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func uniqueSlug(_ slug: String, date: String, among posts: [Post]) -> String {
        var candidate = slug, n = 1
        while posts.contains(where: { $0.date == date && $0.slug == candidate }) {
            n += 1
            candidate = "\(slug)-\(n)"
        }
        return candidate
    }

    // MARK: Small things

    func clear() {
        title = ""
        body = ""
        state = .idle
    }

    /// Reads a dropped text or Markdown file into the draft.
    func load(_ url: URL) {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        guard let text else {
            state = .failed("\(url.lastPathComponent) isn't a text file.")
            return
        }
        body = text
        state = .idle
    }

    func setLogin() {
        let alert = NSAlert()
        alert.messageText = "Your SDF Login"
        alert.informativeText = "Posts go over ssh with your key, as user@host. Your site's address comes from it: https://user.sdf.org/."
        let field = NSTextField(string: login)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            login = field.stringValue.trimmingCharacters(in: .whitespaces)
        }
    }
}
