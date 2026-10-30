// Stage — draws a polyhedron flat-shaded in a Canvas with its own little projection: no
// SceneKit, since a convex solid only needs its front faces, and those never overlap. The
// solid's own faces take the accent colour and its dual's are pale, so you can watch one set
// give way to the other.

import SwiftUI
import simd

struct Look {
    var faces = true
    var edges = true
    var corners = false
    /// Edges and corners round the back, dashed.
    var hidden = false
    /// The centre, with a line out to each corner, seen through the faces.
    var spokes = false
    /// Each distinct angle labelled once, where it's easiest to see.
    var angles = false
}

enum Stage {
    private static let light = simd_normalize(Vec(-0.55, 0.7, 0.45))
    private static let eye = 6.0

    /// Draws the shape filling `size`, turned by `orientation`. `size` fits the shape's
    /// farthest corner to `fill` of the shorter side, times `zoom`.
    static func draw(_ shape: Polyhedron, in context: GraphicsContext, size: CGSize, orientation: simd_quatd,
                     look: Look, accent: Color, ink: Color, paper: Color = .white,
                     zoom: Double = 1, fill: Double = 0.4) {
        let scale = min(size.width, size.height) * fill * zoom
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let turn = simd_matrix3x3(orientation)

        // Turned positions, with a gentle perspective from a viewer `eye` out along +z.
        let turned = shape.vertices.map { turn * $0 }
        let screen = turned.map { p -> CGPoint in
            let f = eye / (eye - p.z)
            return CGPoint(x: centre.x + p.x * f * scale, y: centre.y - p.y * f * scale)
        }
        let normals = shape.faces.map { turn * $0.normal }
        let facing = shape.faces.indices.map { f in
            dot(normals[f], Vec(0, 0, eye) - turned[shape.faces[f].corners[0]]) > 0
        }

        func outline(_ face: Polyhedron.Face) -> Path {
            Path { p in
                p.move(to: screen[face.corners[0]])
                for c in face.corners.dropFirst() { p.addLine(to: screen[c]) }
                p.closeSubpath()
            }
        }

        let edgeWidth = max(1, scale * 0.008)
        let back = look.hidden || !look.faces
        // Faces let the inside show through while there's something in there to see.
        let opacity = look.spokes ? 0.6 : look.hidden ? 0.82 : 1

        // Round the back first, so the front covers it.
        if back {
            for edge in shape.edges where !facing[edge.faces.0] && !facing[edge.faces.1] && look.edges {
                var path = Path()
                path.move(to: screen[edge.a])
                path.addLine(to: screen[edge.b])
                context.stroke(path, with: .color(ink.opacity(look.faces ? 0.45 : 0.3)),
                               style: StrokeStyle(lineWidth: edgeWidth * 0.8, lineCap: .round,
                                                  dash: look.faces ? [edgeWidth * 3, edgeWidth * 3] : []))
            }
        }

        if look.spokes {
            for point in screen {
                var path = Path()
                path.move(to: centre)
                path.addLine(to: point)
                context.stroke(path, with: .color(ink.opacity(0.55)),
                               style: StrokeStyle(lineWidth: edgeWidth * 0.7, lineCap: .round))
            }
            let r = max(3, scale * 0.022)
            context.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                         with: .color(ink))
        }

        if look.faces {
            for (f, face) in shape.faces.enumerated() where facing[f] {
                let path = outline(face)
                let n = normals[f]
                let lambert = max(0, dot(n, light))
                let reflect = 2 * dot(n, light) * n - light
                let shine = pow(max(0, reflect.z), 24)
                let base = face.kind == .face ? accent : Color(white: 0.93)
                context.fill(path, with: .color(base.opacity(opacity)))
                context.fill(path, with: .color(.black.opacity((1 - lambert) * 0.6 * opacity)))
                context.fill(path, with: .color(.white.opacity(shine * 0.4)))
            }
        }

