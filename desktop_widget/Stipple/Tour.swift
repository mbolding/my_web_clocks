// Tour — joins the dots into one continuous line, "TSP art": a short route through every
// dot, as in the travelling salesman problem. It starts by visiting them along a Hilbert
// curve, then untangles that with 2-opt moves (swap two edges for two shorter ones by
// reversing the stretch between), trying only each dot's nearest neighbours. The result
// isn't the shortest route, but it has no crossings and reads as a drawing.

import Foundation

enum Tour {
    /// The order to visit the dots in, as an open path. `progress` gets the route so far now
    /// and then, to draw while it improves.
    static func route(xs: [Float], ys: [Float], width: Int, height: Int,
                      progress: ([Int32]) -> Void, isCancelled: () -> Bool) -> [Int32] {
        let n = xs.count
        guard n > 3 else { return (0..<Int32(n)).map { $0 } }

        var tour = hilbertOrder(xs: xs, ys: ys, width: width, height: height)
        progress(tour)
        let neighbours = nearestNeighbours(xs: xs, ys: ys, width: width, height: height, k: 8)
        untangle(&tour, xs: xs, ys: ys, neighbours: neighbours, k: 8, progress: progress, isCancelled: isCancelled)
        return opened(tour, xs: xs, ys: ys)
    }

    /// Total length of a path, in grid units.
    static func length(_ path: [Int32], xs: [Float], ys: [Float]) -> Float {
        guard path.count > 1 else { return 0 }
        var total: Float = 0
        for i in 1..<path.count {
            let a = Int(path[i - 1]), b = Int(path[i])
            total += hypot(xs[a] - xs[b], ys[a] - ys[b])
        }
        return total
    }

    // MARK: Starting route

    /// The dots in the order a Hilbert curve passes them: neighbours on the curve are
    /// neighbours on the page, so it's a fair route to start from.
    private static func hilbertOrder(xs: [Float], ys: [Float], width: Int, height: Int) -> [Int32] {
        let order = 1 << 16
        let scale = Float(order - 1) / Float(max(width, height))
        let keys = xs.indices.map { i in
            hilbert(Int(xs[i] * scale), Int(ys[i] * scale), side: order)
        }
        return xs.indices.sorted { keys[$0] < keys[$1] }.map { Int32($0) }
    }

    /// Distance along a Hilbert curve filling a side × side square.
    private static func hilbert(_ x: Int, _ y: Int, side: Int) -> Int {
        var x = min(max(x, 0), side - 1), y = min(max(y, 0), side - 1)
        var d = 0
        var s = side / 2
        while s > 0 {
            let rx = (x & s) > 0 ? 1 : 0
            let ry = (y & s) > 0 ? 1 : 0
            d += s * s * ((3 * rx) ^ ry)
            if ry == 0 {
                if rx == 1 { x = side - 1 - x; y = side - 1 - y }
                swap(&x, &y)
            }
            s /= 2
        }
        return d
    }

    /// Each dot's k nearest others, nearest first, flattened into one array.
    private static func nearestNeighbours(xs: [Float], ys: [Float], width: Int, height: Int, k: Int) -> [Int32] {
        let n = xs.count
        let grid = PointGrid(xs: xs, ys: ys, width: width, height: height)
        var result = [Int32](repeating: 0, count: n * k)
        result.withUnsafeMutableBufferPointer { result in
            let out = result.baseAddress!
            DispatchQueue.concurrentPerform(iterations: n) { i in
                var found: [(d: Float, j: Int32)] = []
                found.reserveCapacity(k + 1)
                let x = xs[i], y = ys[i]
                let cx = min(max(Int(x / grid.cell), 0), grid.columns - 1)
                let cy = min(max(Int(y / grid.cell), 0), grid.rows - 1)
                var ring = 0
                while ring <= max(grid.columns, grid.rows) {
                    let near = Float(ring - 1) * grid.cell
                    if found.count == k, near > 0, near * near >= found[k - 1].d { break }
                    for gy in (cy - ring)...(cy + ring) where gy >= 0 && gy < grid.rows {
                        for gx in (cx - ring)...(cx + ring) where gx >= 0 && gx < grid.columns {
                            guard gy == cy - ring || gy == cy + ring || gx == cx - ring || gx == cx + ring else { continue }
                            let c = gy * grid.columns + gx
                            for m in Int(grid.starts[c])..<Int(grid.starts[c + 1]) {
                                let j = grid.members[m]
                                guard Int(j) != i else { continue }
                                let dx = xs[Int(j)] - x, dy = ys[Int(j)] - y
                                let d = dx * dx + dy * dy
                                if found.count < k || d < found[found.count - 1].d {
                                    let at = found.firstIndex { $0.d > d } ?? found.count
                                    found.insert((d, j), at: at)
                                    if found.count > k { found.removeLast() }
                                }
                            }
                        }
                    }
                    ring += 1
                }
                for (slot, f) in found.enumerated() { out[i * k + slot] = f.j }
                // Fewer dots than k: repeat the last, which the search simply tries twice.
                for slot in found.count..<k { out[i * k + slot] = found.last?.j ?? Int32(i) }
            }
        }
        return result
    }

