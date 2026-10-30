// ViewerModel — one window's files: loading them, the series found, and which is shown.
// Display holds what the image view draws (slice, window, zoom), and Tags the current
// file's tag rows. Inbox hands files opened from the Dock, Finder or File → Open to the
// frontmost window.

import SwiftUI
import AppKit

@MainActor
final class ViewerModel: ObservableObject {
    enum Phase: Equatable {
        case empty
        case loading(Double)
        case ready
        case failed(String)
    }

    @Published private(set) var phase = Phase.empty
    @Published private(set) var series: [Series] = []
    @Published var selection: Series.ID? {
        didSet {
            guard selection != oldValue, let selected = series.first(where: { $0.id == selection }) else { return }
            display.show(selected)
        }
    }
    @Published private(set) var thumbnails: [Series.ID: CGImage] = [:]
    @Published private(set) var notice: String?
    @Published private(set) var urls: [URL] = []

    let display = Display()
    let tags = Tags()

    /// Shows files in this window, or in a new one. The window sets it.
    var receive: ([URL]) -> Void = { _ in }

    init() {
        display.fileChanged = { [tags] file in tags.show(file) }
    }

    var isEmpty: Bool { phase == .empty || { if case .failed = phase { return true } else { return false } }() }

    var selected: Series? { series.first { $0.id == selection } }

    func load(_ urls: [URL]) async {
        self.urls = urls
        notice = nil
        guard !urls.isEmpty else {
            phase = .empty
            return
        }
        phase = .loading(0)
        let result = await Task.detached(priority: .userInitiated) {
            Loader.load(urls) { fraction in
                Task { @MainActor [weak self] in
                    if case .loading = self?.phase { self?.phase = .loading(fraction) }
                }
            }
        }.value
        guard self.urls == urls else { return }

        guard !result.series.isEmpty else {
            let what = result.skipped == 1 ? "That file isn’t" : "None of those \(result.skipped.formatted()) files are"
            phase = .failed(result.skipped == 0 ? "There were no files to read." : "\(what) DICOM.")
            return
        }
        series = result.series
        thumbnails = [:]
        phase = .ready
        if result.skipped > 0 {
            flash("Skipped \(Series.count(result.skipped, "file")) that \(result.skipped == 1 ? "isn’t" : "aren’t") DICOM")
        }
        selection = (series.first { $0.hasImage } ?? series[0]).id
        urls.forEach { NSDocumentController.shared.noteNewRecentDocumentURL($0) }
        makeThumbnails()
    }

    /// Small pictures of each series' middle slice, for the sidebar.
    private func makeThumbnails() {
        let list = series.filter(\.hasImage)
        Task.detached(priority: .utility) { [weak self] in
            for series in list {
                guard let image = Self.thumbnail(series) else { continue }
                await self?.setThumbnail(image, for: series.id)
            }
        }
    }

    private func setThumbnail(_ image: CGImage, for id: Series.ID) { thumbnails[id] = image }

    nonisolated private static func thumbnail(_ series: Series) -> CGImage? {
        let slice = series.slices[series.slices.count / 2]
        guard let frame = try? slice.file.decode(frame: slice.frame) else { return nil }
        let window = Display.fileWindow(slice) ?? Display.autoWindow(frame)
        guard let full = frame.render(center: window.center, width: window.width,
                                      invert: slice.file.image?.photometric == "MONOCHROME1") else { return nil }
        let side = 96, scale = Double(side) / Double(max(full.width, full.height))
        let w = max(1, Int(Double(full.width) * scale)), h = max(1, Int(Double(full.height) * scale))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    func step(series delta: Int) {
        guard let i = series.firstIndex(where: { $0.id == selection }) else { return }
        let next = i + delta
        guard series.indices.contains(next) else { return }
        selection = series[next].id
    }

    private var flashID = 0

    func flash(_ message: String) {
        notice = message
        flashID += 1
        let id = flashID
        Task {
            try? await Task.sleep(for: .seconds(3))
            if flashID == id { notice = nil }
        }
    }
}

/// The image view's state: the series and slice shown, its window, and the zoom.
@MainActor
final class Display: ObservableObject {
    struct Window: Equatable {
        var center: Double
        var width: Double
    }

