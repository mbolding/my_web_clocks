// BrowserWindow — an address field and back and forward in the toolbar, the page in the
// middle, and a status bar that says where the link under the pointer goes. Menus are set
// in a monospaced font, as their ASCII art expects, with links in the accent colour.

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
        .alert(model.searching?.title ?? "Search", isPresented: Binding(
            get: { model.searching != nil }, set: { if !$0 { model.searching = nil } })
        ) {
            TextField("Words to search for", text: $model.searchWords)
            Button("Search") { model.search() }
            Button("Cancel", role: .cancel) { model.searching = nil }
        } message: {
            Text("What would you like to search for?")
        }
        .focusedSceneObject(model)
        .tint(accent.color)
        .environment(\.accent, accent.color)
        .onAppear(perform: start)
        .onChange(of: model.address) {
            if !addressFocused { typed = model.url ?? "" }
        }
        .onChange(of: model.focusAddress) { addressFocused = true }
    }

    private func start() {
        guard model.address == nil else { return }
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
        case .failure(let message):
            ContentUnavailableView {
                Label("Couldn't Open the Page", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { model.reload() }
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
                .onHover { inside in
                    if inside {
                        model.hovered = item
                        NSCursor.pointingHand.set()
                    } else if model.hovered?.id == item.id {
                        model.hovered = nil
                        NSCursor.arrow.set()
                    }
                }
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
        if let item = model.hovered { return "\(item.kind.name): \(item.location)" }
        if model.loading {
            return model.received > 0 ? "Loading… \(BrowserModel.size(model.received))" : "Connecting to \(model.address?.host ?? "")…"
        }
        if let note = model.note { return note }
        switch model.page {
        case .menu(let items):
            let links = items.filter { ![.info, .error].contains($0.kind) }.count
            return links == 1 ? "1 link" : "\(links) links"
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
