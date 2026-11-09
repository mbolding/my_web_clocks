// Aligner — where each photo was pointing. Every pair of photos is matched; the pairs that
// agree on a homography join a graph, and the photos joined to the most others are placed
// first, each turned from a neighbour by the rotation its homography implies. A bundle
// adjustment then moves every camera, and the focal length, until the matched points
// line up all at once, the horizon is levelled from the way the cameras turned, and each
// photo's exposure is matched to its neighbours'.
//
// The camera model: a photo's centred pixel c (pixels from its middle, y down) sees the ray
// Rᵀ (cₓ/f, c_y/f, 1), with R the rotation from the world into the camera.

import Foundation
import simd

struct Camera: Sendable {
    /// From the world into the camera.
    var rotation: Mat3
    /// In the photo's own full-size pixels.
    var focal: Double
    /// What its brightness is multiplied by, to match its neighbours.
    var gain: Double
}

struct Placement: Sendable {
    enum FocalSource: Sendable { case exif, estimated, guessed }

    /// By photo index; photos that matched nothing aren't here.
    var cameras: [Int: Camera]
    /// The photos left out, which overlapped too little with the others.
    var unplaced: [Int]
    /// How far matched points still miss, on average, in full-size pixels.
    var error: Double
    /// The focal length used, as on a 35 mm camera, and where it came from.
    var focal35: Double
    var focalSource: FocalSource
}

enum AlignError: LocalizedError {
    case noOverlap

    var errorDescription: String? {
        switch self {
        case .noOverlap:
            "No two of these photos overlap enough to match. Panoramas need photos taken from one spot, each overlapping the next by a third or so."
        }
    }
}

/// A photo as the aligner sees it: its features in a working-size copy.
struct WorkingPhoto: Sendable {
    var photo: Photo
    var bitmap: Bitmap
    var features: Features

    /// Working pixels per full-size pixel.
    var scale: Double { Double(bitmap.width) / Double(photo.width) }
    /// The centre, in pixel indices.
    var centre: SIMD2<Double> { SIMD2(Double(bitmap.width) / 2 - 0.5, Double(bitmap.height) / 2 - 0.5) }
}

enum Aligner {
    static func align(_ photos: [WorkingPhoto], progress: @Sendable (String) -> Void) throws -> Placement {
        let n = photos.count
        guard n >= 2 else { throw AlignError.noOverlap }

        // Match the pairs: all of them for a modest number of photos, otherwise each with
        // its nearer neighbours in the order they were taken.
        var tries: [(Int, Int)] = []
        for i in 0..<n {
            for j in (i + 1)..<n where n <= 18 || j - i <= 4 || (i == 0 && j == n - 1) { tries.append((i, j)) }
        }
        progress("Matching \(n) photos…")
        let lock = NSLock()
        var pairs: [PairMatch] = []
        DispatchQueue.concurrentPerform(iterations: tries.count) { t in
            let (i, j) = tries[t]
            let a = photos[i], b = photos[j]
            let matches = Matcher.match(a.features, b.features)
            let size = { (p: WorkingPhoto) in SIMD2(Double(p.bitmap.width), Double(p.bitmap.height)) }
            if let pair = Matcher.homography(a.features, b.features, matches: matches, i: i, j: j,
                                             sizeA: size(a), sizeB: size(b)) {
                lock.lock()
                pairs.append(pair)
                lock.unlock()
            }
        }
        pairs.sort { ($0.i, $0.j) < ($1.i, $1.j) }
        guard !pairs.isEmpty else { throw AlignError.noOverlap }

        // Place them. When the matches still miss by a lot, see whether that's down to a
        // photo or two that aren't plain photos from the same spot (a panorama made earlier
        // from the same pictures, say). A stray photo drags every camera with it, so how far
        // each photo's own matches miss doesn't single it out, and two strays hold each other
        // in. So: place the rest without each photo in turn, or, when no one photo makes a
        // clear difference, without each pair, and leave out what helps most, a few times
        // over; give back any left out that turn out to fit after all; and keep the result
        // only if it ends up missing by far less.
        let first = try place(photos, pairs: pairs, excluding: [], progress: progress)
        guard first.miss > suspectMiss else { return first.placement }
        func without(_ out: Set<Int>) -> Placed? {
            // Only a trial that loses just those photos: one that cuts others off too would
            // miss less for having less to line up.
            guard let trial = try? place(photos, pairs: pairs, excluding: out, progress: { _ in }),
                  trial.placement.cameras.count == first.placement.cameras.count - out.count else { return nil }
            return trial
        }
        var excluded = Set<Int>()
        var current = first
        for _ in 0..<maxLeftOut where current.miss > suspectMiss && current.missBy.count > 3 {
            let suspects = Array(current.missBy.sorted { $0.value > $1.value }.prefix(maxSuspects).map(\.key))
            var best: (out: Set<Int>, trial: Placed)?
            for k in suspects {
                if let trial = without(excluded.union([k])), trial.miss < best?.trial.miss ?? .infinity { best = ([k], trial) }
            }
            if (best?.trial.miss ?? .infinity) * stepGain > current.miss {
                for (n, a) in suspects.prefix(maxPairSuspects).enumerated() {
                    for b in suspects.prefix(maxPairSuspects).dropFirst(n + 1) {
                        if let trial = without(excluded.union([a, b])), trial.miss < best?.trial.miss ?? .infinity {
                            best = ([a, b], trial)
                        }
                    }
                }
            }
            guard let best, best.trial.miss * stepGain <= current.miss else { break }
            excluded.formUnion(best.out)
            current = best.trial
        }
        // Giving one back can let another rejoin, so until none will.
        var gaveBack = true
        while gaveBack {
            gaveBack = false
            for k in excluded.sorted() {
                if let trial = without(excluded.subtracting([k])), trial.miss <= max(suspectMiss, current.miss * stepGain) {
                    excluded.remove(k)
                    current = trial
                    gaveBack = true
                }
            }
        }
        let better = current.miss <= suspectMiss && current.miss * outlierGain <= first.miss
        return better ? current.placement : first.placement
    }

