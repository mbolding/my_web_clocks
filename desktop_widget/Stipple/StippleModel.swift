// StippleModel — one window's picture and its drawing: reads the image, lets the dots
// settle a step at a time so they're drawn as they move, joins them into a line when asked,
// and saves the result. Inbox hands files opened from the Dock, Finder or File → Open to the
// frontmost window.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Everything that can be set, kept between launches as the starting point for new windows.
struct Settings: Codable, Equatable {
    var style = Style()
    var dots = 4000
    /// Brightness at or above which the picture counts as white; 1 is off.
    var cutoff = 1.0
    /// Rounds of settling each run, before it stops by itself.
    var steps = 60
    var pngSide = 4800
    var showPicture = false

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

@MainActor
final class StippleModel: ObservableObject {
    enum Phase: Equatable {
        case empty, reading, ready
        case failed(String)
    }

    @Published private(set) var phase = Phase.empty
    @Published var settings = Settings.load() {
        didSet { changed(from: oldValue) }
    }
    @Published private(set) var stipples = Stipples.none
    /// The line through the dots, once worked out for the current dots.
    @Published private(set) var path: [Int32]?
    @Published private(set) var picture: CGImage?
    @Published private(set) var step = 0
    @Published private(set) var settling = false
    @Published private(set) var routing = false
    @Published private(set) var settled = false
    @Published private(set) var notice: String?
    private(set) var source: URL?

    private var gray: DensityMap.Gray?
    private var stippler: Stippler?
    private var work: Task<Void, Never>?
    private var pendingRestart: Task<Void, Never>?
    private var runStart = 0

    /// Shows files in this window, or in new ones. The window sets it, since it holds the
    /// window's file and can open others.
    var receive: ([URL]) -> Void = { _ in }

    var canExport: Bool { phase == .ready && stipples.count > 0 && (settings.style.mode == .dots || path != nil) }
    var busy: Bool { settling || routing }

    // MARK: Reading

    func load(_ url: URL?) async {
        source = url
        notice = nil
        stop()
        gray = nil
        stippler = nil
        stipples = .none
        path = nil
        picture = nil
        guard let url else {
            phase = .empty
            return
        }
        phase = .reading
        let result = await Task.detached(priority: .userInitiated) {
            Result { try DensityMap.read(url) }
        }.value
        guard !Task.isCancelled, source == url else { return }

        switch result {
        case .success(let (gray, picture)):
            self.gray = gray
            self.picture = picture
            phase = .ready
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            restart()
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Settling

    /// Scatters a fresh set of dots and lets them settle.
    func restart() {
        pendingRestart?.cancel()
        guard let gray else { return }
        let settings = settings
        run { model in
            let stippler = await Self.make(gray, settings)
            guard !Task.isCancelled else { return }
            model.stippler = stippler
            model.stipples = stippler.snapshot
            model.path = nil
            model.step = 0
            model.settled = false
            await model.settle(stippler)
        }
    }

    /// Pauses settling, or carries on: to the end of this run, or for another run's worth.
    func pauseOrResume() {
        if busy {
            stop()
        } else if let stippler {
            if step - runStart >= settings.steps || settled { runStart = step }
            run { await $0.settle(stippler) }
        }
    }

    func stop() {
        work?.cancel()
        pendingRestart?.cancel()
    }

    /// Runs one piece of work at a time: the next waits for the last to see the cancel and
    /// finish, so a stippler is never stepped by two at once.
    private func run(_ body: @escaping @MainActor (StippleModel) async -> Void) {
        let previous = work
        previous?.cancel()
        work = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await body(self)
        }
    }

    private func settle(_ stippler: Stippler) async {
        if step == 0 { runStart = 0 }
        settling = true
        settled = false
        path = nil
        while step - runStart < settings.steps, !Task.isCancelled {
            let (snapshot, moved) = await Self.relax(stippler)
            guard self.stippler === stippler else { break }
            stipples = snapshot
            step += 1
            // Under a fiftieth of a pixel on average: still now, to the eye.
            if moved < 0.02 {
                settled = true
                break
            }
        }
        settling = false
        if !Task.isCancelled && settings.style.mode == .line { await joinDots() }
    }

    nonisolated private static func make(_ gray: DensityMap.Gray, _ settings: Settings) async -> Stippler {
        let map = DensityMap(gray, cutoff: settings.cutoff, invert: settings.style.invert)
        return Stippler(map: map, count: settings.dots)
    }

    nonisolated private static func relax(_ stippler: Stippler) async -> (Stipples, Float) {
        let moved = stippler.relax()
        return (stippler.snapshot, moved)
    }

    // MARK: The line

    private var routeID = 0

    private func joinDots() async {
        guard path == nil, stipples.count > 0 else { return }
        routing = true
        routeID += 1
        let id = routeID
        let dots = stipples
        let route = await Self.route(dots) { [weak self] partial in
            Task { @MainActor in
                guard let self, self.routeID == id, self.routing else { return }
                self.path = partial
            }
        }
        guard routeID == id else { return }
        routing = false
        // A cancelled route isn't finished, so it's worked out afresh next time.
        path = Task.isCancelled ? nil : route
    }

    nonisolated private static func route(_ dots: Stipples, progress: @escaping @Sendable ([Int32]) -> Void) async -> [Int32] {
        Tour.route(xs: dots.xs, ys: dots.ys, width: dots.width, height: dots.height,
                   progress: progress, isCancelled: { Task.isCancelled })
    }

    // MARK: Changes

    private func changed(from old: Settings) {
        settings.save()
        let new = settings
        if new.style.invert != old.style.invert {
            restart()
        } else if new.dots != old.dots || new.cutoff != old.cutoff {
            // Sliders send a stream of changes; start again once they pause.
            pendingRestart?.cancel()
            pendingRestart = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self?.restart()
            }
        }
        if new.style.mode == .line, old.style.mode != .line, !busy, path == nil, stippler != nil {
            run { await $0.joinDots() }
        }
    }