    struct Preset: Identifiable {
        let name: String
        let window: Window
        var id: String { name }
    }

    @Published private(set) var series: Series?
    @Published var index = 0 {
        didSet {
            guard let series, !series.slices.isEmpty else { return }
            let clamped = min(max(index, 0), series.slices.count - 1)
            if clamped != index { index = clamped; return }
            if index != oldValue { showSlice() }
        }
    }
    @Published private(set) var window = Window(center: 0, width: 1)
    @Published var invert = false { didSet { render() } }
    /// The scale relative to fitting the window, and how far the image is moved, in points.
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published private(set) var image: CGImage?
    @Published private(set) var problem: String?
    /// The name of the window in use, if it's a preset rather than one dragged to.
    @Published private(set) var presetName: String?

    var fileChanged: (DicomFile?) -> Void = { _ in }
    private var frame: DecodedFrame?
    private var cache: [String: DecodedFrame] = [:]
    private var cacheOrder: [String] = []

    var slice: Slice? {
        guard let series, series.slices.indices.contains(index) else { return nil }
        return series.slices[index]
    }

    var file: DicomFile? { slice?.file }
    var count: Int { series?.slices.count ?? 0 }
    var canWindow: Bool { frame.map { !$0.isColor } ?? false }

    /// The pixel size in mm, row spacing first, for drawing non-square pixels.
    var aspect: CGFloat {
        guard let slice, let spacing = slice.file.image?.frames[slice.frame].spacing else { return 1 }
        return CGFloat(spacing[0] / spacing[1])
    }

    func show(_ series: Series) {
        self.series = series
        cache = [:]
        cacheOrder = []
        frame = nil
        zoom = 1
        pan = .zero
        index = 0
        showSlice()
    }

    private func showSlice() {
        guard let slice else { return }
        let previous = frame
        do {
            frame = try decoded(slice)
            problem = nil
        } catch {
            frame = nil
            problem = error.localizedDescription
        }
        if previous == nil, frame != nil { initialWindow() }
        render()
        fileChanged(slice.file)
    }

    private func decoded(_ slice: Slice) throws -> DecodedFrame {
        let key = "\(slice.file.url.path)#\(slice.frame)"
        if let hit = cache[key] { return hit }
        let frame = try slice.file.decode(frame: slice.frame)
        cache[key] = frame
        cacheOrder.append(key)
        if cacheOrder.count > 48 { cache[cacheOrder.removeFirst()] = nil }
        return frame
    }

    private func render() {
        guard let frame, let slice else {
            image = nil
            return
        }
        let monochrome1 = slice.file.image?.photometric == "MONOCHROME1"
        image = frame.render(center: window.center, width: window.width, invert: invert != monochrome1)
    }

    // MARK: Window and level

    /// The file's own window for a slice, if it has one.
    nonisolated static func fileWindow(_ slice: Slice) -> Window? {
        guard let info = slice.file.image?.frames[slice.frame], let c = info.centers.first, let w = info.widths.first, w > 0
        else { return nil }
        return Window(center: c, width: w)
    }

    nonisolated static func autoWindow(_ frame: DecodedFrame) -> Window {
        Window(center: Double(frame.low + frame.high) / 2, width: Double(frame.high - frame.low))
    }

    var presets: [Preset] {
        guard let slice, let frame, !frame.isColor else { return [] }
        var out: [Preset] = []
        if let info = slice.file.image?.frames[slice.frame] {
            let explanations = slice.file.strings(slice.file.dataSet[0x0028_1055])
            for i in 0..<min(info.centers.count, info.widths.count) where info.widths[i] > 0 {
                let name = i < explanations.count && !explanations[i].isEmpty ? explanations[i].capitalized : "Window \(i + 1)"
                out.append(Preset(name: "\(name) (from file)", window: Window(center: info.centers[i], width: info.widths[i])))
            }
        }
        out.append(Preset(name: "Auto", window: Self.autoWindow(frame)))
        out.append(Preset(name: "Full Range", window: Window(center: Double(frame.minimum + frame.maximum) / 2,
                                                             width: Double(max(frame.maximum - frame.minimum, 1)))))
        if slice.file.string(0x0008_0060) == "CT" {
            for (name, c, w) in [("Brain", 40.0, 80.0), ("Subdural", 75, 215), ("Abdomen", 40, 400), ("Lung", -600, 1500), ("Bone", 400, 1800)] {
                out.append(Preset(name: name, window: Window(center: c, width: w)))
            }
        }
        return out
    }

