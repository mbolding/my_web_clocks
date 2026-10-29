// Search — finding places by name through OpenStreetMap's Nominatim service, and naming
// the spot under a click, plus the places you've saved. Nominatim's usage policy allows
// one request a second and no search-as-you-type, so searches go when you press Return
// and wait their turn.

import SwiftUI // for moving places, with move(fromOffsets:toOffset:)
import CoreLocation

struct SearchResult: Decodable, Identifiable, Hashable {
    let id: Int
    let displayName: String
    let name: String?
    let type: String?
    let latitude: Double
    let longitude: Double
    /// South, north, west, east.
    let bounds: [Double]?

    private enum CodingKeys: String, CodingKey {
        case id = "place_id", displayName = "display_name", name, type, lat, lon, boundingbox
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        latitude = Double(try c.decode(String.self, forKey: .lat)) ?? 0
        longitude = Double(try c.decode(String.self, forKey: .lon)) ?? 0
        bounds = try c.decodeIfPresent([String].self, forKey: .boundingbox)?.compactMap(Double.init)
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    private var parts: [String] { displayName.components(separatedBy: ", ") }

    /// How many parts of the address the title takes: two for a house number and its
    /// street ("1754, 1st Avenue South" reads as "1754 1st Avenue South"), else one.
    private var titleParts: Int {
        let first = parts[0] // a house number is one word starting with a digit, unlike "1st Avenue"
        return parts.count > 1 && first.first?.isNumber == true && !first.contains(" ") ? 2 : 1
    }

    var title: String {
        if let name, !name.isEmpty { return name }
        return parts.prefix(titleParts).joined(separator: " ")
    }

    /// The rest of the address after the title.
    var detail: String {
        if let name, !name.isEmpty {
            return (parts.first == name ? parts.dropFirst() : parts[...]).joined(separator: ", ")
        }
        return parts.dropFirst(titleParts).joined(separator: ", ")
    }

    /// What sort of place it is: "City", "Bus stop".
    var kind: String? {
        guard let type, type != "yes" else { return nil }
        return type.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

actor Nominatim {
    static let shared = Nominatim()
    private var nextSlot = Date.distantPast

    /// Up to ten places matching the text, nearer ones first when a viewbox (west, north,
    /// east, south) is given.
    func search(_ text: String, near viewbox: [Double]?) async throws -> [SearchResult] {
        var query = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "limit", value: "10")]
        if let viewbox {
            query.append(URLQueryItem(name: "viewbox", value: viewbox.map { String(format: "%.4f", $0) }.joined(separator: ",")))
        }
        return try JSONDecoder().decode([SearchResult].self, from: try await get("search", query))
    }

    /// The place at a point, at about street level of detail; nil over open sea.
    func reverse(_ c: CLLocationCoordinate2D) async throws -> SearchResult? {
        let data = try await get("reverse", [URLQueryItem(name: "lat", value: String(c.latitude)),
                                             URLQueryItem(name: "lon", value: String(c.longitude)),
                                             URLQueryItem(name: "zoom", value: "18")])
        return try? JSONDecoder().decode(SearchResult.self, from: data) // {"error": …} when there's nothing
    }

    private func get(_ endpoint: String, _ query: [URLQueryItem]) async throws -> Data {
        // Claim the next free second before waiting, so requests made together queue up.
        let slot = max(Date(), nextSlot)
        nextSlot = slot.addingTimeInterval(1)
        let wait = slot.timeIntervalSinceNow
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }

        var url = URLComponents(string: "https://nominatim.openstreetmap.org/\(endpoint)")!
        url.queryItems = query + [URLQueryItem(name: "format", value: "jsonv2")]
        let (data, response) = try await Tiles.session.data(from: url.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

/// A coordinate typed or pasted into the search field, rather than a name: "33.5, -86.8",
/// "geo:33.5,-86.8", or an openstreetmap.org link with #map=zoom/lat/lon in it.
func typedSpot(_ text: String) -> (coordinate: CLLocationCoordinate2D, zoom: Double?)? {
    func number(_ s: Substring) -> Double? { Double(s.prefix { $0.isNumber || $0 == "." || $0 == "-" }) }
    func valid(_ lat: Double?, _ lon: Double?) -> CLLocationCoordinate2D? {
        guard let lat, let lon, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    if let r = text.range(of: "#map=") {
        let parts = text[r.upperBound...].split(separator: "/").map(number)
        guard parts.count >= 3, let c = valid(parts[1], parts[2]) else { return nil }
        return (c, parts[0])
    }
    var s = text.lowercased().trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("geo:") { s = String(s.dropFirst(4).prefix { $0 != ";" && $0 != "?" }) }
    let numbers = s.split(whereSeparator: { $0 == "," || $0 == " " }).map { Double($0) }
    guard numbers.count == 2, let c = valid(numbers[0], numbers[1]) else { return nil }
    return (c, nil)
}

func coordinateText(_ c: CLLocationCoordinate2D) -> String {
    String(format: "%.5f, %.5f", c.latitude, c.longitude)
}

// MARK: - Places

struct Place: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var zoom: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// The saved places, shared by every window and kept in the app's defaults.
@MainActor
final class Places: ObservableObject {
    static let shared = Places()

    @Published private(set) var all: [Place] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: "places") }
    }

    private init() {
        all = (UserDefaults.standard.data(forKey: "places")).flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
    }

    func add(_ place: Place) { all.append(place) }
    func remove(_ id: Place.ID) { all.removeAll { $0.id == id } }
    func move(from source: IndexSet, to destination: Int) { all.move(fromOffsets: source, toOffset: destination) }

    func rename(_ id: Place.ID, to name: String) {
        guard let i = all.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        all[i].name = name
    }
}
