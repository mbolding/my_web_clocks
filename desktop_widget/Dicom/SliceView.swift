// SliceView — draws the current slice, fitted to the view and then zoomed and moved,
// and turns the mouse, trackpad and keys into viewer actions: drag for window and level,
// ⌥-drag to move the image, scroll or arrow keys for slices, pinch to zoom, and a
// double-click to fit it again.

import SwiftUI
import AppKit

struct SliceView: NSViewRepresentable {
    @ObservedObject var display: Display

    func makeNSView(context: Context) -> SliceNSView {
        let view = SliceNSView()
        view.display = display
        return view
    }

    func updateNSView(_ view: SliceNSView, context: Context) {
        view.display = display
        view.image = display.image
        view.zoom = display.zoom
        view.pan = display.pan
        view.aspect = display.aspect
        view.needsDisplay = true
    }
}

final class SliceNSView: NSView {
    weak var display: Display?
    var image: CGImage?
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var aspect: CGFloat = 1

    private var lastDrag: NSPoint?
    private var scrolled: CGFloat = 0
    private var scrolledLines: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    // Takes the focus as the image comes up, so the arrow keys work straight away.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    /// Where the image goes: fitted to the view, scaled by the zoom, moved by the pan.
    private var imageRect: CGRect {
        guard let image else { return .zero }
        let w = CGFloat(image.width), h = CGFloat(image.height) * aspect
        let fit = min(bounds.width / w, bounds.height / h) * zoom
        let size = CGSize(width: w * fit, height: h * fit)
        return CGRect(x: bounds.midX - size.width / 2 + pan.width, y: bounds.midY - size.height / 2 + pan.height,
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
        guard let image else { return }
        let rect = imageRect
        // Smooth, until each pixel is big enough to see as a square.
        context.interpolationQuality = rect.width / CGFloat(image.width) > 8 ? .none : .high
        context.draw(image, in: rect)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            display?.zoomToFit()
            lastDrag = nil
            return
        }
        lastDrag = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDrag, let display else { return }
        let now = event.locationInWindow
        let dx = now.x - last.x, dy = now.y - last.y
        lastDrag = now
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            display.pan = CGSize(width: display.pan.width + dx, height: display.pan.height + dy)
        } else {
            // Window coordinates run upwards; dragging down raises the level.
            display.drag(dx: dx, dy: -dy, fine: event.modifierFlags.contains(.shift))
        }
    }

    override func mouseUp(with event: NSEvent) {
        lastDrag = nil
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard let display else { return }
        display.pan = CGSize(width: display.pan.width + event.deltaX, height: display.pan.height - event.deltaY)
    }

    /// Right-click: the window presets and the rest of the Image menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let display, display.slice != nil else { return nil }
        let menu = NSMenu()
        for preset in display.presets {
            let item = MenuAction(preset.name) { display.apply(named: preset.name) }
            item.state = display.presetName == preset.name ? .on : .off
            menu.addItem(item)
        }
        if !display.presets.isEmpty { menu.addItem(.separator()) }
        for (title, action) in [("Reset Window", display.resetWindow), ("Invert", { display.invert.toggle() }),
                                ("Zoom to Fit", display.zoomToFit), ("Copy Image", display.copyImage)] as [(String, () -> Void)] {
            let item = MenuAction(title, action)
            item.isEnabled = title == "Zoom to Fit" || title == "Copy Image" || display.canWindow
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        return menu
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// Scrolling moves through the slices: one per notch of a mouse wheel, or one per few
    /// points of a trackpad swipe. Momentum after a swipe is ignored, so it stops where the
    /// fingers do.
    override func scrollWheel(with event: NSEvent) {
        guard let display, display.count > 1 else { return }
        if !event.momentumPhase.isEmpty { return }
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        if event.hasPreciseScrollingDeltas {
            if event.phase == .began { scrolled = 0 }
            scrolled += delta
            let steps = Int(scrolled / 6)
            guard steps != 0 else { return }
            scrolled -= CGFloat(steps) * 6
            display.step(-steps)
        } else {
            // A fast-spun wheel sends bigger steps, and events can arrive merged.
            scrolledLines += delta
            let steps = Int(scrolledLines.rounded(.towardZero))
            guard steps != 0 else { return }
            scrolledLines -= CGFloat(steps)
            display.step(-steps)
        }
    }

    /// Pinching zooms about the point under the fingers.
    override func magnify(with event: NSEvent) {
        guard let display else { return }
        let point = convert(event.locationInWindow, from: nil)
        zoom(display, to: display.zoom * (1 + event.magnification), about: point)
    }

    private func zoom(_ display: Display, to next: CGFloat, about point: CGPoint) {
        let next = min(max(next, 0.1), 32), ratio = next / display.zoom
        let from = CGSize(width: point.x - bounds.midX, height: point.y - bounds.midY)
        display.pan = CGSize(width: from.width - (from.width - display.pan.width) * ratio,
                             height: from.height - (from.height - display.pan.height) * ratio)
        display.zoom = next
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let display, let key = event.specialKey else { return super.keyDown(with: event) }
        switch key {
        case .upArrow, .leftArrow: display.step(-1)
        case .downArrow, .rightArrow: display.step(1)
        case .pageUp: display.step(-10)
        case .pageDown: display.step(10)
        case .home: display.first()
        case .end: display.last()
        default: super.keyDown(with: event)
        }
    }
}

/// A menu item that runs a closure.
final class MenuAction: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func runAction() { run() }
}
