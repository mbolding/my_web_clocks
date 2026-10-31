// Gopher Browser — a browser for gopherspace, the menus-and-text internet of 1991 that SDF
// and others still run, and for Gemini, its TLS successor, as a native app since a web page
// can't open the raw connections they need. An ordinary Mac app like Map Browser, with
// windows, a menu bar and a Dock icon, and the handler for gopher:// and gemini:// links
// anywhere on the Mac.

import SwiftUI
import AppKit

@main
struct GopherBrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(for: Opening.self) { $opening in
            BrowserWindow(opening: $opening)
        }
        .defaultSize(width: 960, height: 760)
        .commands {
            TextEditingCommands()
            GopherCommands()
        }

        Window("Bookmarks", id: "bookmarks") {
            BookmarksEditor()
        }
        .defaultSize(width: 520, height: 420)
    }
}

/// gopher:// and gemini:// links clicked in other apps arrive as a Get URL event. It's taken before
/// SwiftUI sees it, so each opens one window of this app's own.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(getURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func getURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        MainActor.assumeIsolated { Inbox.shared.open(url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Inbox.shared.finishLaunching() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct GopherCommands: Commands {
    @FocusedObject private var model: BrowserModel?
    @ObservedObject private var bookmarks = Bookmarks.shared
    @ObservedObject private var history = History.shared
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("home") private var home = BrowserModel.defaultHome
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = Inbox.shared.openWindow = openWindow

        CommandGroup(after: .newItem) {
            Button("Open Location…") { model?.editAddress() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(model == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("Save Page As…") { model?.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(model?.canSave ?? false))
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Link to This Page") { model?.copyLink() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model?.url == nil)
        }

        CommandGroup(before: .toolbar) {
            Button("Reload Page") { model?.reload() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model?.url == nil)
            Button("Stop") { model?.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!(model?.loading ?? false))
            Divider()
            Button("Bigger Text") { fontSize = min(fontSize + 1, 32) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Text") { fontSize = max(fontSize - 1, 9) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { fontSize = 13 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }

        CommandMenu("Go") {
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(model?.canGoBack ?? false))
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(model?.canGoForward ?? false))
            Button("Home") { model?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Set This Page as Home") { if let url = model?.url { home = url } }
                .disabled(model?.url == nil || model?.url == home)
            Divider()
            Section("Recently Visited") {
                ForEach(history.recent.prefix(15)) { visit in
                    Button(visit.title) { model?.go(visit.url) }
                        .disabled(model == nil)
                }
            }
            Divider()
            Button("Clear History") { history.clear() }
                .disabled(history.recent.isEmpty)
        }

        CommandMenu("Bookmarks") {
            Button(bookmarks.contains(model?.url) ? "Remove Bookmark" : "Bookmark This Page") {
                bookmarks.toggle(model?.url, title: model?.title ?? "")
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(model?.url == nil)
            Button("Edit Bookmarks…") { openWindow(id: "bookmarks") }
                .keyboardShortcut("b", modifiers: [.command, .option])
            if !bookmarks.all.isEmpty { Divider() }
            ForEach(bookmarks.all) { visit in
                Button(visit.title) {
                    if let model {
                        model.go(visit.url)
                    } else {
                        openWindow(value: Opening(url: visit.url))
                    }
                }
            }
        }

        CommandGroup(replacing: .help) {
            Link("The Gopher Protocol (RFC 1436)", destination: URL(string: "https://www.rfc-editor.org/rfc/rfc1436")!)
            Link("The Gemini Protocol", destination: URL(string: "https://geminiprotocol.net")!)
            Link("SDF Public Access UNIX System", destination: URL(string: "https://sdf.org")!)
        }
    }
}
