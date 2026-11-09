// Renderer — drawing the panorama. Every pixel of the panorama is a direction from where
// the camera stood: on a cylinder (across is the angle turned, down is height on the
// cylinder), a sphere (across and down are both angles), or a flat plane (an ordinary
// wide-angle picture). Each pixel looks up that direction in every photo that saw it,
// and mixes them with weights that fall off away from each photo's middle and fade to
// nothing at its edges, in two bands (after Burt and Adelson, as Brown and Lowe use it):
// the broad light and colour of each photo are mixed over a wide seam, so exposure and
// vignetting change smoothly across it, and the fine detail over a seam only a few
// pixels wide, so each part of the panorama takes its detail from the one photo that saw
// it most squarely. That keeps away the ghosts a wide blend makes of anything that moved
// between shots, or that sits close enough to the camera to shift against the distance
// as it turns.

import Foundation
import Accelerate
import simd

enum Projection: String, CaseIterable, Identifiable, Sendable {
    case cylinder, sphere, flat

    var id: Self { self }
    var name: String {
        switch self {
        case .cylinder: "Cylinder"
        case .sphere: "Sphere"
        case .flat: "Flat"
        }
    }

    /// Where a direction falls, in the projection's own units (radians across, for the
    /// cylinder and sphere).
    @inline(__always) func place(_ d: SIMD3<Double>) -> SIMD2<Double>? {
        switch self {
        case .cylinder:
            let r = (d.x * d.x + d.z * d.z).squareRoot()
            guard r > 1e-9 else { return nil }
            return SIMD2(atan2(d.x, d.z), d.y / r)
        case .sphere:
            return SIMD2(atan2(d.x, d.z), atan2(d.y, (d.x * d.x + d.z * d.z).squareRoot()))
        case .flat:
            guard d.z > 1e-6 else { return nil }
            return SIMD2(d.x / d.z, d.y / d.z)
        }
    }

    /// The direction at a place.
    @inline(__always) func direction(_ x: Double, _ y: Double) -> SIMD3<Double> {
        switch self {
        case .cylinder: return SIMD3(sin(x), y, cos(x))
        case .sphere:
            let c = cos(y)
            return SIMD3(c * sin(x), sin(y), c * cos(x))
        case .flat: return SIMD3(x, y, 1)
        }
    }

    var wraps: Bool { self != .flat }
}

/// One photo ready to draw from: its pixels and where it pointed, scaled to them.
struct Source: Sendable {
    var bitmap: Bitmap
    var rotation: Mat3
    var focal: Double   // in this bitmap's pixels
    var gain: Double
    /// The part of the panorama it covers, in the projection's units.
    var bounds: Box = Box()
}

struct Box: Sendable, Equatable {
    var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var isEmpty: Bool { !(maxX > minX && maxY > minY) }
    mutating func add(_ p: SIMD2<Double>) {
        minX = min(minX, p.x); maxX = max(maxX, p.x)
        minY = min(minY, p.y); maxY = max(maxY, p.y)
    }
    func union(_ b: Box) -> Box {
        Box(minX: min(minX, b.minX), maxX: max(maxX, b.maxX), minY: min(minY, b.minY), maxY: max(maxY, b.maxY))
    }
    @inline(__always) func contains(_ x: Double, _ y: Double) -> Bool { x >= minX && x <= maxX && y >= minY && y <= maxY }
}

/// Where the panorama lies, and the part of it to keep.
struct Layout: Sendable, Equatable {
    var projection: Projection
    var full: Box
    var crop: Box
    /// Degrees of view across and down.
    var degrees: SIMD2<Double>
}

enum LayoutError: LocalizedError {
    case tooWideForFlat

    var errorDescription: String? {
        "These photos turn too far for a flat panorama, which can't show more than about 150° across. Choose Cylinder or Sphere."
    }
}

enum Renderer {

