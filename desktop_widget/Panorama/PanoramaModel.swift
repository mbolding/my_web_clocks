// PanoramaModel — the photos, the stitch and the settings. Photos are kept in the order
// they were taken; adding or removing one stitches them again, in the background, from
// working copies whose corners are found once and kept. Changing how the panorama is
// projected, cropped or balanced only draws it again. Saving reads the photos at full
// size and draws the panorama from them.

import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// What can be set, kept between launches.
struct Settings: Codable, Equatable {
    var projection = Projection.cylinder
    var crop = true
    var balance = true
    var size = Size.full

    enum Size: String, Codable, CaseIterable, Identifiable {
        case full, half, quarter
        var id: Self { self }
        var name: String { rawValue.capitalized }
        var factor: Double { switch self { case .full: 1; case .half: 0.5; case .quarter: 0.25 } }
    }

    static let key = "settings"

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

extension Projection: Codable {}

@MainActor
final class PanoramaModel: ObservableObject {
    static let shared = PanoramaModel()

    enum Phase: Equatable {
        case empty
        case working(String)
        case ready
        case failed(String)
    }

    @Published private(set) var photos: [Photo] = []
    @Published private(set) var thumbnails: [UUID: CGImage] = [:]
    @Published private(set) var phase = Phase.empty
    @Published private(set) var alignment: Placement?
    @Published private(set) var layout: Layout?
    @Published private(set) var preview: CGImage?
    @Published private(set) var saving: Double?
    @Published private(set) var notice: String?
    @Published var settings = Settings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.projection != oldValue.projection || settings.crop != oldValue.crop
                || settings.balance != oldValue.balance {
                redraw()
            }
        }
    }

    /// Photos that matched none of the others, by id.
    var unplaced: Set<UUID> {
        guard let alignment else { return [] }
        return Set(alignment.unplaced.compactMap { $0 < photos.count ? photos[$0].id : nil })
    }

    var canSave: Bool { phase == .ready && preview != nil && saving == nil }
    var canAnimate: Bool { canSave && (alignment?.cameras.count ?? 0) >= 2 }
    var busy: Bool { if case .working = phase { true } else { false } }

    private var working: [URL: WorkingPhoto] = [:]
    private var colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var stitchTask: Task<Void, Never>?
    private var drawTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    /// The long side of the working copies the photos are matched on.
    nonisolated static let workingSide = 1400
    /// The widest the preview is drawn.
    nonisolated static let previewWidth = 2800.0
    /// Saved panoramas are kept below this many pixels.
    nonisolated static let maxPixels = 400_000_000.0

    // MARK: Photos

    func add(_ urls: [URL]) {
        let known = Set(photos.map(\.url))
        let files = urls.flatMap(Self.expand).filter { !known.contains($0) }
        let read = files.compactMap(Photo.read)
        if read.count < files.count {
            show(files.count - read.count == 1 ? "One file wasn't a picture." : "\(files.count - read.count) files weren't pictures.")
        }
        guard !read.isEmpty else { return }
        photos = Self.ordered(photos + read)
        for photo in read { loadThumbnail(photo) }
        stitch()
    }

    func remove(_ photo: Photo) {
        photos.removeAll { $0.id == photo.id }
        working[photo.url] = nil
        thumbnails[photo.id] = nil
        stitch()
    }

    func clear() {
        stitchTask?.cancel()
        drawTask?.cancel()
        photos = []
        thumbnails = [:]
        working = [:]
        alignment = nil
        layout = nil
        preview = nil
        phase = .empty
    }

    /// Folders dropped or opened stand for the pictures in them.
    nonisolated private static func expand(_ url: URL) -> [URL] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else { return [url] }
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentTypeKey],
                                                                     options: [.skipsHiddenFiles])) ?? []
        return contents.filter {
            (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) ?? false
        }
    }

    /// In the order they were taken, where the photos say; by name otherwise.
    private static func ordered(_ photos: [Photo]) -> [Photo] {
        photos.sorted {
            switch ($0.taken, $1.taken) {
            case let (a?, b?) where a != b: return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    private func loadThumbnail(_ photo: Photo) {
        Task.detached(priority: .utility) {
            let image = photo.thumbnail(side: 240)
            await MainActor.run {
                if let image { self.thumbnails[photo.id] = image }
            }
        }
    }

    // MARK: Stitching

    private func stitch() {
        stitchTask?.cancel()
        drawTask?.cancel()
        alignment = nil
        layout = nil
        guard !photos.isEmpty else {
            preview = nil
            phase = .empty
            return
        }
        guard photos.count >= 2 else {
            preview = nil
            phase = .failed("Add another photo or two. A panorama needs photos that overlap, taken from one spot.")
            return
        }
        let photos = self.photos
        let cached = working
        let space = cached.isEmpty ? photos[0].colorSpace : colorSpace
        colorSpace = space
        phase = .working("Reading \(photos.count) photos…")
        stitchTask = Task.detached(priority: .userInitiated) {
            // Working copies and their corners, for the photos that don't have them yet.
            let missing = photos.filter { cached[$0.url] == nil }
            var made = [WorkingPhoto?](repeating: nil, count: missing.count)
            made.withUnsafeMutableBufferPointer { buf in
                let base = Slots(buf.baseAddress!)
                DispatchQueue.concurrentPerform(iterations: missing.count) { k in
                    guard let bitmap = missing[k].pixels(maxSide: Self.workingSide, colorSpace: space) else { return }
                    base[k] = WorkingPhoto(photo: missing[k], bitmap: bitmap, features: Features.find(in: Gray(bitmap)))
                }
            }
            if Task.isCancelled { return }
            var gathered = cached
            for case let w? in made { gathered[w.photo.url] = w }
            let all = gathered
            let unreadable = photos.filter { all[$0.url] == nil }
            let ready = photos.compactMap { all[$0.url] }
            await MainActor.run { self.working = all }
            guard unreadable.isEmpty else {
                await self.fail("Couldn't read \(unreadable.map(\.name).joined(separator: ", ")).")
                return
            }
            do {
                let alignment = try Aligner.align(ready) { message in
                    Task { @MainActor in
                        if case .working = self.phase { self.phase = .working(message) }
                    }
                }
                if Task.isCancelled { return }
                await MainActor.run {
                    self.alignment = alignment
                    self.redraw()
                }
            } catch {
                if Task.isCancelled { return }
                await self.fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        preview = nil
        phase = .failed(message)
    }

    /// The placed photos as sources to draw from, at the working size.
    private func workingSources() -> [Source] {
        guard let alignment else { return [] }
        return alignment.cameras.keys.sorted().compactMap { k in
            guard k < photos.count, let w = working[photos[k].url], let camera = alignment.cameras[k] else { return nil }
            return Source(bitmap: w.bitmap, rotation: camera.rotation, focal: camera.focal * w.scale, gain: camera.gain)
        }
    }

    /// Lays the panorama out and draws the preview, as the settings are now.
    private func redraw() {
        guard alignment != nil else { return }
        drawTask?.cancel()
        var sources = workingSources()
        let settings = settings
        phase = .working("Drawing…")
        drawTask = Task.detached(priority: .userInitiated) {
            do {
                let layout = try Renderer.layout(&sources, projection: settings.projection)
                let region = settings.crop ? layout.crop : layout.full
                let focal = Aligner.median(sources.map(\.focal))
                let scale = min(focal, Self.previewWidth / region.width)
                let flag = Flag()
                let bitmap = await withTaskCancellationHandler {
                    Renderer.render(sources, projection: settings.projection, region: region, scale: scale,
                                    balance: settings.balance, cancelled: { flag.isSet })
                } onCancel: { flag.set() }
                if Task.isCancelled { return }
                let space = await self.colorSpace
                let image = bitmap.image(colorSpace: space)
                await MainActor.run {
                    self.layout = layout
                    self.preview = image
                    self.phase = .ready
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { self.layout = nil }
                await self.fail(error.localizedDescription)
            }
        }
    }

    // MARK: Sizes

    /// The saved panorama's size in pixels, at the chosen size.
    var outputSize: (width: Int, height: Int)? {
        guard let layout, let alignment else { return nil }
        let region = settings.crop ? layout.crop : layout.full
        let focal = Aligner.median(alignment.cameras.values.map(\.focal)) * settings.size.factor
        var scale = focal
        if region.width * region.height * scale * scale > Self.maxPixels {
            scale = (Self.maxPixels / (region.width * region.height)).squareRoot()
        }
        return (Int((region.width * scale).rounded()), Int((region.height * scale).rounded()))
    }

    // MARK: Saving

    enum Format: String, CaseIterable, Identifiable {
        case jpeg, heic, png, tiff
        var id: Self { self }
        var name: String { rawValue.uppercased() }
        var type: UTType { switch self { case .jpeg: .jpeg; case .heic: .heic; case .png: .png; case .tiff: .tiff } }
        var keepsTransparency: Bool { self == .png || self == .tiff }
    }

    private var formatName: String {
        get { UserDefaults.standard.string(forKey: "format") ?? Format.jpeg.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "format") }
    }

    func save() {
        guard canSave else { return }
        let chooser = FormatChooser(format: Format(rawValue: formatName) ?? .jpeg)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [chooser.format.type]
        let first = photos.first.map { $0.url.deletingPathExtension().lastPathComponent } ?? "Panorama"
        panel.nameFieldStringValue = "\(first) panorama"
        panel.directoryURL = photos.first?.url.deletingLastPathComponent()
        panel.isExtensionHidden = false
        chooser.panel = panel
        let accessory = NSHostingView(rootView: FormatAccessory(chooser: chooser))
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            self.formatName = chooser.format.rawValue
            self.write(to: url, format: chooser.format)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    func write(to url: URL, format: Format) {
        guard let alignment, let size = outputSize else { return }
        let photos = photos, settings = settings, space = colorSpace
        let factor = settings.size.factor
        saving = 0
        Task.detached(priority: .userInitiated) {
            // The photos at the size wanted, and the cameras scaled to them.
            let keys = alignment.cameras.keys.sorted()
            var bitmaps = [Bitmap?](repeating: nil, count: keys.count)
            let read = Counter()
            bitmaps.withUnsafeMutableBufferPointer { buf in
                let base = Slots(buf.baseAddress!)
                DispatchQueue.concurrentPerform(iterations: keys.count) { n in
                    let photo = photos[keys[n]]
                    base[n] = photo.pixels(maxSide: Int((Double(photo.longSide) * factor).rounded()), colorSpace: space)
                    let done = Double(read.increment()) / Double(keys.count)
                    Task { @MainActor in self.saving = 0.25 * done }
                }
            }
            var sources: [Source] = []
            for (n, k) in keys.enumerated() {
                guard let bitmap = bitmaps[n], let camera = alignment.cameras[k] else { continue }
                sources.append(Source(bitmap: bitmap, rotation: camera.rotation,
                                      focal: camera.focal * Double(bitmap.width) / Double(photos[k].width), gain: camera.gain))
            }
            bitmaps = []
            do {
                let layout = try Renderer.layout(&sources, projection: settings.projection)
                let region = settings.crop ? layout.crop : layout.full
                let scale = Double(size.width) / region.width
                let bitmap = Renderer.render(sources, projection: settings.projection, region: region, scale: scale,
                                             balance: settings.balance, progress: { done in
                                                 Task { @MainActor in self.saving = 0.25 + 0.65 * done }
                                             })
                sources = []
                await MainActor.run { self.saving = 0.92 }
                let opaque = settings.crop || !format.keepsTransparency
                guard let image = bitmap.image(colorSpace: space, opaque: opaque) else { throw CocoaError(.fileWriteUnknown) }
                try Self.writeImage(image, to: url, format: format, metadataFrom: photos[keys[keys.count / 2]])
                await MainActor.run {
                    self.saving = nil
                    self.show("Saved \(url.lastPathComponent), \(image.width.formatted()) × \(image.height.formatted()).")
                }
            } catch {
                await MainActor.run {
                    self.saving = nil
                    self.show("Couldn't save: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Asks where to save the photos as an animation, and saves it there.
    func saveAnimation() {
        guard canAnimate else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.gif]
        let first = photos.first.map { $0.url.deletingPathExtension().lastPathComponent } ?? "Panorama"
        panel.nameFieldStringValue = "\(first) animation"
        panel.directoryURL = photos.first?.url.deletingLastPathComponent()
        panel.isExtensionHidden = false
        panel.message = "The photos one after another, as a looping GIF held steady on the background"
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            self.writeAnimation(to: url)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    /// Writes the placed photos, in the order they were taken, as a GIF. It's drawn from
    /// the working copies, which are already larger than a GIF frame wants to be.
    func writeAnimation(to url: URL) {
        guard let alignment else { return }
        let placed = alignment.cameras.keys.sorted().filter { $0 < photos.count && working[photos[$0].url] != nil }
        let taken = placed.map { photos[$0].taken }
        var sources = workingSources()
        let settings = settings, space = colorSpace
        saving = 0
        Task.detached(priority: .userInitiated) {
            do {
                let layout = try Renderer.layout(&sources, projection: settings.projection)
                let (kind, frames) = Animation.frames(sources, projection: settings.projection, full: layout.full,
                                                      balance: settings.balance, progress: { done in
                                                          Task { @MainActor in self.saving = 0.9 * done }
                                                      })
                let images = frames.compactMap { $0.image(colorSpace: space, opaque: true) }
                try Animation.write(images, delays: Animation.delays(taken), to: url)
                let how = kind == .steady ? "held steady" : "over the whole panorama"
                await MainActor.run {
                    self.saving = nil
                    self.show("Saved \(url.lastPathComponent), \(images.count) frames \(how).")
                }
            } catch {
                await MainActor.run {
                    self.saving = nil
                    self.show("Couldn't save: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Writes the panorama, carrying over the camera and date from one of the photos (but
    /// not its size or orientation).
    nonisolated private static func writeImage(_ image: CGImage, to url: URL, format: Format, metadataFrom photo: Photo) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnsupportedScheme) }
        var properties: [CFString: Any] = [:]
        if let source = CGImageSourceCreateWithURL(photo.url as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary] {
                if var dictionary = original[key] as? [CFString: Any] {
                    dictionary[kCGImagePropertyExifPixelXDimension] = nil
                    dictionary[kCGImagePropertyExifPixelYDimension] = nil
                    dictionary[kCGImagePropertyTIFFOrientation] = nil
                    // A panorama has no one focal length; the photo's would make it look
                    // like a photo, if it were dropped in with them again.
                    dictionary[kCGImagePropertyExifFocalLength] = nil
                    dictionary[kCGImagePropertyExifFocalLenIn35mmFilm] = nil
                    properties[key] = dictionary
                }
            }
        }
        properties[kCGImagePropertyOrientation] = 1
        if format == .jpeg || format == .heic { properties[kCGImageDestinationLossyCompressionQuality] = 0.92 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: Small things

    func show(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .folder]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose overlapping photos taken from one spot, or a folder of them"
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }
}

/// Places for parallel work to put its results, one each.
struct Slots<T>: @unchecked Sendable {
    let base: UnsafeMutablePointer<T>
    init(_ base: UnsafeMutablePointer<T>) { self.base = base }
    subscript(_ k: Int) -> T {
        get { base[k] }
        nonmutating set { base[k] = newValue }
    }
}

/// A flag one thread sets and others read, for stopping a render part way.
final class Flag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// The save panel's format menu, which keeps the panel's file type in step.
@MainActor
final class FormatChooser: ObservableObject {
    @Published var format: PanoramaModel.Format {
        didSet {
            panel?.allowedContentTypes = [format.type]
        }
    }
    weak var panel: NSSavePanel?

    init(format: PanoramaModel.Format) { self.format = format }
}

struct FormatAccessory: View {
    @ObservedObject var chooser: FormatChooser

    var body: some View {
        HStack {
            Picker("Format:", selection: $chooser.format) {
                ForEach(PanoramaModel.Format.allCases) { Text($0.name).tag($0) }
            }
            .fixedSize()
            Text(chooser.format.keepsTransparency ? "Uncropped edges stay transparent." : "Uncropped edges are filled with black.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
