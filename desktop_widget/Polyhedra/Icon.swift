// The Polyhedra app icon: a dodecahedron with its corners cut part way towards its dual,
// drawn by the app's own stage, its faces in the accent colour and the new ones pale.

import SwiftUI
import simd

struct IconFace: View {
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.24, blue: 0.34), Color(red: 0.08, green: 0.1, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                Stage.draw(Solid.dodecahedron.shape(morph: 0.18), in: context, size: size,
                           orientation: simd_quatd(angle: 0.42, axis: Vec(1, 0, 0)) * simd_quatd(angle: -0.5, axis: Vec(0, 1, 0)),
                           look: Look(), accent: accent, ink: Color(white: 0.08), fill: 0.37)
            }
        }
    }
}