    /// How sharply the weights fall away from each photo's middle, as a fraction of its
    /// half-width: smaller is a narrower seam. Fine detail changes over the narrow seam,
    /// broad light and colour over the wider one, which is still kept narrow enough that
    /// something close to the camera, seen against different backgrounds in two photos,
    /// isn't smeared across the overlap. The broad weight is also multiplied by
    /// (1 − distance)², so it reaches nothing at a photo's edge without a step.
    static let fineSeam = 0.01
    static let broadSeam = 0.05
    /// The long side of the blurred copy of each photo that holds its broad light and
    /// colour; what's left over is its fine detail.
    static let broadSide = 160
    /// How much of each photo's edge fades out.
    static let fade = 0.03

    /// Works out each source's bounds and the panorama's layout.
    static func layout(_ sources: inout [Source], projection: Projection) throws -> Layout {
        var all = Box()
        for k in sources.indices {
            let s = sources[k]
            let w = Double(s.bitmap.width), h = Double(s.bitmap.height)
            let inverse = s.rotation.transpose
            let centre = projection.place(inverse * SIMD3(0, 0, 1))
            var box = Box()
            let steps = 48
            for t in 0...steps {
                let a = Double(t) / Double(steps)
                for p in [SIMD2(a * w, 0), SIMD2(a * w, h), SIMD2(0, a * h), SIMD2(w, a * h), SIMD2(w / 2, a * h), SIMD2(a * w, h / 2)] {
                    let ray = inverse * SIMD3((p.x - w / 2) / s.focal, (p.y - h / 2) / s.focal, 1)
                    if projection == .flat, ray.z <= 0.05 * simd_length(ray) { throw LayoutError.tooWideForFlat }
                    guard var q = projection.place(ray) else { continue }
                    // Keep a photo's angles together across the ±180° line.
                    if projection.wraps, let c = centre {
                        q.x = c.x + remainder(q.x - c.x, 2 * .pi)
                    }
                    box.add(q)
                }
            }
            sources[k].bounds = box
            all = all.union(box)
        }
        if projection.wraps, all.width > 2 * .pi {
            let middle = (all.minX + all.maxX) / 2
            all.minX = middle - .pi
            all.maxX = middle + .pi
        }
        if projection == .flat, all.width > 6 { throw LayoutError.tooWideForFlat }

        let crop = filledRectangle(sources, projection: projection, within: all)
        let toDegrees = { (v: Double) in v * 180 / .pi }
        let degrees: SIMD2<Double>
        switch projection {
        case .cylinder: degrees = SIMD2(toDegrees(crop.width), toDegrees(atan(crop.maxY) - atan(crop.minY)))
        case .sphere: degrees = SIMD2(toDegrees(crop.width), toDegrees(crop.height))
        case .flat: degrees = SIMD2(toDegrees(atan(crop.maxX) - atan(crop.minX)), toDegrees(atan(crop.maxY) - atan(crop.minY)))
        }
        return Layout(projection: projection, full: all, crop: crop, degrees: degrees)
    }