        if look.edges {
            for edge in shape.edges where facing[edge.faces.0] || facing[edge.faces.1] || !look.faces {
                var path = Path()
                path.move(to: screen[edge.a])
                path.addLine(to: screen[edge.b])
                let front = facing[edge.faces.0] || facing[edge.faces.1]
                context.stroke(path, with: .color(ink.opacity(front ? 0.85 : 0.3)),
                               style: StrokeStyle(lineWidth: edgeWidth, lineCap: .round))
            }
        }

        if look.corners {
            let r = max(2.5, scale * 0.018)
            for (i, point) in screen.enumerated() {
                let front = shape.faces.indices.contains { facing[$0] && shape.faces[$0].corners.contains(i) }
                guard front || back else { continue }
                let dot = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(front ? ink : ink.opacity(0.35)))
            }
        }

        if look.angles {
            drawAngles(shape, in: context, screen: screen, centre: centre, normals: normals, facing: facing,
                       turned: turned, look: look, ink: ink, paper: paper, edgeWidth: edgeWidth, scale: scale)
        }
    }

    /// Labels each distinct angle once, on the face, edge or spoke pair that faces the
    /// viewer most squarely: the angles inside the faces with an arc at each corner, the
    /// dihedral angles at an edge's midpoint, and with the spokes, the angle at the centre.
    private static func drawAngles(_ shape: Polyhedron, in context: GraphicsContext, screen: [CGPoint], centre: CGPoint,
                                   normals: [Vec], facing: [Bool], turned: [Vec], look: Look, ink: Color,
                                   paper: Color, edgeWidth: CGFloat, scale: CGFloat) {
        let fontSize = min(max(scale * 0.032, 10), 14)

        func text(_ degrees: Double) -> String { String(format: "%.1f°", degrees) }

        func label(_ string: String, at point: CGPoint) {
            let resolved = context.resolve(Text(string).font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(ink))
            let size = resolved.measure(in: CGSize(width: 400, height: 100))
            let box = CGRect(x: point.x - size.width / 2 - 5, y: point.y - size.height / 2 - 2,
                             width: size.width + 10, height: size.height + 4)
            context.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(paper.opacity(0.9)))
            context.stroke(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(ink.opacity(0.25)),
                           lineWidth: 0.5)
            context.draw(resolved, at: point)
        }

        /// An arc at `p` sweeping the short way from the direction of `a` to that of `b`;
        /// returns the direction halfway round, to put the label on.
        func arc(at p: CGPoint, from a: CGPoint, to b: CGPoint, radius: CGFloat) -> CGVector {
            let a0 = atan2(a.y - p.y, a.x - p.x)
            let sweep = remainder(atan2(b.y - p.y, b.x - p.x) - a0, 2 * .pi)
            var path = Path()
            for step in 0...16 {
                let t = a0 + sweep * Double(step) / 16
                let q = CGPoint(x: p.x + radius * cos(t), y: p.y + radius * sin(t))
                step == 0 ? path.move(to: q) : path.addLine(to: q)
            }
            context.stroke(path, with: .color(ink.opacity(0.85)), lineWidth: max(1, edgeWidth * 0.8))
            let mid = a0 + sweep / 2
            return CGVector(dx: cos(mid), dy: sin(mid))
        }

        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

        // Inside the faces: one face of each kind, the one most squarely facing the viewer.
        var used = Set<Int>()
        var kinds: [String: Int] = [:]
        for f in shape.faces.indices where facing[f] {
            let key = shape.cornerAngles(of: shape.faces[f]).map { String(format: "%.1f", $0) }.sorted().joined(separator: ",")
            if let best = kinds[key], normals[best].z >= normals[f].z { continue }
            kinds[key] = f
        }
        for f in kinds.values {
            used.insert(f)
            let face = shape.faces[f]
            let n = face.corners.count
            let angles = shape.cornerAngles(of: face)
            var labelled: [Double] = []
            for i in 0..<n {
                let p = screen[face.corners[i]]
                let a = screen[face.corners[(i + n - 1) % n]], b = screen[face.corners[(i + 1) % n]]
                let radius = min(distance(p, a), distance(p, b)) * 0.24
                let toward = arc(at: p, from: a, to: b, radius: radius)
                guard !labelled.contains(where: { abs($0 - angles[i]) < 0.05 }) else { continue }
                labelled.append(angles[i])
                let reach = radius + fontSize * 1.6
                label(text(angles[i]), at: CGPoint(x: p.x + toward.dx * reach, y: p.y + toward.dy * reach))
            }
        }

        // Between the faces: one edge for each dihedral angle, the longest on screen with both
        // its faces in view, preferring one away from the faces already labelled.
        var dihedrals: [String: (edge: Int, score: Double)] = [:]
        for (e, edge) in shape.edges.enumerated() where facing[edge.faces.0] && facing[edge.faces.1] {
            let key = text(shape.dihedralAngle(of: edge))
            let crowded = used.contains(edge.faces.0) || used.contains(edge.faces.1)
            let score = Double(distance(screen[edge.a], screen[edge.b])) * (crowded ? 0.6 : 1)
            if let best = dihedrals[key], best.score >= score { continue }
            dihedrals[key] = (e, score)
        }
        for (key, best) in dihedrals {
            let edge = shape.edges[best.edge]
            var path = Path()
            path.move(to: screen[edge.a])
            path.addLine(to: screen[edge.b])
            context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: edgeWidth * 2.4, lineCap: .round))
            label(key, at: CGPoint(x: (screen[edge.a].x + screen[edge.b].x) / 2,
                                   y: (screen[edge.a].y + screen[edge.b].y) / 2))
        }

        // At the centre: one pair of neighbouring corners for each angle, nearest the viewer.
        guard look.spokes else { return }
        var centrals: [String: Int] = [:]
        for (e, edge) in shape.edges.enumerated() {
            let key = text(shape.centralAngle(of: edge))
            let z = turned[edge.a].z + turned[edge.b].z
            if let best = centrals[key], turned[shape.edges[best].a].z + turned[shape.edges[best].b].z >= z { continue }
            centrals[key] = e
        }
        for (i, (key, e)) in centrals.sorted(by: { $0.key < $1.key }).enumerated() {
            let edge = shape.edges[e]
            let radius = min(distance(centre, screen[edge.a]), distance(centre, screen[edge.b])) * (0.28 + 0.12 * Double(i))
            let toward = arc(at: centre, from: screen[edge.a], to: screen[edge.b], radius: radius)
            let reach = radius + fontSize * 1.6
            label(key, at: CGPoint(x: centre.x + toward.dx * reach, y: centre.y + toward.dy * reach))
        }
    }
}

