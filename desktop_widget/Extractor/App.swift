// Text Extractor — drop a PDF or Word document on it and it shows just the text, to select,
// copy or save as plain text. An ordinary Mac app like Map Browser, with windows, a menu
// bar and a Dock icon, rather than one of the floating widgets.

import SwiftUI
import AppKit

@main
struct TextExtractorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(for: URL.self) { $url in
            ExtractorWindow(url: $url)
        }
        .defaultSize(width: 640, height: 760)
        .commands {
            TextEditingCommands()
            ExtractorCommands()
        }
    }
}

/// Files dropped on the Dock icon, or opened with it from Finder, arrive as an Open
/// Documents event. It's taken before SwiftUI sees it, since SwiftUI would open an empty
/// window for each file on top of any the app opens for them.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openDocuments(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEOpenDocuments))
    }

    @objc private func openDocuments(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let list = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        let urls = (0..<list.numberOfItems).compactMap { list.atIndex($0 + 1)?.fileURLValue }
        MainActor.assumeIsolated { Inbox.shared.open(urls) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Inbox.shared.finishLaunching() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ExtractorCommands: Commands {
    @FocusedObject private var model: ExtractorModel?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = Inbox.shared.openWindow = openWindow
        CommandGroup(after: .newItem) {
            Button("Open…") { Inbox.shared.choose() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("Save as Text…") { model?.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(model?.canExport ?? false))
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy All Text") { model?.copyAll() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!(model?.canExport ?? false))
        }
    }
}
