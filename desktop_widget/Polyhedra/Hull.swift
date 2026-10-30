// Hull — a convex polyhedron worked out from the planes that bound it. Every shape the app
// shows is the intersection of two sets of half-spaces: the Platonic solid's own face
// planes, and planes square to its vertices (which are its dual's face planes). Pushing the
// second set inwards slices the corners off, through the truncations, to the dual itself, so
// one routine draws every step and the numbers are measured rather than looked up.

import Foundation
import simd

typealias Vec = SIMD3<Double>

/// One bounding plane: points x with dot(normal, x) ≤ distance are inside.
struct Plane {
    enum Kind { case face, vertex }
    var normal: Vec
    var distance: Double
    /// Whether it's one of the solid's own faces or one of its dual's.
    var kind: Kind
}

struct Polyhedron {
    struct Face {
        /// Corners, anticlockwise seen from outside.
        var corners: [Int]
        var normal: Vec
        var kind: Plane.Kind
    }

    struct Edge {
        var a: Int, b: Int
        /// The two faces that meet along it.
        var faces: (Int, Int)
    }

    var vertices: [Vec] = []
    var faces: [Face] = []
    var edges: [Edge] = []

    /// The intersection of the half-spaces, scaled so its farthest corner is 1 from the centre.
    init(planes: [Plane]) {
        let eps = 1e-7
        var points: [Vec] = []

        // Every corner is where three planes meet and no plane cuts it off.
        for i in 0..<planes.count {
            for j in (i + 1)..<planes.count {
                for k in (j + 1)..<planes.count {
                    guard let p = Self.meet(planes[i], planes[j], planes[k]) else { continue }
                    guard planes.allSatisfy({ dot($0.normal, p) <= $0.distance + eps }) else { continue }
                    // Several triples meet at one corner where four or more planes do.
                    if !points.contains(where: { simd_distance($0, p) < 1e-5 }) { points.append(p) }
                }
            }
        }
        guard !points.isEmpty else { return }

        var faces: [Face] = []
        for plane in planes {
            let on = points.indices.filter { abs(dot(plane.normal, points[$0]) - plane.distance) < 1e-5 }
            guard on.count >= 3 else { continue }
            faces.append(Face(corners: Self.ordered(on, points: points, normal: plane.normal),
                              normal: plane.normal, kind: plane.kind))
        }

        var edges: [Edge] = []
        var seen: [Int: Int] = [:]
        for (f, face) in faces.enumerated() {
            for (i, a) in face.corners.enumerated() {
                let b = face.corners[(i + 1) % face.corners.count]
                let key = min(a, b) * 10_000 + max(a, b)
                if let e = seen[key] {
                    edges[e].faces.1 = f
                } else {
                    seen[key] = edges.count
                    edges.append(Edge(a: min(a, b), b: max(a, b), faces: (f, f)))
                }
            }
        }

        let scale = 1 / (points.map { simd_length($0) }.max() ?? 1)
        vertices = points.map { $0 * scale }
        self.faces = faces
        self.edges = edges
    }

    private static func meet(_ a: Plane, _ b: Plane, _ c: Plane) -> Vec? {
        let bc = cross(b.normal, c.normal)
        let det = dot(a.normal, bc)
        guard abs(det) > 1e-9 else { return nil }
        return (a.distance * bc + b.distance * cross(c.normal, a.normal) + c.distance * cross(a.normal, b.normal)) / det
    }

    /// Corners of a face sorted by angle round its middle, anticlockwise about the normal.
    private static func ordered(_ indices: [Int], points: [Vec], normal: Vec) -> [Int] {
        let centre = indices.reduce(Vec.zero) { $0 + points[$1] } / Double(indices.count)
        let u = simd_normalize(points[indices[0]] - centre)
        let v = cross(normal, u)
        return indices.sorted {
            let p = points[$0] - centre, q = points[$1] - centre
            return atan2(dot(p, v), dot(p, u)) < atan2(dot(q, v), dot(q, u))
        }
    }

    // MARK: Measurements

    func centre(of face: Face) -> Vec {
        face.corners.reduce(Vec.zero) { $0 + vertices[$1] } / Double(face.corners.count)
    }

    func area(of face: Face) -> Double {
        var sum = Vec.zero
        for (i, a) in face.corners.enumerated() {
            sum += cross(vertices[a], vertices[face.corners[(i + 1) % face.corners.count]])
        }
        return abs(dot(sum, face.normal)) / 2
    }

    var edgeLengths: [Double] { edges.map { simd_distance(vertices[$0.a], vertices[$0.b]) } }

    /// Whether every edge is the same length, as on the Platonic and Archimedean solids.
    var uniform: Bool {
        let lengths = edgeLengths
        guard let lo = lengths.min(), let hi = lengths.max(), lo > 0 else { return false }
        return (hi - lo) / hi < 1e-4
    }

    var surfaceArea: Double { faces.reduce(0) { $0 + area(of: $1) } }

    /// A pyramid from the centre to each face, added up.
    var volume: Double {
        faces.reduce(0) { $0 + area(of: $1) * dot($1.normal, vertices[$1.corners[0]]) / 3 }
    }

    /// The distinct angles between neighbouring faces, in degrees, smallest first.
    var dihedralAngles: [Double] {
        var angles: [Double] = []
        for edge in edges {
            let n1 = faces[edge.faces.0].normal, n2 = faces[edge.faces.1].normal
            let angle = 180 - acos(min(1, max(-1, dot(n1, n2)))) * 180 / .pi
            if !angles.contains(where: { abs($0 - angle) < 0.01 }) { angles.append(angle) }
        }
        return angles.sorted()
    }

    /// The faces round one corner, by their number of sides, in order: "3.8.8" for the
    /// truncated cube. Written from the smallest side the way round that reads lowest.
    func configuration(at vertex: Int) -> [Int] {
        let p = vertices[vertex]
        let axis = simd_normalize(p)
        let around = faces.indices.filter { faces[$0].corners.contains(vertex) }
        guard let first = around.first else { return [] }
        let u = simd_normalize(centre(of: faces[first]) - p - dot(centre(of: faces[first]) - p, axis) * axis)
        let v = cross(axis, u)
        let sides = around.map { f -> (Double, Int) in
            let d = centre(of: faces[f]) - p
            return (atan2(dot(d, v), dot(d, u)), faces[f].corners.count)
        }.sorted { $0.0 < $1.0 }.map(\.1)

        var best = sides
        for list in [sides, sides.reversed()] {
            for r in 0..<list.count {
                let turned = Array(list[r...] + list[..<r])
                if turned.lexicographicallyPrecedes(best) { best = turned }
            }
        }
        return best
    }

    /// The configuration shared by every corner, or nil if they differ.
    var vertexConfiguration: [Int]? {
        guard !vertices.isEmpty else { return nil }
        let first = configuration(at: 0)
        return vertices.indices.allSatisfy { configuration(at: $0) == first } ? first : nil
    }

    /// How many faces have each number of sides, fewest sides first.
    var faceCounts: [(sides: Int, count: Int)] {
        Dictionary(grouping: faces, by: { $0.corners.count })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.sides < $1.sides }
    }
}
