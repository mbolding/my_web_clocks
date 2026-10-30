// PolyhedraWindow — one window: the solid on its stage, and an inspector with the slider
// that morphs it into its dual and the numbers for whatever is showing, measured from the
// shape itself.

import SwiftUI
import simd

struct PolyhedraWindow: View {
    @StateObject private var model = PolyhedraModel()
    @StateObject private var turntable = Turntable()
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    @AppStorage("showInspector") private var showInspector = true

    var body: some View {
        StageView(model: model, turntable: turntable)
            .frame(minWidth: 380, minHeight: 380)
            .inspector(isPresented: $showInspector) {
                Facts(model: model)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
            }
            .toolbar {
                ToolbarItem {
                    Picker("Solid", selection: $model.solid) {
                        ForEach(Solid.allCases) { Text($0.short).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .help("Choose one of the five Platonic solids (⌘1–⌘5)")
                }
                ToolbarItemGroup {
                    Button { model.togglePlaying() } label: {
                        Label(model.playing ? "Stop Morphing" : "Morph", systemImage: model.playing ? "pause.fill" : "play.fill")
                    }
                    .help(model.playing ? "Stop morphing" : "Morph to the dual and back, over and over (⌘K)")
                    Toggle(isOn: $turntable.spinning) {
                        Label("Spin", systemImage: "rotate.3d")
                    }
                    .help("Turn slowly by itself (⌘J)")
                    Button { turntable.reset() } label: { Label("Set Straight", systemImage: "scope") }
                        .help("Turn it back to the starting view (⌘0)")
                }
                ToolbarItem {
                    Button { showInspector.toggle() } label: { Label("Facts", systemImage: "sidebar.trailing") }
                        .help("Show or hide the slider and the numbers")
                }
            }
            .navigationTitle(model.name)
            .navigationSubtitle("\(model.shape.vertices.count) corners · \(model.shape.edges.count) edges · \(model.shape.faces.count) faces")
            .task(id: turntable.spinning || model.playing) { await run() }
            .tint(accent.color)
            .environment(\.accent, accent.color)
            .focusedSceneObject(model)
            .focusedSceneObject(turntable)
    }

    /// Moves the spin and the morph on a frame at a time, while either is running.
    private func run() async {
        var last = Date()
        while !Task.isCancelled && (turntable.spinning || model.playing) {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date()
            let dt = min(now.timeIntervalSince(last), 0.1)
            last = now
            turntable.advance(dt)
            model.advance(dt)
        }
    }
}

/// The inspector: which solid, how far towards its dual, what's shown, and the numbers.
struct Facts: View {
    @ObservedObject var model: PolyhedraModel

    var body: some View {
        let shape = model.shape
        Form {
            Section("Solid") {
                Picker("Solid", selection: $model.solid) {
                    ForEach(Solid.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
            }

            Section("Towards its dual") {
                Text(model.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                // One row, so the slider spans it rather than sitting in the value column.
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { model.morph }, set: { model.slide(to: $0) }), in: 0...1)
                        .labelsHidden()
                    HStack(spacing: 0) {
                        ForEach(Solid.stops.indices, id: \.self) { i in
                            Button { model.go(to: i) } label: {
                                Image(systemName: model.stop == i ? "circle.fill" : "circle")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.borderless)
                            .help(model.solid.stopNames[i])
                            if i < Solid.stops.count - 1 { Spacer() }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                Toggle("Morph back and forth", isOn: Binding(get: { model.playing }, set: { _ in model.togglePlaying() }))
            }

            Section("Show") {
                Toggle("Faces", isOn: $model.showFaces)
                Toggle("Edges", isOn: $model.showEdges)
                Toggle("Corners", isOn: $model.showCorners)
                Toggle("The hidden side", isOn: $model.showHidden)
                    .help("Edges and corners round the back, dashed")
                Toggle("Centre and spokes", isOn: $model.showSpokes)
                    .help("The centre, with a line out to each corner, seen through the faces")
                Toggle("Angles", isOn: $model.showAngles)
                    .help("Each different angle labelled once: inside a face, between two faces, and with the spokes, at the centre")
            }

            Section("Counts") {
                Row("Corners, V", "\(shape.vertices.count)")
                Row("Edges, E", "\(shape.edges.count)")
                Row("Faces, F", "\(shape.faces.count)")
                Row("V − E + F", "\(shape.vertices.count - shape.edges.count + shape.faces.count)")
                    .help("Euler's formula: 2 for every convex polyhedron")
                Row("Faces", faceList(shape))
            }

            Section("Shape") {
                let configuration = shape.vertexConfiguration
                if let configuration, shape.uniform, Set(configuration).count == 1 {
                    Row("Schläfli symbol", "{\(configuration[0]), \(configuration.count)}")
                }
                Row("At each corner", configuration.map { $0.map(String.init).joined(separator: ".") } ?? "Varies")
                    .help("The faces round a corner by their number of sides, in order")
                Row("Face angles", shape.faceAngles.map { degrees($0) }.joined(separator: ", "))
                    .help("The angles inside the faces, at their corners")
                Row("Dihedral angles", shape.dihedralAngles.map { degrees($0) }.joined(separator: ", "))
                    .help("The angles between neighbouring faces")
                Row("Angles at the centre", shape.centralAngles.map { degrees($0) }.joined(separator: ", "))
                    .help("The angles between the spokes to the two ends of an edge")
                Row("Edges", shape.uniform ? "All the same length" : "Two lengths")
            }

            if shape.uniform, let e = shape.edgeLengths.first, e > 0 {
                Section("With edges of length 1") {
                    Row("Circumradius", number(1 / e))
                        .help("Centre to each corner")
                    let mid = simd_length((shape.vertices[shape.edges[0].a] + shape.vertices[shape.edges[0].b]) / 2)
                    Row("Midradius", number(mid / e))
                        .help("Centre to the middle of each edge")
                    let inner = shape.faces.map { dot($0.normal, shape.vertices[$0.corners[0]]) }
                    if let lo = inner.min(), let hi = inner.max(), hi - lo < 1e-6 {
                        Row("Inradius", number(lo / e))
                            .help("Centre to the middle of each face")
                    }
                    Row("Surface area", number(shape.surfaceArea / (e * e)))
                    Row("Volume", number(shape.volume / (e * e * e)))
                }
            }

            Section("About the \(model.solid.name.lowercased())") {
                Row("Symmetry", model.solid.symmetry)
                Row("Dual", model.solid.dual == model.solid ? "Itself" : model.solid.dual.name)
                Row("Plato's element", model.solid.element)
                    .help("From the Timaeus, which matched four of them to the elements and the fifth to the heavens")
            }
        }
        .formStyle(.grouped)
    }

    private func faceList(_ shape: Polyhedron) -> String {
        shape.faceCounts.map { "\($0.count) \(Self.polygon($0.sides, regular: shape.uniform))\($0.count == 1 ? "" : "s")" }
            .joined(separator: ", ")
    }

    static func polygon(_ sides: Int, regular: Bool) -> String {
        switch sides {
        case 3: "triangle"
        case 4: regular ? "square" : "quadrilateral"
        case 5: "pentagon"
        case 6: "hexagon"
        case 7: "heptagon"
        case 8: "octagon"
        case 10: "decagon"
        default: "\(sides)-gon"
        }
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(4)))
    }

    private func degrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2))) + "°"
    }
}

/// A name on the left and its value on the right, wrapping if long.
struct Row: View {
    var title: String
    var value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
