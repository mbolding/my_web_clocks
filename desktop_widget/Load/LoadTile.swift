// LoadTile — the gauge drawn into the Dock icon: CPU load as an outer ring in the accent
// colour with the percentage in the middle, and memory pressure as an inner ring that's
// green, yellow or red as macOS grades it.

import SwiftUI

struct LoadFace: View {
    var cpu: Double
    var memory: Double
    var pressure: Load.Pressure
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Gauge(value: cpu, color: accent, width: side * 0.105)
                    .padding(side * 0.1)
                Gauge(value: memory, color: color, width: side * 0.065)
                    .padding(side * 0.255)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(Int((cpu * 100).rounded()))")
                        .font(.system(size: side * 0.2, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.system(size: side * 0.1, weight: .semibold, design: .rounded))
                }
                .monospacedDigit()
                .foregroundStyle(.white)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
    }

    private var color: Color {
        switch pressure {
        case .normal: Color(red: 0.3, green: 0.82, blue: 0.4)
        case .warning: Color(red: 1, green: 0.8, blue: 0.1)
        case .critical: Color(red: 1, green: 0.27, blue: 0.23)
        }
    }

    /// A ring filled clockwise from the top, over a faint track.
    private struct Gauge: View {
        var value: Double
        var color: Color
        var width: CGFloat

        var body: some View {
            ZStack {
                Circle().stroke(.white.opacity(0.13), lineWidth: width)
                Circle()
                    .trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// The face on a tile the shape of the other Dock icons, sized to fit any square.
struct LoadTile: View {
    var load: Load

    var body: some View {
        // The same grid as the app icon: an 824/1024 rounded square.
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let tile = side * 824 / 1024
            let shape = RoundedRectangle(cornerRadius: tile * 185 / 824, style: .continuous)
            LoadFace(cpu: load.cpu, memory: load.memoryPressure, pressure: load.pressure)
                .frame(width: tile, height: tile)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: max(1, tile * 3 / 824)))
                .background(shape.fill(.black).shadow(color: .black.opacity(0.3), radius: tile * 12 / 824, y: tile * 10 / 824))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
