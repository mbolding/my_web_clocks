// DockTile — the analog dial on the app icon's light tile, sized to fit any square.

import SwiftUI

struct DockTile: View {
    var date: Date
    var showSeconds: Bool

    var body: some View {
        // The same grid as the app icon: an 824/1024 rounded square, so the live tile
        // sits in the Dock like the other icons.
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let tile = side * 824 / 1024
            let shape = RoundedRectangle(cornerRadius: tile * 185 / 824, style: .continuous)
            ClockFace(date: date, showSeconds: showSeconds)
                .padding(tile * 70 / 824)
                .frame(width: tile, height: tile)
                .background(LinearGradient(colors: [Color(white: 0.99), Color(white: 0.86)],
                                           startPoint: .top, endPoint: .bottom))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: max(1, tile * 3 / 824)))
                .background(shape.fill(.black).shadow(color: .black.opacity(0.3), radius: tile * 12 / 824, y: tile * 10 / 824))
                .frame(width: geo.size.width, height: geo.size.height)
                .environment(\.colorScheme, .light)
        }
    }
}