    /// The RMS miss, in working pixels, above which stray photos are looked for; how many
    /// of the photos that miss most are tried without, alone and in pairs; how many rounds
    /// of leaving out there may be; how much better a round must make it; and how many
    /// times smaller the miss must end up for what was left out to stay out.
    static let suspectMiss = 15.0
    static let maxSuspects = 12
    static let maxPairSuspects = 6
    static let maxLeftOut = 3
    static let stepGain = 1.5
    static let outlierGain = 3.0

    /// A placement, with how far its matches still miss and how far each placed photo's
    /// own do, as RMS in working pixels.
    private struct Placed {
        var placement: Placement
        var miss: Double
        var missBy: [Int: Double]
    }

    /// Places the photos joined by the pairs, but those excluded.
    private static func place(_ photos: [WorkingPhoto], pairs allPairs: [PairMatch], excluding excluded: Set<Int>,
                              progress: @Sendable (String) -> Void) throws -> Placed {
        let n = photos.count
        let pairs = allPairs.filter { !excluded.contains($0.i) && !excluded.contains($0.j) }
        guard !pairs.isEmpty else { throw AlignError.noOverlap }

        // The strongest links that join the photos without a loop (a maximum spanning tree),
        // and the largest group of photos they join.
        var parent = Array(0..<n)
        func root(_ k: Int) -> Int { var k = k; while parent[k] != k { parent[k] = parent[parent[k]]; k = parent[k] }; return k }
        var tree: [PairMatch] = []
        for pair in pairs.sorted(by: { $0.pointsI.count > $1.pointsI.count }) {
            let a = root(pair.i), b = root(pair.j)
            if a != b { parent[a] = b; tree.append(pair) }
        }
        var groups: [Int: [Int]] = [:]
        for k in 0..<n where !excluded.contains(k) { groups[root(k), default: []].append(k) }
        // The largest group; between groups as large, the one with more matches, then the
        // one taken first, so the same photos always give the same panorama.
        let strength = { (group: [Int]) -> (Int, Int, Int) in
            let members = Set(group)
            let matches = tree.filter { members.contains($0.i) }.reduce(0) { $0 + $1.pointsI.count }
            return (group.count, matches, -group.min()!)
        }
        let placed = Set(groups.values.max { strength($0) < strength($1) }!)
        guard placed.count >= 2 else { throw AlignError.noOverlap }
        let unplaced = (0..<n).filter { !placed.contains($0) }
        let links = pairs.filter { placed.contains($0.i) && placed.contains($0.j) }
        tree = tree.filter { placed.contains($0.i) }

        progress("Placing the photos…")
        // Focal lengths, in each photo's working pixels: from the EXIF where there is one,
        // else estimated from the homographies, else a phone's wide lens.
        var source = Placement.FocalSource.exif
        var perDiagonal: Double
        let exifRatios = placed.compactMap { photos[$0].photo.focal35 }.map { $0 / 43.27 }
        if !exifRatios.isEmpty {
            perDiagonal = median(exifRatios)
        } else {
            let estimates = tree.compactMap { pair -> Double? in
                let a = photos[pair.i], b = photos[pair.j]
                guard let f = focalFromHomography(centred(pair.homography, a.centre, b.centre)) else { return nil }
                let diagonal = (Double(a.bitmap.width * a.bitmap.width + a.bitmap.height * a.bitmap.height)).squareRoot()
                return f / diagonal
            }.filter { $0 > 0.3 && $0 < 5 }
            if estimates.isEmpty {
                perDiagonal = 28 / 43.27
                source = .guessed
            } else {
                perDiagonal = median(estimates)
                source = .estimated
            }
        }
        var baseFocal = [Double](repeating: 0, count: n)
        for k in placed {
            let w = Double(photos[k].bitmap.width), h = Double(photos[k].bitmap.height)
            let ratio = photos[k].photo.focal35.map { $0 / 43.27 } ?? perDiagonal
            baseFocal[k] = ratio * (w * w + h * h).squareRoot()
        }

        // First placing: from the best-connected photo outwards along the tree.
        let degree = Dictionary(grouping: links.flatMap { [($0.i, $0.pointsI.count), ($0.j, $0.pointsI.count)] }, by: \.0)
            .mapValues { $0.reduce(0) { $0 + $1.1 } }
        let rootPhoto = placed.max { degree[$0, default: 0] < degree[$1, default: 0] }!
        var rotations = [Int: Mat3]()
        rotations[rootPhoto] = matrix_identity_double3x3
        var frontier = [rootPhoto]
        while let k = frontier.popLast() {
            for pair in tree where pair.i == k || pair.j == k {
                let (known, other) = pair.i == k ? (pair.i, pair.j) : (pair.j, pair.i)
                guard rotations[other] == nil else { continue }
                // H takes j to i: R_i R_jᵀ = K_i⁻¹ H K_j.
                let h = centred(pair.homography, photos[pair.i].centre, photos[pair.j].centre)
                let m = orthonormal(diag(1 / baseFocal[pair.i]) * h * diag(baseFocal[pair.j]))
                rotations[other] = known == pair.i ? m.transpose * rotations[known]! : m * rotations[known]!
                frontier.append(other)
            }
        }

        // Bundle adjustment over every link, not just the tree's.
        progress("Lining them up…")
        let order = placed.sorted()
        let (adjusted, scale, rms, missBy) = adjust(photos: photos, order: order, root: rootPhoto, rotations: rotations,
                                            baseFocal: baseFocal, links: links, focalFromExif: source == .exif)
        var cameras = [Int: Camera]()
        for k in order {
            cameras[k] = Camera(rotation: adjusted[k]!, focal: baseFocal[k] * scale / photos[k].scale, gain: 1)
        }
        level(&cameras, root: rootPhoto)

        let gains = exposureGains(photos: photos, order: order, links: links)
        for k in order { cameras[k]?.gain = gains[k] ?? 1 }

        let fullScale = median(order.map { 1 / photos[$0].scale })
        return Placed(placement: Placement(cameras: cameras, unplaced: unplaced, error: rms * fullScale,
                                           focal35: perDiagonal * scale * 43.27, focalSource: source),
                      miss: rms, missBy: missBy)
    }

