// Panorama — drop overlapping photos on it, taken from one spot, and it stitches them into
// one panorama: corners matched between every pair, the cameras' turns worked out and
// refined together, the horizon levelled, exposures evened and the seams kept narrow, then
// unrolled onto a cylinder, a sphere or a flat plane and saved at full size. An ordinary
// Mac app like Stipple, with a window, a menu bar and a Dock icon, rather than one of the
// floating widgets. Everything happens on the Mac; nothing is sent anywhere.

import SwiftUI
import AppKit

@main
struct PanoramaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Panorama", id: "main") {
            PanoramaWindow(model: .shared)
        }
        .defaultSize(width: 1200, height: 720)
        .commands {
            InspectorCommands()
            PanoramaCommands(model: .shared)
        }
    }
}

/// Photos dropped on the Dock icon, or opened with it from Finder, arrive as an Open
/// Documents event, and go into the panorama.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openDocuments(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEOpenDocuments))
    }

    @objc private func openDocuments(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let list = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        let urls = (0..<list.numberOfItems).compactMap { list.atIndex($0 + 1)?.fileURLValue }
        MainActor.assumeIsolated {
            PanoramaModel.shared.add(urls)
            WindowOpener.ensureOpen()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { WindowOpener.ensureOpen() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Opens the window when photos arrive without one, as when the app is launched by
/// opening photos with it, which SwiftUI takes as a reason not to open its window.
@MainActor
enum WindowOpener {
    /// SwiftUI's action for opening the window. The menu commands hand it over, as SwiftUI
    /// sets them up at launch.
    static var open: OpenWindowAction?

    static func ensureOpen() {
        DispatchQueue.main.async {
            let showing = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
            if !showing { open?(id: "main") }
        }
    }
}

struct PanoramaCommands: Commands {
    @ObservedObject var model: PanoramaModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = WindowOpener.open = openWindow
        CommandGroup(replacing: .newItem) {
            Button("New Panorama") { model.clear() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.photos.isEmpty)
            Button("Add Photos…") { model.choose() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save…") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canSave)
            Button("Save as Animation…") { model.saveAnimation() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!model.canAnimate)
        }

        CommandMenu("Panorama") {
            ForEach(Array(Projection.allCases.enumerated()), id: \.element) { n, projection in
                Button(projection.name) { model.settings.projection = projection }
                    .keyboardShortcut(KeyEquivalent(Character("\(n + 1)")), modifiers: .command)
            }
            Divider()
            Toggle("Crop to the Filled Area", isOn: $model.settings.crop)
                .keyboardShortcut("k", modifiers: .command)
            Toggle("Even Out Exposure", isOn: $model.settings.balance)
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}
