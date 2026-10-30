// ExtractorModel — one window's file and its text, with Copy All and Save as Text. Inbox
// hands files opened from the Dock, Finder or File → Open to the frontmost window.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ExtractorModel: ObservableObject {
    enum Phase: Equatable {
        case empty, reading, ready
        case failed(String)
    }

    @Published private(set) var phase = Phase.empty
    @Published var text = "" {
        didSet {
            words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            characters = text.count
        }
    }
    @Published private(set) var words = 0
    @Published private(set) var characters = 0
    @Published private(set) var notice: String?
    private(set) var source: URL?

    /// Shows files in this window, or in new ones. The window sets it, since it holds the
    /// window's file and can open others.
    var receive: ([URL]) -> Void = { _ in }

    var canExport: Bool { phase == .ready && !text.isEmpty }

    func load(_ url: URL?) async {
        source = url
        notice = nil
        guard let url else {
            text = ""
            phase = .empty
            return
        }
        phase = .reading
        let result = await Task.detached(priority: .userInitiated) {
            Result { try Extraction.text(of: url) }
        }.value
        guard !Task.isCancelled, source == url else { return }

        switch result {
        case .success(let string):
            text = string
            phase = .ready
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        case .failure(let error):
            text = ""
            phase = .failed(error.localizedDescription)
        }
    }

    func copyAll() {
        guard canExport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash("Copied \(Self.count(words, "word"))")
    }

    /// Asks where to save, starting beside the original with its name and ".txt".
    func save() {
        guard canExport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (source?.deletingPathExtension().lastPathComponent ?? "Extracted Text") + ".txt"
        panel.directoryURL = source?.deletingLastPathComponent()

        let text = text
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
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

    /// "1,234 words · 6,789 characters", for the window's subtitle.
    var counts: String { "\(Self.count(words, "word")) · \(Self.count(characters, "character"))" }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n.formatted()) \(noun)\(n == 1 ? "" : "s")"
    }
}

/// Where opened files go: to the frontmost window, or to new windows while there's none.
@MainActor
final class Inbox {
    static let shared = Inbox()

    /// SwiftUI's action for opening a window on a file. The menu commands hand it over, as
    /// SwiftUI sets them up at launch, before any window.
    var openWindow: OpenWindowAction?
    private weak var front: ExtractorModel?
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
    func makeFront(_ model: ExtractorModel) {
        front = model
        guard !pending.isEmpty else { return }
        let urls = pending
        pending = []
        model.receive(urls)
    }

    func closed(_ model: ExtractorModel) {
        if front === model { front = nil }
    }

    var hasFront: Bool { front != nil }

    /// File → Open…
    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Extraction.contentTypes
        panel.allowsMultipleSelection = true
        panel.message = "Choose a PDF, Word document or other text file"
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }
}
