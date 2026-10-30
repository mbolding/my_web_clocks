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
}

enum Stage {
    private static let light = simd_normalize(Vec(-0.55, 0.7, 0.45))
    private static let eye = 6.0

    /// Draws the shape filling `size`, turned by `orientation`. `size` fits the shape's
    /// farthest corner to `fill` of the shorter side, times `zoom`.
    static func draw(_ shape: Polyhedron, in context: GraphicsContext, size: CGSize, orientation: simd_quatd,
                     look: Look, accent: Color, ink: Color, zoom: Double = 1, fill: Double = 0.4) {
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

        if look.faces {
            for (f, face) in shape.faces.enumerated() where facing[f] {
                let path = outline(face)
                let n = normals[f]
                let lambert = max(0, dot(n, light))
                let reflect = 2 * dot(n, light) * n - light
                let shine = pow(max(0, reflect.z), 24)
                let base = face.kind == .face ? accent : Color(white: 0.93)
                let opacity = look.hidden ? 0.82 : 1
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
                                  hidden: model.showHidden),
                       accent: accent, ink: .primary, zoom: turntable.zoom)
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