    // MARK: 2-opt

    /// 2-opt on the route as a closed loop, with "don't look" bits: only dots whose edges
    /// changed are looked at again, so it settles in roughly linear time.
    private static func untangle(_ tour: inout [Int32], xs: [Float], ys: [Float], neighbours: [Int32], k: Int,
                                 progress: ([Int32]) -> Void, isCancelled: () -> Bool) {
        let n = tour.count
        var pos = [Int32](repeating: 0, count: n)
        for (p, c) in tour.enumerated() { pos[Int(c)] = Int32(p) }

        func dist(_ a: Int, _ b: Int) -> Float { hypot(xs[a] - xs[b], ys[a] - ys[b]) }
        func next(_ c: Int) -> Int { Int(tour[(Int(pos[c]) + 1) % n]) }
        func prev(_ c: Int) -> Int { Int(tour[(Int(pos[c]) + n - 1) % n]) }

        /// Reverses tour[i...j], going forwards round the loop, or the rest of the loop if
        /// that's shorter; on a loop the two are the same move.
        func reverse(_ from: Int, _ to: Int) {
            var i = from, j = to
            var length = (j - i + n) % n + 1
            if length * 2 > n {
                i = (to + 1) % n
                j = (from + n - 1) % n
                length = n - length
            }
            for _ in 0..<(length / 2) {
                let a = tour[i], b = tour[j]
                tour[i] = b; pos[Int(b)] = Int32(i)
                tour[j] = a; pos[Int(a)] = Int32(j)
                i = (i + 1) % n
                j = (j + n - 1) % n
            }
        }

        var queue = tour.map { Int($0) }
        var head = 0
        var queued = [Bool](repeating: true, count: n)
        func push(_ c: Int) {
            guard !queued[c] else { return }
            queued[c] = true
            queue.append(c)
        }

        var lastReport = Date()
        var steps = 0
        while head < queue.count {
            let a = queue[head]
            head += 1
            queued[a] = false
            // Keep the queue from growing without end.
            if head > 65_536 && head * 2 > queue.count {
                queue.removeFirst(head)
                head = 0
            }

            steps += 1
            if steps & 255 == 0 {
                if isCancelled() { return }
                if Date().timeIntervalSince(lastReport) > 0.25 {
                    progress(tour)
                    lastReport = Date()
                }
            }

            search: for forward in [true, false] {
                let b = forward ? next(a) : prev(a)
                let ab = dist(a, b)
                for slot in 0..<k {
                    let c = Int(neighbours[a * k + slot])
                    let ac = dist(a, c)
                    // Neighbours come nearest first, so no later one can do better.
                    if ac >= ab { break }
                    let d = forward ? next(c) : prev(c)
                    if c == b || d == a { continue }
                    let gain = ab + dist(c, d) - ac - dist(b, d)
                    if gain > 1e-3 {
                        if forward {
                            reverse(Int(pos[b]), Int(pos[c]))
                        } else {
                            reverse(Int(pos[a]), Int(pos[d]))
                        }
                        push(a); push(b); push(c); push(d)
                        break search
                    }
                }
            }
        }
    }

    /// Opens the loop at its longest edge, so the drawing doesn't jump across the page.
    private static func opened(_ tour: [Int32], xs: [Float], ys: [Float]) -> [Int32] {
        let n = tour.count
        var longest = 0
        var longestLength: Float = -1
        for i in 0..<n {
            let a = Int(tour[i]), b = Int(tour[(i + 1) % n])
            let d = hypot(xs[a] - xs[b], ys[a] - ys[b])
            if d > longestLength { longestLength = d; longest = i }
        }
        let start = (longest + 1) % n
        return Array(tour[start...] + tour[..<start])
    }
}
