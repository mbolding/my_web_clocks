// Polyhedra — the five Platonic solids to turn over and look at, each with a slider that
// morphs it into its dual through the truncations between, and the numbers for whatever is
// showing. An ordinary Mac app like Map Browser, with windows, a menu bar and a Dock icon,
// rather than one of the floating widgets.

import SwiftUI
import AppKit

@main
struct PolyhedraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            PolyhedraWindow()
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            InspectorCommands()
            PolyhedraCommands()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct PolyhedraCommands: Commands {
    @FocusedObject private var model: PolyhedraModel?
    @FocusedObject private var turntable: Turntable?

    var body: some Commands {
        CommandMenu("Solid") {
            ForEach(Array(Solid.allCases.enumerated()), id: \.element) { i, solid in
                Button(solid.name) { model?.solid = solid }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Divider()
            Button("Towards the Dual") { model?.step(1) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Back Towards the Solid") { model?.step(-1) }
                .keyboardShortcut("[", modifiers: .command)
            Button(model?.playing ?? false ? "Stop Morphing" : "Morph Back and Forth") { model?.togglePlaying() }
                .keyboardShortcut("k", modifiers: .command)
        }

        CommandGroup(before: .toolbar) {
            Toggle("Faces", isOn: Binding(get: { model?.showFaces ?? true }, set: { model?.showFaces = $0 }))
                .keyboardShortcut("1", modifiers: [.command, .option])
            Toggle("Edges", isOn: Binding(get: { model?.showEdges ?? true }, set: { model?.showEdges = $0 }))
                .keyboardShortcut("2", modifiers: [.command, .option])
            Toggle("Corners", isOn: Binding(get: { model?.showCorners ?? false }, set: { model?.showCorners = $0 }))
                .keyboardShortcut("3", modifiers: [.command, .option])
            Toggle("The Hidden Side", isOn: Binding(get: { model?.showHidden ?? false }, set: { model?.showHidden = $0 }))
                .keyboardShortcut("4", modifiers: [.command, .option])
            Divider()
            Toggle("Spin", isOn: Binding(get: { turntable?.spinning ?? false }, set: { turntable?.spinning = $0 }))
                .keyboardShortcut("j", modifiers: .command)
            Button("Set Straight") { turntable?.reset() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }
    }
}
