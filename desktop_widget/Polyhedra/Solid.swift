// Solid — the five Platonic solids, each as two sets of directions: towards its corners
// and towards the middles of its faces. Each set is the other's dual, so a cube's faces
// point where an octahedron's corners are. From those come the stops on the way from a
// solid to its dual: truncated, rectified (cut to the edge midpoints), and truncated dual.

import Foundation
import simd

enum Solid: String, CaseIterable, Identifiable {
    case tetrahedron, cube, octahedron, dodecahedron, icosahedron

    var id: Self { self }
    var name: String { rawValue.capitalized }

    /// A short name for the toolbar.
    var short: String {
        switch self {
        case .tetrahedron: "Tetra"
        case .cube: "Cube"
        case .octahedron: "Octa"
        case .dodecahedron: "Dodeca"
        case .icosahedron: "Icosa"
        }
    }

    var dual: Solid {
        switch self {
        case .tetrahedron: .tetrahedron
        case .cube: .octahedron
        case .octahedron: .cube
        case .dodecahedron: .icosahedron
        case .icosahedron: .dodecahedron
        }
    }

    /// Sides of each face, p, and faces at each corner, q: the Schläfli symbol {p, q}.
    var schlafli: (p: Int, q: Int) {
        switch self {
        case .tetrahedron: (3, 3)
        case .cube: (4, 3)
        case .octahedron: (3, 4)
        case .dodecahedron: (5, 3)
        case .icosahedron: (3, 5)
        }
    }

    var symmetry: String {
        switch self {
        case .tetrahedron: "Tetrahedral, Td, order 24"
        case .cube, .octahedron: "Octahedral, Oh, order 48"
        case .dodecahedron, .icosahedron: "Icosahedral, Ih, order 120"
        }
    }

    /// The element Plato gave it in the Timaeus.
    var element: String {
        switch self {
        case .tetrahedron: "Fire"
        case .cube: "Earth"
        case .octahedron: "Air"
        case .dodecahedron: "The heavens"
        case .icosahedron: "Water"
        }
    }

    /// The names at the five stops, from the solid to its dual.
    var stopNames: [String] {
        switch self {
        case .tetrahedron:
            ["Tetrahedron", "Truncated tetrahedron", "Octahedron (rectified tetrahedron)",
             "Truncated tetrahedron", "Tetrahedron (its own dual)"]
        case .cube: ["Cube", "Truncated cube", "Cuboctahedron", "Truncated octahedron", "Octahedron"]
        case .octahedron: ["Octahedron", "Truncated octahedron", "Cuboctahedron", "Truncated cube", "Cube"]
        case .dodecahedron:
            ["Dodecahedron", "Truncated dodecahedron", "Icosidodecahedron", "Truncated icosahedron", "Icosahedron"]
        case .icosahedron:
            ["Icosahedron", "Truncated icosahedron", "Icosidodecahedron", "Truncated dodecahedron", "Dodecahedron"]
        }
    }

    static let stops: [Double] = [0, 0.25, 0.5, 0.75, 1]

    // MARK: Geometry

    private static let phi = (1 + 5.0.squareRoot()) / 2

    private static func cyclic(_ v: Vec) -> [Vec] {
        [v, Vec(v.y, v.z, v.x), Vec(v.z, v.x, v.y)]
    }

    /// Every sign combination of a point, without repeats where a coordinate is 0.
    private static func signs(_ v: Vec) -> [Vec] {
        var out: [Vec] = []
        for sx in [1.0, -1] {
            for sy in [1.0, -1] {
                for sz in [1.0, -1] {
                    let p = Vec(v.x * sx, v.y * sy, v.z * sz)
                    if !out.contains(p) { out.append(p) }
                }
            }
        }
        return out
    }

    /// Directions from the centre to the corners.
    var corners: [Vec] {
        let points: [Vec]
        switch self {
        case .tetrahedron:
            points = [Vec(1, 1, 1), Vec(1, -1, -1), Vec(-1, 1, -1), Vec(-1, -1, 1)]
        case .cube:
            points = Self.signs(Vec(1, 1, 1))
        case .octahedron:
            points = Self.cyclic(Vec(1, 0, 0)).flatMap { [$0, -$0] }
        case .dodecahedron:
            points = Self.signs(Vec(1, 1, 1)) + Self.cyclic(Vec(0, Self.phi, 1 / Self.phi)).flatMap(Self.signs)
        case .icosahedron:
            points = Self.cyclic(Vec(0, 1, Self.phi)).flatMap(Self.signs)
        }
        return points.map(simd_normalize)
    }

    /// Directions to the middles of the faces: the dual's corners (turned inside out for
    /// the tetrahedron, whose dual is itself upside down).
    var faceNormals: [Vec] {
        self == .tetrahedron ? corners.map { -$0 } : dual.corners
    }

    /// The shape `morph` of the way from this solid (0) to its dual (1), through the stops.
    func shape(morph: Double) -> Polyhedron {
        let cuts = cutDistances
        let s = min(max(morph, 0), 1)
        // Between stops the cut moves evenly on a log scale, which looks even to the eye.
        let i = min(Int(s * 4), 3)
        let f = (s - Self.stops[i]) / 0.25
        let cut = exp(log(cuts[i]) * (1 - f) + log(cuts[i + 1]) * f)
        let planes = faceNormals.map { Plane(normal: $0, distance: 1, kind: .face) }
            + corners.map { Plane(normal: $0, distance: cut, kind: .vertex) }
        return Polyhedron(planes: planes)
    }

    /// How far out the corner-cutting planes sit at each stop, with the solid's own faces
    /// at 1: touching the corners, uniformly truncated, through the edge midpoints, cutting
    /// the dual uniformly, and just touching the dual's corners.
    private var cutDistances: [Double] {
        // The solid with its faces 1 from the centre: corners k out.
        let k = 1 / (faceNormals.map { dot($0, corners[0]) }.max() ?? 1)
        let v = corners[0] * k
        let w = nearest(to: corners[0], in: corners) * k

        // Truncating a {p, q} so the cut faces and the trimmed ones have equal edges takes
        // 1 / (2 + 2 cos(π/p)) off each end of every edge.
        func cut(_ v: Vec, _ w: Vec, sides: Int) -> Double {
            let t = 1 / (2 + 2 * cos(.pi / Double(sides)))
            return dot(simd_normalize(v), v + t * (w - v))
        }
        let truncated = cut(v, w, sides: schlafli.p)
        let rectified = dot(corners[0], (v + w) / 2)

        // The same for the dual, worked out with the dual's faces at 1 and then scaled.
        let u = faceNormals[0] * k
        let u2 = nearest(to: faceNormals[0], in: faceNormals) * k
        let dualTruncated = 1 / cut(u, u2, sides: schlafli.q)
        return [k, truncated, rectified, dualTruncated, 1 / k]
    }

    private func nearest(to direction: Vec, in set: [Vec]) -> Vec {
        set.filter { simd_distance($0, direction) > 1e-6 }
            .min { simd_distance($0, direction) < simd_distance($1, direction) }!
    }
}
