// Features — the points two photos are matched by. Corners are found with the Harris
// detector on three octaves of each photo, spread evenly over it, and each is described by
// a small patch of the blurred picture around it, turned to its own gradient and
// normalised for brightness and contrast (Brown, Szeliski and Winder's MOPS, which was
// made for stitching panoramas). Patches are compared with one matrix product, and the
// matches between two photos are sorted out by RANSAC into a homography and the matches
// that agree with it.

import Foundation
import Accelerate
import simd

/// A greyscale picture in floats, 0 to 1.
struct Gray {
    var width: Int, height: Int
    var pixels: [Float]

    init(width: Int, height: Int, pixels: [Float]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init(_ bitmap: Bitmap) {
        width = bitmap.width
        height = bitmap.height
        var out = [Float](repeating: 0, count: width * height)
        let data = bitmap.data
        out.withUnsafeMutableBufferPointer { buf in
            for i in 0..<buf.count {
                let r = Float(data[i * 4]), g = Float(data[i * 4 + 1]), b = Float(data[i * 4 + 2])
                buf[i] = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            }
        }
        pixels = out
    }

    @inline(__always) func at(_ x: Int, _ y: Int) -> Float {
        pixels[min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)]
    }

    /// Bilinear sample, in pixel-index coordinates (a pixel's centre is its index).
    @inline(__always) func sample(_ x: Float, _ y: Float) -> Float {
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Float(x0), fy = y - Float(y0)
        let a = at(x0, y0), b = at(x0 + 1, y0), c = at(x0, y0 + 1), d = at(x0 + 1, y0 + 1)
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
    }

    /// Separable Gaussian blur.
    func blurred(_ sigma: Float) -> Gray {
        let radius = max(1, Int((sigma * 3).rounded(.up)))
        var kernel = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
        let sum = kernel.reduce(0, +)
        kernel = kernel.map { $0 / sum }
        let w = width, h = height
        var temp = [Float](repeating: 0, count: w * h)
        var out = [Float](repeating: 0, count: w * h)
        pixels.withUnsafeBufferPointer { src in
            temp.withUnsafeMutableBufferPointer { tmp in
                let tmpBase = tmp.baseAddress!
                DispatchQueue.concurrentPerform(iterations: h) { y in
                    let row = y * w
                    for x in 0..<w {
                        var acc: Float = 0
                        for k in -radius...radius {
                            acc += kernel[k + radius] * src[row + min(max(x + k, 0), w - 1)]
                        }
                        tmpBase[row + x] = acc
                    }
                }
            }
        }
        temp.withUnsafeBufferPointer { tmp in
            out.withUnsafeMutableBufferPointer { dst in
                let dstBase = dst.baseAddress!
                DispatchQueue.concurrentPerform(iterations: h) { y in
                    for x in 0..<w {
                        var acc: Float = 0
                        for k in -radius...radius {
                            acc += kernel[k + radius] * tmp[min(max(y + k, 0), h - 1) * w + x]
                        }
                        dstBase[y * w + x] = acc
                    }
                }
            }
        }
        return Gray(width: w, height: h, pixels: out)
    }

    /// Half the size, each pixel the mean of a 2×2 block.
    func halved() -> Gray {
        let w = width / 2, h = height / 2
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = 2 * y * width + 2 * x
                out[y * w + x] = (pixels[i] + pixels[i + 1] + pixels[i + width] + pixels[i + width + 1]) / 4
            }
        }
        return Gray(width: w, height: h, pixels: out)
    }
}

/// One photo's corners: positions in its working picture's pixel indices, and a 64-number
/// patch for each.
struct Features: Sendable {
    var xs: [Float] = []
    var ys: [Float] = []
    var descriptors: [Float] = []   // count × 64, row by row
    var count: Int { xs.count }

    static let size = 64

    /// Finds the corners of a working picture.
    static func find(in gray: Gray) -> Features {
        var features = Features()
        var level = gray.blurred(0.7)
        for octave in 0..<3 {
            if level.width < 120 || level.height < 120 { break }
            features.add(level, octave: octave, perCell: octave == 0 ? 3 : 2)
            level = level.blurred(1).halved()
        }
        return features
    }