    /// The largest rectangle every part of which some photo covers, found on a coarse
    /// grid over the panorama.
    static func filledRectangle(_ sources: [Source], projection: Projection, within box: Box) -> Box {
        let columns = 600
        let rows = max(20, min(1200, Int(Double(columns) * box.height / box.width)))
        let dx = box.width / Double(columns), dy = box.height / Double(rows)
        var covered = [Bool](repeating: false, count: columns * rows)
        covered.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: rows) { r in
                let y = box.minY + (Double(r) + 0.5) * dy
                for c in 0..<columns {
                    let x = box.minX + (Double(c) + 0.5) * dx
                    let d = projection.direction(x, y)
                    for s in sources where sees(s, x, y, d, projection: projection, inset: 0.01) {
                        base[r * columns + c] = true
                        break
                    }
                }
            }
        }
        // Largest rectangle of trues, by the histogram method a row at a time.
        var heights = [Int](repeating: 0, count: columns)
        var best = (area: 0, left: 0, right: 0, top: 0, bottom: 0)
        for r in 0..<rows {
            for c in 0..<columns { heights[c] = covered[r * columns + c] ? heights[c] + 1 : 0 }
            var stack: [Int] = []
            for c in 0...columns {
                let h = c < columns ? heights[c] : 0
                while let top = stack.last, heights[top] >= h {
                    stack.removeLast()
                    let height = heights[top]
                    let left = (stack.last ?? -1) + 1
                    let area = height * (c - left)
                    if area > best.area { best = (area, left, c, r - height + 1, r + 1) }
                    if stack.isEmpty { break }
                }
                if c < columns { stack.append(c) }
            }
        }
        guard best.area > 0 else { return box }
        // In a cell from the edges found, to be sure every pixel is covered.
        let inset = 1.0
        return Box(minX: box.minX + (Double(best.left) + inset) * dx, maxX: box.minX + (Double(best.right) - inset) * dx,
                   minY: box.minY + (Double(best.top) + inset) * dy, maxY: box.minY + (Double(best.bottom) - inset) * dy)
    }

    /// Whether a source saw a place in the panorama (given there and as its direction).
    @inline(__always) static func sees(_ s: Source, _ x: Double, _ y: Double, _ d: SIMD3<Double>,
                                       projection: Projection, inset: Double = 0) -> Bool {
        guard inBounds(s, x, y, projection: projection) else { return false }
        let c = s.rotation * d
        guard c.z > 1e-9 else { return false }
        let w = Double(s.bitmap.width), h = Double(s.bitmap.height)
        let u = s.focal * c.x / c.z + w / 2, v = s.focal * c.y / c.z + h / 2
        return u >= w * inset && u <= w * (1 - inset) && v >= h * inset && v <= h * (1 - inset)
    }

    @inline(__always) static func inBounds(_ s: Source, _ x: Double, _ y: Double, projection: Projection) -> Bool {
        if s.bounds.contains(x, y) { return true }
        guard projection.wraps else { return false }
        return s.bounds.contains(x + 2 * .pi, y) || s.bounds.contains(x - 2 * .pi, y)
    }

    /// A source flattened to plain numbers and a pointer, for the inner loop, where
    /// retaining and releasing a class reference for every pixel would cost more than the
    /// arithmetic.
    private struct Lens {
        var r: Mat3, focal, w, h, gain: Double
        var bounds: Box
        var pixels: UnsafePointer<UInt8>
        var width, height: Int
        var broad: UnsafePointer<UInt8>
        var broadWidth, broadHeight: Int
    }

    /// A small, blurred copy of a photo: its light and colour without the detail. Shrunk
    /// to `broadSide` along its long side, then blurred by three passes of a box, close to
    /// a Gaussian about a fiftieth of the photo across.
    static func broad(_ bitmap: Bitmap) -> Bitmap {
        let ratio = Double(broadSide) / Double(max(bitmap.width, bitmap.height))
        let w = max(2, Int((Double(bitmap.width) * ratio).rounded())), h = max(2, Int((Double(bitmap.height) * ratio).rounded()))
        let small = Bitmap(width: w, height: h), spare = Bitmap(width: w, height: h)
        var source = vImage_Buffer(data: bitmap.data, height: vImagePixelCount(bitmap.height),
                                   width: vImagePixelCount(bitmap.width), rowBytes: bitmap.width * 4)
        var a = vImage_Buffer(data: small.data, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
        var b = vImage_Buffer(data: spare.data, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
        vImageScale_ARGB8888(&source, &a, nil, vImage_Flags(kvImageHighQualityResampling))
        for _ in 0..<3 {
            vImageBoxConvolve_ARGB8888(&a, &b, nil, 0, 0, 7, 7, nil, vImage_Flags(kvImageEdgeExtend))
            swap(&a, &b)
        }
        // Three passes leave the result in the spare.
        return a.data == small.data ? small : spare
    }

    /// Draws a region of the panorama at `scale` pixels to the projection's unit, as an
    /// RGBA bitmap, transparent where no photo saw. `progress` hears the fraction done.
    static func render(_ sources: [Source], projection: Projection, region: Box, scale: Double,
                       balance: Bool, progress: (@Sendable (Double) -> Void)? = nil,
                       cancelled: (@Sendable () -> Bool)? = nil) -> Bitmap {
        let width = max(1, Int((region.width * scale).rounded())), height = max(1, Int((region.height * scale).rounded()))
        let out = Bitmap(width: width, height: height)
        let data = out.data
        var broads = [Bitmap?](repeating: nil, count: sources.count)
        broads.withUnsafeMutableBufferPointer { buffer in
            let slots = Slots(buffer.baseAddress!)
            DispatchQueue.concurrentPerform(iterations: sources.count) { slots[$0] = broad(sources[$0].bitmap) }
        }
        let blurred = broads.map { $0! }
        let lenses = zip(sources, blurred).map { source, broad in
            Lens(r: source.rotation, focal: source.focal, w: Double(source.bitmap.width), h: Double(source.bitmap.height),
                 gain: balance ? source.gain : 1, bounds: source.bounds, pixels: UnsafePointer(source.bitmap.data),
                 width: source.bitmap.width, height: source.bitmap.height,
                 broad: UnsafePointer(broad.data), broadWidth: broad.width, broadHeight: broad.height)
        }
        let count = lenses.count
        let wraps = projection.wraps
        // What each column and row contribute to the direction, worked out once.
        let xs = (0..<width).map { region.minX + (Double($0) + 0.5) / scale }
        let ys = (0..<height).map { region.minY + (Double($0) + 0.5) / scale }
        let sinX = xs.map(sin), cosX = xs.map(cos)
        let band = 16
        let bands = (height + band - 1) / band
        let done = Counter()
        withExtendedLifetime((sources, blurred)) {
            lenses.withUnsafeBufferPointer { lens in
                DispatchQueue.concurrentPerform(iterations: bands) { b in
                    if cancelled?() == true { return }
                    var fineExponents = [Double](repeating: 0, count: count)
                    var broadWeights = [Double](repeating: 0, count: count)
                    var fineDistances = [Double](repeating: 0, count: count)
                    var colours = [SIMD3<Double>](repeating: .zero, count: count)
                    var lights = [SIMD3<Double>](repeating: .zero, count: count)
                    var active = [Int](repeating: 0, count: count)
                    for row in (b * band)..<min(height, (b + 1) * band) {
                        let y = ys[row]
                        let sinY = sin(y), cosY = cos(y)
                        // The photos this row passes through at all.
                        var rowCount = 0
                        for k in 0..<count where y >= lens[k].bounds.minY && y <= lens[k].bounds.maxY {
                            active[rowCount] = k
                            rowCount += 1
                        }
                        let rowBase = row * width
                        for column in 0..<width {
                            let x = xs[column]
                            let d: SIMD3<Double>
                            switch projection {
                            case .cylinder: d = SIMD3(sinX[column], y, cosX[column])
                            case .sphere: d = SIMD3(cosY * sinX[column], sinY, cosY * cosX[column])
                            case .flat: d = SIMD3(x, y, 1)
                            }
                            var used = 0
                            var nearestFine = Double.infinity
                            for a in 0..<rowCount {
                                let s = lens[active[a]]
                                let bx = s.bounds
                                guard (x >= bx.minX && x <= bx.maxX)
                                    || (wraps && ((x + 2 * .pi >= bx.minX && x + 2 * .pi <= bx.maxX)
                                        || (x - 2 * .pi >= bx.minX && x - 2 * .pi <= bx.maxX)))
                                else { continue }
                                let c = s.r * d
                                guard c.z > 1e-9 else { continue }
                                let u = s.focal * c.x / c.z + s.w / 2, v = s.focal * c.y / c.z + s.h / 2
                                guard u >= 0, u <= s.w, v >= 0, v <= s.h else { continue }
                                let distance = max(abs(u - s.w / 2) / (s.w / 2), abs(v - s.h / 2) / (s.h / 2))
                                let taper = min(1, (1 - distance) / fade)
                                guard taper > 0 else { continue }
                                colours[used] = sample(s.pixels, s.width, s.height, u - 0.5, v - 0.5) * s.gain
                                // The fine weight is exp(−distance / seam) × taper, kept as its
                                // exponent so the weights can be formed relative to the largest
                                // without overflowing.
                                fineExponents[used] = distance - fineSeam * log(taper)
                                nearestFine = min(nearestFine, fineExponents[used])
                                broadWeights[used] = (1 - distance) * (1 - distance)
                                fineDistances[used] = distance
                                used += 1
                                lights[used - 1] = sample(s.broad, s.broadWidth, s.broadHeight,
                                                          u * Double(s.broadWidth) / s.w - 0.5,
                                                          v * Double(s.broadHeight) / s.h - 0.5) * s.gain
                            }
                            guard used > 0 else { continue }
                            let c: SIMD3<Double>
                            if used == 1 {
                                c = colours[0]
                            } else {
                                // Broad light from the wide mix, and on top of it the detail
                                // (each photo less its broad light) from the narrow one.
                                var closest = Double.infinity
                                for k in 0..<used { closest = min(closest, fineDistances[k]) }
                                var fineTotal = 0.0, broadTotal = 0.0
                                var fine = SIMD3<Double>.zero, light = SIMD3<Double>.zero
                                for k in 0..<used {
                                    let wf = exp(-(fineExponents[k] - nearestFine) / fineSeam)
                                    let wb = broadWeights[k] * exp(-(fineDistances[k] - closest) / broadSeam)
                                    fineTotal += wf
                                    broadTotal += wb
                                    fine += (colours[k] - lights[k]) * wf
                                    light += lights[k] * wb
                                }
                                c = light / broadTotal + fine / fineTotal
                            }
                            let i = (rowBase + column) * 4
                            data[i] = UInt8(max(0, min(255, c.x.rounded())))
                            data[i + 1] = UInt8(max(0, min(255, c.y.rounded())))
                            data[i + 2] = UInt8(max(0, min(255, c.z.rounded())))
                            data[i + 3] = 255
                        }
                    }
                    if let progress { progress(Double(done.increment()) / Double(bands)) }
                }
            }
        }
        return out
    }

    @inline(__always) static func sample(_ d: UnsafePointer<UInt8>, _ w: Int, _ h: Int,
                                         _ x: Double, _ y: Double) -> SIMD3<Double> {
        let xc = min(max(x, 0), Double(w - 1)), yc = min(max(y, 0), Double(h - 1))
        let x0 = min(Int(xc), max(0, w - 2)), y0 = min(Int(yc), max(0, h - 2))
        let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
        let fx = xc - Double(x0), fy = yc - Double(y0)
        let i00 = (y0 * w + x0) * 4, i10 = (y0 * w + x1) * 4, i01 = (y1 * w + x0) * 4, i11 = (y1 * w + x1) * 4
        let p00 = SIMD3(Double(d[i00]), Double(d[i00 + 1]), Double(d[i00 + 2]))
        let p10 = SIMD3(Double(d[i10]), Double(d[i10 + 1]), Double(d[i10 + 2]))
        let p01 = SIMD3(Double(d[i01]), Double(d[i01 + 1]), Double(d[i01 + 2]))
        let p11 = SIMD3(Double(d[i11]), Double(d[i11 + 1]), Double(d[i11 + 2]))
        let top = p00 + (p10 - p00) * fx
        let bottom = p01 + (p11 - p01) * fx
        return top + (bottom - top) * fy
    }
}

/// A thread-safe count, for progress from the render's bands.
final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
