// Parks — state parks anywhere, fetched from OpenStreetMap through the Overpass API for
// the part of the map you're looking at, and kept on disk for a month. The map is cut
// into one-degree cells; a pan asks only for the cells it hasn't got, in one query
// over their rectangle, and every cell it covered is remembered, even an empty one. A
// park is anything tagged as a park, nature reserve or protected area whose name says
// "State Park", "State Historic Park" or "Historical State Park". The Overpass servers
// are shared and often busy, so a failed fetch backs off and tries again later.

import Foundation
import MapKit

struct Park: Codable, Hashable {
    let id: String              // "way/123" or "relation/456"
    let name: String
    let historic: Bool
    let lat: Double, lon: Double
    let rings: [[[Double]]]     // [lon, lat] pairs

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

final class ParkShape: MKPolygon {}

@MainActor
final class ParkStore {
    static let shared = ParkStore()

    /// Overpass's main instance; its usage policy asks for a User-Agent and a gentle pace.
    static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    static let keep: TimeInterval = 30 * 24 * 3600
    /// A view missing more cells than this says to zoom in, rather than fetch half a
    /// continent; about zoom 6 in a large window.
    static let maxCells = 400
    /// Each query covers at most a block this many cells square; a wide view is fetched
    /// block by block, nearest the middle first, and fills in as each arrives.
    static let block = 8

    private struct Cell: Codable {
        let fetched: Date
        let parks: [Park]
    }

    private var cells: [String: Cell] = [:]
    private var loading = false
    /// Windows that asked while a fetch was out; each looks again once it's back.
    private var waiting: [(Outcome) -> Void] = []
    private var busyUntil = Date.distantPast
    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.mbolding.mapbrowser/Parks")

    /// `again`: another window's fetch has finished, so ask again for what's still missing.
    enum Outcome { case ready, again, tooWide, busy, failed(String) }

    /// The parks in a box, as far as the cache has them.
    func parks(south: Double, west: Double, north: Double, east: Double) -> [Park] {
        var seen = Set<String>(), names = Set<String>(), out: [Park] = []
        for key in keys(south: south, west: west, north: north, east: east) {
            for park in cell(key)?.parks ?? [] where seen.insert(park.id).inserted {
                // A park is often mapped twice, as a park and as a protected area.
                guard names.insert(park.name.lowercased()).inserted else { continue }
                out.append(park)
            }
        }
        return out
    }

