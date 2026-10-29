// Map Browser — an OpenStreetMap browser, and an ordinary Mac app rather than one of the
// floating widgets: windows with a sidebar and toolbar, a menu bar, a Dock icon and a
// Settings window. Search for places, save them, and switch between map styles.

import SwiftUI
import MapKit

@main
struct MapBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            MapWindow()
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            MapCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct MapCommands: Commands {
    @FocusedObject private var model: MapModel?
    @ObservedObject private var places = Places.shared

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Link to This View") { model?.copyLink() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model == nil)
            Button("Copy Coordinates") { model?.copyCoordinates() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model == nil)
        }

        CommandGroup(before: .sidebar) {
            ForEach(Array(MapStyle.allCases.enumerated()), id: \.element) { i, style in
                Toggle(style.name, isOn: Binding(get: { model?.style == style }, set: { _ in model?.style = style }))
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Divider()
            Button("Zoom In") { model?.zoomIn() }.keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { model?.zoomOut() }.keyboardShortcut("-", modifiers: .command)
            Button("Show My Location") { model?.showMyLocation() }.keyboardShortcut("l", modifiers: .command)
            Button("Remove Pin") { model?.clearPin() }.disabled(model?.pin == nil)
            Divider()
            Button("Open in Web Browser") { model?.openInBrowser() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
        }

        CommandMenu("Places") {
            Button("Save This Place…") { model?.beginSaving() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model == nil)
            if !places.all.isEmpty { Divider() }
            ForEach(places.all) { place in
                Button(place.name) { model?.go(to: place) }.disabled(model == nil)
            }
        }

        CommandGroup(replacing: .help) {
            Link("OpenStreetMap Copyright and Licence", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            Link("About OpenStreetMap", destination: URL(string: "https://www.openstreetmap.org/about")!)
            Divider()
            Button("Report a Problem with the Map…") { model?.reportProblem() }.disabled(model == nil)
        }
    }
}

struct SettingsView: View {
    @AppStorage("defaultStyle") private var defaultStyle = MapStyle.standard
    @AppStorage("searchNearby") private var searchNearby = true
    @AppStorage("sharpTiles") private var sharp = false
    @State private var cacheSize = Tiles.cache.currentDiskUsage

    var body: some View {
        Form {
            Picker("New windows show", selection: $defaultStyle) {
                ForEach(MapStyle.allCases) { Text($0.name).tag($0) }
            }
            Toggle("Sharper map, with smaller text", isOn: $sharp)
            Toggle("Rank search results near the map first", isOn: $searchNearby)
            LabeledContent("Saved map tiles") {
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                        .monospacedDigit()
                    Button("Clear") {
                        Tiles.cache.removeAllCachedResponses()
                        cacheSize = Tiles.cache.currentDiskUsage
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onAppear { cacheSize = Tiles.cache.currentDiskUsage }
    }
}
