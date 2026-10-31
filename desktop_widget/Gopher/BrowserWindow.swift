// BrowserWindow — an address field and back and forward in the toolbar, the page in the
// middle, and a status bar that says where the link under the pointer goes. Gopher menus are
// set in a monospaced font, as their ASCII art expects, and Gemini pages in the system font
// with their preformatted blocks monospaced; links are in the accent colour in both.

import SwiftUI
import AppKit

struct BrowserWindow: View {
    @Binding var opening: Opening?
    @StateObject private var model = BrowserModel()
    @ObservedObject private var bookmarks = Bookmarks.shared
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    @AppStorage("fontSize") private var fontSize = 13.0
    @State private var typed = ""
    @FocusState private var addressFocused: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            StatusBar(model: model)
        }
        .frame(minWidth: 520, minHeight: 360)
        .toolbar { toolbar }
        .navigationTitle(model.title.isEmpty ? "Gopher Browser" : model.title)
        .focusedSceneObject(model)
        .tint(accent.color)
        .environment(\.accent, accent.color)
        .onAppear(perform: start)
        .onChange(of: model.location) {
            if !addressFocused { typed = model.url ?? "" }
        }
        .onChange(of: model.focusAddress) { addressFocused = true }
    }

    private func start() {
        guard model.location == nil else { return }
        let id = opening?.id ?? UUID()
        model.onVisit = { opening = Opening(url: $0, id: id) }
        if let url = opening?.url ?? Inbox.shared.takeFirst() {
            model.go(url)
        } else {
            model.goHome()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.page {
        case nil:
            ProgressView()
        case .menu(let items):
            MenuPage(items: items, model: model, fontSize: fontSize) { openWindow(value: Opening(url: $0)) }
                .id(model.pageID)
        case .gemtext(let lines):
            GemPage(lines: lines, model: model, fontSize: fontSize) { openWindow(value: Opening(url: $0)) }
                .id(model.pageID)
        case .text(let text):
            TextPage(text: text, fontSize: fontSize)
                .id(model.pageID)
        case .image(let image):
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .frame(width: image.size.width, height: image.size.height)
                    .padding(20)
            }
            .id(model.pageID)
        case .input(let prompt, let sensitive):
            InputPage(prompt: prompt, sensitive: sensitive, model: model)
                .id(model.pageID)
        case .file(let type, let size):
            ContentUnavailableView {
                Label("A File to Save", systemImage: "arrow.down.circle")
            } description: {
                Text("This is a \(type) file of \(BrowserModel.size(size)), which Gopher Browser can't show.")
            } actions: {
                Button("Save…") { model.save() }
            }
        case .failure(let message):
            ContentUnavailableView {
                Label("Couldn't Open the Page", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { model.reload() }
            }
        case .certificateChanged(let changed):
            ContentUnavailableView {
                Label("The Certificate Has Changed", systemImage: "lock.trianglebadge.exclamationmark")
            } description: {
                Text("\(changed.server) shows a different certificate from the one it showed before. "
                     + "Servers change them now and then, but it could also mean someone is in the way. "
                     + "Trust it only if you expected the change.")
            } actions: {
                Button("Trust the New Certificate") { model.trust(changed) }
                Button("Go Back") { model.goBack() }.disabled(!model.canGoBack)
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.goBack() } label: { Label("Back", systemImage: "chevron.backward") }
                .disabled(!model.canGoBack)
                .help("Back")
            Button { model.goForward() } label: { Label("Forward", systemImage: "chevron.forward") }
                .disabled(!model.canGoForward)
                .help("Forward")
        }
        ToolbarItem(placement: .principal) {
            TextField("gopher://", text: $typed)
                .textFieldStyle(.roundedBorder)
                .focused($addressFocused)
                .onSubmit {
                    model.go(typed)
                    addressFocused = false
                }
                .onExitCommand {
                    typed = model.url ?? ""
                    addressFocused = false
                }
                .frame(minWidth: 240, idealWidth: 560, maxWidth: 720)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.loading {
                Button { model.stop() } label: { Label("Stop", systemImage: "xmark") }
                    .help("Stop loading")
            } else {
                Button { model.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    .help("Reload")
            }
            Button { bookmarks.toggle(model.url, title: model.title) } label: {
                Label("Bookmark", systemImage: bookmarks.contains(model.url) ? "star.fill" : "star")
            }
            .disabled(model.url == nil)
            .help(bookmarks.contains(model.url) ? "Remove the bookmark" : "Bookmark this page")
            Button { model.goHome() } label: { Label("Home", systemImage: "house") }
                .help("Go to the home page")
        }
    }
}

/// A menu, one line to a row, with each link's type as a symbol in a column of its own so
/// the text of links and plain lines starts at the same place.
struct MenuPage: View {
    let items: [Item]
    @ObservedObject var model: BrowserModel
    var fontSize: Double
    var openInNewWindow: (String) -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { row($0) }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: fontSize, design: .monospaced))
    }

    @ViewBuilder private func row(_ item: Item) -> some View {
        let line = HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.6) {
            Image(systemName: item.kind.symbol.isEmpty ? "circle" : item.kind.symbol)
                .font(.system(size: fontSize * 0.9))
                .opacity(item.kind.symbol.isEmpty ? 0 : 1)
                .frame(width: fontSize * 1.5)
            // An empty line still takes a line's height, so spacing in the menu survives.
            Text(item.display.isEmpty ? " " : item.display)
        }

        switch item.kind {
        case .info:
            line
        case .error:
            line.foregroundStyle(.red)
        default:
            Button { model.open(item) } label: { line.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .linkHover("\(item.kind.name): \(item.location)", model: model)
                .contextMenu {
                    if [.menu, .text, .image, .search].contains(item.kind) {
                        Button("Open in New Window") { openInNewWindow(item.address.url) }
                    }
                    Button("Copy Link") { model.copyLink(item.location) }
                    if item.kind != .web && item.kind != .telnet {
                        Button(Bookmarks.shared.contains(item.address.url) ? "Remove Bookmark" : "Bookmark Link") {
                            Bookmarks.shared.toggle(item.address.url, title: item.display.trimmingCharacters(in: .whitespaces))
                        }
                    }
                }
        }
    }
}