    // MARK: Bundle adjustment

    /// Levenberg–Marquardt over each camera's rotation (but the root's) and one scale on
    /// every focal length, minimising how far each matched point lands from its partner in
    /// both directions. Returns the rotations, the focal scale, the RMS error in working
    /// pixels, and the same for each photo's own matches.
    private static func adjust(photos: [WorkingPhoto], order: [Int], root: Int, rotations start: [Int: Mat3],
                               baseFocal: [Double], links: [PairMatch], focalFromExif: Bool)
        -> ([Int: Mat3], Double, Double, [Int: Double]) {
        let moving = order.filter { $0 != root }
        var slot = [Int: Int]()
        for (s, k) in moving.enumerated() { slot[k] = 1 + 3 * s }
        let count = 1 + 3 * moving.count

        // Up to 60 matches a link, spread through its list.
        struct Obs { var i, j: Int; var pi, pj: SIMD2<Double> }
        var observations: [Obs] = []
        for link in links {
            let step = max(1, link.pointsI.count / 60)
            for m in stride(from: 0, to: link.pointsI.count, by: step) {
                observations.append(Obs(i: link.i, j: link.j,
                                        pi: link.pointsI[m] - photos[link.i].centre,
                                        pj: link.pointsJ[m] - photos[link.j].centre))
            }
        }
        let priorWeight = (focalFromExif ? 20 : 0.5) * Double(observations.count * 4).squareRoot()

        func cameras(_ x: [Double]) -> ([Int: Mat3], Double) {
            var r = [Int: Mat3]()
            for k in order {
                if let s = slot[k] {
                    r[k] = rotationFromVector(SIMD3(x[s], x[s + 1], x[s + 2])) * start[k]!
                } else {
                    r[k] = start[k]!
                }
            }
            return (r, exp(x[0]))
        }

        func residuals(_ x: [Double]) -> [Double] {
            let (r, scale) = cameras(x)
            var out = [Double]()
            out.reserveCapacity(observations.count * 4 + 1)
            for o in observations {
                for (from, to, p, q) in [(o.j, o.i, o.pj, o.pi), (o.i, o.j, o.pi, o.pj)] {
                    let ff = baseFocal[from] * scale, ft = baseFocal[to] * scale
                    let ray = r[from]!.transpose * SIMD3(p.x / ff, p.y / ff, 1)
                    let seen = r[to]! * ray
                    if seen.z <= 1e-6 {
                        out += [1000, 1000]
                    } else {
                        out.append(ft * seen.x / seen.z - q.x)
                        out.append(ft * seen.y / seen.z - q.y)
                    }
                }
            }
            out.append(priorWeight * x[0])
            return out
        }

        // Huber weights, so a few bad matches can't drag the rest.
        func weighted(_ r: [Double]) -> [Double] {
            var w = r
            let delta = 2.0
            var k = 0
            while k + 1 < r.count - 1 {
                let e = (r[k] * r[k] + r[k + 1] * r[k + 1]).squareRoot()
                if e > delta {
                    let s = (delta / e).squareRoot()
                    w[k] *= s
                    w[k + 1] *= s
                }
                k += 2
            }
            return w
        }
        func cost(_ r: [Double]) -> Double { weighted(r).reduce(0) { $0 + $1 * $1 } }

        var x = [Double](repeating: 0, count: count)
        var r = residuals(x)
        var current = cost(r)
        var lambda = 1e-3
        for _ in 0..<50 {
            let m = r.count
            // Numeric Jacobian, a column per parameter.
            var jacobian = [[Double]](repeating: [], count: count)
            let w = weighted(r)
            let factors = (0..<m).map { r[$0] == 0 ? 1 : w[$0] / r[$0] }
            let point = x, base = r
            jacobian.withUnsafeMutableBufferPointer { buf in
                let columns = buf.baseAddress!
                DispatchQueue.concurrentPerform(iterations: count) { p in
                    var xp = point
                    let eps = 1e-6
                    xp[p] += eps
                    let rp = residuals(xp)
                    var column = [Double](repeating: 0, count: m)
                    for q in 0..<m { column[q] = (rp[q] - base[q]) / eps * factors[q] }
                    columns[p] = column
                }
            }
            var jtj = [Double](repeating: 0, count: count * count), jtr = [Double](repeating: 0, count: count)
            for a in 0..<count {
                let ca = jacobian[a]
                var s = 0.0
                for q in 0..<m { s += ca[q] * w[q] }
                jtr[a] = s
                for b in a..<count {
                    let cb = jacobian[b]
                    var t = 0.0
                    for q in 0..<m { t += ca[q] * cb[q] }
                    jtj[a * count + b] = t
                    jtj[b * count + a] = t
                }
            }
            var improved = false
            for _ in 0..<8 {
                var damped = jtj
                for a in 0..<count { damped[a * count + a] += lambda * max(jtj[a * count + a], 1e-9) }
                guard let step = Linear.solve(damped, jtr.map { -$0 }, n: count) else { lambda *= 10; continue }
                let trial = zip(x, step).map(+)
                let rt = residuals(trial)
                let c = cost(rt)
                if c < current {
                    let gain = (current - c) / current
                    x = trial
                    r = rt
                    current = c
                    lambda = max(lambda / 3, 1e-9)
                    improved = gain > 1e-7
                    break
                }
                lambda *= 4
            }
            if !improved { break }
        }

        let (final, scale) = cameras(x)
        let errors = residuals(x).dropLast()
        var sum = 0.0, used = 0
        var perPhoto = [Int: (sum: Double, used: Int)]()
        var k = errors.startIndex
        while k + 1 < errors.endIndex {
            let e2 = errors[k] * errors[k] + errors[k + 1] * errors[k + 1]
            // Each observation gives two pairs of residuals, one each way; both count for
            // both of its photos. A point behind a camera counts as a large miss.
            let o = observations[(k - errors.startIndex) / 4]
            let miss = min(e2, 1e5)
            for p in [o.i, o.j] { perPhoto[p, default: (0, 0)].sum += miss; perPhoto[p, default: (0, 0)].used += 1 }
            if e2 < 1e5 { sum += e2; used += 1 }
            k += 2
        }
        let missBy = perPhoto.mapValues { ($0.sum / Double(max($0.used, 1))).squareRoot() }
        return (final, scale, used > 0 ? (sum / Double(used)).squareRoot() : 0, missBy)
    }

