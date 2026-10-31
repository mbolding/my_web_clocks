// Render — one post written three ways: a text file for the phlog, wrapped to 70 columns
// as gopher readers expect; a gemtext page for the gemlog; and an HTML page for the web
// blog; and the three indexes that list them, newest first. The gemlog index uses
// Gemini's subscription format, a link per post starting with its date.

import Foundation

struct Post: Equatable {
    /// YYYY-MM-DD, by SDF's clock, which keeps UTC.
    var date: String
    var slug: String
    var title: String
    var body: String
    /// When it was posted, as an ISO 8601 time, to order a day's posts; empty if not known.
    var posted = ""

    var name: String { "\(date)-\(slug)" }

    /// Newest first: by date, then by the time posted.
    static func newestFirst(_ a: Post, _ b: Post) -> Bool {
        (a.date, a.posted, a.name) > (b.date, b.posted, b.name)
    }

    /// The post's source as kept in ~/.sdfpost/posts: title and time, a blank line, then
    /// the text as it was written, unwrapped.
    var source: String { "title: \(title)\nposted: \(posted)\n\n\(body)\n" }

    init?(source file: String, text: String) {
        guard var post = Post(file: file, text: "") else { return nil }
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        while let line = lines.first, !line.isEmpty {
            lines.removeFirst()
            if line.hasPrefix("title: ") { post.title = String(line.dropFirst(7)) }
            if line.hasPrefix("posted: ") { post.posted = String(line.dropFirst(8)) }
        }
        if !lines.isEmpty { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        post.body = lines.joined(separator: "\n")
        self = post
    }

    /// Reads a phlog text file: its title, the date, a blank line, then the body.
    init?(file: String, text: String) {
        guard file.hasSuffix(".txt"), file.count > 15, Self.isDate(String(file.prefix(10))) else { return nil }
        date = String(file.prefix(10))
        slug = String(file.dropFirst(11).dropLast(4))
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        title = lines.isEmpty ? slug : lines.removeFirst().trimmingCharacters(in: .whitespaces)
        if let first = lines.first, Self.isDate(first.trimmingCharacters(in: .whitespaces)) { lines.removeFirst() }
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        body = lines.joined(separator: "\n")
    }

    init(date: String, slug: String, title: String, body: String, posted: String = "") {
        self.date = date
        self.slug = slug
        self.title = title
        self.body = body
        self.posted = posted
    }

    static func isDate(_ s: String) -> Bool {
        s.count == 10 && s.enumerated().allSatisfy { i, c in i == 4 || i == 7 ? c == "-" : c.isASCII && c.isNumber }
    }

    /// A file name from a title: plain lowercase letters and digits joined by hyphens.
    static func slug(_ title: String) -> String {
        let plain = title.applyingTransform(.stripDiacritics, reverse: false) ?? title
        var out = ""
        for c in plain.lowercased() {
            if c.isASCII && (c.isLetter || c.isNumber) {
                out.append(c)
            } else if !out.isEmpty && out.last != "-" {
                out.append("-")
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        if out.count > 50 { out = String(out.prefix(50)); while out.hasSuffix("-") { out.removeLast() } }
        return out.isEmpty ? "post" : out
    }
}

/// Where a site's three halves live, for links between them.
struct Site {
    /// The SDF login, which names the site.
    var user: String
    /// The server for gopher and Gemini, such as sdf.org.
    var host: String
    /// The web site's address, ending in a slash.
    var web: String

    var blog: String { web + "blog/" }
    var phlog: String { "gopher://\(host)/1/users/\(user)/phlog/" }
    var gemlog: String { "gemini://\(host)/\(user)/gemlog/" }

    func post(_ post: Post) -> (web: String, gopher: String, gemini: String) {
        (blog + post.name + ".html", "gopher://\(host)/0/users/\(user)/phlog/\(post.name).txt", gemlog + post.name + ".gmi")
    }
}

enum Render {
    // MARK: Gopher

    static func text(_ post: Post) -> String {
        ([post.title, post.date, ""] + wrap(post.body, width: 70)).joined(separator: "\n") + "\n"
    }

    static func phlogIndex(_ posts: [Post]) -> String {
        (["Phlog", ""] + posts.map { "0\($0.date)  \(tabless($0.title))\t\($0.name).txt" }).joined(separator: "\n") + "\n"
    }

    /// Lines longer than `width` broken at spaces; shorter ones, and their breaks, kept. A
    /// quote's lines carry on with its ">"s; lines that start with a space, like code or
    /// ASCII art, are left alone.
    static func wrap(_ text: String, width: Int) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                out.append(line)
                continue
            }
            let marks = line.prefix { $0 == ">" || $0 == " " }
            let prefix = marks.contains(">") ? String(marks) : ""
            var rest = Substring(line)
            var first = true
            while rest.count + (first ? 0 : prefix.count) > width {
                let room = width - (first ? 0 : prefix.count)
                let window = rest.prefix(room + 1)
                guard let space = window.lastIndex(of: " "), space > rest.index(rest.startIndex, offsetBy: first ? prefix.count : 0) else { break }
                out.append((first ? "" : prefix) + rest[..<space])
                rest = rest[rest.index(after: space)...].drop { $0 == " " }
                first = false
            }
            out.append((first ? "" : prefix) + rest)
        }
        return out
    }

