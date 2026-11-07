// Layers — what Map Browser can draw over the tiles, ported from the 67 Counties wall map:
// Alabama's county borders, the counties coloured by your run, bike,
// camp and paddle pins, the long trails, state parks (in Parks.swift), and the Army
// Corps of Engineers' campgrounds across the country. Which layers
// show is one setting for every window, kept across launches. The shapes come from
// AlabamaData.swift, which tools/build_layers.py writes; the pins from a JSON file in
// Application Support that File › Import County Pins… replaces, since they're personal
// and live with the wall map, not in this repository.

import SwiftUI
import MapKit
import UniformTypeIdentifiers

/// Which pin the counties are coloured by, as the wall map's five views.
enum PinView: String, CaseIterable, Identifiable {
    case all, run, bike, camp, paddle

    var id: Self { self }

    var name: String {
        switch self {
        case .all: "All Four"
        case .run: "Run"
        case .bike: "Bike"
        case .camp: "Camp"
        case .paddle: "Paddle"
        }
    }
}

@MainActor
final class Layers: ObservableObject {
    static let shared = Layers()

    @Published var counties: Bool { didSet { save("layerCounties", counties) } }
    @Published var pins: Bool { didSet { save("layerPins", pins) } }
    @Published var trails: Bool { didSet { save("layerTrails", trails) } }
    @Published var parks: Bool { didSet { save("layerParks", parks) } }
    @Published var corps: Bool { didSet { save("layerCorps", corps) } }
    @Published var pinView: PinView { didSet { UserDefaults.standard.set(pinView.rawValue, forKey: "pinView") } }

    private init() {
        let d = UserDefaults.standard
        counties = d.bool(forKey: "layerCounties")
        pins = d.bool(forKey: "layerPins")
        trails = d.bool(forKey: "layerTrails")
        parks = d.bool(forKey: "layerParks")
        corps = d.bool(forKey: "layerCorps")
        pinView = PinView(rawValue: d.string(forKey: "pinView") ?? "") ?? .all
    }

    private func save(_ key: String, _ value: Bool) { UserDefaults.standard.set(value, forKey: key) }
}

/// The layer switches, shared by the View menu and the toolbar's Layers menu.
struct LayerToggles: View {
    @ObservedObject var layers: Layers

    var body: some View {
        Toggle("County Borders", isOn: $layers.counties)
            .keyboardShortcut("1", modifiers: [.command, .option])
        Toggle("County Pins", isOn: $layers.pins)
            .keyboardShortcut("2", modifiers: [.command, .option])
        Picker("Colour Counties By", selection: $layers.pinView) {
            ForEach(PinView.allCases) { Text($0.name).tag($0) }
        }
        .disabled(!layers.pins)
        Toggle("Long Trails", isOn: $layers.trails)
            .keyboardShortcut("3", modifiers: [.command, .option])
        Toggle("State Parks", isOn: $layers.parks)
            .keyboardShortcut("4", modifiers: [.command, .option])
        Toggle("Corps of Engineers Campgrounds", isOn: $layers.corps)
            .keyboardShortcut("5", modifiers: [.command, .option])
    }
}

// MARK: Shapes