    private mutating func add(_ image: Gray, octave: Int, perCell: Int) {
        let w = image.width, h = image.height
        // Harris corner strength, as the harmonic mean of the structure tensor's eigenvalues.
        let smooth = image.blurred(1)
        var ixx = [Float](repeating: 0, count: w * h), iyy = ixx, ixy = ixx
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let gx = (smooth.pixels[i + 1] - smooth.pixels[i - 1]) / 2
                let gy = (smooth.pixels[i + w] - smooth.pixels[i - w]) / 2
                ixx[i] = gx * gx
                iyy[i] = gy * gy
                ixy[i] = gx * gy
            }
        }
        let sxx = Gray(width: w, height: h, pixels: ixx).blurred(1.5)
        let syy = Gray(width: w, height: h, pixels: iyy).blurred(1.5)
        let sxy = Gray(width: w, height: h, pixels: ixy).blurred(1.5)
        var strength = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let a = sxx.pixels[i], b = syy.pixels[i], c = sxy.pixels[i]
            strength[i] = (a * b - c * c) / (a + b + 1e-10)
        }

        // Local maxima, away from the edges so a whole patch fits, kept a few to a cell so
        // they cover the picture evenly.
        let margin = 30
        guard w > margin * 2 + 4, h > margin * 2 + 4 else { return }
        let cell = max(16, max(w, h) / 24)
        let columns = (w + cell - 1) / cell, rows = (h + cell - 1) / cell
        var cells = [[(Float, Int, Int)]](repeating: [], count: columns * rows)
        let threshold: Float = 2e-5
        for y in margin..<(h - margin) {
            for x in margin..<(w - margin) {
                let i = y * w + x
                let s = strength[i]
                guard s > threshold else { continue }
                var peak = true
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        if strength[i + dy * w + dx] >= s { peak = false }
                    }
                }
                guard peak else { continue }
                let c = (y / cell) * columns + x / cell
                cells[c].append((s, x, y))
            }
        }

        let orient = image.blurred(4.5)
        let patchSource = image.blurred(2)
        let scale = Float(1 << octave)
        for var list in cells {
            list.sort { $0.0 > $1.0 }
            for (_, x, y) in list.prefix(perCell) {
                // Sub-pixel peak, from a parabola through the neighbours.
                let i = y * w + x
                func offset(_ m: Float, _ c: Float, _ p: Float) -> Float {
                    let d = 2 * c - m - p
                    return d > 1e-12 ? max(-0.5, min(0.5, (p - m) / (2 * d))) : 0
                }
                let fx = Float(x) + offset(strength[i - 1], strength[i], strength[i + 1])
                let fy = Float(y) + offset(strength[i - w], strength[i], strength[i + w])

                let gx = orient.sample(fx + 1, fy) - orient.sample(fx - 1, fy)
                let gy = orient.sample(fx, fy + 1) - orient.sample(fx, fy - 1)
                let angle = atan2(gy, gx)
                let ca = cos(angle), sa = sin(angle)

                var patch = [Float](repeating: 0, count: Features.size)
                let spacing: Float = 5
                for row in 0..<8 {
                    for column in 0..<8 {
                        let u = (Float(column) - 3.5) * spacing, v = (Float(row) - 3.5) * spacing
                        patch[row * 8 + column] = patchSource.sample(fx + ca * u - sa * v, fy + sa * u + ca * v)
                    }
                }
                let mean = patch.reduce(0, +) / Float(Features.size)
                var variance: Float = 0
                for k in 0..<Features.size { patch[k] -= mean; variance += patch[k] * patch[k] }
                let deviation = (variance / Float(Features.size)).squareRoot()
                guard deviation > 0.004 else { continue }
                for k in 0..<Features.size { patch[k] /= deviation }

                // Back to the working picture's pixels: an octave pixel's centre sits at
                // the middle of the block it was averaged from.
                xs.append((fx + 0.5) * scale - 0.5)
                ys.append((fy + 0.5) * scale - 0.5)
                descriptors += patch
            }
        }
    }
}

/// The matches between two photos that agree on one homography, mapping points of the
/// second photo onto the first.
struct PairMatch: Sendable {
    var i: Int, j: Int
    var homography: Mat3                 // j's working pixels → i's
    var pointsI: [SIMD2<Double>]         // inliers, in i's working pixel indices
    var pointsJ: [SIMD2<Double>]
    var candidates: Int                  // matches before RANSAC
}