    /// Fetches whatever cells of the box are missing or stale. `done` runs on the main
    /// actor once there's something new to show, or once it's clear there won't be.
    func load(south: Double, west: Double, north: Double, east: Double, done: @escaping (Outcome) -> Void) {
        let missing = keys(south: south, west: west, north: north, east: east).filter { key in
            guard let c = cell(key) else { return true }
            return Date.now.timeIntervalSince(c.fetched) > Self.keep
        }
        guard !missing.isEmpty else { return done(.ready) }
        guard missing.count <= Self.maxCells else { return done(.tooWide) }
        guard !loading else { return waiting.append(done) }
        guard Date.now > busyUntil else { return done(.busy) }
        loading = true

        // The missing cells grouped into blocks, each fetched as the rectangle around its
        // missing cells, the blocks nearest the middle of the view first.
        typealias Box = (s: Int, w: Int, n: Int, e: Int)
        func blockOf(_ v: Int) -> Int { Int(floor(Double(v) / Double(Self.block))) }
        let grouped = Dictionary(grouping: missing) { "\(blockOf($0.lat))_\(blockOf($0.lon))" }
        let boxes: [Box] = grouped.values.map { cells in
            let lats = cells.map(\.lat), lons = cells.map(\.lon)
            return (lats.min()!, lons.min()!, lats.max()! + 1, lons.max()! + 1)
        }
        let mid = (lat: (south + north) / 2, lon: (west + east) / 2)
        func distance(_ b: Box) -> Double {
            let lat = Double(b.s + b.n) / 2, lon = Double(b.w + b.e) / 2
            return hypot(lat - mid.lat, lon - mid.lon)
        }
        let blocks = boxes.sorted { distance($0) < distance($1) }
        Task {
            defer {
                loading = false
                let others = waiting
                waiting = []
                for other in others { other(.again) }
            }
            for (i, box) in blocks.enumerated() {
                let token = Activity.shared.begin(blocks.count > 1 ? "Loading state parks, \(i + 1) of \(blocks.count)"
                                                                   : "Loading state parks")
                defer { Activity.shared.end(token) }
                do {
                    let parks = try await Self.fetch(south: Double(box.s), west: Double(box.w),
                                                     north: Double(box.n), east: Double(box.e))
                    var by: [String: [Park]] = [:]
                    for park in parks { by[Self.key(park.lat, park.lon), default: []].append(park) }
                    // Every cell in the rectangle was asked for, so all of them are now known.
                    for lat in box.s..<box.n {
                        for lon in box.w..<box.e {
                            let key = "\(lat)_\(lon)"
                            store(key, Cell(fetched: .now, parks: by[key] ?? []))
                        }
                    }
                    done(.ready)
                } catch ParkError.busy {
                    busyUntil = .now + 60
                    return done(.busy)
                } catch {
                    busyUntil = .now + 60
                    return done(.failed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: Cells

    private func keys(south: Double, west: Double, north: Double, east: Double) -> [(key: String, lat: Int, lon: Int)] {
        let s = Int(floor(max(south, -85))), n = Int(floor(min(north, 85)))
        let w = Int(floor(max(west, -180))), e = Int(floor(min(east, 179.999)))
        guard s <= n, w <= e else { return [] }
        return (s...n).flatMap { lat in (w...e).map { lon in ("\(lat)_\(lon)", lat, lon) } }
    }

    private static func key(_ lat: Double, _ lon: Double) -> String { "\(Int(floor(lat)))_\(Int(floor(lon)))" }

    private func cell(_ key: (key: String, lat: Int, lon: Int)) -> Cell? { cell(key.key) }

    private func cell(_ key: String) -> Cell? {
        if let c = cells[key] { return c }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(key).json")),
              let c = try? JSONDecoder().decode(Cell.self, from: data) else { return nil }
        cells[key] = c
        return c
    }

    private func store(_ key: String, _ cell: Cell) {
        cells[key] = cell
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(cell).write(to: folder.appendingPathComponent("\(key).json"), options: .atomic)
    }

    // MARK: Overpass

    enum ParkError: Error { case busy }

    static func query(south: Double, west: Double, north: Double, east: Double) -> String {
        let box = "\(south),\(west),\(north),\(east)"
        let name = #"["name"~"State (Historic(al)? )?Park|Historic(al)? State Park"]"#
        return """
        [out:json][timeout:60][bbox:\(box)];
        (
          nwr["leisure"~"^(park|nature_reserve)$"]\(name);
          nwr["boundary"~"^(protected_area|national_park)$"]\(name);
        );
        out geom;
        """
    }

    /// One query, tried three times with a growing pause when the server is busy.
    static func fetch(south: Double, west: Double, north: Double, east: Double) async throws -> [Park] {
        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = query(south: south, west: west, north: north, east: east)
        request.httpBody = ("data=" + (body.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).data(using: .utf8)
        for attempt in 1...3 {
            if attempt > 1 { try await Task.sleep(for: .seconds(attempt == 2 ? 5 : 15)) }
            guard let (data, response) = try? await Tiles.session.data(for: request) else { continue }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return parse(data) }
            if ![429, 502, 503, 504].contains(status) { throw URLError(.badServerResponse) }
        }
        throw ParkError.busy
    }

    static func parse(_ data: Data) -> [Park] {
        struct Point: Decodable { let lat: Double; let lon: Double }
        struct Member: Decodable { let type: String; let role: String?; let geometry: [Point]? }
        struct Bounds: Decodable { let minlat, minlon, maxlat, maxlon: Double }
        struct Element: Decodable {
            let type: String; let id: Int
            let tags: [String: String]?
            let bounds: Bounds?
            let geometry: [Point]?
            let members: [Member]?
        }
        struct Reply: Decodable { let elements: [Element] }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return [] }
        return reply.elements.compactMap { e in
            guard let name = e.tags?["name"], let b = e.bounds else { return nil }
            let lines: [[Point]]
            if let g = e.geometry {
                lines = [g]
            } else {
                lines = (e.members ?? []).filter { $0.type == "way" && ($0.role ?? "outer") != "inner" }.compactMap(\.geometry)
            }
            let rings = joined(lines.map { $0.map { [$0.lon, $0.lat] } }).filter { $0.count > 2 }
            return Park(id: "\(e.type)/\(e.id)", name: name, historic: name.range(of: "histor", options: .caseInsensitive) != nil,
                        lat: (b.minlat + b.maxlat) / 2, lon: (b.minlon + b.maxlon) / 2, rings: rings)
        }
    }

    /// Chains the ways of a multipolygon's outline end to end into rings.
    static func joined(_ lines: [[[Double]]]) -> [[[Double]]] {
        var rest = lines.filter { $0.count > 1 }, out: [[[Double]]] = []
        while !rest.isEmpty {
            var ring = rest.removeFirst()
            var grew = true
            while grew, ring.first != ring.last {
                grew = false
                for (i, l) in rest.enumerated() {
                    if l.first == ring.last { ring += l.dropFirst() }
                    else if l.last == ring.last { ring += l.reversed().dropFirst() }
                    else if l.last == ring.first { ring = l.dropLast() + ring }
                    else if l.first == ring.first { ring = l.reversed().dropLast() + ring }
                    else { continue }
                    rest.remove(at: i)
                    grew = true
                    break
                }
            }
            out.append(ring)
        }
        return out
    }
}