/// Google's encoded polyline format, latitude first, five decimal places.
enum Polyline {
    static func decode(_ text: String) -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        var lat = 0, lon = 0
        var bytes = Array(text.utf8)[...]
        func next() -> Int? {
            var result = 0, shift = 0
            while let b = bytes.popFirst() {
                let v = Int(b) - 63
                result |= (v & 0x1F) << shift
                shift += 5
                if v < 0x20 { return result & 1 != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }
        while let dlat = next(), let dlon = next() {
            lat += dlat
            lon += dlon
            points.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return points
    }
}

final class CountyShape: MKPolygon {
    var county = ""
}

final class TrailLine: MKPolyline {
    var kind = ""
}

/// The decoded shapes, made once and shared by every window.
@MainActor
enum Alabama {
    static let counties: [(county: AlabamaData.County, rings: [[CLLocationCoordinate2D]])] =
        AlabamaData.counties.map { ($0, $0.rings.map(Polyline.decode)) }

    /// South, west, north and east edges of the state.
    static let bounds: (south: Double, west: Double, north: Double, east: Double) = {
        let all = counties.flatMap { $0.rings.joined() }
        return (all.map(\.latitude).min()!, all.map(\.longitude).min()!,
                all.map(\.latitude).max()!, all.map(\.longitude).max()!)
    }()

    static let trails: [(trail: AlabamaData.Trail, lines: [[CLLocationCoordinate2D]])] =
        AlabamaData.trails.map { ($0, $0.lines.map(Polyline.decode)) }

    static func countyShapes() -> [CountyShape] {
        counties.flatMap { county, rings in
            rings.map { ring in
                let shape = CountyShape(coordinates: ring, count: ring.count)
                shape.county = county.id
                shape.title = county.name
                return shape
            }
        }
    }

    static func trailLines() -> [TrailLine] {
        // Water and plans first, so the land trails draw over them where they cross.
        let order = ["water": 0, "plan": 1, "bike": 2, "hike": 3]
        return trails.sorted { order[$0.trail.kind, default: 4] < order[$1.trail.kind, default: 4] }
            .flatMap { trail, lines in
                lines.map { line in
                    let shape = TrailLine(coordinates: line, count: line.count)
                    shape.kind = trail.kind
                    shape.title = trail.name
                    return shape
                }
            }
    }

    /// The county a spot is in, if it's in Alabama.
    static func county(at c: CLLocationCoordinate2D) -> AlabamaData.County? {
        counties.first { _, rings in rings.contains { contains($0, c) } }?.county
    }

    private static func contains(_ ring: [CLLocationCoordinate2D], _ c: CLLocationCoordinate2D) -> Bool {
        var hit = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.latitude > c.latitude) != (b.latitude > c.latitude),
               c.longitude < a.longitude + (c.latitude - a.latitude) * (b.longitude - a.longitude) / (b.latitude - a.latitude) {
                hit.toggle()
            }
            j = i
        }
        return hit
    }
}

// MARK: Pins

/// One county's pins, as the wall map stores them.
struct CountyPin: Codable {
    var run = false, bike = false, camp = false, paddle = false
    /// False for a run whose spot wasn't written down.
    var runLocated: Bool?

    var done: Int { [run, bike, camp, paddle].filter { $0 }.count }

    func has(_ view: PinView) -> Bool {
        switch view {
        case .all: done == 4
        case .run: run
        case .bike: bike
        case .camp: camp
        case .paddle: paddle
        }
    }

    var summary: String {
        if done == 4 { return "all four done" }
        let names = ["run", "bike", "camp", "paddle"]
        let left = zip(names, [run, bike, camp, paddle]).filter { !$0.1 }.map(\.0)
        return "\(done) of 4, left: \(left.joined(separator: ", "))"
    }
}

@MainActor
final class CountyPins: ObservableObject {
    static let shared = CountyPins()

    @Published private(set) var byCounty: [String: CountyPin] = [:]

    static let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.mbolding.mapbrowser/County Pins.json")

    private init() { load() }

    func load() {
        byCounty = (try? Data(contentsOf: Self.file)).flatMap(Self.decode) ?? [:]
    }

    /// Reads either a map of county id to its pins, or the wall map's documents in a list
    /// with an "id" each.
    static func decode(_ data: Data) -> [String: CountyPin]? {
        let ids = Set(AlabamaData.counties.map(\.id))
        if let map = try? JSONDecoder().decode([String: CountyPin].self, from: data) {
            return map.filter { ids.contains($0.key) }
        }
        struct Doc: Decodable { let id: String; let pin: CountyPin
            init(from d: Decoder) throws {
                id = try d.container(keyedBy: Key.self).decode(String.self, forKey: .id)
                pin = try CountyPin(from: d)
            }
            enum Key: CodingKey { case id }
        }
        guard let docs = try? JSONDecoder().decode([Doc].self, from: data) else { return nil }
        return Dictionary(docs.filter { ids.contains($0.id) }.map { ($0.id, $0.pin) }) { a, _ in a }
    }

