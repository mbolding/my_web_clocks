// PolyhedraModel — one window's solid, how far it has morphed towards its dual, and what's
// shown; and the turntable that holds which way it faces. Both move a frame at a time while
// spinning or morphing on their own.

import SwiftUI
import simd

@MainActor
final class PolyhedraModel: ObservableObject {
    @Published var solid: Solid = Solid(rawValue: UserDefaults.standard.string(forKey: "solid") ?? "") ?? .cube {
        didSet {
            UserDefaults.standard.set(solid.rawValue, forKey: "solid")
            update()
        }
    }
    /// 0 is the solid, 1 its dual, with the truncations between.
    @Published var morph = 0.0 {
        didSet { update() }
    }
    @Published private(set) var shape = Solid.cube.shape(morph: 0)

    @Published var showFaces = PolyhedraModel.flag("showFaces", true) { didSet { save("showFaces", showFaces) } }
    @Published var showEdges = PolyhedraModel.flag("showEdges", true) { didSet { save("showEdges", showEdges) } }
    @Published var showCorners = PolyhedraModel.flag("showCorners", false) { didSet { save("showCorners", showCorners) } }
    @Published var showHidden = PolyhedraModel.flag("showHidden", false) { didSet { save("showHidden", showHidden) } }
    @Published var showSpokes = PolyhedraModel.flag("showSpokes", false) { didSet { save("showSpokes", showSpokes) } }
    @Published var showAngles = PolyhedraModel.flag("showAngles", false) { didSet { save("showAngles", showAngles) } }

    /// Morphing to the dual and back by itself.
    @Published var playing = false
    private var phase = 0.0

    init() { update() }

    private func update() {
        shape = solid.shape(morph: morph)
    }

    private static func flag(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    private func save(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: Stops

    /// The stop the morph is at, if it's at one.
    var stop: Int? {
        Solid.stops.firstIndex { abs($0 - morph) < 0.001 }
    }

    /// The name of what's showing: a named solid at a stop, or the two it's between.
    var name: String {
        let names = solid.stopNames
        if let stop { return names[stop] }
        let i = min(Int(morph * 4), 3)
        return "Between \(names[i].lowercased()) and \(names[i + 1].lowercased())"
    }

    func go(to stop: Int) {
        playing = false
        morph = Solid.stops[stop]
    }

    func step(_ direction: Int) {
        let target = direction > 0
            ? Solid.stops.first { $0 > morph + 0.001 } ?? 1
            : Solid.stops.last { $0 < morph - 0.001 } ?? 0
        playing = false
        morph = target
    }

    /// Slider changes snap to a stop when close to one, so they're easy to land on.
    func slide(to value: Double) {
        playing = false
        morph = Solid.stops.first { abs($0 - value) < 0.015 } ?? value
    }

    func togglePlaying() {
        if !playing {
            // Pick up from where the morph is now, heading for the far end.
            phase = acos(1 - 2 * morph)
        }
        playing.toggle()
    }

    /// Moves the morph on by dt seconds: there and back in 16, easing at each end.
    func advance(_ dt: Double) {
        guard playing else { return }
        phase += dt * 2 * .pi / 16
        morph = (1 - cos(phase)) / 2
    }
}

/// Which way the solid faces, turned by drags and the spin.
@MainActor
final class Turntable: ObservableObject {
    static let start = simd_quatd(angle: 0.38, axis: Vec(1, 0, 0)) * simd_quatd(angle: -0.62, axis: Vec(0, 1, 0))

    @Published var orientation = Turntable.start
    @Published var zoom = 1.0
    @Published var spinning = UserDefaults.standard.object(forKey: "spinning") as? Bool ?? true {
        didSet { UserDefaults.standard.set(spinning, forKey: "spinning") }
    }

    /// Turns by a drag of (dx, dy) points: the front follows the pointer.
    func drag(_ dx: Double, _ dy: Double) {
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }
        let turn = simd_quatd(angle: length * 0.01, axis: Vec(dy, dx, 0) / length)
        orientation = simd_normalize(turn * orientation)
    }

    func advance(_ dt: Double) {
        guard spinning else { return }
        orientation = simd_normalize(simd_quatd(angle: dt * 0.35, axis: Vec(0, 1, 0)) * orientation)
    }

    func reset() {
        orientation = Turntable.start
        zoom = 1
    }
}
