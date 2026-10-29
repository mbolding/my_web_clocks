// MapWindow — one window: a sidebar of search results and saved places beside the map,
// a search field and style picker in the toolbar, and the position and OpenStreetMap
// credit along the bottom of the map.

import SwiftUI
import MapKit

struct MapWindow: View {
    @StateObject private var model = MapModel()
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    @AppStorage("sharpTiles") private var sharp = false

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 380)
        } detail: {
            MapView(model: model, tint: NSColor(accent.color), sharp: sharp)
                .overlay(alignment: .bottomTrailing) { StatusBar(readout: model.readout, style: model.style) }
                .overlay(alignment: .top) {
                    if let notice = model.notice {
                        Text(notice)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                            .padding(.top, 10)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.notice)
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search places or coordinates")
        .onSubmit(of: .search) { model.search() }
        .toolbar {
            ToolbarItemGroup {
                ControlGroup {
                    Button { model.zoomOut() } label: { Label("Zoom Out", systemImage: "minus") }
                        .help("Zoom out")
                    Button { model.zoomIn() } label: { Label("Zoom In", systemImage: "plus") }
                        .help("Zoom in")
                }
                Picker("Map Style", selection: $model.style) {
                    ForEach(MapStyle.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Map style")
                Button { model.showMyLocation() } label: { Label("My Location", systemImage: "location") }
                    .help("Show my location")
                Button { model.beginSaving() } label: { Label("Save Place", systemImage: "star") }
                    .help("Save this place")
            }
        }
        .navigationTitle(model.pin?.title ?? "Map Browser")
        .navigationSubtitle(model.style.name)
        .alert("Save Place", isPresented: $model.naming) {
            TextField("Name", text: $model.draftName)
            Button("Save") { model.finishSaving() }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be listed under Places in the sidebar and the Places menu.")
        }
        .alert("Rename Place", isPresented: Binding(get: { model.renaming != nil },
                                                    set: { if !$0 { model.renaming = nil } })) {
            TextField("Name", text: $model.draftName)
            Button("Rename") { model.finishRenaming() }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        }
        .tint(accent.color)
        .focusedSceneObject(model)
    }
}

struct Sidebar: View {
    @ObservedObject var model: MapModel
    @ObservedObject private var places = Places.shared

    var body: some View {
        List(selection: $model.selection) {
            if model.searching || !model.results.isEmpty {
                Section {
                    ForEach(model.results) { result in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).lineLimit(1)
                            Text([result.kind, result.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                        .tag(SidebarItem.result(result.id))
                    }
                } header: {
                    HStack {
                        Text("Results")
                        Spacer()
                        if model.searching {
                            ProgressView().controlSize(.mini)
                        } else {
                            Button("Clear") { model.clearResults() }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section("Places") {
                ForEach(places.all) { place in
                    Label(place.name, systemImage: "star")
                        .lineLimit(1)
                        .tag(SidebarItem.place(place.id))
                        .contextMenu {
                            Button("Rename…") { model.beginRenaming(place) }
                            Button("Delete") { places.remove(place.id) }
                        }
                }
                .onMove { places.move(from: $0, to: $1) }
                if places.all.isEmpty {
                    Text("Save a place with ⌘D, or by right-clicking the map.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDeleteCommand { model.deleteSelectedPlace() }
    }
}

struct StatusBar: View {
    @ObservedObject var readout: MapReadout
    var style: MapStyle

    var body: some View {
        HStack(spacing: 8) {
            Text("\(coordinateText(readout.center))  ·  zoom \(Int(readout.zoom.rounded()))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Divider().frame(height: 10)
            Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            if let credit = style.credit {
                Text(credit).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .padding(6)
    }
}