    /// Asks for a file of pins and keeps a copy of it. Returns a line for the notice.
    func chooseFile() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a JSON file of county pins, as exported from the 67 Counties map."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = try? Data(contentsOf: url), let pins = Self.decode(data), !pins.isEmpty else {
            return "That file doesn't hold any county pins."
        }
        do {
            try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(pins).write(to: Self.file, options: .atomic)
        } catch {
            return "Couldn't keep the pins: \(error.localizedDescription)"
        }
        byCounty = pins
        Layers.shared.pins = true
        return "Imported pins for \(pins.count) counties."
    }

    func count(_ view: PinView) -> Int { byCounty.values.filter { $0.has(view) }.count }
}

// MARK: Colours

/// The wall map's palette, in its light theme.
enum WallMap {
    static let border = NSColor(srgbRed: 0.29, green: 0.33, blue: 0.32, alpha: 0.85)
    static let gold = NSColor(srgbRed: 0.929, green: 0.631, blue: 0, alpha: 1)
    static let grays = [NSColor(srgbRed: 0.643, green: 0.667, blue: 0.651, alpha: 1),  // 1 of 4
                        NSColor(srgbRed: 0.424, green: 0.451, blue: 0.439, alpha: 1),  // 2 of 4
                        NSColor(srgbRed: 0.227, green: 0.251, blue: 0.243, alpha: 1)]  // 3 of 4
    static let run = NSColor(srgbRed: 0.89, green: 0.286, blue: 0.282, alpha: 1)
    static let pink = NSColor(srgbRed: 0.941, green: 0.561, blue: 0.651, alpha: 1)
    static let bike = NSColor(srgbRed: 0.165, green: 0.184, blue: 0.176, alpha: 1)
    static let camp = NSColor(srgbRed: 0, green: 0.514, blue: 0, alpha: 1)
    static let paddle = NSColor(srgbRed: 0.145, green: 0.416, blue: 0.749, alpha: 1)
    static let trail = NSColor(srgbRed: 0.706, green: 0.267, blue: 0.102, alpha: 1)
    static let water = NSColor(srgbRed: 0.043, green: 0.478, blue: 0.522, alpha: 1)
    static let park = NSColor(srgbRed: 0.106, green: 0.49, blue: 0.231, alpha: 1)
    static let historic = NSColor(srgbRed: 0.545, green: 0.353, blue: 0.169, alpha: 1)
    /// The Corps' own red.
    static let corps = NSColor(srgbRed: 0.78, green: 0.063, blue: 0.18, alpha: 1)

    /// A county's fill for the pin view, or nil to leave it clear.
    static func fill(_ pin: CountyPin?, _ view: PinView) -> NSColor? {
        guard let pin else { return nil }
        switch view {
        case .all: return pin.done == 4 ? gold : pin.done == 0 ? nil : grays[pin.done - 1]
        case .run: return pin.run ? (pin.runLocated == false ? pink : run) : nil
        case .bike: return pin.bike ? bike : nil
        case .camp: return pin.camp ? camp : nil
        case .paddle: return pin.paddle ? paddle : nil
        }
    }

    /// The key for a pin view: colour and label.
    static func key(_ view: PinView) -> [(NSColor, String)] {
        switch view {
        case .all: [(gold, "All four"), (grays[2], "3 of 4"), (grays[1], "2 of 4"), (grays[0], "1 of 4")]
        case .run: [(run, "Run"), (pink, "Run, spot not recorded")]
        case .bike: [(bike, "Biked")]
        case .camp: [(camp, "Camped")]
        case .paddle: [(paddle, "Paddled")]
        }
    }
}

// MARK: Drawing

/// A trail line over a pale halo, so it reads on any tile style. Hiking trails are
/// dashed, plans dotted, and the paddling trail is teal.
final class TrailRenderer: MKPolylineRenderer {
    /// Made this way, not by an initializer of its own, so it keeps the ones MapKit calls.
    static func make(_ line: TrailLine) -> TrailRenderer {
        let r = TrailRenderer(polyline: line)
        r.style(line)
        return r
    }

