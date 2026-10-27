// MakeIcon — renders a clock's app icon into an .iconset folder.
// build.sh compiles this with the clock's face files and its Icon.swift (which defines
// IconFace), runs it, then hands the folder to iconutil.
//   MakeIcon <output.iconset>

import SwiftUI
import AppKit

// Fixed moment so every build draws the same icon: the classic 10:09 pose.
let iconDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26,
                                                          hour: 10, minute: 9, second: 37))!

struct IconView: View {
    var body: some View {
        // Standard macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        IconFace()
            .frame(width: 824, height: 824)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 3))
            .background(shape.fill(.black).shadow(color: .black.opacity(0.3), radius: 12, y: 10))
            .frame(width: 1024, height: 1024)
    }
}

@main
struct MakeIcon {
    @MainActor static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: IconView())
                renderer.scale = CGFloat(points * scale) / 1024
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown) }
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                try png.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