/// The solid on the window's stage, turned by dragging and zoomed by pinching.
struct StageView: View {
    @ObservedObject var model: PolyhedraModel
    @ObservedObject var turntable: Turntable
    @Environment(\.accent) private var accent
    @State private var lastDrag = CGSize.zero
    @State private var startZoom: Double?

    var body: some View {
        Canvas { context, size in
            Stage.draw(model.shape, in: context, size: size, orientation: turntable.orientation,
                       look: Look(faces: model.showFaces, edges: model.showEdges, corners: model.showCorners,
                                  hidden: model.showHidden, spokes: model.showSpokes, angles: model.showAngles),
                       accent: accent, ink: .primary, paper: Color(nsColor: .windowBackgroundColor),
                       zoom: turntable.zoom)
        }
        .background(
            RadialGradient(colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                           center: .center, startRadius: 40, endRadius: 600)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { drag in
                    turntable.drag(drag.translation.width - lastDrag.width, drag.translation.height - lastDrag.height)
                    lastDrag = drag.translation
                }
                .onEnded { _ in lastDrag = .zero }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { pinch in
                    if startZoom == nil { startZoom = turntable.zoom }
                    turntable.zoom = min(max((startZoom ?? 1) * pinch.magnification, 0.4), 2.5)
                }
                .onEnded { _ in startZoom = nil }
        )
        .onTapGesture(count: 2) { turntable.reset() }
        .help("Drag to turn it, pinch to zoom, double-click to set it straight")
    }
}
