// ReaderWindow — three columns, as newsreaders have long had them: servers and their
// subscribed groups with unread counts, the open group's threads, and the article. Articles
// are set in a monospaced font, as Usenet's quoting and ASCII art expect, with quoted lines
// shaded by depth and the signature dimmed.

import SwiftUI
import AppKit

struct ReaderWindow: View {
    @StateObject private var model = ReaderModel()
    @ObservedObject private var library = Library.shared
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            ThreadList(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 380)
        } detail: {
            ArticleView(model: model)
        }
        .navigationTitle(model.group?.name ?? "News Reader")
        .navigationSubtitle(model.server?.name ?? "")
        .toolbar { toolbar }
        .focusedSceneObject(model)
        .tint(accent.color)
        .environment(\.accent, accent.color)
        .sheet(item: $model.draft) { draft in
            ComposeView(draft: draft, model: model)
        }
        .sheet(item: $model.browsing) { server in
            GroupBrowser(server: server)
        }
        .task { await library.refreshAll() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.refresh() } label: { Label("Get New Articles", systemImage: "arrow.clockwise") }
                .help("Get new articles")
                .disabled(model.group == nil)
            Button { model.nextUnread() } label: { Label("Next Unread", systemImage: "arrow.down.circle") }
                .help("Next unread article")
                .disabled(model.rows.isEmpty)
            Button { model.followUp() } label: { Label("Follow Up", systemImage: "arrowshape.turn.up.left") }
                .help("Follow up to this article")
                .disabled(model.article == nil)
            Button { model.newPost() } label: { Label("New Post", systemImage: "square.and.pencil") }
                .help("Post a new article to this group")
                .disabled(model.group == nil)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject var model: ReaderModel
    @ObservedObject private var library = Library.shared

    var body: some View {
        List(selection: $model.group) {
            ForEach(library.servers) { server in
                Section(server.name) {
                    ForEach(library.groups(on: server), id: \.self) { name in
                        row(GroupRef(server: server.id, name: name))
                    }
                    Button { model.browsing = server } label: {
                        Label("Subscribe to Groups…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ ref: GroupRef) -> some View {
        HStack {
            Text(ref.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let problem = library.problem(ref) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(problem)
            } else if let unread = library.unread(ref), unread > 0 {
                Text("\(unread)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .tag(ref)
        .contextMenu {
            Button("Mark All as Read") {
                if let info = library.info[ref], info.high >= info.low { library.markRead(ref, info.low...info.high) }
            }
            Button("Unsubscribe") {
                if model.group == ref { model.group = nil }
                library.unsubscribe(ref)
            }
        }
    }
}

// MARK: - Threads

struct ThreadList: View {
    @ObservedObject var model: ReaderModel
    @ObservedObject private var library = Library.shared
    @Environment(\.accent) private var accent

    var body: some View {
        Group {
            if model.group == nil {
                ContentUnavailableView("No Group Chosen", systemImage: "newspaper",
                                       description: Text("Choose a group in the sidebar, or subscribe to one."))
            } else if let problem = model.groupProblem, model.rows.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't Open the Group", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(problem)
                } actions: {
                    Button("Try Again") { Task { await model.load() } }
                    if problem.contains("Settings") { SettingsLink { Text("Open Settings…") } }
                }
            } else if model.rows.isEmpty {
                if model.loadingGroup {
                    ProgressView()
                } else {
                    ContentUnavailableView("No Articles", systemImage: "tray",
                                           description: Text("Nothing has been posted here lately."))
                }
            } else {
                List(model.rows, selection: $model.selection) { row in
                    ThreadRowView(row: row, read: model.isRead(row.article.number))
                        .tag(row.article.number)
                }
                .listStyle(.inset)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { status }
    }

    private var status: some View {
        HStack(spacing: 8) {
            if model.loadingGroup { ProgressView().controlSize(.small) }
            Text(statusText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

    private var statusText: String {
        if let note = model.note { return note }
        if model.loadingGroup { return "Getting articles…" }
        if let problem = model.groupProblem { return problem }
        guard model.group != nil else { return "" }
        let unread = model.rows.filter { !model.isRead($0.article.number) }.count
        let total = model.rows.count
        return "\(total) article\(total == 1 ? "" : "s"), \(unread) unread"
    }
}

struct ThreadRowView: View {
    let row: ThreadRow
    let read: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(read ? Color.clear : accent)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                if row.root {
                    Text(row.article.subject.isEmpty ? "(no subject)" : row.article.subject)
                        .fontWeight(read ? .regular : .semibold)
                        .lineLimit(2)
                    HStack {
                        Text(row.article.author).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(Self.date(row.article.date)).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Text(row.article.author)
                            .fontWeight(read ? .regular : .semibold)
                            .lineLimit(1)
                        if row.newSubject {
                            Text(row.article.subject).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(Self.date(row.article.date))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.leading, CGFloat(min(row.depth, 8)) * 14)
        .padding(.top, row.root ? 4 : 0)
        .foregroundStyle(read ? .secondary : .primary)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

// MARK: - Article

struct ArticleView: View {
    @ObservedObject var model: ReaderModel
    @AppStorage("fontSize") private var fontSize = 13.0

    var body: some View {
        if let article = model.article {
            VStack(alignment: .leading, spacing: 0) {
                header(article)
                Divider()
                BodyText(text: article.body, fontSize: fontSize)
            }
        } else if model.loadingArticle {
            ProgressView()
        } else if let problem = model.articleProblem {
            ContentUnavailableView {
                Label("Couldn't Get the Article", systemImage: "exclamationmark.triangle")
            } description: {
                Text(problem)
            }
        } else {
            ContentUnavailableView("No Article Open", systemImage: "doc.text",
                                   description: Text(model.rows.isEmpty ? "" : "Choose an article, or press ⌘] for the next unread one."))
        }
    }

    private func header(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.subject.isEmpty ? "(no subject)" : article.subject)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
            if model.showAllHeaders {
                ScrollView {
                    Text(article.headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
                    field("From", article.from)
                    if let date = article.date {
                        field("Date", date.formatted(date: .complete, time: .shortened))
                    }
                    field("Groups", article.newsgroups.replacingOccurrences(of: ",", with: ", "))
                    if let followups = article.header("Followup-To"), !followups.isEmpty {
                        field("Follow-ups to", followups)
                    }
                }
                .font(.callout)
            }
        }
        .textSelection(.enabled)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder private func field(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// An article's text in a text view, so long ones scroll smoothly and Find (⌘F) works, with
/// quotes shaded by depth, the signature dimmed and web addresses made links.
struct BodyText: NSViewRepresentable {
    let text: String
    var fontSize: Double
    @Environment(\.accent) private var accent

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.textContainerInset = NSSize(width: 16, height: 14)
        view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let key = "\(text.hashValue)/\(fontSize)/\(accent.description)"
        guard context.coordinator.shown != key else { return }
        context.coordinator.shown = key
        view.textStorage?.setAttributedString(styled())
        view.scrollToBeginningOfDocument(nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var shown = ""
    }

    private func styled() -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let out = NSMutableAttributedString()
        let quoteColors: [NSColor] = [NSColor(accent).withAlphaComponent(0.9), .secondaryLabelColor, .tertiaryLabelColor]
        var inSignature = false
        for (n, line) in text.components(separatedBy: "\n").enumerated() {
            if line == "-- " { inSignature = true }
            let depth = line.prefix { $0 == ">" || $0 == " " }.filter { $0 == ">" }.count
            let color: NSColor = inSignature ? .tertiaryLabelColor
                : depth == 0 ? .labelColor : quoteColors[min(depth, quoteColors.count) - 1]
            out.append(NSAttributedString(string: (n > 0 ? "\n" : "") + line,
                                          attributes: [.font: font, .foregroundColor: color]))
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let whole = NSRange(location: 0, length: out.length)
            for match in detector.matches(in: out.string, range: whole) {
                if let url = match.url { out.addAttribute(.link, value: url, range: match.range) }
            }
        }
        return out
    }
}

// MARK: - Writing

struct ComposeView: View {
    @State var draft: Draft
    @ObservedObject var model: ReaderModel
    @AppStorage("name") private var name = ""
    @AppStorage("email") private var email = ""
    @AppStorage("signature") private var signature = ""
    @State private var sending = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("From").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    HStack {
                        Text(identityMissing ? "Set your name and address in Settings first." : Headers.from(name: name, address: email))
                            .foregroundStyle(identityMissing ? .red : .primary)
                        Spacer()
                        Text("on \(draft.server.name)").foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Groups").foregroundStyle(.secondary)
                    TextField("comp.misc, alt.test", text: $draft.newsgroups).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Subject").foregroundStyle(.secondary)
                    TextField("Subject", text: $draft.subject).textFieldStyle(.roundedBorder)
                }
            }
            .padding(16)
            Divider()
            TextEditor(text: $draft.body)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
            Divider()
            HStack {
                if let problem {
                    Text(problem).foregroundStyle(.red).lineLimit(3).font(.callout)
                } else {
                    Text("Long lines are wrapped when it's sent; your signature goes below.")
                        .foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                if identityMissing { SettingsLink { Text("Settings…") } }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(sending ? "Posting…" : "Post") { post() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!ready || sending)
            }
            .padding(12)
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 480, idealHeight: 560)
    }

    private var identityMissing: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty || !email.contains("@")
    }

    private var ready: Bool {
        !identityMissing && !draft.newsgroups.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.subject.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func post() {
        sending = true
        problem = nil
        let lines = draft.lines(name: name, address: email.trimmingCharacters(in: .whitespaces), signature: signature)
        let session = Library.shared.session(draft.server)
        Task {
            do {
                try await session.post(lines)
                model.note = "Posted to \(draft.newsgroups). It can take a minute to show up."
                dismiss()
            } catch {
                problem = error.localizedDescription
                sending = false
            }
        }
    }
}

/// Every group a server carries, to search and subscribe to.
struct GroupBrowser: View {
    let server: Server
    @ObservedObject private var library = Library.shared
    @State private var groups: [GroupInfo] = []
    @State private var search = ""
    @State private var loading = true
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(groups.isEmpty ? "" : "\(groups.count) ")groups on \(server.name)", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            Group {
                if loading {
                    ProgressView("Getting the list of groups…")
                } else if let problem {
                    ContentUnavailableView {
                        Label("Couldn't Get the Groups", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(problem)
                    } actions: {
                        if problem.contains("Settings") { SettingsLink { Text("Open Settings…") } }
                    }
                } else {
                    List(shown, id: \.name) { group in
                        let ref = GroupRef(server: server.id, name: group.name)
                        Toggle(isOn: Binding(get: { library.isSubscribed(ref) },
                                             set: { $0 ? library.subscribe(ref) : library.unsubscribe(ref) })) {
                            HStack {
                                Text(group.name)
                                Spacer()
                                Text(group.count == 0 ? "empty" : "\(group.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                if !group.postingAllowed {
                                    Image(systemName: "lock").foregroundStyle(.secondary).help("No posting here")
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(footer).foregroundStyle(.secondary).font(.callout)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 480, idealHeight: 600)
        .task {
            do {
                groups = try await library.session(server).groups().sorted { $0.name < $1.name }
            } catch {
                problem = error.localizedDescription
            }
            loading = false
        }
    }

    /// Groups whose names hold every word searched for, at most a few thousand at once.
    private var shown: [GroupInfo] {
        let words = search.lowercased().split(separator: " ")
        let matches = words.isEmpty ? groups : groups.filter { group in
            let name = group.name.lowercased()
            return words.allSatisfy { name.contains($0) }
        }
        return Array(matches.prefix(3000))
    }

    private var footer: String {
        let matching = search.isEmpty ? groups.count : shown.count
        if matching >= 3000 { return "Showing the first 3,000; search to narrow them." }
        return "\(matching) group\(matching == 1 ? "" : "s")"
    }
}