    // MARK: Saving

    func copyImage() {
        guard canExport, let png = Drawing.png(stipples, path: path, style: settings.style, longSide: 2400) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        flash("Copied the drawing")
    }

    /// Asks where to save, starting beside the picture with its name.
    func save(_ type: UTType) {
        guard canExport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        let name = source?.deletingPathExtension().lastPathComponent ?? "Stipple"
        panel.nameFieldStringValue = "\(name) \(settings.style.mode == .line ? "line" : "stipple").\(type.preferredFilenameExtension ?? "")"
        panel.directoryURL = source?.deletingLastPathComponent()

        let stipples = stipples, path = path, settings = settings
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                if type == .svg {
                    try Drawing.svg(stipples, path: path, style: settings.style).write(to: url, atomically: true, encoding: .utf8)
                } else {
                    guard let png = Drawing.png(stipples, path: path, style: settings.style, longSide: settings.pngSide)
                    else { throw CocoaError(.fileWriteUnknown) }
                    try png.write(to: url, options: .atomic)
                }
                self?.flash("Saved \(url.lastPathComponent)")
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private var flashID = 0

    private func flash(_ message: String) {
        notice = message
        flashID += 1
        let id = flashID
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if flashID == id { notice = nil }
        }
    }

    /// "4,000 dots · settling, step 12", for the window's subtitle.
    var status: String {
        guard phase == .ready, stipples.count > 0 else { return "" }
        let dots = "\(stipples.count.formatted()) dots"
        if routing { return "\(dots) · joining them into one line…" }
        if settling { return "\(dots) · settling, step \(step)" }
        if settled { return "\(dots) · settled after \(step) steps" }
        return "\(dots) · \(step) steps"
    }
}

/// Where opened files go: to the frontmost window, or to new windows while there's none.
@MainActor
final class Inbox {
    static let shared = Inbox()

    /// SwiftUI's action for opening a window on a file. The menu commands hand it over, as
    /// SwiftUI sets them up at launch, before any window.
    var openWindow: OpenWindowAction?
    private weak var front: StippleModel?
    private var pending: [URL] = []

    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let front {
            front.receive(urls)
        } else if let openWindow {
            urls.forEach { openWindow(value: $0) }
        } else {
            pending += urls
        }
    }

    /// Opens windows for files that came in before SwiftUI was ready for them.
    func finishLaunching() {
        let urls = pending
        pending = []
        open(urls)
    }

    /// Called as a window comes up or to the front.
    func makeFront(_ model: StippleModel) {
        front = model
        guard !pending.isEmpty else { return }
        let urls = pending
        pending = []
        model.receive(urls)
    }

    func closed(_ model: StippleModel) {
        if front === model { front = nil }
    }

    var hasFront: Bool { front != nil }

    /// File → Open…
    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose a picture to stipple"
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }
}
