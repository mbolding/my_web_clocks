// Stippler — weighted Voronoi stippling, after Adrian Secord's 2002 paper and Evil Mad
// Scientist's StippleGen. Dots start scattered by the image's darkness, then each moves to
// the darkness-weighted centre of the pixels nearest it (Lloyd's method), over and over,
// until they settle into an even, tone-following spread. Written fresh in Swift rather than
// ported, since StippleGen is LGPL.

import CoreGraphics
import Foundation
import ImageIO

/// The picture as a grid of darkness, 0 for white (or the cut-off) to 1 for black, sized so
/// its long side is `DensityMap.side` whatever the image's own size. Its pixels are the
/// units every drawing is measured in.
struct DensityMap: Sendable {
    static let side = 1200

    let width: Int
    let height: Int
    let darkness: [Float]

    /// The picture's own brightness, 0 to 1, before any cut-off or inversion, so changing
    /// those doesn't mean reading the file again.
    struct Gray: Sendable {
        let width: Int
        let height: Int
        let brightness: [UInt8]
    }

    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? {
            "This file couldn't be read as a picture. Stipple reads JPEG, PNG, HEIC, TIFF, GIF and the other kinds macOS can open."
        }
    }

    /// The image, turned upright, flattened onto white and scaled to the grid; and a smaller
    /// colour copy to show underneath the dots.
    static func read(_ url: URL) throws -> (gray: Gray, preview: CGImage) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: side * 2,
              ] as CFDictionary)
        else { throw Failure.unreadable }

        let scale = Double(side) / Double(max(image.width, image.height))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))

        var bytes = [UInt8](repeating: 255, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw Failure.unreadable }
        return (Gray(width: width, height: height, brightness: bytes), image)
    }

    /// Darkness from brightness. Pixels at or above `cutoff` count as white and get no dots;
    /// `invert` stipples the light parts instead, for light dots on black.
    init(_ gray: Gray, cutoff: Double, invert: Bool) {
        width = gray.width
        height = gray.height
        let limit = Float(cutoff)
        darkness = gray.brightness.map { byte in
            let b = Float(byte) / 255
            let tone = invert ? 1 - b : b
            return tone >= limit && limit < 1 ? 0 : 1 - tone
        }
    }

    func at(_ x: Float, _ y: Float) -> Float {
        let i = min(max(Int(x), 0), width - 1), j = min(max(Int(y), 0), height - 1)
        return darkness[j * width + i]
    }
}

/// The dots at one moment, to draw or save: centres in grid units, and each one's shade,
/// the mean darkness of the pixels it gathers, which sets its size.
struct Stipples: Sendable {
    var width: Int
    var height: Int
    var xs: [Float]
    var ys: [Float]
    var shades: [Float]

    var count: Int { xs.count }
    static let none = Stipples(width: 1, height: 1, xs: [], ys: [], shades: [])
}

/// One stippling in progress. It isn't safe to use from two threads at once; the model
/// runs one step at a time.
final class Stippler: @unchecked Sendable {
    let map: DensityMap
    private(set) var xs: [Float] = []
    private(set) var ys: [Float] = []
    private(set) var shades: [Float] = []
    private var generator = SystemRandomNumberGenerator()

    init(map: DensityMap, count: Int) {
        self.map = map
        xs.reserveCapacity(count)
        ys.reserveCapacity(count)
        for _ in 0..<count {
            let (x, y) = randomPoint()
            xs.append(x)
            ys.append(y)
            shades.append(map.at(x, y))
        }
    }

    var snapshot: Stipples {
        Stipples(width: map.width, height: map.height, xs: xs, ys: ys, shades: shades)
    }

    /// A spot picked with probability following the darkness, so the first scatter already
    /// looks like the picture. An all-white picture gets dots anywhere.
    private func randomPoint() -> (Float, Float) {
        for _ in 0..<10_000 {
            let x = Float.random(in: 0..<Float(map.width), using: &generator)
            let y = Float.random(in: 0..<Float(map.height), using: &generator)
            if Float.random(in: 0..<1, using: &generator) < map.at(x, y) { return (x, y) }
        }
        return (Float.random(in: 0..<Float(map.width), using: &generator),
                Float.random(in: 0..<Float(map.height), using: &generator))
    }