    /// A menu line can't hold a tab, which separates its fields.
    private static func tabless(_ s: String) -> String { s.replacingOccurrences(of: "\t", with: " ") }

    // MARK: Gemini

    static func gemtext(_ post: Post) -> String {
        var lines = ["# \(post.title)", "", post.date, "", post.body, ""]
        let urls = links(in: post.body)
        if !urls.isEmpty { lines += urls.map { "=> \($0)" } + [""] }
        lines.append("=> ./ Gemlog")
        return lines.joined(separator: "\n") + "\n"
    }

    static func gemlogIndex(_ posts: [Post], site: Site) -> String {
        (["# \(site.user)'s gemlog", ""] + posts.map { "=> \($0.name).gmi \($0.date) \($0.title)" }
            + ["", "=> ../ Home", "=> \(site.phlog) The same posts in gopherspace", "=> \(site.blog) And on the web"])
            .joined(separator: "\n") + "\n"
    }

    // MARK: Web

    static func html(_ post: Post, site: Site) -> String {
        let urls = site.post(post)
        return page(title: "\(post.title) · \(site.user)", body: """
            <header><a href="./">\(escape(site.user))'s blog</a></header>
            <h1>\(escape(post.title))</h1>
            <p class="date">\(post.date)</p>
            \(paragraphs(post.body))
            <footer>Also in <a href="\(urls.gopher)">gopherspace</a> and <a href="\(urls.gemini)">Geminispace</a>.</footer>
            """)
    }

    static func blogIndex(_ posts: [Post], site: Site) -> String {
        let items = posts.map { "<li><span class=\"date\">\($0.date)</span> <a href=\"\($0.name).html\">\(escape($0.title))</a></li>" }
        return page(title: "\(site.user)'s blog", body: """
            <header><a href="../">\(escape(site.user))</a></header>
            <h1>\(escape(site.user))'s blog</h1>
            <ul class="posts">
            \(items.joined(separator: "\n"))
            </ul>
            <footer>Also as a <a href="\(site.phlog)">phlog</a> in gopherspace and a <a href="\(site.gemlog)">gemlog</a> in Geminispace.</footer>
            """)
    }

    private static func page(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>
        body { font: 17px/1.6 Georgia, "Times New Roman", serif; max-width: 40em; margin: 2.5em auto; padding: 0 1.2em; color: #222; background: #fdfdfb; }
        a { color: #0b5cad; }
        header, footer, .date { font: 14px/1.5 -apple-system, system-ui, sans-serif; color: #777; }
        header { margin-bottom: 2em; } footer { margin-top: 3em; border-top: 1px solid #ddd; padding-top: 1em; }
        h1 { line-height: 1.25; margin-bottom: 0.2em; }
        blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid #ccc; color: #555; }
        .posts { list-style: none; padding: 0; } .posts li { margin: 0.4em 0; } .posts .date { margin-right: 0.8em; }
        @media (prefers-color-scheme: dark) {
          body { color: #ddd; background: #16181d; } a { color: #8ab4f8; }
          footer { border-color: #333; } blockquote { border-color: #444; color: #aaa; }
        }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>

        """
    }

    /// Paragraphs at blank lines; lines that start with ">" as quotes; line breaks kept.
    static func paragraphs(_ text: String) -> String {
        text.components(separatedBy: "\n\n").compactMap { block -> String? in
            let lines = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !lines.isEmpty else { return nil }
            if lines.allSatisfy({ $0.hasPrefix(">") }) {
                let inner = lines.map { linked(escape(String($0.dropFirst().drop { $0 == " " }))) }.joined(separator: "<br>\n")
                return "<blockquote><p>\(inner)</p></blockquote>"
            }
            return "<p>" + lines.map { linked(escape($0)) }.joined(separator: "<br>\n") + "</p>"
        }.joined(separator: "\n")
    }

    // MARK: Text

    private static let urlPattern = try! NSRegularExpression(pattern: #"(https?|gopher|gemini)://[^\s<>"]+[^\s<>".,;:!?)]"#)

    static func links(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return urlPattern.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }.filter { seen.insert($0).inserted }
    }

    /// Addresses in already-escaped text made into links.
    private static func linked(_ escaped: String) -> String {
        let range = NSRange(escaped.startIndex..., in: escaped)
        return urlPattern.stringByReplacingMatches(in: escaped, range: range, withTemplate: "<a href=\"$0\">$0</a>")
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
