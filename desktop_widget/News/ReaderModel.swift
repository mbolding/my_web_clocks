// ReaderModel — one window's reading: the group chosen in the sidebar, its threads, the
// article open, and any post being written. A group shows its latest 500 articles, and
// Get New Articles adds whatever has arrived since.

import SwiftUI
import AppKit

/// A post being written: a follow-up to an article, or something new.
struct Draft: Identifiable {
    let id = UUID()
    var server: Server
    var newsgroups: String
    var subject: String
    var references: [String] = []
    var body = ""

    /// A follow-up: to the groups the article asks for (Followup-To) or the ones it was in,
    /// "Re:" its subject, with the article quoted below who wrote it.
    static func followUp(to article: Article, on server: Server, from group: String) -> Draft {
        var groups = article.header("Followup-To") ?? ""
        if groups.isEmpty || groups.lowercased() == "poster" { groups = article.newsgroups }
        if groups.isEmpty { groups = group }
        let subject = Threads.bare(article.subject) == article.subject ? "Re: \(article.subject)" : article.subject

        // RFC 5537 asks to keep References short: the first, then the latest ones.
        var references = article.references + [article.messageID].filter { !$0.isEmpty }
        if references.count > 21 { references = [references[0]] + references.suffix(20) }

        var lines = article.body.components(separatedBy: "\n")
        if let signature = lines.lastIndex(of: "-- ") { lines.removeSubrange(signature...) }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        let quoted = lines.map { $0.hasPrefix(">") ? ">" + $0 : ($0.isEmpty ? ">" : "> " + $0) }
        let body = "\(Headers.name(article.from)) wrote:\n" + quoted.joined(separator: "\n") + "\n\n"
        return Draft(server: server, newsgroups: groups, subject: subject, references: references, body: body)
    }

    /// The article to send: headers, a blank line, then the text wrapped as format=flowed
    /// with the signature under it.
    func lines(name: String, address: String, signature: String) -> [String] {
        let groups = newsgroups.split { $0 == "," || $0.isWhitespace }.joined(separator: ",")
        var headers = [
            "From: \(Headers.from(name: name, address: address))",
            "Newsgroups: \(groups)",
            "Subject: \(Headers.encode(subject.trimmingCharacters(in: .whitespaces)))",
            "Date: \(Headers.rfc5322(Date()))",
        ]
        if !references.isEmpty { headers.append("References: \(references.joined(separator: " "))") }
        headers += [
            "User-Agent: News Reader (desktop_widget)",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8; format=flowed",
            "Content-Transfer-Encoding: 8bit",
        ]
        var text = body.trimmingCharacters(in: .newlines)
        let signature = signature.trimmingCharacters(in: .newlines)
        if !signature.isEmpty { text += "\n\n-- \n" + signature }
        return headers + [""] + MIME.flow(text)
    }
}

@MainActor
final class ReaderModel: ObservableObject {
    static let fetchCount = 500

    @Published var group: GroupRef? {
        didSet { if group != oldValue { selection = nil; Task { await load() } } }
    }
    @Published private(set) var rows: [ThreadRow] = []
    @Published var selection: Int? {
        didSet { if selection != oldValue { Task { await open() } } }
    }
    @Published private(set) var article: Article?
    @Published private(set) var loadingGroup = false
    @Published private(set) var loadingArticle = false
    @Published private(set) var groupProblem: String?
    @Published private(set) var articleProblem: String?
    @Published var showAllHeaders = false
    @Published var draft: Draft?
    /// The server whose group list is open for subscribing.
    @Published var browsing: Server?
    @Published var note: String?

    private var overviews: [GroupRef: [Overview]] = [:]
    private var library: Library { .shared }

    var server: Server? { group.flatMap { library.server($0.server) } }

    // MARK: Groups

    /// Loads the chosen group: its latest articles, or with `newer`, just those since the last look.
    func load(newer: Bool = false) async {
        guard let ref = group, let server else {
            rows = []
            return
        }
        loadingGroup = true
        groupProblem = nil
        if !newer { rows = overviews[ref].map(Threads.rows) ?? [] }
        defer { if group == ref { loadingGroup = false } }
        do {
            let session = library.session(server)
            let info = try await session.group(ref.name)
            library.note(info, for: ref)
            var articles = overviews[ref] ?? []
            let newest = articles.map(\.number).max()
            let first = max(info.low, newest.map { $0 + 1 } ?? info.high - Self.fetchCount + 1)
            if info.count > 0, info.high >= first {
                articles += try await session.overview(ref.name, first...info.high)
            }
            articles.removeAll { $0.number < info.low }
            overviews[ref] = articles
            guard group == ref else { return }
            rows = Threads.rows(articles)
        } catch {
            guard group == ref else { return }
            groupProblem = error.localizedDescription
        }
    }

    func refresh() {
        Task {
            await load(newer: true)
            await library.refreshAll()
        }
    }

    func markAllRead() {
        guard let ref = group else { return }
        let numbers = (overviews[ref] ?? []).map(\.number)
        if let info = library.info[ref], info.high >= info.low {
            library.markRead(ref, info.low...info.high)
        } else if let low = numbers.min(), let high = numbers.max() {
            library.markRead(ref, low...high)
        }
    }

    func isRead(_ number: Int) -> Bool {
        group.map { library.isRead($0, number) } ?? false
    }

    // MARK: Articles

    private func open() async {
        guard let ref = group, let number = selection, let server else {
            article = nil
            return
        }
        loadingArticle = true
        articleProblem = nil
        defer { if selection == number { loadingArticle = false } }
        do {
            let fetched = try await library.session(server).article(ref.name, number: number)
            guard selection == number, group == ref else { return }
            article = fetched
            library.markRead(ref, number...number)
        } catch {
            guard selection == number else { return }
            article = nil
            articleProblem = error.localizedDescription
        }
    }

    /// Moves to the next unread article after the one open, going round to the top.
    func nextUnread() {
        guard !rows.isEmpty else { return }
        let here = rows.firstIndex { $0.article.number == selection } ?? -1
        let order = rows[(here + 1)...] + rows[..<max(here + 1, 0)]
        if let next = order.first(where: { !isRead($0.article.number) }) {
            selection = next.article.number
        } else {
            note = "There are no unread articles here."
        }
    }

    func markUnread() {
        guard let ref = group, let number = selection else { return }
        library.markUnread(ref, number)
        objectWillChange.send()
    }

    // MARK: Writing

    func followUp() {
        guard let article, let server, let ref = group else { return }
        draft = .followUp(to: article, on: server, from: ref.name)
    }

    func newPost() {
        guard let server else { return }
        draft = Draft(server: server, newsgroups: group?.name ?? "", subject: "")
    }

    var canPost: Bool {
        guard let ref = group else { return false }
        return library.info[ref]?.postingAllowed ?? true
    }
}
