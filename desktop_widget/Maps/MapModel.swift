// MapModel — one window's map: where it's looking, its style, the pin, the search and its
// results, and the actions the toolbar, menus and right-click menu share. Zoom levels are
// the slippy-map ones openstreetmap.org uses, worked out from MapKit's visible map rect:
// at zoom z a 256-point tile covers 2^(20 − z) map points.

import SwiftUI
import MapKit

enum SidebarItem: Hashable {
    case result(SearchResult.ID)
    case place(Place.ID)
}

struct Pin {
    var coordinate: CLLocationCoordinate2D
    var title: String
    var subtitle: String?
}

/// The centre and zoom, which change on every frame of a drag, kept apart from the model
/// so only the status bar redraws with them.
@MainActor
final class MapReadout: ObservableObject {
    @Published var center = CLLocationCoordinate2D()
    @Published var zoom = 0.0
}

@MainActor
final class MapModel: ObservableObject {
    @Published var style = MapStyle(rawValue: UserDefaults.standard.string(forKey: "defaultStyle") ?? "") ?? .standard {
        didSet { if style != oldValue { applyOverlay() } }
    }
    @Published private(set) var pin: Pin?
    @Published var query = ""
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var searching = false
    @Published var selection: SidebarItem? {
        didSet { if selection != oldValue { open(selection) } }
    }
    /// A short message shown over the map for a few seconds.
    @Published private(set) var notice: String?

    // Naming a place to save, or renaming a saved one.
    @Published var naming = false
    @Published var renaming: Place?
    @Published var draftName = ""
    private var draftSpot = CLLocationCoordinate2D()

    let readout = MapReadout()
    var center: CLLocationCoordinate2D { readout.center }
    var zoom: Double { readout.zoom }

    /// Set from the Settings window; see TileOverlay.
    var sharp = false {
        didSet { if sharp != oldValue { applyOverlay() } }
    }

    private weak var map: MKMapView?
    private var overlay: TileOverlay?
    private let marker = MKPointAnnotation()
    private let locator = CLLocationManager()
    private var wantsLocation = false
    private var restored = false
    /// Where the last setView headed, and where the map went for the sidebar selection.
    private var target: (center: CLLocationCoordinate2D, zoom: Double)?
    private var selectionTarget: (center: CLLocationCoordinate2D, zoom: Double, at: Date)?
    private var noticeTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    func attach(_ map: MKMapView) {
        self.map = map
        applyOverlay()
    }

    /// Once the map has a size: back to where the last window was looking.
    func restoreView() {
        let last = UserDefaults.standard.array(forKey: "lastView") as? [Double] ?? []
        if last.count == 3 {
            setView(CLLocationCoordinate2D(latitude: last[0], longitude: last[1]), zoom: last[2], animated: false)
        }
        restored = true
    }

    private func applyOverlay() {
        guard let map else { return }
        let new = TileOverlay(style: style, sharp: sharp)
        map.addOverlay(new, level: .aboveLabels)
        if let overlay { map.removeOverlay(overlay) }
        overlay = new
    }

    // MARK: Moving the map

    func regionChanged(settled: Bool) {
        guard let map, map.bounds.width > 0 else { return }
        readout.center = map.centerCoordinate
        readout.zoom = 20 - log2(map.visibleMapRect.width / map.bounds.width)
        if settled && restored {
            UserDefaults.standard.set([center.latitude, center.longitude, zoom], forKey: "lastView")
            deselectIfMovedAway()
        }
    }

    func setView(_ center: CLLocationCoordinate2D, zoom: Double, animated: Bool = true) {
        guard let map, map.bounds.width > 0 else { return }
        target = (center, min(max(zoom, 1), 21))
        let scale = pow(2, 20 - min(max(zoom, 1), 21))
        let w = map.bounds.width * scale, h = map.bounds.height * scale
        let p = MKMapPoint(center)
        map.setVisibleMapRect(MKMapRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: animated)
    }

    func zoomIn() { setView(center, zoom: zoom.rounded() + 1) }
    func zoomOut() { setView(center, zoom: zoom.rounded() - 1) }

    func go(to place: Place) {
        setPin(place.coordinate, title: place.name)
        setView(place.coordinate, zoom: place.zoom)
    }