    func apply(_ preset: Preset) {
        window = preset.window
        presetName = preset.name
        render()
    }

    func apply(named name: String) {
        if let preset = presets.first(where: { $0.name == name }) { apply(preset) }
    }

    /// The slice as shown, at its own size, for pasting elsewhere.
    func copyImage() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))])
    }

    /// The file's window, or else Auto for the middle slice, since the first is often
    /// nearly empty.
    private func initialWindow() {
        if let slice, Self.fileWindow(slice) != nil { return resetWindow() }
        guard let series, let middle = try? decoded(series.slices[series.slices.count / 2]) else { return resetWindow() }
        apply(Preset(name: "Auto", window: Self.autoWindow(middle)))
    }

    /// Back to the file's window for this slice, or Auto if it has none.
    func resetWindow() {
        guard let first = presets.first else { return }
        apply(first)
    }

    /// Dragging across the image: right widens the window, down raises the level. The
    /// steps scale with the width, so narrow windows move finely and wide ones quickly.
    func drag(dx: CGFloat, dy: CGFloat, fine: Bool) {
        guard canWindow else { return }
        let k = fine ? 0.001 : 0.005
        var next = window
        next.width = max(next.width * exp(Double(dx) * k), 1e-3)
        next.center += Double(dy) * k * max(next.width, 1)
        window = next
        presetName = nil
        render()
    }

    // MARK: Moving and zooming

    func step(_ delta: Int) { index += delta }
    func first() { index = 0 }
    func last() { index = count - 1 }

    func zoomIn() { zoom = min(zoom * 1.25, 32) }
    func zoomOut() { zoom = max(zoom / 1.25, 0.1) }

    func zoomToFit() {
        zoom = 1
        pan = .zero
    }
}

/// The current file's tags, updated a moment after the slice stops changing, so scrolling
/// through a long series doesn't rebuild the list for every slice on the way.
@MainActor
final class Tags: ObservableObject {
    @Published private(set) var file: DicomFile?
    @Published private(set) var rows: [TagRow] = []
    private var target: DicomFile?
    private var pending: Task<Void, Never>?
    private var cache: [URL: [TagRow]] = [:]

    func show(_ next: DicomFile?) {
        guard next !== target else { return }
        target = next
        pending?.cancel()
        pending = Task {
            if file != nil { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            file = next
            guard let next else { rows = []; return }
            if let hit = cache[next.url] { rows = hit; return }
            let made = TagRows.rows(for: next)
            if cache.count > 64 { cache = [:] }
            cache[next.url] = made
            rows = made
        }
    }

    /// All the tags as text, one per line.
    func copyAll() {
        guard !rows.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rows.map(\.line).joined(separator: "\n"), forType: .string)
    }
}

/// Where opened files go: to the frontmost window, or to new windows while there's none.
@MainActor
final class Inbox {
    static let shared = Inbox()

    /// SwiftUI's action for opening a window on files. The menu commands hand it over, as
    /// SwiftUI sets them up at launch, before any window.
    var openWindow: OpenWindowAction?
    private weak var front: ViewerModel?
    private var pending: [URL] = []

    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let front {
            front.receive(urls)
        } else if let openWindow {
            openWindow(value: urls)
        } else {
            pending += urls
        }
    }

    /// Opens a window for files that came in before SwiftUI was ready for them.
    func finishLaunching() {
        let urls = pending
        pending = []
        open(urls)
    }

    /// Called as a window comes up or to the front.
    func makeFront(_ model: ViewerModel) {
        front = model
        guard !pending.isEmpty else { return }
        let urls = pending
        pending = []
        model.receive(urls)
    }

    func closed(_ model: ViewerModel) {
        if front === model { front = nil }
    }

    var hasFront: Bool { front != nil }

    /// File → Open…: files, folders, or both.
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose DICOM files, or a folder of them"
        panel.prompt = "Open"
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }
}