    private func style(_ line: TrailLine) {
        lineJoin = .round
        lineCap = .round
        switch line.kind {
        case "water": strokeColor = WallMap.water; lineWidth = 3.2
        case "plan": strokeColor = WallMap.trail; lineWidth = 2.6; lineDashPattern = [0, 5.5]
        case "hike": strokeColor = WallMap.trail; lineWidth = 2.8; lineDashPattern = [6, 4]; lineCap = .butt
        default: strokeColor = WallMap.trail; lineWidth = 2.8
        }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        if path == nil { createPath() }
        guard let path else { return }
        context.addPath(path)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth((lineWidth + 3) / zoomScale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
        applyStrokeProperties(to: context, atZoomScale: zoomScale)
        context.addPath(path)
        context.strokePath()
    }
}

/// A place drawn as a dot: a state park, a Corps campground.
struct Dot {
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let colour: NSColor
    /// Its page, for the right-click menu: a Recreation.gov booking page.
    var link: URL? = nil
}

/// A set of dots as one overlay, which DotsRenderer draws.
final class Dots: NSObject, MKOverlay {
    let dots: [Dot]
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world

    init(_ dots: [Dot]) { self.dots = dots }
}

/// Dots with a white rim, each with its name beside it from zoom 9 in. All of a layer's
/// dots are one overlay: MapKit draws an overlay once and keeps the result, but given
/// even a few annotations here instead, it redrew the whole map on every frame and
/// everything on it jiggled.
final class DotsRenderer: MKOverlayRenderer {
    static let side: CGFloat = 12

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let dots = overlay as? Dots else { return }
        let side = Self.side / zoomScale, rim = 2 / zoomScale
        let named = 20 + log2(zoomScale) >= 9
        // Reach far enough to catch a dot or name that only overhangs this tile.
        let tile = rect(for: mapRect).insetBy(dx: -(named ? 240 : Self.side) / zoomScale, dy: -side)
        let font = NSFont.systemFont(ofSize: 11 / zoomScale, weight: .semibold)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for dot in dots.dots {
            let p = point(for: MKMapPoint(dot.coordinate))
            guard tile.contains(p) else { continue }
            let disc = NSBezierPath(ovalIn: CGRect(x: p.x - side / 2 + rim / 2, y: p.y - side / 2 + rim / 2,
                                                   width: side - rim, height: side - rim))
            dot.colour.setFill()
            disc.fill()
            NSColor.white.setStroke()
            disc.lineWidth = rim
            disc.stroke()
            guard named else { continue }
            NSAttributedString(string: dot.name, attributes: [
                .font: font,
                .foregroundColor: dot.colour.blended(withFraction: 0.35, of: .black)!,
                .strokeColor: NSColor.white.withAlphaComponent(0.9),
                .strokeWidth: -3.0,
            ]).draw(at: CGPoint(x: p.x + side * 0.75, y: p.y - font.pointSize * 0.62))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// The Corps of Engineers campgrounds, from CorpsData.swift, as dots.
@MainActor
enum Corps {
    static let dots: [Dot] = CorpsData.campgrounds.map { camp in
        Dot(name: camp.name,
            subtitle: camp.sites > 0 ? "Corps of Engineers campground, \(camp.sites) sites" : "Corps of Engineers campground",
            coordinate: CLLocationCoordinate2D(latitude: camp.lat, longitude: camp.lon),
            colour: WallMap.corps,
            link: URL(string: "https://www.recreation.gov/camping/campgrounds/\(camp.id)"))
    }
}

// MARK: The key

/// The pin colours and counts, over the bottom-left of the map while pins show.
struct PinKey: View {
    @ObservedObject private var layers = Layers.shared
    @ObservedObject private var pins = CountyPins.shared

    var body: some View {
        if layers.pins {
            VStack(alignment: .leading, spacing: 4) {
                Picker("Colour by", selection: $layers.pinView) {
                    ForEach(PinView.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                if pins.byCounty.isEmpty {
                    Text("No pins yet: File › Import County Pins…")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        ForEach(Array(WallMap.key(layers.pinView).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(Color(item.0).opacity(0.75))
                                    .frame(width: 10, height: 10)
                                Text(item.1)
                            }
                        }
                        Text("\(pins.count(layers.pinView)) of 67")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
        }
    }
}
