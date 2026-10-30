// Drawing — puts the dots or the line on paper: into the window, a PNG or an SVG. The window
// and the PNG share one Core Graphics routine, so what's saved is what's shown.

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// How the drawing looks, apart from where the dots are.
struct Style: Equatable, Codable, Sendable {
    enum Mode: String, CaseIterable, Identifiable, Codable, Sendable {
        case dots, line
        var id: Self { self }
        var name: String { self == .dots ? "Dots" : "Line" }
    }

    var mode = Mode.dots
    /// Dot diameters in grid units, for the lightest and darkest parts.
    var smallest = 2.0
    var largest = 6.0
    var lineWidth = 1.5
    /// Light ink on black rather than black on white.
    var invert = false

    var ink: CGColor { invert ? .white : .black }
    var paper: CGColor { invert ? .black : .white }

    func diameter(_ shade: Float) -> CGFloat {
        CGFloat(smallest + (largest - smallest) * Double(min(max(shade, 0), 1)))
    }
}

enum Drawing {
    /// Draws on a context whose units are grid units with y pointing down. The window lays
    /// its own paper first, to put the picture between it and the ink.
    static func draw(_ stipples: Stipples, path: [Int32]?, style: Style, paper: Bool = true, in context: CGContext) {
        if paper {
            context.setFillColor(style.paper)
            context.fill(CGRect(x: 0, y: 0, width: stipples.width, height: stipples.height))
        }
        context.setFillColor(style.ink)
        context.setStrokeColor(style.ink)

        if style.mode == .line, let path, path.count > 1 {
            context.setLineWidth(style.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(stipples.xs[Int(path[0])]), y: CGFloat(stipples.ys[Int(path[0])])))
            for i in path.dropFirst() {
                context.addLine(to: CGPoint(x: CGFloat(stipples.xs[Int(i)]), y: CGFloat(stipples.ys[Int(i)])))
            }
            context.strokePath()
        } else {
            context.beginPath()
            for i in 0..<stipples.count {
                let d = style.diameter(stipples.shades[i])
                context.addEllipse(in: CGRect(x: CGFloat(stipples.xs[i]) - d / 2, y: CGFloat(stipples.ys[i]) - d / 2,
                                              width: d, height: d))
            }
            context.fillPath()
        }
    }

    /// The drawing as a bitmap `longSide` pixels on its long side.
    static func image(_ stipples: Stipples, path: [Int32]?, style: Style, longSide: Int) -> CGImage? {
        let scale = CGFloat(longSide) / CGFloat(max(stipples.width, stipples.height))
        let width = Int((CGFloat(stipples.width) * scale).rounded())
        let height = Int((CGFloat(stipples.height) * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        draw(stipples, path: path, style: style, in: context)
        return context.makeImage()
    }

    static func png(_ stipples: Stipples, path: [Int32]?, style: Style, longSide: Int) -> Data? {
        guard let image = image(stipples, path: path, style: style, longSide: longSide) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width / 2, height: image.height / 2)  // 144 dpi
        return rep.representation(using: .png, properties: [:])
    }

    /// The drawing as SVG, in grid units: filled circles for dots, or one polyline. The
    /// black-on-white version has no background, so a pen plotter draws only the ink.
    static func svg(_ stipples: Stipples, path: [Int32]?, style: Style) -> String {
        let w = stipples.width, h = stipples.height
        let ink = style.invert ? "#fff" : "#000"
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">

        """
        if style.invert {
            out += "<rect width=\"\(w)\" height=\"\(h)\" fill=\"#000\"/>\n"
        }
        func n(_ v: Float) -> String { String(format: "%.2f", v) }

        if style.mode == .line, let path, path.count > 1 {
            out += "<polyline fill=\"none\" stroke=\"\(ink)\" stroke-width=\(quoted(style.lineWidth)) "
            out += "stroke-linecap=\"round\" stroke-linejoin=\"round\" points=\""
            var line = ""
            line.reserveCapacity(path.count * 16)
            for (k, i) in path.enumerated() {
                if k > 0 { line += k % 8 == 0 ? "\n" : " " }
                line += "\(n(stipples.xs[Int(i)])),\(n(stipples.ys[Int(i)]))"
            }
            out += line + "\"/>\n"
        } else {
            out += "<g fill=\"\(ink)\">\n"
            var dots = ""
            dots.reserveCapacity(stipples.count * 48)
            for i in 0..<stipples.count {
                let r = Float(style.diameter(stipples.shades[i]) / 2)
                dots += "<circle cx=\"\(n(stipples.xs[i]))\" cy=\"\(n(stipples.ys[i]))\" r=\"\(n(r))\"/>\n"
            }
            out += dots + "</g>\n"
        }
        return out + "</svg>\n"
    }

    private static func quoted(_ v: Double) -> String { "\"\(String(format: "%.2f", v))\"" }
}
