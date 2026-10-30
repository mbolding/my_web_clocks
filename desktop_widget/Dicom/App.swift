// DICOM Viewer — open or drop DICOM files or folders on it to see their images, with
// window and level, scrolling through each series, and the tags. An ordinary Mac app like
// Map Browser, with windows, a menu bar and a Dock icon, rather than one of the floating
// widgets. Files are read on the Mac and nothing is sent anywhere.

import SwiftUI
import AppKit

@main
struct DicomViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(for: [URL].self) { $urls in
            ViewerWindow(urls: $urls)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            SidebarCommands()
            InspectorCommands()
            ViewerCommands()
        }
    }
}

/// Files dropped on the Dock icon, or opened with it from Finder, arrive as an Open
/// Documents event. It's taken before SwiftUI sees it, since SwiftUI would open an empty
/// window for each file on top of the one the app opens for them all.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Archives unpacked by a run that didn't get to tidy up. This comes before any
        // window is restored and unpacks its own.
        Loader.clearUnpacked()
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

struct ViewerCommands: Commands {
    // The front window's model rather than its display, which changes with every slice and
    // drag: the menus needn't be rebuilt that often. The actions look it up when chosen,
    // so the menus don't keep a closed window's files.
    @ObservedObject private var inbox = Inbox.shared
    @Environment(\.openWindow) private var openWindow

    private var model: ViewerModel? { Inbox.shared.front }
    private var display: Display? { Inbox.shared.front?.display }

    var body: some Commands {
        let _ = Inbox.shared.openWindow = openWindow
        let ready = inbox.front?.phase == .ready
        let seriesCount = inbox.front?.series.count ?? 0

        CommandGroup(after: .newItem) {
            Button("Open…") { Inbox.shared.choose() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Image") { display?.copyImage() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!ready)
            Button("Copy All Tags") { model?.tags.copyAll() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!ready)
        }

        CommandGroup(before: .toolbar) {
            Button("Zoom In") { display?.zoomIn() }.keyboardShortcut("=", modifiers: .command).disabled(!ready)
            Button("Zoom Out") { display?.zoomOut() }.keyboardShortcut("-", modifiers: .command).disabled(!ready)
            Button("Zoom to Fit") { display?.zoomToFit() }.keyboardShortcut("0", modifiers: .command).disabled(!ready)
            Divider()
        }

        CommandMenu("Image") {
            let presets = inbox.front?.display.presets ?? []
            ForEach(Array(presets.enumerated()), id: \.element.id) { i, preset in
                if i < 9 {
                    Button(preset.name) { display?.apply(named: preset.name) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                } else {
                    Button(preset.name) { display?.apply(named: preset.name) }
                }
            }
            if !presets.isEmpty { Divider() }
            Button("Reset Window") { display?.resetWindow() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!ready)
            Button("Invert") { display?.invert.toggle() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!ready)
            Divider()
            Button("First Image") { display?.first() }.disabled(!ready)
            Button("Last Image") { display?.last() }.disabled(!ready)
            Divider()
            Button("Previous Series") { model?.step(series: -1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(seriesCount < 2)
            Button("Next Series") { model?.step(series: 1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(seriesCount < 2)
        }
    }
}