enum Matcher {
    /// Nearest-neighbour matches from a to b, kept when each is the other's best and
    /// clearly better than the next best.
    static func match(_ a: Features, _ b: Features) -> [(Int, Int)] {
        let na = a.count, nb = b.count
        guard na >= 8, nb >= 8 else { return [] }
        // Every dot product at once: a's patches (na × 64) times b's turned on their side.
        let size = Features.size
        var columns = [Float](repeating: 0, count: size * nb)
        for c in 0..<nb { for k in 0..<size { columns[k * nb + c] = b.descriptors[c * size + k] } }
        var dots = [Float](repeating: 0, count: na * nb)
        vDSP_mmul(a.descriptors, 1, columns, 1, &dots, 1, vDSP_Length(na), vDSP_Length(nb), vDSP_Length(size))
        // Each patch has 64 numbers of mean 0 and deviation 1, so the squared distance
        // between two is 128 − 2 × their dot product.
        let n = Float(2 * Features.size)
        var bestForB = [Int](repeating: -1, count: nb)
        var bestDotForB = [Float](repeating: -.infinity, count: nb)
        for r in 0..<na {
            for c in 0..<nb where dots[r * nb + c] > bestDotForB[c] {
                bestDotForB[c] = dots[r * nb + c]
                bestForB[c] = r
            }
        }
        var matches: [(Int, Int)] = []
        for r in 0..<na {
            var first: Float = -.infinity, second: Float = -.infinity, best = -1
            for c in 0..<nb {
                let d = dots[r * nb + c]
                if d > first { second = first; first = d; best = c } else if d > second { second = d }
            }
            guard best >= 0, bestForB[best] == r else { continue }
            let d1 = n - 2 * first, d2 = n - 2 * second
            if d1 < 0.6 * d2 { matches.append((r, best)) }
        }
        return matches
    }

    /// RANSAC for the homography from b's points to a's, then least squares over the
    /// matches that agree with it. Nil when too few agree for the pair to be trusted.
    static func homography(_ a: Features, _ b: Features, matches: [(Int, Int)], i: Int, j: Int,
                           sizeA: SIMD2<Double>, sizeB: SIMD2<Double>) -> PairMatch? {
        guard matches.count >= 12 else { return nil }
        // Points centred and scaled about each picture's middle, for a well-conditioned fit.
        let scale = 2 / max(sizeA.x, sizeA.y, sizeB.x, sizeB.y)
        let ca = sizeA / 2, cb = sizeB / 2
        let pa = matches.map { (SIMD2(Double(a.xs[$0.0]), Double(a.ys[$0.0])) - ca) * scale }
        let pb = matches.map { (SIMD2(Double(b.xs[$0.1]), Double(b.ys[$0.1])) - cb) * scale }
        let threshold = 3 * scale, threshold2 = threshold * threshold

        var rng = SplitMix(seed: UInt64(i * 7919 + j * 104_729 + matches.count))
        var bestInliers: [Int] = []
        var iterations = 1500, k = 0
        while k < iterations {
            k += 1
            var picks = Set<Int>()
            while picks.count < 4 { picks.insert(Int(rng.next() % UInt64(matches.count))) }
            let idx = Array(picks)
            guard let h = Homography.fit(from: idx.map { pb[$0] }, to: idx.map { pa[$0] }) else { continue }
            var inliers: [Int] = []
            for m in 0..<matches.count where Homography.error2(h, pb[m], pa[m]) < threshold2 { inliers.append(m) }
            if inliers.count > bestInliers.count {
                bestInliers = inliers
                let ratio = Double(inliers.count) / Double(matches.count)
                let needed = log(0.001) / log(max(1e-9, 1 - pow(ratio, 4)))
                iterations = min(iterations, Int(needed.rounded(.up)) + 20)
            }
        }
        guard bestInliers.count >= 10 else { return nil }

        // Refit to every inlier, and let the inliers settle.
        var h = Homography.fit(from: bestInliers.map { pb[$0] }, to: bestInliers.map { pa[$0] })
        for _ in 0..<3 {
            guard let fit = h else { break }
            let inliers = (0..<matches.count).filter { Homography.error2(fit, pb[$0], pa[$0]) < threshold2 }
            guard inliers.count >= bestInliers.count / 2 else { break }
            bestInliers = inliers
            h = Homography.fit(from: inliers.map { pb[$0] }, to: inliers.map { pa[$0] })
        }
        guard let normalised = h else { return nil }

        // A pair is trusted when its inliers aren't a chance alignment of a few matches
        // (after Brown and Lowe's test). It counts only the matches that fall where the two
        // pictures overlap: water, sky and foliage give plenty of false matches elsewhere,
        // which say nothing about whether the overlap agrees.
        let halfA = ca * scale
        let overlapping = (0..<matches.count).filter { m in
            let p = normalised * SIMD3(pb[m].x, pb[m].y, 1)
            guard p.z > 0 else { return false }
            return abs(p.x / p.z) <= halfA.x && abs(p.y / p.z) <= halfA.y
        }.count
        guard Double(bestInliers.count) > 8 + 0.3 * Double(overlapping) else { return nil }

        // Back to pixel indices: x_a = Ta⁻¹ · H · Tb · x_b.
        let tb = Mat3(rows: [SIMD3(scale, 0, -cb.x * scale), SIMD3(0, scale, -cb.y * scale), SIMD3(0, 0, 1)])
        let ta = Mat3(rows: [SIMD3(scale, 0, -ca.x * scale), SIMD3(0, scale, -ca.y * scale), SIMD3(0, 0, 1)])
        let full = ta.inverse * normalised * tb
        return PairMatch(i: i, j: j, homography: full,
                         pointsI: bestInliers.map { SIMD2(Double(a.xs[matches[$0].0]), Double(a.ys[matches[$0].0])) },
                         pointsJ: bestInliers.map { SIMD2(Double(b.xs[matches[$0].1]), Double(b.ys[matches[$0].1])) },
                         candidates: matches.count)
    }
}