    // MARK: Levelling

    /// Turns the world so its vertical is the cameras' own: when they panned, the axis
    /// they turned about (the direction their x-axes keep square to); otherwise the mean
    /// of their down directions. Forward is the root photo's view, levelled.
    private static func level(_ cameras: inout [Int: Camera], root: Int) {
        var spread = Mat3()
        var downs = SIMD3<Double>(0, 0, 0)
        for camera in cameras.values {
            let r = camera.rotation.transpose  // columns are the camera's axes in the world
            let x = r.columns.0
            spread += Mat3(columns: (x * x.x, x * x.y, x * x.z))
            downs += r.columns.1
        }
        let (values, vectors) = symmetricEigen(spread)
        var down = simd_normalize(downs)
        if cameras.count >= 3, values[1] > 0.1 * values[2] {
            var axis = vectors[0]
            if simd_dot(axis, down) < 0 { axis = -axis }
            down = axis
        }
        let view = cameras[root]!.rotation.transpose.columns.2
        let forward = simd_normalize(view - simd_dot(view, down) * down)
        let right = simd_cross(down, forward)
        let world = Mat3(rows: [right, down, forward])
        for key in cameras.keys { cameras[key]!.rotation = cameras[key]!.rotation * world.transpose }
    }

    // MARK: Exposure