    /// Shows a search result: pinned, and framed by its outline where it has one.
    func show(_ result: SearchResult) {
        setPin(result.coordinate, title: result.title, subtitle: result.detail)
        guard let b = result.bounds, b.count == 4, let map, map.bounds.width > 0 else {
            return setView(result.coordinate, zoom: 16)
        }
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: b[1], longitude: b[2]))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: b[0], longitude: b[3]))
        let fit = 20 - log2(max(abs(se.x - nw.x) / map.bounds.width, abs(se.y - nw.y) / map.bounds.height, 1e-9))
        setView(MKMapPoint(x: (nw.x + se.x) / 2, y: (nw.y + se.y) / 2).coordinate, zoom: min(fit - 0.3, 18))
    }

    private func open(_ item: SidebarItem?) {
        switch item {
        case .result(let id): if let r = results.first(where: { $0.id == id }) { show(r) }
        case .place(let id): if let p = Places.shared.all.first(where: { $0.id == id }) { go(to: p) }
        case nil: break
        }
        selectionTarget = item == nil ? nil : target.map { ($0.center, $0.zoom, .now) }
    }

    /// Once the map has moved off the selected place or result, drops the selection, so
    /// clicking that row again counts as a change and goes back there. A list only
    /// reports a click that changes its selection.
    private func deselectIfMovedAway() {
        // Skip the first moments, while the map is still flying there.
        guard let goal = selectionTarget, Date.now.timeIntervalSince(goal.at) > 1.5 else { return }
        let a = MKMapPoint(center), b = MKMapPoint(goal.center)
        let points = hypot(a.x - b.x, a.y - b.y) / pow(2, 20 - zoom)
        if points > 30 || abs(zoom - goal.zoom) > 0.3 {
            selectionTarget = nil
            selection = nil
        }
    }

    // MARK: The pin

    /// Places the pin, with its title under it. It isn't selected from here: a click on
    /// the map makes MapKit deselect it a moment later, so the pin would grow, shrink
    /// and grow again as its name arrived. Clicking the pin selects it.
    func setPin(_ c: CLLocationCoordinate2D, title: String, subtitle: String? = nil) {
        pin = Pin(coordinate: c, title: title, subtitle: subtitle)
        marker.coordinate = c
        marker.title = title
        marker.subtitle = subtitle
        guard let map else { return }
        if !map.annotations.contains(where: { $0 === marker }) { map.addAnnotation(marker) }
    }

    func clearPin() {
        pin = nil
        map?.removeAnnotation(marker)
    }

    /// Pins the spot, then names it from OpenStreetMap once the answer comes.
    func whatsHere(_ c: CLLocationCoordinate2D) {
        setPin(c, title: "Looking…", subtitle: coordinateText(c))
        Task {
            do {
                guard let place = try await Nominatim.shared.reverse(c) else {
                    return setPin(c, title: "Unnamed spot", subtitle: coordinateText(c))
                }
                setPin(c, title: place.title, subtitle: place.detail)
            } catch {
                setPin(c, title: "Dropped Pin", subtitle: coordinateText(c))
                tell("Couldn't reach OpenStreetMap to name this spot.")
            }
        }
    }

    // MARK: Search

    func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let spot = typedSpot(text) {
            clearResults()
            setPin(spot.coordinate, title: coordinateText(spot.coordinate))
            return setView(spot.coordinate, zoom: spot.zoom ?? max(zoom, 15))
        }
        searchTask?.cancel()
        searching = true
        let viewbox = UserDefaults.standard.object(forKey: "searchNearby") as? Bool ?? true ? visibleBox() : nil
        searchTask = Task {
            defer { searching = false }
            do {
                let found = try await Nominatim.shared.search(text, near: viewbox)
                guard !Task.isCancelled else { return }
                results = found
                if let first = found.first {
                    selection = .result(first.id)
                } else {
                    tell("No places found for “\(text)”.")
                }
            } catch {
                if !Task.isCancelled { tell("Search failed: \(error.localizedDescription)") }
            }
        }
    }

    func clearResults() {
        searchTask?.cancel()
        results = []
        if case .result = selection { selection = nil }
    }

    /// West, north, east, south of what's on screen, to rank nearby results first; nil
    /// when most of the world is showing.
    private func visibleBox() -> [Double]? {
        guard let map, zoom >= 4 else { return nil }
        let rect = map.visibleMapRect
        let nw = MKMapPoint(x: rect.minX, y: rect.minY).coordinate
        let se = MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate
        return [max(nw.longitude, -180), nw.latitude, min(se.longitude, 180), se.latitude]
    }

    // MARK: Places

    /// Asks for a name for the spot: the given one, else the pin, else the map's centre.
    func beginSaving(at c: CLLocationCoordinate2D? = nil) {
        draftSpot = c ?? pin?.coordinate ?? center
        draftName = c == nil ? pin?.title ?? "" : ""
        naming = true
    }

    func finishSaving() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        let place = Place(name: name.isEmpty ? coordinateText(draftSpot) : name,
                          latitude: draftSpot.latitude, longitude: draftSpot.longitude, zoom: max(zoom.rounded(), 15))
        Places.shared.add(place)
        tell("Saved “\(place.name)” to Places.")
    }

    func beginRenaming(_ place: Place) {
        draftName = place.name
        renaming = place
    }

    func finishRenaming() {
        if let renaming { Places.shared.rename(renaming.id, to: draftName.trimmingCharacters(in: .whitespaces)) }
        renaming = nil
    }

    func deleteSelectedPlace() {
        if case .place(let id) = selection {
            Places.shared.remove(id)
            selection = nil
        }
    }

    // MARK: Location

    func showMyLocation() {
        guard let map else { return }
        switch locator.authorizationStatus {
        case .denied, .restricted:
            return tell("Location Services are off for Map Browser. Turn them on in System Settings › Privacy & Security.")
        case .notDetermined:
            locator.requestWhenInUseAuthorization()
        default: break
        }
        wantsLocation = true
        map.showsUserLocation = true
        located(map.userLocation.location)
    }

    func located(_ location: CLLocation?) {
        guard wantsLocation, let location else { return }
        wantsLocation = false
        setView(location.coordinate, zoom: max(zoom, 15))
    }

    func locationFailed() {
        guard wantsLocation else { return }
        wantsLocation = false
        tell("Couldn't find your location.")
    }

    // MARK: Sharing

    /// An openstreetmap.org link to this view, marking the pin if there is one.
    var link: URL {
        let c = pin?.coordinate ?? center
        let mark = pin.map { String(format: "?mlat=%.5f&mlon=%.5f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? ""
        let layers = style.layerCode.map { "&layers=\($0)" } ?? ""
        return URL(string: String(format: "https://www.openstreetmap.org/%@#map=%d/%.5f/%.5f%@",
                                  mark, Int(zoom.rounded()), c.latitude, c.longitude, layers))!
    }

    func copyLink() {
        copy(link.absoluteString)
        tell("Copied a link to this view.")
    }

    func copyCoordinates(_ c: CLLocationCoordinate2D? = nil) {
        copy(coordinateText(c ?? pin?.coordinate ?? center))
        tell("Copied the coordinates.")
    }

    func openInBrowser() { NSWorkspace.shared.open(link) }

    /// openstreetmap.org's form for leaving a note about something wrong on the map.
    func reportProblem(at c: CLLocationCoordinate2D? = nil) {
        let c = c ?? pin?.coordinate ?? center
        NSWorkspace.shared.open(URL(string: String(format: "https://www.openstreetmap.org/note/new#map=%d/%.5f/%.5f",
                                                   max(Int(zoom.rounded()), 16), c.latitude, c.longitude))!)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Right-click menu

    func menu(at c: CLLocationCoordinate2D) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(MenuAction("What's Here?") { [weak self] in self?.whatsHere(c) })
        menu.addItem(MenuAction("Drop Pin") { [weak self] in self?.setPin(c, title: "Dropped Pin", subtitle: coordinateText(c)) })
        if pin != nil { menu.addItem(MenuAction("Remove Pin") { [weak self] in self?.clearPin() }) }
        menu.addItem(MenuAction("Save as a Place…") { [weak self] in self?.beginSaving(at: c) })
        menu.addItem(.separator())
        menu.addItem(MenuAction("Copy Coordinates") { [weak self] in self?.copyCoordinates(c) })
        menu.addItem(MenuAction("Report a Problem Here…") { [weak self] in self?.reportProblem(at: c) })
        return menu
    }

    func tell(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
    }
}

/// A menu item that runs a closure.
final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