/// A Gemini page: text that wraps to a comfortable measure, headings, lists, quotes, links
/// one to a line, and preformatted blocks kept as they are.
struct GemPage: View {
    let lines: [GemLine]
    @ObservedObject var model: BrowserModel
    var fontSize: Double
    var openInNewWindow: (String) -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: fontSize * 0.45) {
                ForEach(lines) { line($0) }
            }
            .frame(maxWidth: fontSize * 48, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .font(.system(size: fontSize + 1))
        .textSelection(.enabled)
    }

    @ViewBuilder private func line(_ line: GemLine) -> some View {
        switch line.kind {
        case .text(let text):
            Text(text.isEmpty ? " " : text)
                .lineSpacing(fontSize * 0.25)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: fontSize * [1.9, 1.45, 1.2][level - 1], weight: level == 3 ? .semibold : .bold))
                .padding(.top, fontSize * (level == 1 ? 0.4 : 0.6))
                .fixedSize(horizontal: false, vertical: true)
        case .item(let text):
            HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.6) {
                Text("•").foregroundStyle(.secondary)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, fontSize * 0.6)
        case .quote(let text):
            Text(text)
                .italic()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, fontSize)
                .overlay(alignment: .leading) {
                    Rectangle().fill(accent.opacity(0.5)).frame(width: 3)
                }
        case .preformatted(let alt, let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: fontSize, design: .monospaced))
                    .fixedSize()
                    .padding(fontSize * 0.7)
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .help(alt)
            .accessibilityLabel(alt.isEmpty ? "Preformatted text" : alt)
        case .link(let url, let label):
            link(url, label: label)
        }
    }

    @ViewBuilder private func link(_ url: URL?, label: String) -> some View {
        let scheme = url?.scheme?.lowercased() ?? ""
        let symbol = switch scheme {
        case "gemini": "arrow.right.circle"
        case "gopher": "folder"
        case "http", "https": "globe"
        case "mailto": "envelope"
        default: "questionmark.square"
        }
        let row = HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.5) {
            Image(systemName: symbol).font(.system(size: fontSize * 0.9))
            // A label spaced into columns, as SDF's index is, keeps them in a fixed-width font.
            Text(label)
                .font(label.contains("  ") ? .system(size: fontSize, design: .monospaced) : nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let url {
            Button { model.follow(url.absoluteString, title: label) } label: { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .linkHover(url.absoluteString, model: model)
                .contextMenu {
                    if scheme == "gemini" || scheme == "gopher" {
                        Button("Open in New Window") { openInNewWindow(url.absoluteString) }
                    }
                    Button("Copy Link") { model.copyLink(url.absoluteString) }
                    if scheme == "gemini" || scheme == "gopher" {
                        Button(Bookmarks.shared.contains(url.absoluteString) ? "Remove Bookmark" : "Bookmark Link") {
                            Bookmarks.shared.toggle(url.absoluteString, title: label)
                        }
                    }
                }
        } else {
            row.foregroundStyle(.secondary)
        }
    }
}

/// A server's question, such as a search, with a field for the answer.
struct InputPage: View {
    let prompt: String
    let sensitive: Bool
    @ObservedObject var model: BrowserModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: sensitive ? "lock" : "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(prompt)
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Group {
                    if sensitive {
                        SecureField("Answer", text: $model.inputWords)
                    } else {
                        TextField("Words to send", text: $model.inputWords)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { model.submit() }
                Button("Send") { model.submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.inputWords.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(maxWidth: 420)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
    }
}

extension View {
    /// Shows where a link goes in the status bar, with the pointing hand, while the pointer is on it.
    func linkHover(_ destination: String, model: BrowserModel) -> some View {
        onHover { inside in
            if inside {
                model.hovered = destination
                NSCursor.pointingHand.set()
            } else if model.hovered == destination {
                model.hovered = nil
                NSCursor.arrow.set()
            }
        }
    }
}

/// A text file, in a text view rather than a SwiftUI Text so long ones scroll smoothly and
/// can be searched with Find (⌘F).
struct TextPage: NSViewRepresentable {
    let text: String
    var fontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.textContainerInset = NSSize(width: 20, height: 16)
        view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor
        view.textColor = .textColor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if view.string != text { view.string = text }
        if view.font != font { view.font = font }
    }
}

struct StatusBar: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        HStack(spacing: 8) {
            if model.loading {
                ProgressView().controlSize(.small)
            }
            Text(message)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

    private var message: String {
        if let hovered = model.hovered { return hovered }
        if model.loading {
            return model.received > 0 ? "Loading… \(BrowserModel.size(model.received))" : "Connecting to \(model.location?.host ?? "")…"
        }
        if let note = model.note { return note }
        switch model.page {
        case .menu(let items):
            let links = items.filter { ![.info, .error].contains($0.kind) }.count
            return links == 1 ? "1 link" : "\(links) links"
        case .gemtext(let lines):
            let links = lines.filter { if case .link = $0.kind { true } else { false } }.count
            return links == 1 ? "1 link" : "\(links) links"
        case .input:
            return "Waiting for your words"
        case .text(let text):
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            return lines == 1 ? "1 line" : "\(lines) lines"
        case .image(let image):
            return "\(Int(image.size.width)) × \(Int(image.size.height))"
        default:
            return ""
        }
    }
}

/// Bookmarks to rename, reorder and delete.
struct BookmarksEditor: View {
    @ObservedObject private var bookmarks = Bookmarks.shared
    @State private var selection = Set<UUID>()

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($bookmarks.all) { $bookmark in
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Name", text: $bookmark.title)
                            .textFieldStyle(.plain)
                        Text(bookmark.url)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                    .tag(bookmark.id)
                }
                .onMove { bookmarks.all.move(fromOffsets: $0, toOffset: $1) }
            }
            .onDeleteCommand(perform: delete)
            Divider()
            HStack {
                Button("Delete", action: delete).disabled(selection.isEmpty)
                Spacer()
                Button("Restore the Starting Bookmarks") {
                    for visit in Bookmarks.starting where !bookmarks.contains(visit.url) {
                        bookmarks.all.append(visit)
                    }
                }
            }
            .padding(10)
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private func delete() {
        bookmarks.all.removeAll { selection.contains($0.id) }
        selection = []
    }
}