    /// One gain a photo so that where photos overlap they're equally bright, kept near 1
    /// (the least-squares gains of Brown and Lowe).
    private static func exposureGains(photos: [WorkingPhoto], order: [Int], links: [PairMatch]) -> [Int: Double] {
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let n = order.count
        var a = [Double](repeating: 0, count: n * n), b = [Double](repeating: 0, count: n)
        let sigmaN = 10.0, sigmaG = 0.1
        func brightness(_ photo: WorkingPhoto, _ p: SIMD2<Double>) -> Double {
            let bm = photo.bitmap
            var sum = 0.0, count = 0.0
            let cx = Int(p.x.rounded()), cy = Int(p.y.rounded())
            for y in max(0, cy - 3)...min(bm.height - 1, cy + 3) {
                for x in max(0, cx - 3)...min(bm.width - 1, cx + 3) {
                    let i = (y * bm.width + x) * 4
                    sum += 0.299 * Double(bm.data[i]) + 0.587 * Double(bm.data[i + 1]) + 0.114 * Double(bm.data[i + 2])
                    count += 1
                }
            }
            return sum / max(1, count)
        }
        for link in links {
            guard let i = index[link.i], let j = index[link.j], !link.pointsI.isEmpty else { continue }
            let mi = link.pointsI.map { brightness(photos[link.i], $0) }.reduce(0, +) / Double(link.pointsI.count)
            let mj = link.pointsJ.map { brightness(photos[link.j], $0) }.reduce(0, +) / Double(link.pointsJ.count)
            let count = Double(link.pointsI.count)
            a[i * n + i] += count * (mi * mi / (sigmaN * sigmaN) + 1 / (sigmaG * sigmaG))
            a[j * n + j] += count * (mj * mj / (sigmaN * sigmaN) + 1 / (sigmaG * sigmaG))
            a[i * n + j] -= count * mi * mj / (sigmaN * sigmaN)
            a[j * n + i] -= count * mi * mj / (sigmaN * sigmaN)
            b[i] += count / (sigmaG * sigmaG)
            b[j] += count / (sigmaG * sigmaG)
        }
        for k in 0..<n where a[k * n + k] == 0 { a[k * n + k] = 1; b[k] = 1 }
        guard let gains = Linear.solve(a, b, n: n) else { return [:] }
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, max(0.5, min(2, gains[$0]))) })
    }

    // MARK: Small pieces of geometry

    /// A homography between pixel indices, as one between centred pixels.
    static func centred(_ h: Mat3, _ ci: SIMD2<Double>, _ cj: SIMD2<Double>) -> Mat3 {
        let toI = Mat3(rows: [SIMD3(1, 0, -ci.x), SIMD3(0, 1, -ci.y), SIMD3(0, 0, 1)])
        let fromJ = Mat3(rows: [SIMD3(1, 0, cj.x), SIMD3(0, 1, cj.y), SIMD3(0, 0, 1)])
        return toI * h * fromJ
    }

    static func diag(_ f: Double) -> Mat3 { Mat3(diagonal: SIMD3(f, f, 1)) }

    /// The nearest rotation to a matrix a rotation has been scaled into.
    static func orthonormal(_ m: Mat3) -> Mat3 {
        let d = m.determinant
        var x = m * (1 / cbrt(d))
        for _ in 0..<30 { x = (x + x.inverse.transpose) * 0.5 }
        return x
    }

    static func rotationFromVector(_ w: SIMD3<Double>) -> Mat3 {
        let angle = simd_length(w)
        guard angle > 1e-12 else { return matrix_identity_double3x3 }
        return Mat3(simd_quatd(angle: angle, axis: w / angle))
    }

    /// The focal length a homography between two photos from one camera turning about its
    /// centre implies, in its pixels (Szeliski and Shum's estimate, as OpenCV has it).
    static func focalFromHomography(_ m: Mat3) -> Double? {
        let s = m[2, 2]
        guard abs(s) > 1e-12 else { return nil }
        let h = (0..<9).map { m[$0 % 3, $0 / 3] / s }  // row by row
        func pick(_ d1: Double, _ d2: Double, _ v1: Double, _ v2: Double) -> Double? {
            var (a, b) = (v1, v2)
            if a < b { swap(&a, &b) }
            if a > 0, b > 0 { return (abs(d1) > abs(d2) ? a : b).squareRoot() }
            if a > 0 { return a.squareRoot() }
            return nil
        }
        var d1 = h[6] * h[7], d2 = (h[7] - h[6]) * (h[7] + h[6])
        let f1 = pick(d1, d2, -(h[0] * h[1] + h[3] * h[4]) / d1, (h[0] * h[0] + h[3] * h[3] - h[1] * h[1] - h[4] * h[4]) / d2)
        d1 = h[0] * h[3] + h[1] * h[4]
        d2 = h[0] * h[0] + h[1] * h[1] - h[3] * h[3] - h[4] * h[4]
        let f0 = pick(d1, d2, -h[2] * h[5] / d1, (h[5] * h[5] - h[2] * h[2]) / d2)
        guard let a = f0, let b = f1, a.isFinite, b.isFinite else { return nil }
        return (a * b).squareRoot()
    }

    /// Eigenvalues (smallest first) and their eigenvectors of a symmetric 3 × 3 matrix, by
    /// Jacobi rotations.
    static func symmetricEigen(_ m: Mat3) -> ([Double], [SIMD3<Double>]) {
        var a = [[Double]](repeating: [0, 0, 0], count: 3)
        for r in 0..<3 { for c in 0..<3 { a[r][c] = m[c, r] } }
        var v: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<50 {
            var off = 0.0
            for p in 0..<3 { for q in (p + 1)..<3 { off += a[p][q] * a[p][q] } }
            if off < 1e-20 { break }
            for p in 0..<3 {
                for q in (p + 1)..<3 where abs(a[p][q]) > 1e-30 {
                    let theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
                    let t = (theta >= 0 ? 1 : -1) / (abs(theta) + (theta * theta + 1).squareRoot())
                    let c = 1 / (t * t + 1).squareRoot(), s = t * c
                    for k in 0..<3 {
                        let akp = a[k][p], akq = a[k][q]
                        a[k][p] = c * akp - s * akq
                        a[k][q] = s * akp + c * akq
                    }
                    for k in 0..<3 {
                        let apk = a[p][k], aqk = a[q][k]
                        a[p][k] = c * apk - s * aqk
                        a[q][k] = s * apk + c * aqk
                    }
                    for k in 0..<3 {
                        let vkp = v[k][p], vkq = v[k][q]
                        v[k][p] = c * vkp - s * vkq
                        v[k][q] = s * vkp + c * vkq
                    }
                }
            }
        }
        let order = (0..<3).sorted { a[$0][$0] < a[$1][$1] }
        return (order.map { a[$0][$0] }, order.map { SIMD3(v[0][$0], v[1][$0], v[2][$0]) })
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
