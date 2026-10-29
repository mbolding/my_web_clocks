// Tiles — the map styles, and the overlay that draws their OpenStreetMap tiles in place of
// Apple's map. Tiles come through one URLSession with an on-disk cache and a User-Agent
// naming the app, as the tile servers' usage policies ask, and past a style's last zoom
// level the overlay enlarges part of a lower tile rather than leaving the map blank.

import MapKit
import AppKit

enum MapStyle: String, CaseIterable, Identifiable {
    case standard, humanitarian, cyclosm, topo

    var id: Self { self }

    var name: String {
        switch self {
        case .standard: "Standard"
        case .humanitarian: "Humanitarian"
        case .cyclosm: "CyclOSM"
        case .topo: "OpenTopoMap"
        }
    }

    var template: String {
        switch self {
        case .standard: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        case .humanitarian: "https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png"
        case .cyclosm: "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png"
        case .topo: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png"
        }
    }

    /// The deepest zoom the server draws; beyond it, tiles are enlarged from this level.
    var maxZoom: Int {
        switch self {
        case .standard, .humanitarian: 19
        case .cyclosm: 20
        case .topo: 17
        }
    }

    /// Credit for the style itself, shown after the OpenStreetMap one.
    var credit: String? {
        switch self {
        case .standard: nil
        case .humanitarian: "Style: Humanitarian OSM Team, hosted by OSM France"
        case .cyclosm: "Style: CyclOSM, hosted by OSM France"
        case .topo: "SRTM · Style: © OpenTopoMap (CC-BY-SA)"
        }
    }

    /// The style's code in openstreetmap.org links, where it has one.
    var layerCode: String? {
        switch self {
        case .humanitarian: "H"
        case .cyclosm: "Y"
        case .standard, .topo: nil
        }
    }
}

final class TileOverlay: MKTileOverlay {
    let style: MapStyle
    let sharp: Bool

    /// Sharp tiles are drawn at half size, so they're crisp on a Retina screen but their
    /// labels are small.
    init(style: MapStyle, sharp: Bool) {
        self.style = style
        self.sharp = sharp
        super.init(urlTemplate: style.template)
        canReplaceMapContent = true
        tileSize = CGSize(width: sharp ? 128 : 256, height: sharp ? 128 : 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let z = min(path.z, style.maxZoom), extra = path.z - z
        let source = MKTileOverlayPath(x: path.x >> extra, y: path.y >> extra, z: z,
                                       contentScaleFactor: path.contentScaleFactor)
        Tiles.fetch(url(forTilePath: source)) { data, error in
            guard extra > 0, let data else { return result(data, error) }
            result(Tiles.enlarge(data, part: (path.x, path.y), of: 1 << extra), nil)
        }
    }
}

enum Tiles {
    static let userAgent = "MapBrowser/1.0 (macOS; +https://github.com/mbolding/my_web_clocks)"

    static let cache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20,
                                directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                    .appendingPathComponent("com.mbolding.mapbrowser/Tiles"))

    /// Used for search too, so every request to OpenStreetMap carries the User-Agent.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    /// Fetches a tile, honouring the server's cache headers. A failed fetch is tried twice
    /// more, since MapKit leaves a tile blank until it scrolls away; then, offline or
    /// refused, it falls back to a cached copy however old it is.
    static func fetch(_ url: URL, attempt: Int = 1, done: @escaping (Data?, Error?) -> Void) {
        session.dataTask(with: url) { data, response, error in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200, NSBitmapImageRep(data: data) != nil {
                return done(data, nil)
            }
            if attempt < 3 {
                return DispatchQueue.global().asyncAfter(deadline: .now() + Double(attempt)) {
                    fetch(url, attempt: attempt + 1, done: done)
                }
            }
            if let cached = cache.cachedResponse(for: URLRequest(url: url)) { return done(cached.data, nil) }
            done(nil, error ?? URLError(.badServerResponse))
        }.resume()
    }

    /// One of the n×n parts of a tile, scaled up to the tile's full size.
    static func enlarge(_ data: Data, part: (x: Int, y: Int), of n: Int) -> Data? {
        guard let image = NSBitmapImageRep(data: data)?.cgImage else { return nil }
        let size = image.width, side = CGFloat(size) / CGFloat(n)
        let rect = CGRect(x: CGFloat(part.x % n) * side, y: CGFloat(part.y % n) * side, width: side, height: side)
        guard let piece = image.cropping(to: rect.integral),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(piece, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let enlarged = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: enlarged).representation(using: .png, properties: [:])
    }
}
