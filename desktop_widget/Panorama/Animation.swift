// Animation — the photos one after another, as a looping GIF, held steady on what didn't
// move. It's for a burst of something moving, taken from one spot. When the photos share
// most of their view, as a burst from a steady hand does, every photo is turned back into
// the view of the middle one and cropped to the part they all saw, so the background stays
// put and no edge comes and goes. When the camera followed what it was taking, so the
// photos share little, each frame is the whole panorama, dimmed, with one photo lit up in
// its place: the moving thing crosses a still scene, and the view moves with it. Frames
// are shown for as long as there was between the shots, up to a second.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd

enum Animation {
    enum Kind: Sendable { case steady, backdrop }

    /// The longest side of a frame, in pixels: GIFs get large quickly.
    static let maxSide = 960.0
    /// How much of the middle photo's view every photo must share for a steady crop.
    static let steadyShare = 0.5
    /// How bright the panorama behind the lit photo is drawn.
    static let dim = 0.4
    /// What shows where no photo saw, behind the panorama.
    static let empty: UInt8 = 24
    /// How long each frame shows when the photos don't say when they were taken.
    static let defaultDelay = 0.1

    /// The frames, one per source in the order given. The sources come laid out for the
    /// panorama in `projection`, and `full` is the whole of it, for the backdrop.
    static func frames(_ sources: [Source], projection: Projection, full: Box, balance: Bool,
                       progress: (@Sendable (Double) -> Void)? = nil) -> (kind: Kind, frames: [Bitmap]) {
        if let steady = steadyFrames(sources, balance: balance, progress: progress) {
            return (.steady, steady)
        }
        let focal = Aligner.median(sources.map(\.focal))
        let scale = min(focal, maxSide / max(full.width, full.height))
        let backdrop = Renderer.render(sources, projection: projection, region: full, scale: scale, balance: balance)
        var frames: [Bitmap] = []
        for (n, s) in sources.enumerated() {
            let lit = Renderer.render([s], projection: projection, region: full, scale: scale, balance: balance)
            let frame = Bitmap(width: lit.width, height: lit.height)
            for i in stride(from: 0, to: lit.bytes, by: 4) {
                if lit.data[i + 3] != 0 {
                    for c in 0..<3 { frame.data[i + c] = lit.data[i + c] }
                } else if backdrop.data[i + 3] != 0 {
                    for c in 0..<3 { frame.data[i + c] = UInt8(Double(backdrop.data[i + c]) * dim) }
                } else {
                    for c in 0..<3 { frame.data[i + c] = empty }
                }
                frame.data[i + 3] = 255
            }
            frames.append(frame)
            progress?(Double(n + 1) / Double(sources.count))
        }
        return (.backdrop, frames)
    }

    /// Each source drawn alone in the middle source's view and cropped to the view they
    /// all share; nil when they share too little of it.
    static func steadyFrames(_ sources: [Source], balance: Bool, progress: (@Sendable (Double) -> Void)?) -> [Bitmap]? {
        guard sources.count >= 2 else { return nil }
        // Turn the world so the middle photo looks straight along it, upright as it was taken.
        let reference = sources[sources.count / 2]
        let turn = reference.rotation.transpose
        var turned = sources.map { s -> Source in
            var s = s
            s.rotation = s.rotation * turn
            return s
        }
        guard (try? Renderer.layout(&turned, projection: .flat)) != nil else { return nil }
        // The part of the view every photo filled.
        var shared = Box(minX: -.infinity, maxX: .infinity, minY: -.infinity, maxY: .infinity)
        for s in turned {
            let filled = Renderer.filledRectangle([s], projection: .flat, within: s.bounds)
            shared = Box(minX: max(shared.minX, filled.minX), maxX: min(shared.maxX, filled.maxX),
                         minY: max(shared.minY, filled.minY), maxY: min(shared.maxY, filled.maxY))
        }
        let referenceArea = Double(reference.bitmap.width * reference.bitmap.height) / (reference.focal * reference.focal)
        guard !shared.isEmpty, shared.width * shared.height >= steadyShare * referenceArea else { return nil }
        // At the middle photo's own resolution, or smaller to keep within the frame size.
        let scale = min(reference.focal, maxSide / max(shared.width, shared.height))
        var frames: [Bitmap] = []
        for (n, s) in turned.enumerated() {
            frames.append(Renderer.render([s], projection: .flat, region: shared, scale: scale, balance: balance))
            progress?(Double(n + 1) / Double(turned.count))
        }
        return frames
    }

    /// How long each photo should show: the time until the next was taken, and for the
    /// last one the typical gap, kept between a fiftieth of a second and one second, so
    /// shots taken far apart don't make a slideshow.
    static func delays(_ taken: [Date?]) -> [Double] {
        var gaps: [Double?] = []
        for k in taken.indices.dropLast() {
            if let a = taken[k], let b = taken[k + 1] {
                let gap = b.timeIntervalSince(a)
                gaps.append(gap > 0 ? gap : nil)
            } else {
                gaps.append(nil)
            }
        }
        let known = gaps.compactMap { $0 }
        let typical = known.isEmpty ? defaultDelay : Aligner.median(known)
        return (gaps + [typical]).map { min(1, max(0.02, $0 ?? typical)) }
    }

    /// Writes the frames as a GIF that loops for ever.
    static func write(_ frames: [CGImage], delays: [Double], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { throw CocoaError(.fileWriteUnsupportedScheme) }
        let file: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, file as CFDictionary)
        for (image, delay) in zip(frames, delays) {
            let frame: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                                          kCGImagePropertyGIFUnclampedDelayTime: delay]]
            CGImageDestinationAddImage(destination, image, frame as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
