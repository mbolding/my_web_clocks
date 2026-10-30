// Stipple — drop a picture on it and it's redrawn in dots, gathered where the picture is
// dark (weighted Voronoi stippling), or as one continuous line through them ("TSP art"), to
// save as SVG for a pen plotter or PNG for everything else. A native take on Evil Mad
// Scientist's StippleGen, and an ordinary Mac app like Text Extractor, with windows, a menu
// bar and a Dock icon, rather than one of the floating widgets.

import SwiftUI
import AppKit

@main
struct StippleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(for: URL.self) { $url in
            StippleWindow(url: $url)
        }
        .defaultSize(width: 1100, height: 780)
        .commands {
            InspectorCommands()
            StippleCommands()
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

struct StippleCommands: Commands {
    @FocusedObject private var model: StippleModel?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = Inbox.shared.openWindow = openWindow
        let ready = model?.phase == .ready

        CommandGroup(after: .newItem) {
            Button("Open…") { Inbox.shared.choose() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("Save as SVG…") { model?.save(.svg) }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(model?.canExport ?? false))
            Button("Save as PNG…") { model?.save(.png) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!(model?.canExport ?? false))
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Drawing") { model?.copyImage() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!(model?.canExport ?? false))
        }

        CommandMenu("Drawing") {
            Button("Dots") { model?.settings.style.mode = .dots }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!ready)
            Button("Line") { model?.settings.style.mode = .line }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!ready)
            Divider()
            Button(model?.busy ?? false ? "Pause" : "Keep Settling") { model?.pauseOrResume() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!ready)
            Button("Start Over") { model?.restart() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!ready)
            Divider()
            Button(model?.settings.showPicture ?? false ? "Hide the Picture" : "Show the Picture Underneath") {
                model?.settings.showPicture.toggle()
            }
            .keyboardShortcut("u", modifiers: .command)
            .disabled(!ready)
        }
    }
}
