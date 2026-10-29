// MapView — MapKit's map view wrapped for SwiftUI, showing the model's tile overlay in
// place of Apple's map. MapKit brings the dragging, pinch and scroll zoom, double-click
// zoom and the scale; this adds the right-click menu and the pin's colour.

import SwiftUI
import MapKit

struct MapView: NSViewRepresentable {
    var model: MapModel
    var tint: NSColor
    var sharp: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> MapCanvas {
        let map = MapCanvas()
        map.delegate = context.coordinator
        map.isRotateEnabled = false // raster tiles keep north up, as on openstreetmap.org
        map.isPitchEnabled = false
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.onMenu = { [weak model] c in model?.menu(at: c) }
        map.onFirstLayout = { [weak model] in model?.restoreView() }
        model.sharp = sharp
        model.attach(map)
        return map
    }

    func updateNSView(_ map: MapCanvas, context: Context) {
        model.sharp = sharp
        context.coordinator.tint = tint
        for annotation in map.annotations {
            (map.view(for: annotation) as? MKMarkerAnnotationView)?.markerTintColor = tint
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        let model: MapModel
        var tint = NSColor.systemOrange

        init(model: MapModel) { self.model = model }

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tiles = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            return MKTileOverlayRenderer(tileOverlay: tiles)
        }

        func mapViewDidChangeVisibleRegion(_ map: MKMapView) { model.regionChanged(settled: false) }
        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) { model.regionChanged(settled: true) }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = map.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.annotation = annotation
            view.markerTintColor = tint
            view.canShowCallout = true
            return view
        }

        func mapView(_ map: MKMapView, didUpdate userLocation: MKUserLocation) { model.located(userLocation.location) }
        func mapView(_ map: MKMapView, didFailToLocateUserWithError error: Error) { model.locationFailed() }
    }
}

final class MapCanvas: MKMapView {
    var onMenu: ((CLLocationCoordinate2D) -> NSMenu?)?
    var onFirstLayout: (() -> Void)?

    /// Runs once the map has a size, on the next turn of the run loop, after MapKit has
    /// set its own starting region.
    override func layout() {
        super.layout()
        if bounds.width > 0, let first = onFirstLayout {
            onFirstLayout = nil
            DispatchQueue.main.async(execute: first)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onMenu?(convert(convert(event.locationInWindow, from: nil), toCoordinateFrom: self))
    }
}