enum Homography {
    /// The homography taking `from` to `to`, by the direct linear transform with h₃₃ = 1:
    /// exactly through four points, in the least-squares sense through more.
    static func fit(from: [SIMD2<Double>], to: [SIMD2<Double>]) -> Mat3? {
        var ata = [Double](repeating: 0, count: 64), atb = [Double](repeating: 0, count: 8)
        for (p, q) in zip(from, to) {
            let rows: [([Double], Double)] = [
                ([p.x, p.y, 1, 0, 0, 0, -q.x * p.x, -q.x * p.y], q.x),
                ([0, 0, 0, p.x, p.y, 1, -q.y * p.x, -q.y * p.y], q.y),
            ]
            for (r, v) in rows {
                for a in 0..<8 {
                    atb[a] += r[a] * v
                    for b in 0..<8 { ata[a * 8 + b] += r[a] * r[b] }
                }
            }
        }
        guard let h = Linear.solve(ata, atb, n: 8) else { return nil }
        let m = Mat3(rows: [SIMD3(h[0], h[1], h[2]), SIMD3(h[3], h[4], h[5]), SIMD3(h[6], h[7], 1)])
        // Reject folds and wild perspective: a camera turning sees nothing like either.
        let d = h[0] * h[4] - h[1] * h[3]
        guard d > 0.2, d < 5, abs(h[6]) < 2, abs(h[7]) < 2 else { return nil }
        return m
    }

    @inline(__always) static func apply(_ h: Mat3, _ p: SIMD2<Double>) -> SIMD2<Double>? {
        let v = h * SIMD3(p.x, p.y, 1)
        guard abs(v.z) > 1e-12 else { return nil }
        return SIMD2(v.x / v.z, v.y / v.z)
    }

    @inline(__always) static func error2(_ h: Mat3, _ p: SIMD2<Double>, _ q: SIMD2<Double>) -> Double {
        guard let m = apply(h, p) else { return .infinity }
        let d = m - q
        return d.x * d.x + d.y * d.y
    }
}

/// A small, seedable random number generator, so a stitch comes out the same every time.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Linear {
    /// Solves A x = b (A is n × n, row by row) by Gaussian elimination with partial pivoting.
    static func solve(_ a: [Double], _ b: [Double], n: Int) -> [Double]? {
        var m = a, v = b
        for col in 0..<n {
            var pivot = col
            for r in (col + 1)..<max(col + 1, n) where abs(m[r * n + col]) > abs(m[pivot * n + col]) { pivot = r }
            guard abs(m[pivot * n + col]) > 1e-14 else { return nil }
            if pivot != col {
                for c in 0..<n { m.swapAt(col * n + c, pivot * n + c) }
                v.swapAt(col, pivot)
            }
            for r in (col + 1)..<max(col + 1, n) {
                let f = m[r * n + col] / m[col * n + col]
                if f == 0 { continue }
                for c in col..<n { m[r * n + c] -= f * m[col * n + c] }
                v[r] -= f * v[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = v[r]
            for c in (r + 1)..<max(r + 1, n) { s -= m[r * n + c] * x[c] }
            x[r] = s / m[r * n + r]
        }
        return x.allSatisfy(\.isFinite) ? x : nil
    }
}