    /// One round of Lloyd's method. Returns how far the dots moved, on average, in pixels;
    /// it falls towards zero as they settle.
    @discardableResult
    func relax() -> Float {
        let n = xs.count
        guard n > 0 else { return 0 }
        let width = map.width, height = map.height
        let grid = PointGrid(xs: xs, ys: ys, width: width, height: height)

        // Rows are shared out in bands, one per core, each summing into its own arrays so no
        // locks are needed.
        let bands = ProcessInfo.processInfo.activeProcessorCount
        let rowsPerBand = (height + bands - 1) / bands
        var sums = [Double](repeating: 0, count: bands * n * 4)

        xs.withUnsafeBufferPointer { xs in
        ys.withUnsafeBufferPointer { ys in
        map.darkness.withUnsafeBufferPointer { darkness in
        sums.withUnsafeMutableBufferPointer { sums in
            let sumsBase = sums.baseAddress!
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                let sum = sumsBase + band * n * 4
                let rows = (band * rowsPerBand)..<min(height, (band + 1) * rowsPerBand)
                for y in rows {
                    var nearest = -1
                    let py = Float(y) + 0.5
                    for x in 0..<width {
                        let d = darkness[y * width + x]
                        guard d > 0 else { continue }
                        let px = Float(x) + 0.5
                        nearest = grid.nearest(px, py, xs: xs, ys: ys, guess: nearest)
                        let s = sum + nearest * 4
                        s[0] += Double(d * px)
                        s[1] += Double(d * py)
                        s[2] += Double(d)
                        s[3] += 1
                    }
                }
            }
        }}}}

        var moved: Float = 0
        for i in 0..<n {
            var sx = 0.0, sy = 0.0, weight = 0.0, area = 0.0
            for band in 0..<bands {
                let s = (band * n + i) * 4
                sx += sums[s]; sy += sums[s + 1]; weight += sums[s + 2]; area += sums[s + 3]
            }
            let x: Float, y: Float
            if weight > 0 {
                x = Float(sx / weight)
                y = Float(sy / weight)
                shades[i] = Float(weight / area)
            } else {
                // A dot stranded where there's nothing to gather goes somewhere useful.
                (x, y) = randomPoint()
                shades[i] = map.at(x, y)
            }
            moved += hypot(x - xs[i], y - ys[i])
            xs[i] = x
            ys[i] = y
        }
        return moved / Float(n)
    }
}

/// The dots binned into square cells about one dot apart, to find the nearest dot to a
/// spot without checking them all.
struct PointGrid {
    let cell: Float
    let columns: Int
    let rows: Int
    /// Dots in cell c are `members[starts[c]..<starts[c + 1]]`.
    let starts: [Int32]
    let members: [Int32]

    init(xs: [Float], ys: [Float], width: Int, height: Int) {
        let n = max(xs.count, 1)
        cell = max(1, (Float(width * height) / Float(n)).squareRoot())
        columns = max(1, Int((Float(width) / cell).rounded(.up)))
        rows = max(1, Int((Float(height) / cell).rounded(.up)))

        var counts = [Int32](repeating: 0, count: columns * rows + 1)
        var cellOf = [Int32](repeating: 0, count: xs.count)
        for i in xs.indices {
            let c = Self.index(xs[i], ys[i], cell: cell, columns: columns, rows: rows)
            cellOf[i] = Int32(c)
            counts[c + 1] += 1
        }
        for c in 1..<counts.count { counts[c] += counts[c - 1] }
        var fill = counts
        var members = [Int32](repeating: 0, count: xs.count)
        for i in xs.indices {
            let c = Int(cellOf[i])
            members[Int(fill[c])] = Int32(i)
            fill[c] += 1
        }
        starts = counts
        self.members = members
    }

    private static func index(_ x: Float, _ y: Float, cell: Float, columns: Int, rows: Int) -> Int {
        let cx = min(max(Int(x / cell), 0), columns - 1)
        let cy = min(max(Int(y / cell), 0), rows - 1)
        return cy * columns + cx
    }

    /// The nearest dot to (x, y), searching rings of cells outwards until no closer dot can
    /// be left. `guess`, the answer for the pixel before, gives a close start, so most
    /// searches end after the first ring.
    func nearest(_ x: Float, _ y: Float, xs: UnsafeBufferPointer<Float>, ys: UnsafeBufferPointer<Float>,
                 guess: Int) -> Int {
        var best = guess
        var bestDistance = Float.infinity
        if guess >= 0 {
            let dx = xs[guess] - x, dy = ys[guess] - y
            bestDistance = dx * dx + dy * dy
        }
        let cx = min(max(Int(x / cell), 0), columns - 1)
        let cy = min(max(Int(y / cell), 0), rows - 1)
        let reach = max(columns, rows)

        var ring = 0
        while ring <= reach {
            // Anything in this ring or beyond is at least (ring - 1) cells away.
            let near = Float(ring - 1) * cell
            if ring > 0, best >= 0, near > 0, near * near >= bestDistance { break }
            for gy in (cy - ring)...(cy + ring) where gy >= 0 && gy < rows {
                let edge = gy == cy - ring || gy == cy + ring
                var gx = cx - ring
                while gx <= cx + ring {
                    if gx >= 0 && gx < columns {
                        let c = gy * columns + gx
                        for m in Int(starts[c])..<Int(starts[c + 1]) {
                            let i = Int(members[m])
                            let dx = xs[i] - x, dy = ys[i] - y
                            let d = dx * dx + dy * dy
                            if d < bestDistance { bestDistance = d; best = i }
                        }
                    }
                    // Inside rows of the ring only have its two end cells.
                    gx += edge || ring == 0 ? 1 : 2 * ring
                }
            }
            ring += 1
        }
        return best
    }
}
